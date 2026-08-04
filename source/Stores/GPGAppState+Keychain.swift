import Foundation

@MainActor
extension GPGAppState {
    /// Synchronous check whether the local Keychain has a passphrase entry for
    /// this key's primary keygrip. Used to hide the "Enable Touch ID" button
    /// once the entry has been migrated/created.
    func hasKeychainEntry(for key: GPGKey) -> Bool {
        _ = keychainRevision // Observe so views re-evaluate on Keychain writes.
        guard let grip = key.primaryKeygrip, !grip.isEmpty else { return false }
        return keychainStore.exists(account: grip)
    }

    /// Reads the saved passphrase for this key's primary keygrip back out of
    /// the Keychain. Entries saved by this app carry a userPresence ACL, so the
    /// system shows a Touch ID / password prompt before releasing the value.
    /// `SecItemCopyMatching` blocks its thread while that prompt is up, so the
    /// read runs off the main actor to keep the UI responsive.
    /// Returns nil when the key has no keygrip, no entry exists, or the user
    /// cancels the authentication prompt.
    func revealPassphrase(for key: GPGKey) async -> String? {
        guard let grip = key.primaryKeygrip, !grip.isEmpty else { return nil }
        let store = keychainStore
        return await Task.detached { store.readPassphrase(account: grip) }.value
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
}
