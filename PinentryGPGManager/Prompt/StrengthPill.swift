import SwiftUI

/// Compact strength indicator that lives inside the SecureField's row,
/// so revealing it doesn't push other content down (the pinentry host
/// window doesn't auto-resize on SwiftUI content growth).
struct StrengthPill: View {
    let passphrase: String
    let tooltip: String?

    private var score: Int { PassphraseStrength.score(passphrase) }
    private var bucket: String { PassphraseStrength.bucketLabel(forScore: score) }
    private var color: Color {
        switch score {
        case ..<25:  .red
        case ..<50:  .orange
        case ..<75:  .yellow
        default:     .green
        }
    }

    var body: some View {
        Text(bucket)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: .capsule)
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
            .help(tooltip ?? "Passphrase strength: \(bucket)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Passphrase strength: \(bucket)"))
            // Animate bucket boundary crossings so color/label settle smoothly.
            .animation(.easeInOut(duration: 0.15), value: bucket)
    }
}
