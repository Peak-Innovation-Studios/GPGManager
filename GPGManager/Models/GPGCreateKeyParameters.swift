import Foundation

struct GPGCreateKeyParameters: Equatable {
    enum Algorithm: String, CaseIterable, Identifiable {
        case ecc     = "ECC (ed25519 + cv25519)"
        case rsa4096 = "RSA 4096"
        case rsa3072 = "RSA 3072"

        var id: String { rawValue }

        var primaryType: String {
            switch self {
            case .rsa4096, .rsa3072: "RSA"
            case .ecc:               "EDDSA"
            }
        }

        var primaryParameterLine: String {
            switch self {
            case .rsa4096: "Key-Length: 4096"
            case .rsa3072: "Key-Length: 3072"
            case .ecc:     "Key-Curve: ed25519"
            }
        }

        var subkeyType: String {
            switch self {
            case .rsa4096, .rsa3072: "RSA"
            case .ecc:               "ECDH"
            }
        }

        var subkeyParameterLine: String {
            switch self {
            case .rsa4096: "Subkey-Length: 4096"
            case .rsa3072: "Subkey-Length: 3072"
            case .ecc:     "Subkey-Curve: cv25519"
            }
        }
    }

    enum Expiration: String, CaseIterable, Identifiable {
        case oneYear   = "1 year"
        case twoYears  = "2 years"
        case fiveYears = "5 years"
        case never     = "Never"

        var id: String { rawValue }

        var gpgValue: String {
            switch self {
            case .oneYear:   "1y"
            case .twoYears:  "2y"
            case .fiveYears: "5y"
            case .never:     "0"
            }
        }
    }

    var name: String = ""
    var email: String = ""
    var comment: String = ""
    var algorithm: Algorithm = .ecc
    var expiration: Expiration = .oneYear
    var passphrase: String = ""

    var isValid: Bool {
        !trimmed(name).isEmpty &&
        looksLikeEmail(trimmed(email)) &&
        !passphrase.isEmpty
    }

    /// Renders to gpg's `--gen-key` batch format. The passphrase is passed
    /// inline so we never need to write a temp file to disk.
    func renderBatchScript() -> String {
        var lines: [String] = []
        lines.append("%echo Generating key…")
        lines.append("Key-Type: \(algorithm.primaryType)")
        lines.append(algorithm.primaryParameterLine)
        lines.append("Key-Usage: sign,cert")
        lines.append("Subkey-Type: \(algorithm.subkeyType)")
        lines.append(algorithm.subkeyParameterLine)
        lines.append("Subkey-Usage: encrypt")
        lines.append("Name-Real: \(trimmed(name))")
        let trimmedComment = trimmed(comment)
        if !trimmedComment.isEmpty {
            lines.append("Name-Comment: \(trimmedComment)")
        }
        lines.append("Name-Email: \(trimmed(email))")
        lines.append("Expire-Date: \(expiration.gpgValue)")
        lines.append("Passphrase: \(passphrase)")
        lines.append("%commit")
        lines.append("%echo Done.")
        return lines.joined(separator: "\n") + "\n"
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeEmail(_ value: String) -> Bool {
        guard let atIndex = value.firstIndex(of: "@") else { return false }
        let local = value[..<atIndex]
        let domain = value[value.index(after: atIndex)...]
        return !local.isEmpty && domain.contains(".")
    }
}
