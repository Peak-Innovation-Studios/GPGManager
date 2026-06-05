import SwiftUI

/// Sheet for renaming a GitHub-registered key. GitHub has no rename endpoint,
/// so saving deletes and re-uploads the key under the new name (see
/// `GPGAppState.renameGitHubKey`).
struct RenameSheet: View {
    let pending: PendingKeyAction
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename GitHub key")
                .font(.headline)
            Text("GitHub doesn't allow editing the name directly, so this will delete and re-upload the key with the new name. Past commits keep their Verified badge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            name = pending.remote.name ?? pending.remote.primaryEmail ?? ""
        }
    }
}
