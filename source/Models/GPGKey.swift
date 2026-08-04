import Foundation

struct GPGKey: Identifiable, Hashable {
    enum KeyClass: String {
        case `public` = "Public"
        case secret = "Secret"
    }

    let id: String
    var keyClass: KeyClass
    var keyID: String
    var fingerprint: String
    var userIDs: [String]
    var createdAt: Date?
    var expiresAt: Date?
    var capabilities: String
    var trust: String
    var algorithmCode: Int = 0
    var bitLength: Int = 0
    var curveName: String?
    var primaryKeygrip: String?
    var subkeyKeygrips: [String] = []

    /// Every keygrip the key owns, primary first. Keychain passphrase entries
    /// are stored per-keygrip, and pinentry saves under whichever subkey
    /// gpg-agent was unlocking — so lookups must consider all of them.
    var allKeygrips: [String] {
        var grips: [String] = []
        if let primaryKeygrip, !primaryKeygrip.isEmpty {
            grips.append(primaryKeygrip)
        }
        grips.append(contentsOf: subkeyKeygrips.filter { !$0.isEmpty })
        return grips
    }

    var algorithm: GPGKeyAlgorithm {
        GPGKeyAlgorithm(
            code: algorithmCode,
            bitLength: bitLength,
            curveName: (curveName?.isEmpty == false) ? curveName : nil
        )
    }

    var primaryUserID: String {
        userIDs.first ?? "(No user ID)"
    }

    var shortFingerprint: String {
        guard fingerprint.count > 16 else { return fingerprint }
        return String(fingerprint.suffix(16))
    }

    struct UserIDParts: Equatable {
        var name: String
        var comment: String
        var email: String

        /// Reconstructs the canonical UID string. Comment is parenthesized only when present.
        var formatted: String {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let trimmedComment = comment.trimmingCharacters(in: .whitespaces)
            let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
            if trimmedComment.isEmpty {
                return "\(trimmedName) <\(trimmedEmail)>"
            }
            return "\(trimmedName) (\(trimmedComment)) <\(trimmedEmail)>"
        }
    }

    /// Splits a `"Name (Comment) <Email>"` user-ID string into parts.
    /// Comment is optional; any missing field becomes the empty string.
    static func parseUserID(_ uid: String) -> UserIDParts {
        let trimmed = uid.trimmingCharacters(in: .whitespaces)
        var name = trimmed
        var comment = ""
        var email = ""

        if let openAngle = name.lastIndex(of: "<"),
           let closeAngle = name.lastIndex(of: ">"),
           openAngle < closeAngle {
            email = String(name[name.index(after: openAngle)..<closeAngle])
            name = String(name[..<openAngle]).trimmingCharacters(in: .whitespaces)
        }
        if let openParen = name.lastIndex(of: "("),
           let closeParen = name.lastIndex(of: ")"),
           openParen < closeParen {
            comment = String(name[name.index(after: openParen)..<closeParen])
            name = String(name[..<openParen]).trimmingCharacters(in: .whitespaces)
        }
        return UserIDParts(name: name, comment: comment, email: email)
    }

    /// Resolves a raw `user.signingkey` value (full fingerprint, long key ID,
    /// short suffix, or 0x-prefixed) to a known key.
    static func match(signingKey rawValue: String?, in keys: [GPGKey]) -> GPGKey? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let normalized = rawValue
            .uppercased()
            .replacingOccurrences(of: "0X", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard !normalized.isEmpty else { return nil }

        if let exact = keys.first(where: { $0.fingerprint.uppercased() == normalized }) {
            return exact
        }
        if let byID = keys.first(where: { $0.keyID.uppercased() == normalized }) {
            return byID
        }
        if normalized.count >= 8,
           let suffix = keys.first(where: { $0.fingerprint.uppercased().hasSuffix(normalized) }) {
            return suffix
        }
        return nil
    }
}
