import SwiftUI
import AppKit

struct GPGNotInstalledView: View {
    @Environment(GPGAppState.self) private var state
    let brewPath: String?

    private static let installCommand = "brew install gnupg"
    private static let homebrewSite = URL(string: "https://brew.sh")!

    init(brewPath: String? = HomebrewDiscoveryService().discoverBrewPath()) {
        self.brewPath = brewPath
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if brewPath != nil {
                    homebrewReadyCard
                } else {
                    homebrewMissingCard
                    installCommandCard
                }
                rescanRow
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "key.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("GPG isn't installed yet")
                .font(.largeTitle)
                .bold()
            Text("Install GPG to sign Git commits, encrypt files, and manage keys with GPG Manager.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var homebrewReadyCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Homebrew detected")
                        .font(.subheadline.weight(.medium))
                    if let brewPath {
                        Text(brewPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                commandPill
                Text("Then click Rescan below to detect the new installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        } label: {
            Label("Install with Homebrew", systemImage: "shippingbox")
                .labelStyle(.largeIcon)
        }
    }

    private var homebrewMissingCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Homebrew is the macOS package manager most developers use to install command-line tools.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: Self.homebrewSite) {
                    Label("Open brew.sh", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
        } label: {
            Label("Step 1 — Install Homebrew", systemImage: "1.circle")
                .labelStyle(.largeIcon)
        }
    }

    private var installCommandCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Once Homebrew is installed, run this in Terminal:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                commandPill
            }
            .padding(10)
        } label: {
            Label("Step 2 — Install GPG", systemImage: "2.circle")
                .labelStyle(.largeIcon)
        }
    }

    private var commandPill: some View {
        HStack(spacing: 8) {
            Text(Self.installCommand)
                .font(.body.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: .rect(cornerRadius: 6))
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button("Copy & Open Terminal", systemImage: "doc.on.doc") {
                copyAndOpenTerminal()
            }
        }
    }

    private var rescanRow: some View {
        HStack(spacing: 10) {
            Button("Rescan", systemImage: "arrow.clockwise") {
                Task { await state.refreshInstallations() }
            }
            .buttonStyle(.bordered)

            Button("Choose Executable…", systemImage: "folder") {
                Task { await state.chooseCustomGPGPath() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    private func copyAndOpenTerminal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

#if DEBUG
#Preview("Homebrew present") {
    GPGNotInstalledView(brewPath: "/opt/homebrew/bin/brew")
        .environment(GPGAppState.previewEmpty)
        .frame(width: 900, height: 620)
}

#Preview("Homebrew missing") {
    GPGNotInstalledView(brewPath: nil)
        .environment(GPGAppState.previewEmpty)
        .frame(width: 900, height: 620)
}
#endif
