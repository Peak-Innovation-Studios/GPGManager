import AppKit
import SwiftUI

/// Shows the Keychain-saved passphrase for a key. The read itself is gated by
/// the entry's userPresence ACL, so the system prompts for Touch ID / password
/// before anything is displayed. The value stays masked until the user
/// explicitly reveals it, and copying marks the pasteboard as concealed so
/// clipboard managers skip it.
struct RevealPassphraseSheet: View {
    @Environment(GPGAppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let key: GPGKey

    private enum LoadState {
        case loading
        case loaded(String)
        case unavailable
    }

    @State private var loadState: LoadState = .loading
    @State private var isVisible = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Passphrase for \(key.primaryUserID)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            switch loadState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for Keychain approval…")
                        .foregroundStyle(.secondary)
                }
            case .loaded(let passphrase):
                PassphraseRow(
                    passphrase: passphrase,
                    isVisible: $isVisible,
                    didCopy: $didCopy
                )
            case .unavailable:
                Text("The passphrase couldn't be read from the Keychain. The request may have been cancelled, or no entry exists for this key.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task {
            if let passphrase = await state.revealPassphrase(for: key) {
                loadState = .loaded(passphrase)
            } else {
                loadState = .unavailable
            }
        }
    }
}

private struct PassphraseRow: View {
    let passphrase: String
    @Binding var isVisible: Bool
    @Binding var didCopy: Bool

    var body: some View {
        HStack(spacing: 6) {
            maskedText
                .font(.body.monospaced())
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: .rect(cornerRadius: 6))

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isVisible ? "Hide passphrase" : "Show passphrase")

            Button {
                copyToPasteboard()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy passphrase")
        }
    }

    @ViewBuilder
    private var maskedText: some View {
        if isVisible {
            Text(passphrase)
                .textSelection(.enabled)
        } else {
            Text(String(repeating: "•", count: max(8, passphrase.count)))
        }
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // org.nspasteboard.ConcealedType tells clipboard managers this is a
        // secret they should not record.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString(passphrase, forType: .string)
        pasteboard.setString("", forType: concealed)
        didCopy = true
    }
}

#if DEBUG
#Preview {
    RevealPassphraseSheet(key: GPGAppState.preview.secretKeys[0])
        .environment(GPGAppState.preview)
}
#endif
