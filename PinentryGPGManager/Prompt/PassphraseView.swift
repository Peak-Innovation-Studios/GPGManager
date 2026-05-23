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

    private enum Field: Hashable { case primary, confirm }

    var body: some View {
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
            }

            if let message = displayedError, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            SecureField(request.effectivePrompt, text: $passphrase)
                .textContentType(request.requiresConfirmation ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .primary)
                .onSubmit { advance() }

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
            }

            if request.allowKeychainSave {
                Toggle("Save in Keychain", isOn: $saveToKeychain)
                    .toggleStyle(.checkbox)
                    .font(.callout)
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
        .frame(width: 460)
        .onAppear { focusedField = .primary }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(size: 56, fallbackSystemImage: "lock.shield")
            VStack(alignment: .leading, spacing: 2) {
                Text(request.effectiveTitle)
                    .font(.headline)
                Text("GPG Manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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
