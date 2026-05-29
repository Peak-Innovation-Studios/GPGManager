import AppKit
import SwiftUI

struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            markdown(text)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        markdown(item)
                    }
                }
            }

        case .steps(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        markdown(item)
                    }
                }
            }

        case .code(let snippet, let caption):
            CodeBlock(snippet: snippet, caption: caption)

        case .tip(let text):
            CalloutBlock(icon: "lightbulb", tint: .yellow, label: "Tip", text: text)

        case .note(let text):
            CalloutBlock(icon: "info.circle", tint: .accentColor, label: "Note", text: text)

        case .warning(let text):
            CalloutBlock(icon: "exclamationmark.triangle", tint: .orange, label: "Heads up", text: text)

        case .keyValue(let pairs):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(pair.0)
                            .bold()
                            .frame(width: 160, alignment: .leading)
                        markdown(pair.1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func markdown(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct CodeBlock: View {
    let snippet: String
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(snippet)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
            .padding(12)
            .background(.quaternary, in: .rect(cornerRadius: 8))

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalloutBlock: View {
    let icon: String
    let tint: Color
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.body.weight(.semibold))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(LocalizedStringKey(text))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HelpBlockView(block: .paragraph("A short **paragraph** with *Markdown* and a `code` span."))
            HelpBlockView(block: .bullets(["First bullet", "Second bullet"]))
            HelpBlockView(block: .steps(["Step one", "Step two", "Step three"]))
            HelpBlockView(block: .code("brew install gnupg", caption: "Run in Terminal"))
            HelpBlockView(block: .tip("Touch ID makes signing one fingerprint instead of one passphrase."))
            HelpBlockView(block: .note("Settings → Passphrase controls the pinentry program."))
            HelpBlockView(block: .warning("Don't lose your passphrase."))
            HelpBlockView(block: .keyValue([("Algorithm", "Ed25519 recommended"), ("Expires", "2 years default")]))
        }
        .padding(24)
    }
    .frame(width: 600, height: 700)
}
#endif
