import Foundation
import SwiftUI

// NOTE: Mirror of PinentryGPGManager/Prompt/PassphraseStrength.swift.
// The two targets are separate Swift modules so this lightweight utility
// is duplicated rather than shared via a framework. Keep both copies in
// sync when adjusting the scoring heuristic.

enum PassphraseStrength {
    /// Returns a 0–100 score for the given passphrase.
    /// Heuristic only — favors length and character variety; penalizes obvious weak inputs.
    static func score(_ passphrase: String) -> Int {
        guard !passphrase.isEmpty else { return 0 }

        let length = passphrase.count
        var score = min(length * 4, 50)

        if passphrase.contains(where: \.isUppercase) { score += 12 }
        if passphrase.contains(where: \.isLowercase) { score += 12 }
        if passphrase.contains(where: \.isNumber) { score += 12 }
        if passphrase.contains(where: isSymbol) { score += 12 }

        if length > 12 {
            score += min((length - 12) * 2, 10)
        }

        let lower = passphrase.lowercased()
        let weakNeedles = ["password", "passwd", "12345", "qwerty", "abc123", "admin", "letmein", "iloveyou"]
        if weakNeedles.contains(where: { lower.contains($0) }) {
            score = max(0, score - 30)
        }

        if Set(passphrase).count == 1 {
            score = max(0, score - 40)
        }

        return min(max(score, 0), 100)
    }

    private static func isSymbol(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber && !character.isWhitespace
    }
}

struct PassphraseStrengthBar: View {
    let passphrase: String
    let label: String?
    let tooltip: String?

    private var score: Int { PassphraseStrength.score(passphrase) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(score), total: 100)
                .progressViewStyle(.linear)
                .tint(strengthColor)
                .frame(maxWidth: .infinity)
        }
        .help(tooltip ?? "")
    }

    private var strengthColor: Color {
        switch score {
        case ..<25:  .red
        case ..<50:  .orange
        case ..<75:  .yellow
        default:     .green
        }
    }
}
