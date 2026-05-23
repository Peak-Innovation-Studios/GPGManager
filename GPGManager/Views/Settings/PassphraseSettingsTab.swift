import AppKit
import SwiftUI

struct PassphraseSettingsTab: View {
    @Environment(GPGAppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            PassphraseProviderSection()

            Section {
                Toggle(isOn: $state.rememberPasswordEnabled) {
                    HStack(spacing: 6) {
                        Text("Remember for")
                        TextField(
                            "Seconds",
                            value: rememberSecondsBinding,
                            format: .number.precision(.fractionLength(0))
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(!state.rememberPasswordEnabled)
                        Text("seconds")
                    }
                }
            } footer: {
                Text("Sets default-cache-ttl and max-cache-ttl in ~/.gnupg/gpg-agent.conf.")
            }

            Section {
                Button("Open Keychain Access…", systemImage: "key.viewfinder") {
                    openKeychainAccess()
                }
            } header: {
                Text("Recovery")
            } footer: {
                Text("A forgotten passphrase cannot be recovered from the key itself. If you stored it in the macOS Keychain, search for \"GnuPG\" in Keychain Access to look it up.")
            }
        }
        .formStyle(.grouped)
    }

    private func openKeychainAccess() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess") {
            NSWorkspace.shared.open(url)
        }
    }

    private var rememberSecondsBinding: Binding<Int> {
        Binding {
            state.agentConfig.defaultCacheTTL ?? 0
        } set: { newValue in
            let clamped = max(0, newValue)
            state.agentConfig.defaultCacheTTL = clamped
            if clamped > (state.agentConfig.maxCacheTTL ?? 0) {
                state.agentConfig.maxCacheTTL = clamped
            }
        }
    }
}

#Preview {
    PassphraseSettingsTab()
        .environment(GPGAppState.preview)
        .frame(width: 620, height: 700)
}
