import SwiftUI

/// Parses gpg's free-form SETDESC / key-info text into the structured pieces
/// the header and the "Details" popover render. Members used by the view's
/// `header` (in PassphraseView.swift) are `internal`; the parsing internals
/// stay `private` to this file.
extension PassphraseView {
    /// First quoted substring from the description (typically the
    /// OpenPGP user-id: "Name (Comment) <email>").
    private var parsedUserID: String? {
        guard let description = request.description else { return nil }
        if let match = description.firstMatch(of: /"([^"]+)"/) {
            return String(match.1)
        }
        return nil
    }

    private struct ParsedKeyMetadata {
        let bitLength: String
        let algorithm: String
        let fullKeyID: String
        let createdDate: String

        var shortKeyID: String {
            fullKeyID.count > 8 ? String(fullKeyID.prefix(8)) : fullKeyID
        }
    }

    private var parsedKeyMetadata: ParsedKeyMetadata? {
        guard let description = request.description else { return nil }
        let pattern = /(\d+)-bit (\w+) key, ID ([0-9A-Fa-f]+),\s*created (\d{4}-\d{2}-\d{2})/
        if let match = description.firstMatch(of: pattern) {
            return ParsedKeyMetadata(
                bitLength: String(match.1),
                algorithm: String(match.2),
                fullKeyID: String(match.3),
                createdDate: String(match.4)
            )
        }
        return nil
    }

    /// gpg's algorithm/ID/created summary, compacted. Long key ID is
    /// truncated to the first 8 hex chars (the short ID developers
    /// actually recognize); full fingerprint stays in Details.
    var parsedMetadata: String? {
        guard let m = parsedKeyMetadata else { return nil }
        return "\(m.algorithm) · ID \(m.shortKeyID) · created \(m.createdDate)"
    }

    /// Falls back to the first meaningful line of description when no
    /// user-id was quoted (covers SETDESC text that doesn't follow
    /// gpg's standard unlock template).
    var primaryDetailLine: String? {
        if let userID = parsedUserID { return userID }
        guard let description = request.description, !description.isEmpty else { return nil }
        for line in description.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("please enter") { continue }
            if lower.hasPrefix("enter ") { continue }
            return trimmed
        }
        return description
    }

    var hasDetails: Bool {
        let hasFullDescription = (request.description?.isEmpty == false)
        let hasKeyInfo = (request.keyInfo?.isEmpty == false)
        return hasFullDescription || hasKeyInfo
    }

    @ViewBuilder
    var detailsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = parsedKeyMetadata {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    detailRow(label: "Algorithm", value: "\(m.bitLength)-bit \(m.algorithm)")
                    detailRow(label: "Key ID", value: m.fullKeyID, monospaced: true)
                    detailRow(label: "Created", value: m.createdDate)
                }
            } else if let description = request.description, !description.isEmpty {
                // Parse failed — show the raw SETDESC with the prompt
                // preamble and the user-id quote line filtered out (both
                // duplicated by the header).
                let filtered = filteredFallbackDescription(description)
                if !filtered.isEmpty {
                    Text(filtered)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let keyInfo = request.keyInfo, !keyInfo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keygrip")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(keyInfo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func filteredFallbackDescription(_ description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return nil }
                let lower = trimmed.lowercased()
                if lower.hasPrefix("please enter") { return nil }
                if lower.hasPrefix("enter ") { return nil }
                if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") { return nil }
                return trimmed
            }
            .joined(separator: "\n")
    }

    var accessibilityHeaderLabel: Text {
        var components = [request.effectiveTitle]
        if let primary = primaryDetailLine { components.append(primary) }
        if let metadata = parsedMetadata { components.append(metadata) }
        return Text(components.joined(separator: ". "))
    }
}
