import SwiftUI

struct EditUserIDSheet: View {
    @Environment(GPGAppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let key: GPGKey
    @State private var parts: GPGKey.UserIDParts
    @State private var revokePrevious: Bool = true
    @State private var isSaving = false
    @State private var localError: String?

    init(key: GPGKey) {
        self.key = key
        _parts = State(initialValue: GPGKey.parseUserID(key.primaryUserID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section {
                    TextField("Name", text: $parts.name)
                    TextField("Email", text: $parts.email)
                        .textContentType(.emailAddress)
                    TextField("Comment (optional)", text: $parts.comment)
                } header: {
                    Text("New User ID")
                } footer: {
                    Text("Current: \(key.primaryUserID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Revoke the previous User ID", isOn: $revokePrevious)
                        .help("Marks the old UID as revoked so it's no longer offered as an identity for this key.")
                } footer: {
                    Text(revokePreviousFooter)
                }

                if let localError {
                    Section {
                        Text(localError)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .disabled(isSaving)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit User ID")
                    .font(.headline)
                Text("Adds a new identity to the key and makes it the primary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                Text("Updating…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(16)
    }

    private var canSave: Bool {
        let trimmedName = parts.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = parts.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty, trimmedEmail.contains("@") else { return false }
        return parts != GPGKey.parseUserID(key.primaryUserID) && !isSaving
    }

    private var revokePreviousFooter: String {
        if revokePrevious {
            return "Old UID stays on the key but is flagged as revoked. GitHub and keyservers will show it as such."
        }
        return "Old UID remains valid and visible. You'll have two active identities on the same key."
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await state.updateUserID(key, parts: parts, revokePrevious: revokePrevious)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    EditUserIDSheet(key: GPGAppState.preview.secretKeys.first!)
        .environment(GPGAppState.preview)
}
#endif
