import AppKit
import Foundation
import Observation
import OSLog

private let appStateLog = Logger(
    subsystem: "com.peakinnovationstudios.GPGManager",
    category: "state"
)

@MainActor
@Observable
final class GPGAppState {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case signing = "Signing"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .overview: "gauge"
            case .signing: "signature"
            }
        }
    }

    var selectedSection: Section = .overview
    var installations: [GPGInstallation] = []
    var selectedGPGPath: String = UserDefaults.standard.string(forKey: "selectedGPGPath") ?? ""
    var keys: [GPGKey] = []
    var selectedKeyID: GPGKey.ID?
    var agentConfig: GPGAgentConfig = .empty
    var gpgConfig: GPGConfig = .empty
    var gitGPGProgram = ""
    var gitSigning: GitSigningConfiguration = .empty
    var gitConfigScope: GitConfigScope = .global
    var rememberedRepos: [RememberedRepo] = []
    var gitHubKeyCheck: GitHubKeyCheckStatus = .notChecked
    var gitHubUsername: String?
    /// Accounts that `gh` currently has authentication for (one entry per `gh auth login`).
    var availableGitHubAccounts: [String] = []
    /// nil means "use whichever account gh considers active".
    var selectedGitHubAccount: String?
    var pinentryStatus: PinentryInstallStatus = .helperMissing
    var statusMessage = "Ready"
    var errorMessage: String?
    var isRefreshing = false

    /// Bumped on every Keychain mutation so SwiftUI views that call
    /// hasKeychainEntry(for:) re-evaluate. exists() is a function call against
    /// the live Keychain, not a stored property, so it isn't observed
    /// automatically — touching this counter from any view that reads
    /// hasKeychainEntry forces a re-render when the Keychain changes.
    var keychainRevision: Int = 0

    private static let selectedPathKey = "selectedGPGPath"

    private let discoveryService = GPGDiscoveryService()
    let keyService = GPGKeyService()
    private let agentConfigStore = GPGAgentConfigStore()
    private let gpgConfigStore = GPGConfigStore()
    private let agentService = GPGAgentService()
    let gitConfigService = GitConfigService()
    let rememberedReposStore = RememberedReposStore()
    let gitHubService = GitHubGPGService()
    let pinentryInstaller = PinentryInstallerService()
    private let keychainStore = KeychainPassphraseStore()

    var selectedKey: GPGKey? {
        keys.first { $0.id == selectedKeyID }
    }

    var selectedInstallation: GPGInstallation? {
        installations.first { $0.path == selectedGPGPath }
    }

    var secretKeys: [GPGKey] {
        keys.filter { $0.keyClass == .secret }
    }

    func bootstrap() async {
        await refreshInstallations()
        loadAgentConfig()
        loadGPGConfig()
        refreshPinentryStatus()
        await refreshKeys()
        await refreshGitSigningConfiguration()

        // Background check — don't block bootstrap on a network call.
        Task { await refreshGitHubRegisteredKeys() }
    }

    func refreshAll() async {
        await refreshInstallations()
        loadAgentConfig()
        loadGPGConfig()
        refreshPinentryStatus()
        await refreshKeys()
        await refreshGitSigningConfiguration()
    }



    func refreshInstallations() async {
        installations = await discoveryService.discover()
        if selectedGPGPath.isEmpty || !FileManager.default.isExecutableFile(atPath: selectedGPGPath) {
            selectedGPGPath = installations.first?.path ?? ""
            persistSelectedPath()
        }
    }

    func selectGPGPath(_ path: String) async {
        selectedGPGPath = path
        persistSelectedPath()
        await refreshKeys()
    }

    func chooseCustomGPGPath() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a GPG executable."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let installation = GPGInstallation(path: url.path, kind: .custom)
        if !installations.contains(where: { $0.path == installation.path }) {
            installations.append(installation)
        }
        await selectGPGPath(url.path)
    }

    func refreshKeys() async {
        guard !selectedGPGPath.isEmpty else {
            keys = []
            statusMessage = "No GPG executable selected."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            keys = try await keyService.listKeys(gpgPath: selectedGPGPath)
            if selectedKeyID == nil {
                selectedKeyID = keys.first?.id
            }
            statusMessage = "Loaded \(keys.count) keys."
            errorMessage = nil
        } catch {
            keys = []
            errorMessage = error.localizedDescription
            statusMessage = "Could not load keys."
        }
    }

    func createKey(parameters: GPGCreateKeyParameters, saveToKeychain: Bool = false, uploadToGitHub: Bool = false) async throws {
        guard !selectedGPGPath.isEmpty else {
            throw GPGServiceError.commandFailed("No GPG executable selected.")
        }

        let result = try await keyService.createKey(gpgPath: selectedGPGPath, parameters: parameters)

        statusMessage = "Created new key for \(parameters.email)."
        errorMessage = nil
        await refreshKeys()

        // Locate the new key in the refreshed list — preferring the fingerprint
        // parsed from gpg's gen-key output, falling back to email match for
        // safety. We do the keychain save AFTER refresh because the new key's
        // primaryKeygrip is populated by `--with-keygrip` in the list call,
        // and querying it directly via fetchPrimaryKeygrip immediately after
        // gen-key can race with gpg 2.5's keyboxd backend and return nil.
        let newKey: GPGKey? = result.fingerprint
            .flatMap { fingerprint in secretKeys.first(where: { $0.fingerprint == fingerprint }) }
            ?? secretKeys.first(where: { key in
                key.userIDs.contains(where: { $0.range(of: parameters.email, options: .caseInsensitive) != nil })
            })

        if saveToKeychain {
            if let key = newKey {
                // Query gpg directly rather than relying on the in-memory key
                // model. Retry with a short backoff: gpg 2.5's keyboxd commits
                // newly-created keys asynchronously, and an immediate
                // `--list-secret-keys --with-keygrip` call can return the key
                // without its keygrip lines. Three tries spaced 250ms apart
                // covers the typical commit latency.
                var keygrips: [String] = []
                var lastError: Error?
                for attempt in 0..<3 {
                    if attempt > 0 {
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    do {
                        keygrips = try await keyService.fetchAllKeygrips(
                            gpgPath: selectedGPGPath,
                            fingerprint: key.fingerprint
                        )
                        if !keygrips.isEmpty { break }
                    } catch {
                        lastError = error
                    }
                }
                if let keygrip = keygrips.first {
                    let label = keychainLabel(for: parameters, fingerprint: key.fingerprint)
                    let ok = keychainStore.savePassphrase(parameters.passphrase, account: keygrip, label: label)
                    if !ok {
                        errorMessage = "Key created, but saving its passphrase to the Keychain failed. Click Enable Touch ID on the key to retry."
                    } else {
                        keychainRevision &+= 1
                        // Refresh once more so the in-memory key's primaryKeygrip
                        // is populated. Without this, hasKeychainEntry() returns
                        // false (guards on a nil keygrip) and the "Enable Touch
                        // ID" button stays visible on the freshly-saved key.
                        await refreshKeys()
                    }
                } else if let lastError {
                    errorMessage = "Key created, but couldn't read its keygrip: \(lastError.localizedDescription)"
                } else {
                    errorMessage = "Key created, but couldn't determine its keygrip to save the passphrase. Click Enable Touch ID on the key to retry."
                }
            } else {
                errorMessage = "Key created, but couldn't locate it in the keyring to save the passphrase. Click Enable Touch ID on the key to retry."
            }
        }

        if uploadToGitHub, let key = newKey {
            let trimmedTitle = parameters.githubTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveTitle = trimmedTitle.isEmpty ? parameters.name : trimmedTitle
            await uploadKeyToGitHub(key, name: effectiveTitle)
        }
    }

    func importKey(from url: URL) async {
        guard !selectedGPGPath.isEmpty else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let output = try await keyService.importKey(gpgPath: selectedGPGPath, fileURL: url)
            statusMessage = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported key." : output
            errorMessage = nil
            await refreshKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyPublicKeyToPasteboard(_ key: GPGKey) async {
        do {
            let exported = try await keyService.exportPublicKey(gpgPath: selectedGPGPath, fingerprint: key.fingerprint)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(exported, forType: .string)
            statusMessage = "Copied public key for \(key.shortFingerprint)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAgentConfig() {
        do {
            agentConfig = try agentConfigStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAgentConfig() {
        do {
            try agentConfigStore.save(agentConfig)
            statusMessage = "Saved \(agentConfigStore.configURL.path)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadGPGConfig() {
        do {
            gpgConfig = try gpgConfigStore.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGPGConfig() {
        do {
            try gpgConfigStore.save(gpgConfig)
            statusMessage = "Saved \(gpgConfigStore.configURL.path)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Synchronous check whether the local Keychain has a passphrase entry for
    /// this key's primary keygrip. Used to hide the "Enable Touch ID" button
    /// once the entry has been migrated/created.
    func hasKeychainEntry(for key: GPGKey) -> Bool {
        _ = keychainRevision // Observe so views re-evaluate on Keychain writes.
        guard let grip = key.primaryKeygrip, !grip.isEmpty else { return false }
        return keychainStore.exists(account: grip)
    }

    /// Migrates existing GPG Suite / pinentry-mac Keychain entries for this key
    /// to ones protected by Touch ID. Checks every keygrip the key has (primary
    /// + subkeys) since pinentry-mac stores entries per-keygrip and we can't
    /// tell up-front which were saved.
    func enableTouchID(for key: GPGKey) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }
        do {
            let keygrips = try await keyService.fetchAllKeygrips(
                gpgPath: selectedGPGPath,
                fingerprint: key.fingerprint
            )
            guard !keygrips.isEmpty else {
                errorMessage = "Couldn't determine the keygrip for this key."
                return
            }

            let existing = keygrips.filter { keychainStore.exists(account: $0) }
            guard !existing.isEmpty else {
                let prefixes = keygrips.map { String($0.prefix(12)) + "…" }.joined(separator: ", ")
                errorMessage = "No Keychain entry found for this key (looked under: \(prefixes)). Open Keychain Access, search “GnuPG”, and check whether an entry exists. If not, tick “Save in Keychain” next time you're prompted."
                return
            }

            var biometricCount = 0
            var fallbackCount = 0
            var lastFailure: KeychainPassphraseStore.MigrationResult?
            for grip in existing {
                switch keychainStore.migrateToBiometric(account: grip) {
                case .migrated:              biometricCount += 1
                case .savedWithoutBiometric: fallbackCount += 1
                case let other:              lastFailure = other
                }
            }
            if biometricCount + fallbackCount > 0 {
                keychainRevision &+= 1
            }

            let saved = biometricCount + fallbackCount
            if saved == existing.count, let failure = lastFailure {
                errorMessage = "Migrated \(saved) of \(existing.count) entries. \(failure.diagnostic). Check Console.app (filter “GPGManager Keychain”) for details."
            } else if biometricCount == existing.count {
                statusMessage = "Touch ID enabled for \(key.primaryUserID)."
                errorMessage = nil
            } else if fallbackCount > 0 {
                statusMessage = "Saved passphrase for \(key.primaryUserID) (\(saved) of \(existing.count) entries). Touch ID couldn't be enabled — this is normal in debug builds since the helper is ad-hoc signed. gpg-agent will still use the Keychain entry."
                errorMessage = nil
            } else if let failure = lastFailure {
                errorMessage = "Couldn't migrate entries. \(failure.diagnostic). Check Console.app (filter “GPGManager Keychain”) for details."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDefaultKey(_ key: GPGKey) {
        gpgConfig.defaultKey = key.keyID
        saveGPGConfig()
        statusMessage = "Default key set to \(key.primaryUserID)."
    }

    /// Permanently removes a key (secret + public) from the local keyring and
    /// any associated Keychain passphrase entries. Past commits signed with the
    /// key remain verifiable on systems that have the public key, but new
    /// signing operations are no longer possible without restoring a backup.
    func deleteKey(_ key: GPGKey) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }
        let keygrips = (try? await keyService.fetchAllKeygrips(
            gpgPath: selectedGPGPath,
            fingerprint: key.fingerprint
        )) ?? []
        do {
            if key.keyClass == .secret {
                try await keyService.deleteSecretAndPublicKey(gpgPath: selectedGPGPath, fingerprint: key.fingerprint)
            } else {
                try await keyService.deletePublicKey(gpgPath: selectedGPGPath, fingerprint: key.fingerprint)
            }
            for grip in keygrips {
                keychainStore.deletePassphrase(account: grip)
            }
            if gpgConfig.defaultKey == key.keyID || gpgConfig.defaultKey == key.fingerprint {
                gpgConfig.defaultKey = nil
                saveGPGConfig()
            }
            statusMessage = "Deleted \(key.primaryUserID)."
            errorMessage = nil
            await refreshKeys()
        } catch {
            errorMessage = error.localizedDescription
            await refreshKeys()
        }
    }

    /// Adds a new user ID, makes it the primary, and optionally revokes the old
    /// primary UID. GPG doesn't support in-place UID edits — this is the
    /// idiomatic equivalent. Throws on failure so callers can surface the
    /// specific error instead of relying on `errorMessage` (which gets cleared
    /// when `refreshKeys` runs successfully on the next bootstrap).
    func updateUserID(_ key: GPGKey, parts: GPGKey.UserIDParts, revokePrevious: Bool) async throws {
        guard !selectedGPGPath.isEmpty else {
            throw GPGServiceError.commandFailed("No GPG executable selected.")
        }
        let newUserID = parts.formatted
        let oldUserID = key.primaryUserID
        let alreadyExists = key.userIDs.contains { $0 == newUserID }
        do {
            // Only add the UID if it's not already on the key. Re-adding fails
            // with "already exists"; we want to allow flipping primary among
            // existing UIDs too.
            if !alreadyExists {
                try await keyService.addUserID(gpgPath: selectedGPGPath, fingerprint: key.fingerprint, userID: newUserID)
            }
            try await keyService.setPrimaryUserID(gpgPath: selectedGPGPath, fingerprint: key.fingerprint, userID: newUserID)
            if revokePrevious, oldUserID != newUserID, !oldUserID.isEmpty,
               oldUserID != "(No user ID)" {
                try await keyService.revokeUserID(gpgPath: selectedGPGPath, fingerprint: key.fingerprint, userID: oldUserID)
            }
            statusMessage = alreadyExists
                ? "Switched primary user ID on \(key.shortFingerprint)."
                : "Updated user ID on \(key.shortFingerprint)."
            errorMessage = nil
            await refreshKeys()
        } catch {
            errorMessage = error.localizedDescription
            appStateLog.error("updateUserID failed for \(key.fingerprint, privacy: .public) -> \(newUserID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func restartAgent() async {
        guard !selectedGPGPath.isEmpty else { return }

        do {
            try await agentService.restart(gpgPath: selectedGPGPath)
            statusMessage = "Restarted gpg-agent."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSelectedPath() {
        UserDefaults.standard.set(selectedGPGPath, forKey: Self.selectedPathKey)
    }

    /// Builds a friendly Keychain entry label in the same shape pinentry-mac uses:
    /// `"Name [(Comment)] <Email> (KEYID)"`. Becomes the entry's display Name in
    /// Keychain Access, instead of the generic "GnuPG" service name fallback.
    private func keychainLabel(for parameters: GPGCreateKeyParameters, fingerprint: String) -> String {
        let name = parameters.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = parameters.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = parameters.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyID = String(fingerprint.suffix(16))
        let uid: String
        if comment.isEmpty {
            uid = "\(name) <\(email)>"
        } else {
            uid = "\(name) (\(comment)) <\(email)>"
        }
        return keyID.isEmpty ? uid : "\(uid) (\(keyID))"
    }
}
