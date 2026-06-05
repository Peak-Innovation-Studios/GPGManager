import AppKit
import SwiftUI

/// Shown when `gh` lacks the `admin:gpg_key` scope: surfaces the exact command
/// the user needs to run, with a one-click copy button.
struct ScopeRequiredView: View {
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.orange)
                Text("Grant GitHub GPG-keys access:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(command)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
                    .textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }
}
