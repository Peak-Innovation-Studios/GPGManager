import SwiftUI
import UniformTypeIdentifiers

struct PublicKeysView: View {
    @Environment(GPGAppState.self) private var state
    @State private var showImporter = false

    private var visibleKeys: [GPGKey] {
        state.publicOnlyKeys
    }

    var body: some View {
        @Bindable var state = state

        HSplitView {
            Table(visibleKeys, selection: $state.selectedKeyID) {
                TableColumn("User ID") { key in
                    PublicKeyCell(key: key)
                }
                TableColumn("Key ID") { key in
                    Text(key.keyID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .width(180)
                TableColumn("Expires") { key in
                    Text(formatDate(key.expiresAt))
                        .foregroundStyle(key.expiresAt == nil ? .secondary : .primary)
                }
                .width(140)
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minWidth: 560)

            PublicKeyDetailView(key: state.selectedPublicKey)
                .frame(minWidth: 280, idealWidth: 340)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await state.importKey(from: url) }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import Key", systemImage: "square.and.arrow.down") {
                    showImporter = true
                }
                .help("Import a public key from a file")

                Button("Copy Public Key", systemImage: "doc.on.doc") {
                    if let key = state.selectedPublicKey {
                        Task { await state.copyPublicKeyToPasteboard(key) }
                    }
                }
                .disabled(state.selectedPublicKey == nil)
                .help("Copy the selected key's armored public block to the clipboard")
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension GPGAppState {
    var selectedPublicKey: GPGKey? {
        guard let id = selectedKeyID else { return nil }
        return publicOnlyKeys.first { $0.id == id }
    }
}

private struct PublicKeyCell: View {
    let key: GPGKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.primaryUserID)
                .lineLimit(1)
            Text(key.shortFingerprint)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct PublicKeyDetailView: View {
    let key: GPGKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let key {
                Text(key.primaryUserID)
                    .font(.title3)
                    .bold()
                    .lineLimit(3)

                detail("Fingerprint", key.fingerprint)
                detail("Key ID", key.keyID)
                detail("Algorithm", key.algorithm.displayName)
                detail("Capabilities", key.capabilities.isEmpty ? "-" : key.capabilities)
                detail("Trust", key.trust.isEmpty ? "-" : key.trust)
                detail("Created", key.createdAt?.formatted(date: .complete, time: .omitted) ?? "-")
                detail("Expires", key.expiresAt?.formatted(date: .complete, time: .omitted) ?? "Never")

                if key.userIDs.count > 1 {
                    Divider()
                    Text("User IDs")
                        .font(.headline)
                    ForEach(key.userIDs, id: \.self) { uid in
                        Text(uid)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Key Selected",
                    systemImage: "key",
                    description: Text("Select a public key to inspect its metadata.")
                )
            }

            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

#Preview {
    PublicKeysView()
        .environment(GPGAppState.preview)
        .frame(width: 900, height: 600)
}
