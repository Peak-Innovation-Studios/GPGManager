import SwiftUI

struct KeyDetailsPopover: View {
    let key: GPGKey

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(key.primaryUserID)
                .font(.headline)
                .lineLimit(2)

            detail("Fingerprint", key.fingerprint, monospaced: true)
            detail("Key ID", key.keyID, monospaced: true)
            detail("Algorithm", key.algorithm.displayName)
            if let advice = key.algorithm.advice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(advice)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            detail("Capabilities", expandedCapabilities)
            detail("Trust", expandedTrust)
            detail("Created", key.createdAt?.formatted(date: .complete, time: .omitted) ?? "Unknown")
            detail("Expires", key.expiresAt?.formatted(date: .complete, time: .omitted) ?? "Never")

            if key.userIDs.count > 1 {
                Divider()
                Text("Additional User IDs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(key.userIDs.dropFirst(), id: \.self) { uid in
                    Text(uid)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
    }

    private var expandedCapabilities: String {
        guard !key.capabilities.isEmpty else { return "—" }
        let mapped = key.capabilities.compactMap { capabilityName(for: $0) }
        return mapped.isEmpty ? key.capabilities : mapped.joined(separator: ", ")
    }

    private func capabilityName(for char: Character) -> String? {
        switch char {
        case "s", "S": "Sign"
        case "c", "C": "Certify"
        case "e", "E": "Encrypt"
        case "a", "A": "Authenticate"
        default: nil
        }
    }

    private var expandedTrust: String {
        switch key.trust {
        case "u": "Ultimate"
        case "f": "Full"
        case "m": "Marginal"
        case "n": "Never"
        case "q": "Unknown"
        case "r": "Revoked"
        case "e": "Expired"
        case "-", "": "Unknown"
        default:  key.trust
        }
    }

    private func detail(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
