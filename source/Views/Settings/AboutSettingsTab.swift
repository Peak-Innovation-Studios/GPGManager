import AppKit
import SwiftUI

struct AboutSettingsTab: View {
    @Environment(GPGAppState.self) private var state

    private static let repoURL = URL(string: "https://github.com/Peak-Innovation-Studios/GPGManager")!
    private static let websiteURL = URL(string: "https://peakinnovationstudios.com")!
    private static let issuesURL = URL(string: "https://github.com/Peak-Innovation-Studios/GPGManager/issues")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyrightYear: String {
        Calendar.current.component(.year, from: .now).description
    }

    var body: some View {
        VStack(spacing: 18) {
            hero
            linkRow
            runtimeCard
            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)

            Text("GPG Manager")
                .font(.system(size: 26, weight: .semibold))

            Text("A modern macOS GPG manager.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                versionPill
                Button {
                    copyVersionInfo()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy version info")
            }
            .padding(.top, 2)
        }
    }

    private var versionPill: some View {
        Text("Version \(appVersion) · Build \(buildNumber)")
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
            .textSelection(.enabled)
    }

    private var linkRow: some View {
        HStack(spacing: 10) {
            Link(destination: Self.websiteURL) {
                Label("Website", systemImage: "globe")
            }
            Link(destination: Self.repoURL) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: Self.issuesURL) {
                Label("Report an Issue", systemImage: "ant")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var runtimeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let installation = state.selectedInstallation {
                    runtimeRow("Installation", installation.kind.rawValue)
                    if let version = installation.version {
                        runtimeRow("GPG version", version)
                    }
                    runtimeRow("Path", installation.path, monospaced: true, truncatesMiddle: true)
                } else {
                    Text("No GPG installation selected.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        } label: {
            Label("Runtime", systemImage: "terminal")
        }
    }

    private func runtimeRow(_ label: String, _ value: String, monospaced: Bool = false, truncatesMiddle: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .lineLimit(1)
                .truncationMode(truncatesMiddle ? .middle : .tail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("© \(copyrightYear) Peak Innovation Studios")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("GnuPG is a separate project, licensed under the GPL.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private func copyVersionInfo() {
        let line = [
            "GPG Manager \(appVersion) (\(buildNumber))",
            state.selectedInstallation?.version.map { "GPG \($0)" } ?? nil,
            state.selectedInstallation?.path
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }
}

#if DEBUG
#Preview {
    AboutSettingsTab()
        .environment(GPGAppState.preview)
        .frame(width: 560, height: 480)
}
#endif
