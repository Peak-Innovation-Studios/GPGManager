import Foundation

@MainActor
extension GPGAppState {
    /// Public keys with no matching secret key — safe to delete without affecting signing.
    var publicOnlyKeys: [GPGKey] {
        keys.filter { $0.keyClass == .public }
    }

    /// Deletes the given public keys via `gpg --delete-keys`. Reports a status summary
    /// on completion and refreshes the keys list.
    func deletePublicKeys(_ fingerprints: [String]) async {
        guard !selectedGPGPath.isEmpty else {
            errorMessage = "No GPG executable selected."
            return
        }

        var deleted = 0
        var failures: [String] = []
        for fingerprint in fingerprints {
            do {
                try await keyService.deletePublicKey(gpgPath: selectedGPGPath, fingerprint: fingerprint)
                deleted += 1
            } catch {
                failures.append("\(GPGKey.shortened(fingerprint: fingerprint)): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            statusMessage = "Removed \(deleted) public key\(deleted == 1 ? "" : "s")."
            errorMessage = nil
        } else {
            statusMessage = "Removed \(deleted) of \(fingerprints.count) public keys."
            errorMessage = failures.joined(separator: "\n")
        }

        await refreshKeys()
    }
}

private extension GPGKey {
    static func shortened(fingerprint: String) -> String {
        guard fingerprint.count > 16 else { return fingerprint }
        return String(fingerprint.suffix(16))
    }
}
