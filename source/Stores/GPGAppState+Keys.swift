import AppKit
import Foundation

@MainActor
extension GPGAppState {
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
