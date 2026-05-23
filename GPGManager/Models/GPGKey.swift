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

    var primaryUserID: String {
        userIDs.first ?? "(No user ID)"
    }

    var shortFingerprint: String {
        guard fingerprint.count > 16 else { return fingerprint }
        return String(fingerprint.suffix(16))
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
