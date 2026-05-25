import Foundation

/// A GPG key registered against the authenticated GitHub account, as returned by
/// the `gh api user/gpg_keys` endpoint.
struct GitHubRegisteredKey: Identifiable, Equatable, Hashable {
    /// GitHub's internal numeric ID — required for DELETE.
    let id: Int
    /// 16-char hex key ID of the primary key.
    let keyID: String
    let name: String?
    let emails: [String]
    let createdAt: Date?
    let expiresAt: Date?
    let subkeyIDs: [String]

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    var primaryEmail: String? { emails.first }

    /// Returns true if `lookup` matches the primary key or any subkey ID.
    func matches(keyID lookup: String) -> Bool {
        let normalized = lookup.uppercased()
        if keyID.uppercased() == normalized { return true }
        return subkeyIDs.contains { $0.uppercased() == normalized }
    }
}
