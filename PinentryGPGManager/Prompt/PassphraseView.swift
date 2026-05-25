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
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private enum Field: Hashable { case primary, confirm }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let description = request.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let keyInfo = request.keyInfo, !keyInfo.isEmpty {
                    Text(keyInfo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(Text("Key info: \(keyInfo)"))
                }

                if let message = displayedError, !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.isStaticText)
                }

                SecureField(request.effectivePrompt, text: $passphrase)
                    .textContentType(request.requiresConfirmation ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
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
                        .focused($focusedField, equals: .confirm)
                        .onSubmit { submit() }
                        .accessibilityLabel(Text(request.effectiveRepeatPrompt))
                }

                if request.allowKeychainSave {
                    Toggle("Save in Keychain", isOn: $saveToKeychain)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                        .accessibilityHint(Text("Remember this passphrase so future operations can unlock the key with Touch ID."))
                }

                HStack {
                    Spacer()
                    Button(request.effectiveCancel, role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button(request.effectiveOK, action: submit)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 240)
        .onAppear { focusedField = .primary }
        .onChange(of: displayedError) { _, newValue in
            announce(newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(size: iconSize, fallbackSystemImage: "lock.shield")
            VStack(alignment: .leading, spacing: 2) {
                Text(request.effectiveTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("GPG Manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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
