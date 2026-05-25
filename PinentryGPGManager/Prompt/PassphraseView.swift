import SwiftUI

struct PassphraseView: View {
    let request: PinentryRequest
    let onSubmit: (String, Bool) -> Void
    let onCancel: () -> Void

    @State private var passphrase: String = ""
    @State private var confirm: String = ""
    @State private var saveToKeychain: Bool = false
    @State private var localError: String?
    @FocusState private var focusedField: Field?
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72

    private enum Field: Hashable { case primary, confirm }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let description = request.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quinary, in: .rect(cornerRadius: 10))
                }

                if let keyInfo = request.keyInfo, !keyInfo.isEmpty {
                    Text(keyInfo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quinary, in: .capsule)
                        .accessibilityLabel(Text("Key info: \(keyInfo)"))
                }

                if let message = displayedError, !message.isEmpty {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
                        .accessibilityAddTraits(.isStaticText)
                }

                SecureField(request.effectivePrompt, text: $passphrase)
                    .textContentType(request.requiresConfirmation ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focusedField, equals: .primary)
                    .onSubmit { advance() }
                    .accessibilityLabel(Text(request.effectivePrompt))

                if request.showsQualityBar {
                    PassphraseStrengthBar(
                        passphrase: passphrase,
                        label: request.qualityBarLabel,
                        tooltip: request.qualityBarTooltip
                    )
                }

                if request.requiresConfirmation {
                    SecureField(request.effectiveRepeatPrompt, text: $confirm)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focusedField, equals: .confirm)
                        .onSubmit { submit() }
                        .accessibilityLabel(Text(request.effectiveRepeatPrompt))
                }

                if request.allowKeychainSave {
                    Toggle(isOn: $saveToKeychain) {
                        Label("Save in Keychain", systemImage: "touchid")
                            .font(.callout)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityHint(Text("Remember this passphrase so future operations can unlock the key with Touch ID."))
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button(request.effectiveCancel, role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button(request.effectiveOK, action: submit)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canSubmit)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(minWidth: 520, idealWidth: 540, maxWidth: 640)
        .fixedSize(horizontal: false, vertical: true)
        .containerBackground(.regularMaterial, for: .window)
        .onAppear { focusedField = .primary }
        .onChange(of: displayedError) { _, newValue in
            announce(newValue)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppIconView(size: iconSize, fallbackSystemImage: "lock.shield")
            VStack(spacing: 2) {
                Text(request.effectiveTitle)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("GPG Manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(request.effectiveTitle). GPG Manager."))
    }

    private func announce(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private var displayedError: String? {
        localError ?? request.errorMessage
    }

    private var canSubmit: Bool {
        guard !passphrase.isEmpty else { return false }
        if request.requiresConfirmation, confirm.isEmpty { return false }
        return true
    }

    private func advance() {
        guard !passphrase.isEmpty else { return }
        if request.requiresConfirmation, focusedField == .primary {
            focusedField = .confirm
            return
        }
        submit()
    }

    private func submit() {
        guard !passphrase.isEmpty else { return }

        if request.requiresConfirmation {
            guard passphrase == confirm else {
                localError = request.repeatError?.isEmpty == false
                    ? request.repeatError
                    : "Passphrases don't match."
                confirm = ""
                focusedField = .confirm
                return
            }
        }

        onSubmit(passphrase, saveToKeychain)
    }
}

#if DEBUG
#Preview("Unlock") {
    PassphraseView(
        request: PinentryRequest(
            title: "Unlock Secret Key",
            description: "Please enter the passphrase to unlock the OpenPGP secret key:\n\"David Peak (Studios) <david@peakinnovationstudios.com>\"\n255-bit EDDSA key, ID EC9EC663E46AD1DA, created 2026-05-23.",
            prompt: "Passphrase",
            keyInfo: "n/99C467344C53512B95145F844823FADE86C2D6FA",
            allowKeychainSave: true
        ),
        onSubmit: { _, _ in },
        onCancel: {}
    )
}
#endif
