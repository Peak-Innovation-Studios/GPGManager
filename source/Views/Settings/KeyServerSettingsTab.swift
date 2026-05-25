import SwiftUI

struct KeyServerSettingsTab: View {
    @Environment(GPGAppState.self) private var state
    @State private var showsCleanupSheet = false

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Server") {
                Picker("Key server", selection: keyserverBinding) {
                    ForEach(GPGKeyserverPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset.rawValue)
                    }
                    if let current = state.gpgConfig.keyserver,
                       !current.isEmpty,
                       !GPGKeyserverPreset.allCases.contains(where: { $0.rawValue == current }) {
                        Text(current).tag(current)
                    }
                }
                .labelsHidden()
            }

            Section {
                Toggle("Automatically download public keys", isOn: $state.gpgConfig.autoKeyRetrieve)
            } footer: {
                Text("Search key servers for public keys when signatures cannot be verified because the public key does not exist in the GPG Keychain.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(state.publicOnlyKeys.count) public-only key\(state.publicOnlyKeys.count == 1 ? "" : "s") in your keyring.")
                        Text("These were downloaded for signature verification and aren't needed to sign your own commits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Clean…", systemImage: "trash") {
                        showsCleanupSheet = true
                    }
                    .disabled(state.publicOnlyKeys.isEmpty || state.selectedGPGPath.isEmpty)
                }
            } header: {
                Text("Downloaded Keys")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsCleanupSheet) {
            CleanPublicKeysSheet()
                .environment(state)
        }
    }

    private var keyserverBinding: Binding<String> {
        Binding {
            state.gpgConfig.keyserver ?? GPGKeyserverPreset.openPGP.rawValue
        } set: { newValue in
            state.gpgConfig.keyserver = newValue.isEmpty ? nil : newValue
        }
    }
}

#if DEBUG
#Preview {
    KeyServerSettingsTab()
        .environment(GPGAppState.preview)
        .frame(width: 560, height: 420)
}
#endif
