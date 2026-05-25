import AppKit
import SwiftUI

struct AboutSettingsTab: View {
    @Environment(GPGAppState.self) private var state

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .padding(.top, 12)

            Text("GPG Manager")
                .font(.title)
                .bold()

            Text("Version \(appVersion) (\(buildNumber))")
                .foregroundStyle(.secondary)

            if let installation = state.selectedInstallation {
                Divider()
                    .padding(.horizontal, 40)

                VStack(spacing: 6) {
                    LabeledContent("GPG installation") {
                        Text(installation.kind.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    if let version = installation.version {
                        LabeledContent("Version") {
                            Text(version)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    LabeledContent("Path") {
                        Text(installation.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 400)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#if DEBUG
#Preview {
    AboutSettingsTab()
        .environment(GPGAppState.preview)
        .frame(width: 560, height: 460)
}
#endif
