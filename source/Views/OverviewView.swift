import SwiftUI

struct OverviewView: View {
    @Environment(GPGAppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    private var hasPublicKeys: Bool {
        !state.publicOnlyKeys.isEmpty
    }

    var body: some View {
        if state.installations.isEmpty {
            GPGNotInstalledView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(
                        title: "GPG Manager",
                        subtitle: "Local GPG keys, agent settings, and signing configuration."
                    )

                    HStack(alignment: .top, spacing: 18) {
                        InstallationPanel()
                        SetupPanel()
                    }

                    MyKeysPanel()

                    HStack {
                        Spacer()
                        Button("View Public Keys…", systemImage: "list.bullet.rectangle") {
                            openWindow(id: "public-keys")
                        }
                        .disabled(!hasPublicKeys)
                        .help(hasPublicKeys
                              ? "Browse downloaded public keys"
                              : "No public keys downloaded yet")
                    }
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct InstallationPanel: View {
    @Environment(GPGAppState.self) private var state

    private var current: GPGInstallation? { state.selectedInstallation }

    var body: some View {
        GroupBox {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current?.kind.rawValue ?? "Not selected")
                        .font(.headline)
                    Text(current?.path ?? "—")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let version = current?.version {
                        Text(version)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                changeMenu
            }
            .padding(8)
        } label: {
            Label("GPG Executable", systemImage: "terminal")
                .labelStyle(.largeIcon)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var changeMenu: some View {
        Menu("Change") {
            ForEach(state.installations) { installation in
                Button {
                    Task { await state.selectGPGPath(installation.path) }
                } label: {
                    Text("\(installation.kind.rawValue) — \(installation.path)")
                }
            }
            Divider()
            Button("Choose Custom Executable…") {
                Task { await state.chooseCustomGPGPath() }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct HeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle)
                .bold()
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Populated") {
    OverviewView()
        .environment(GPGAppState.preview)
        .frame(width: 900, height: 620)
}

#Preview("Empty") {
    OverviewView()
        .environment(GPGAppState.previewEmpty)
        .frame(width: 900, height: 620)
}
