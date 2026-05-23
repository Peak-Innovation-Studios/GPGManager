import Foundation

struct GPGKeyService {
    private let runner = GPGCommandRunner()
    private let parser = GPGKeyParser()

    func listKeys(gpgPath: String) async throws -> [GPGKey] {
        // Run sequentially. Concurrent gpg invocations can race on the gpg-agent
        // / keyboxd socket in 2.5.x, causing --list-secret-keys to silently
        // return empty while --list-keys succeeds.
        let publicOutput = try await runner.run(
            executablePath: gpgPath,
            arguments: ["--batch", "--with-colons", "--fingerprint", "--list-keys"]
        )
        if !publicOutput.succeeded {
            throw GPGServiceError.commandFailed(publicOutput.stderr.isEmpty ? publicOutput.stdout : publicOutput.stderr)
        }

        let secretOutput = try await runner.run(
            executablePath: gpgPath,
            arguments: ["--batch", "--with-colons", "--fingerprint", "--list-secret-keys"]
        )
        guard secretOutput.succeeded else {
            let message = secretOutput.stderr.isEmpty ? secretOutput.stdout : secretOutput.stderr
            throw GPGServiceError.commandFailed(
                "Couldn't list secret keys: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        let secretFingerprints = parser.parseSecretFingerprints(secretOutput.stdout)
        return parser.parsePublicKeys(publicOutput.stdout, secretFingerprints: secretFingerprints)
    }

    func importKey(gpgPath: String, fileURL: URL) async throws -> String {
        let result = try await runner.run(executablePath: gpgPath, arguments: ["--import", fileURL.path])
        guard result.succeeded else {
            throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stderr.isEmpty ? result.stdout : result.stderr
    }

    /// Removes a public key from the keyring. `gpg --delete-keys` refuses if a
    /// corresponding secret key exists — that protects us if a caller miscategorizes.
    func deletePublicKey(gpgPath: String, fingerprint: String) async throws {
        let result = try await runner.run(
            executablePath: gpgPath,
            arguments: ["--batch", "--yes", "--delete-keys", fingerprint]
        )
        guard result.succeeded else {
            throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    func exportPublicKey(gpgPath: String, fingerprint: String) async throws -> String {
        let result = try await runner.run(executablePath: gpgPath, arguments: ["--armor", "--export", fingerprint])
        guard result.succeeded else {
            throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }

    func createKey(gpgPath: String, parameters: GPGCreateKeyParameters) async throws -> GPGCreateKeyResult {
        let script = parameters.renderBatchScript()
        let result = try await runner.run(
            executablePath: gpgPath,
            arguments: ["--batch", "--pinentry-mode", "loopback", "--gen-key"],
            standardInput: script
        )
        guard result.succeeded else {
            throw GPGServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        let log = result.stderr.isEmpty ? result.stdout : result.stderr
        return GPGCreateKeyResult(fingerprint: extractFingerprint(from: log), output: log)
    }

    /// Looks up the primary keygrip for a known fingerprint.
    /// Used right after key creation to populate the macOS Keychain.
    func fetchPrimaryKeygrip(gpgPath: String, fingerprint: String) async throws -> String? {
        let result = try await runner.run(
            executablePath: gpgPath,
            arguments: ["--batch", "--with-colons", "--with-keygrip", "--list-secret-keys", fingerprint]
        )
        guard result.succeeded else { return nil }
        return parser.parsePrimaryKeygrip(result.stdout)
    }

    /// gpg --batch --gen-key writes the path to the revocation cert into stderr,
    /// e.g. "openpgp-revocs.d/<FINGERPRINT>.rev". Pull the fingerprint from there.
    private func extractFingerprint(from log: String) -> String? {
        guard let range = log.range(of: "openpgp-revocs.d/") else { return nil }
        let after = log[range.upperBound...]
        let fingerprintScalars = after.prefix(while: { $0.isHexDigit })
        let fingerprint = String(fingerprintScalars)
        return fingerprint.count >= 40 ? String(fingerprint.prefix(40)) : nil
    }
}

struct GPGCreateKeyResult {
    let fingerprint: String?
    let output: String
}

enum GPGServiceError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "GPG command failed." : message
        }
    }
}
