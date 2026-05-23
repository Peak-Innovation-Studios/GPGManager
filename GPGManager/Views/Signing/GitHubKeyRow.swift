import SwiftUI

struct GitHubKeyRow: View {
    let registered: GitHubRegisteredKey
    let match: GPGKey?
    let defaultKey: GPGKey?
    let onDelete: () -> Void
    let onReplace: (GPGKey) -> Void
    let onRefresh: (GPGKey) -> Void
    let onRename: (GPGKey) -> Void

    /// GitHub's stored `name` if present, otherwise the primary email
    /// (every registered key has at least one), otherwise the key ID.
    private var primaryLabel: String {
        if let name = registered.name, !name.isEmpty { return name }
        if let email = registered.primaryEmail, !email.isEmpty { return email }
        return registered.keyID
    }

    /// GitHub thinks the key is expired, but our local copy isn't —
    /// this is the case a Refresh fixes.
    private var isStale: Bool {
        guard let match else { return false }
        guard registered.isExpired else { return false }
        let localExpired = match.expiresAt.map { $0 < Date() } ?? false
        return !localExpired
    }

    private var status: (icon: String, color: Color, text: String) {
        if isStale, let match {
            return ("arrow.triangle.2.circlepath", .orange,
                    "Stale — local \(match.primaryUserID) is valid; GitHub copy expired")
        }
        if registered.isExpired {
            return ("exclamationmark.triangle.fill", .orange, "Expired on GitHub")
        }
        if let match {
            return ("checkmark.circle.fill", .green, "Matches local: \(match.primaryUserID)")
        }
        return ("circle.dashed", .secondary, "No matching local secret key")
    }

    private var canRefresh: Bool { isStale && match != nil }

    private var canReplace: Bool {
        guard let defaultKey else { return false }
        if isStale { return false }
        if registered.isExpired { return true }
        return !registered.matches(keyID: defaultKey.keyID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(.headline)
                        .lineLimit(1)
                    if let email = registered.primaryEmail, registered.name != nil {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                actions
            }
            Text(status.text)
                .font(.caption)
                .foregroundStyle(.secondary)
            metadataLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if let match {
                Button("Rename…") { onRename(match) }
                    .controlSize(.small)
                    .help("Set the display name shown on GitHub")
            }
            if canRefresh, let match {
                Button("Refresh…") { onRefresh(match) }
                    .controlSize(.small)
                    .help("Re-upload the current local copy of this key")
            }
            if canReplace, let defaultKey {
                Button("Replace…") { onReplace(defaultKey) }
                    .controlSize(.small)
                    .help("Upload current default key, then remove this one")
            }
            Button(role: .destructive) { onDelete() } label: {
                Text("Delete…")
            }
            .controlSize(.small)
        }
    }

    private var metadataLine: some View {
        let added = registered.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
        let expires: String
        if let date = registered.expiresAt {
            expires = registered.isExpired
                ? "Expired \(date.formatted(date: .abbreviated, time: .omitted))"
                : "Expires \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            expires = "Never expires"
        }
        return Text("\(registered.keyID) · Added \(added) · \(expires)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
