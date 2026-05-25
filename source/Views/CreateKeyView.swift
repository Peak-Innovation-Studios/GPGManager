import SwiftUI

struct CreateKeyView: View {
    @Environment(GPGAppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var parameters = GPGCreateKeyParameters()
    @State private var confirmPassphrase: String = ""
    @State private var saveToKeychain: Bool = false
    @State private var uploadToGitHub: Bool = false
    @State private var isPassphraseVisible: Bool = false
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                identitySection
                keySection
                passphraseSection
                gitHubSection
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .disabled(isGenerating)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Create a New Key")
                    .font(.headline)
                Text("Generate a new OpenPGP key pair locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var identitySection: some View {
        Section {
            TextField("Name", text: $parameters.name)
            TextField("Email", text: $parameters.email)
                .textContentType(.emailAddress)
            TextField("Comment (optional)", text: $parameters.comment)
        } header: {
            Text("Identity")
        } footer: {
            Text("Your name and email are embedded in the key as the user ID. They appear next to signed commits and on GitHub.")
        }
    }

    private var keySection: some View {
        Section("Key") {
            Picker("Algorithm", selection: $parameters.algorithm) {
                ForEach(GPGCreateKeyParameters.Algorithm.allCases) { algorithm in
                    Text(algorithm.rawValue).tag(algorithm)
                }
            }
            Picker("Expires", selection: $parameters.expiration) {
                ForEach(GPGCreateKeyParameters.Expiration.allCases) { expiration in
                    Text(expiration.rawValue).tag(expiration)
                }
            }
        }
    }

    private var passphraseSection: some View {
        Section {
            RevealableSecureField(
                title: "Passphrase",
                text: $parameters.passphrase,
                isVisible: $isPassphraseVisible,
                showsToggle: true
            )
            RevealableSecureField(
                title: "Confirm passphrase",
                text: $confirmPassphrase,
                isVisible: $isPassphraseVisible
            )

            HStack {
                Button("Suggest strong passphrase", systemImage: "wand.and.stars") {
                    suggestPassphrase()
                }
                .buttonStyle(.borderless)
                .help("Generate an 8-word random passphrase (~64 bits of entropy)")
                Spacer()
            }

            if !parameters.passphrase.isEmpty {
                PassphraseStrengthBar(
                    passphrase: parameters.passphrase,
                    label: "Strength",
                    tooltip: "Estimated passphrase strength"
                )
            }
            if passphraseMismatch {
                Text("Passphrases don't match.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Toggle("Save in Keychain", isOn: $saveToKeychain)
                .help("Store the passphrase in your macOS Keychain. Future signing operations will unlock it with Touch ID.")
        } header: {
            Text("Passphrase")
        } footer: {
            Text("Keep this safe — if it's lost, the secret key cannot be recovered.")
        }
    }

    private var gitHubSection: some View {
        Section {
            Toggle("Upload to GitHub after creation", isOn: $uploadToGitHub)
                .help("Adds the new public key to your GitHub account. Requires gh CLI with admin:gpg_key scope.")
        } header: {
            Text("GitHub")
        } footer: {
            Text(gitHubFooterText)
        }
    }

    private var gitHubFooterText: String {
        let trimmed = parameters.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if uploadToGitHub, !trimmed.isEmpty {
            return "Will show as “\(trimmed)” on GitHub. You can rename it later from the Signing tab."
        }
        return "So signed commits show as Verified on github.com."
    }

    private func suggestPassphrase() {
        let suggestion = PassphraseGenerator.suggest()
        parameters.passphrase = suggestion
        confirmPassphrase = suggestion
        saveToKeychain = true
        isPassphraseVisible = true
    }

    private var footer: some View {
        HStack {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                Text("Generating key…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isGenerating)
            Button("Create Key") {
                Task { await generate() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canCreate)
        }
        .padding(16)
    }

    private var passphraseMismatch: Bool {
        !confirmPassphrase.isEmpty && parameters.passphrase != confirmPassphrase
    }

    private var canCreate: Bool {
        parameters.isValid && parameters.passphrase == confirmPassphrase && !isGenerating
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            try await state.createKey(
                parameters: parameters,
                saveToKeychain: saveToKeychain,
                uploadToGitHub: uploadToGitHub
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    CreateKeyView()
        .environment(GPGAppState.preview)
}
#endif
