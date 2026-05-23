import AppKit
import Foundation

@MainActor
extension GPGAppState {
    func refreshGitSigningConfiguration() async {
        rememberedRepos = rememberedReposStore.load()
        if case .repository(let path) = gitConfigScope,
           !rememberedRepos.contains(where: { $0.path == path }) {
            gitConfigScope = .global
        }
        var config = await gitConfigService.currentConfiguration(scope: gitConfigScope)
        config.signingKey = normalizeSigningKey(config.signingKey)
        gitSigning = config
        gitGPGProgram = config.gpgProgram ?? ""
    }

    func setGitConfigScope(_ scope: GitConfigScope) async {
        gitConfigScope = scope
        await refreshGitSigningConfiguration()
    }

    func applyGitSigningConfiguration(_ configuration: GitSigningConfiguration) async {
        var normalized = configuration
        normalized.signingKey = normalizeSigningKey(configuration.signingKey)
        do {
            try await gitConfigService.apply(normalized, scope: gitConfigScope)
            await refreshGitSigningConfiguration()
            statusMessage = "Updated \(gitConfigScope.displayName) Git signing."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Converts any recognized signing-key form (long ID, short ID, 0x-prefixed)
    /// into the canonical 40-char fingerprint, so we never persist anything else.
    private func normalizeSigningKey(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        if let match = GPGKey.match(signingKey: raw, in: secretKeys) {
            return match.fingerprint
        }
        return raw
    }

    func chooseRepository() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a Git repository."
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        guard await gitConfigService.isGitRepository(at: path) else {
            errorMessage = "That folder isn't a Git working tree."
            return
        }

        if !rememberedRepos.contains(where: { $0.path == path }) {
            rememberedRepos.append(RememberedRepo(path: path, name: nil))
            rememberedReposStore.save(rememberedRepos)
        }
        await setGitConfigScope(.repository(path: path))
    }

    func forgetRepository(_ repo: RememberedRepo) async {
        rememberedRepos.removeAll { $0.path == repo.path }
        rememberedReposStore.save(rememberedRepos)
        if case .repository(let path) = gitConfigScope, path == repo.path {
            await setGitConfigScope(.global)
        }
    }

    func renameRepository(_ repo: RememberedRepo, to newName: String?) {
        guard let index = rememberedRepos.firstIndex(where: { $0.path == repo.path }) else { return }
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        rememberedRepos[index].name = (trimmed?.isEmpty == false) ? trimmed : nil
        rememberedReposStore.save(rememberedRepos)
    }

    func refreshGitHubRegisteredKeys() async {
        gitHubKeyCheck = .checking
        do {
            let keys = try await gitHubService.fetchRegisteredKeys()
            gitHubKeyCheck = .loaded(registeredKeys: keys)
            gitHubUsername = try? await gitHubService.fetchAuthenticatedUser()
        } catch GitHubGPGService.FetchError.scopeRequired(let command) {
            gitHubKeyCheck = .scopeRequired(command: command)
        } catch {
            gitHubKeyCheck = .unavailable(reason: error.localizedDescription)
            gitHubUsername = nil
        }
    }

    func deleteGitHubKey(_ key: GitHubRegisteredKey) async {
        do {
            try await gitHubService.deleteKey(githubID: key.id)
            statusMessage = "Removed \(key.keyID) from GitHub."
            errorMessage = nil
            await refreshGitHubRegisteredKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadKeyToGitHub(_ key: GPGKey, name: String? = nil) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: key.fingerprint)
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            try await gitHubService.uploadKey(armoredPublic: armored, name: trimmed?.isEmpty == false ? trimmed : nil)
            statusMessage = "Uploaded \(key.primaryUserID) to GitHub."
            errorMessage = nil
            await refreshGitHubRegisteredKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// GitHub has no rename endpoint, so we delete the existing registration
    /// and upload the same local public key with the new name.
    func renameGitHubKey(_ remote: GitHubRegisteredKey, with local: GPGKey, name: String) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: local.fingerprint)
            try await gitHubService.deleteKey(githubID: remote.id)
            try await gitHubService.uploadKey(armoredPublic: armored, name: trimmed.isEmpty ? nil : trimmed)
            statusMessage = "Renamed GitHub key \(remote.keyID)."
            errorMessage = nil
            await refreshGitHubRegisteredKeys()
        } catch {
            errorMessage = error.localizedDescription
            await refreshGitHubRegisteredKeys()
        }
    }

    /// Re-uploads the *same* key after extending or updating its expiry locally.
    /// GitHub deduplicates by key_id, so we must delete the stale registration
    /// before uploading. There's a brief window with no GitHub registration —
    /// previously signed commits still verify because GitHub stores the
    /// signature at sign time.
    func refreshGitHubKey(_ remote: GitHubRegisteredKey, with local: GPGKey) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: local.fingerprint)
            try await gitHubService.deleteKey(githubID: remote.id)
            try await gitHubService.uploadKey(armoredPublic: armored)
            statusMessage = "Refreshed \(remote.keyID) on GitHub."
            errorMessage = nil
            await refreshGitHubRegisteredKeys()
        } catch {
            errorMessage = error.localizedDescription
            await refreshGitHubRegisteredKeys()
        }
    }

    /// Uploads the new key first, then removes the old one. If the upload fails
    /// the old key stays in place so the user isn't left with no key on GitHub.
    func replaceGitHubKey(removing remote: GitHubRegisteredKey, with local: GPGKey) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: local.fingerprint)
            try await gitHubService.uploadKey(armoredPublic: armored)
            try await gitHubService.deleteKey(githubID: remote.id)
            statusMessage = "Replaced \(remote.keyID) with \(local.primaryUserID) on GitHub."
            errorMessage = nil
            await refreshGitHubRegisteredKeys()
        } catch {
            errorMessage = error.localizedDescription
            await refreshGitHubRegisteredKeys()
        }
    }
}
