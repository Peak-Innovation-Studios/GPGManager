import SwiftUI

struct PassphraseProviderSection: View {
    @Environment(GPGAppState.self) private var state

    var body: some View {
        Section {
            Picker("Provider", selection: providerBinding) {
                ForEach(visibleProviders) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if state.passphraseProvider == .pinentryMac, !state.isPinentryMacAvailable {
                MissingPinentryMacWarning()
            }

            if case .installedElsewhere(let installedPath, _) = state.pinentryStatus.state {
                AppMoveWarning(installedPath: installedPath)
            }

            if state.passphraseProvider == .gpgManager,
               let previous = state.pinentryStatus.previousProgram,
               !previous.isEmpty {
                LabeledContent("Previous") {
                    Text(previous)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if state.passphraseProvider == .custom,
               let custom = state.agentConfig.pinentryProgram {
                LabeledContent("Current") {
                    Text(custom)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Passphrase Prompt")
        } footer: {
            Text(state.passphraseProvider.description)
        }
    }

    private var visibleProviders: [GPGAppState.PassphraseProvider] {
        var providers: [GPGAppState.PassphraseProvider] = [.systemDefault, .gpgManager]
        if state.isPinentryMacAvailable || state.passphraseProvider == .pinentryMac {
            providers.insert(.pinentryMac, at: 1)
        }
        if state.passphraseProvider == .custom {
            providers.append(.custom)
        }
        return providers
    }

    private var providerBinding: Binding<GPGAppState.PassphraseProvider> {
        Binding {
            state.passphraseProvider
        } set: { newValue in
            guard newValue != .custom else { return }
            Task { await state.setPassphraseProvider(newValue) }
        }
    }
}

private struct MissingPinentryMacWarning: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("pinentry-mac isn't installed. Install via `brew install pinentry-mac`.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppMoveWarning: View {
    @Environment(GPGAppState.self) private var state
    let installedPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Helper points at \(installedPath); doesn't match this app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Update Path to This App") {
                Task { await state.rewritePinentryToCurrentPath() }
            }
        }
    }
}
