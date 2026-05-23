import SwiftUI

struct ContentView: View {
    @Environment(GPGAppState.self) private var state
    @State private var showCreateKey = false
    @State private var showImporter = false

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            List(GPGAppState.Section.allCases, selection: $state.selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .labelStyle(.largeIcon(size: 20))
                    .padding(.vertical, 2)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch state.selectedSection {
                    case .overview:
                        OverviewView()
                    case .signing:
                        SigningView()
                    }
                }
                StatusBarView()
            }
            .frame(minWidth: 900, minHeight: 620)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("New Key", systemImage: "key.fill") {
                    showCreateKey = true
                }
                .disabled(state.selectedGPGPath.isEmpty)
                .help("Generate a new OpenPGP key pair")

                Button("Import Key", systemImage: "square.and.arrow.down") {
                    showImporter = true
                }
                .help("Import a public or secret key from a file")

                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await state.refreshAll() }
                }
                .disabled(state.isRefreshing)
                .help("Rediscover GPG installations and reload keys (⌘R)")

                Button("Restart Agent", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await state.restartAgent() }
                }
                .disabled(state.selectedGPGPath.isEmpty)
                .help("Kill and restart gpg-agent (⇧⌘K)")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await state.importKey(from: url) }
            }
        }
        .sheet(isPresented: $showCreateKey) {
            CreateKeyView()
                .environment(state)
        }
    }
}

private struct StatusBarView: View {
    @Environment(GPGAppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(state.errorMessage ?? state.statusMessage)
                .lineLimit(1)
                .foregroundStyle(state.errorMessage == nil ? Color.secondary : Color.red)

            Spacer()

            Text(state.selectedGPGPath.isEmpty ? "No GPG selected" : state.selectedGPGPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview("Populated") {
    ContentView()
        .environment(GPGAppState.preview)
        .frame(width: 1000, height: 680)
}

#Preview("Empty") {
    ContentView()
        .environment(GPGAppState.previewEmpty)
        .frame(width: 1000, height: 680)
}
