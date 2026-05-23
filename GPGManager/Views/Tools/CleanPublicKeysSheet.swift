import SwiftUI

struct CleanPublicKeysSheet: View {
    @Environment(GPGAppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isWorking = false

    private var candidates: [GPGKey] { state.publicOnlyKeys }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            footer
        }
        .padding(20)
        .frame(width: 560, height: 480)
        .onAppear {
            selected = Set(candidates.map(\.fingerprint))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clean Downloaded Public Keys")
                .font(.title2).bold()
            Text("These public keys aren't yours. They were imported or auto-downloaded for signature verification. Removing them won't affect your ability to sign commits.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if candidates.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Your keyring is already clean.")
                    .font(.headline)
                Text("No public-only keys were found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            keyList
        }
    }

    private var keyList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(candidates) { key in
                    KeyRow(key: key, isSelected: binding(for: key.fingerprint))
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack {
            if !candidates.isEmpty {
                Button(selected.count == candidates.count ? "Deselect All" : "Select All") {
                    if selected.count == candidates.count {
                        selected.removeAll()
                    } else {
                        selected = Set(candidates.map(\.fingerprint))
                    }
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(role: .destructive) {
                Task { await performDelete() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text(deleteButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(selected.isEmpty || isWorking)
        }
    }

    private var deleteButtonTitle: String {
        let count = selected.count
        return "Delete \(count) Key\(count == 1 ? "" : "s")"
    }

    private func binding(for fingerprint: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(fingerprint) },
            set: { isOn in
                if isOn {
                    selected.insert(fingerprint)
                } else {
                    selected.remove(fingerprint)
                }
            }
        )
    }

    private func performDelete() async {
        isWorking = true
        await state.deletePublicKeys(Array(selected))
        isWorking = false
        dismiss()
    }
}

private struct KeyRow: View {
    let key: GPGKey
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.primaryUserID)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(key.shortFingerprint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let created = key.createdAt {
                    Text("Added \(created.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview {
    CleanPublicKeysSheet()
        .environment(GPGAppState.preview)
}
#endif
