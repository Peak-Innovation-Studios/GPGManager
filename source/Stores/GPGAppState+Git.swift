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
        // Align the committer email with the chosen key's UID so GitHub verifies
        // the signature. When the key can't be resolved to an email we leave the
        // email field nil, which tells the service not to touch user.email.
        normalized.userEmail = signingKeyEmail(for: normalized.signingKey)
        do {
            try await gitConfigService.apply(normalized, scope: gitConfigScope)
            await refreshGitSigningConfiguration()
            if let email = normalized.userEmail {
                statusMessage = "Updated \(gitConfigScope.displayName) Git signing. Committer email set to \(email)."
            } else {
                statusMessage = "Updated \(gitConfigScope.displayName) Git signing."
            }
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

    /// The email on the selected signing key's primary UID. Used to keep the
    /// committer email aligned with the key so GitHub verifies signatures.
    /// Returns nil when the key can't be resolved or carries no email.
    private func signingKeyEmail(for signingKey: String?) -> String? {
        guard let key = GPGKey.match(signingKey: signingKey, in: secretKeys) else { return nil }
        let email = GPGKey.parseUserID(key.primaryUserID).email.trimmingCharacters(in: .whitespaces)
        return email.isEmpty ? nil : email
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

    func refreshGitHubAccounts() async {
        availableGitHubAccounts = (try? await gitHubService.fetchAccounts()) ?? []
        if let selected = selectedGitHubAccount, !availableGitHubAccounts.contains(selected) {
            selectedGitHubAccount = nil
        }
    }

    func selectGitHubAccount(_ account: String?) async {
        selectedGitHubAccount = account
        await refreshGitHubRegisteredKeys()
    }

    func refreshGitHubRegisteredKeys() async {
        gitHubKeyCheck = .checking
        await refreshGitHubAccounts()
        do {
            let keys = try await gitHubService.fetchRegisteredKeys(forAccount: selectedGitHubAccount)
            gitHubKeyCheck = .loaded(registeredKeys: keys)
            gitHubUsername = try? await gitHubService.fetchAuthenticatedUser(forAccount: selectedGitHubAccount)
        } catch GitHubGPGService.FetchError.scopeRequired(let command) {
            gitHubKeyCheck = .scopeRequired(command: command)
        } catch {
            gitHubKeyCheck = .unavailable(reason: error.localizedDescription)
            gitHubUsername = nil
        }
    }

    func deleteGitHubKey(_ key: GitHubRegisteredKey) async {
        do {
            try await gitHubService.deleteKey(githubID: key.id, forAccount: selectedGitHubAccount)
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
            try await gitHubService.uploadKey(
                armoredPublic: armored,
                name: trimmed?.isEmpty == false ? trimmed : nil,
                forAccount: selectedGitHubAccount
            )
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
        let account = selectedGitHubAccount
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: local.fingerprint)
            try await gitHubService.deleteKey(githubID: remote.id, forAccount: account)
            try await gitHubService.uploadKey(
                armoredPublic: armored,
                name: trimmed.isEmpty ? nil : trimmed,
                forAccount: account
            )
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
        let account = selectedGitHubAccount
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: local.fingerprint)
            try await gitHubService.deleteKey(githubID: remote.id, forAccount: account)
            try await gitHubService.uploadKey(armoredPublic: armored, forAccount: account)
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
        let account = selectedGitHubAccount
        do {
            let armored = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: local.fingerprint)
            try await gitHubService.uploadKey(armoredPublic: armored, forAccount: account)
            try await gitHubService.deleteKey(githubID: remote.id, forAccount: account)
            statusMessage = "Replaced \(remote.keyID) with \(local.primaryUserID) on GitHub."
            errorMessage = nil
            await refreshGitHubRegisteredKeys()
        } catch {
            errorMessage = error.localizedDescription
            await refreshGitHubRegisteredKeys()
        }
    }
}
