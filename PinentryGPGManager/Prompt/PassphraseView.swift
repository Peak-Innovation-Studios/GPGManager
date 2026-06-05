import LocalAuthentication
import SwiftUI

struct PassphraseView: View {
    let request: PinentryRequest
    let onSubmit: (String, Bool) -> Void
    let onCancel: () -> Void

    @State private var passphrase: String = ""
    @State private var confirm: String = ""
    @State private var saveToKeychain: Bool = false
    @State private var localError: String?
    /// Resolved once on appear via LAContext. Drives both the keychain-save
    /// default (pre-checked when we have biometrics, since the canonical
    /// experience is "Touch ID handles unlock from here on") and the
    /// label wording / icon shown next to the checkbox.
    @State private var biometricsAvailable: Bool = false
    @State private var detailsExpanded: Bool = false
    @FocusState private var focusedField: Field?
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    private enum Field: Hashable { case primary, confirm }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let message = displayedError, !message.isEmpty {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
                        .accessibilityAddTraits(.isStaticText)
                }

                HStack(alignment: .center, spacing: 10) {
                    SecureField(request.effectivePrompt, text: $passphrase)
                        .textContentType(request.requiresConfirmation ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focusedField, equals: .primary)
                        .onSubmit { advance() }
                        .accessibilityLabel(Text(request.effectivePrompt))

                    if request.showsQualityBar && !passphrase.isEmpty {
                        StrengthPill(passphrase: passphrase, tooltip: request.qualityBarTooltip)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
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
                        Label(
                            biometricsAvailable ? "Use Touch ID next time" : "Save in Keychain",
                            systemImage: biometricsAvailable ? "touchid" : "lock.fill"
                        )
                        .font(.callout)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityHint(Text(
                        biometricsAvailable
                            ? "Save this passphrase so future operations can unlock with Touch ID instead of typing."
                            : "Save this passphrase so future operations don't need to re-type it."
                    ))
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
        .animation(.easeInOut(duration: 0.18), value: passphrase.isEmpty)
        .frame(minWidth: 520, idealWidth: 540, maxWidth: 640)
        .fixedSize(horizontal: false, vertical: true)
        .containerBackground(.regularMaterial, for: .window)
        .onAppear {
            focusedField = .primary
            // Resolve biometric availability once. If we have Touch ID
            // and the request allows keychain save, pre-check the box —
            // the canonical experience is "type once, unlock with Touch
            // ID thereafter". User can still uncheck before submitting
            // if they don't want the passphrase persisted.
            biometricsAvailable = Self.canUseBiometrics()
            if request.allowKeychainSave && biometricsAvailable {
                saveToKeychain = true
            }
        }
        .onChange(of: displayedError) { _, newValue in
            announce(newValue)
        }
    }

    private static func canUseBiometrics() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconView(size: iconSize, fallbackSystemImage: "lock.shield")
            VStack(alignment: .leading, spacing: 3) {
                Text(request.effectiveTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let primary = primaryDetailLine {
                    Text(primary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let metadata = parsedMetadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasDetails {
                    Button {
                        detailsExpanded.toggle()
                    } label: {
                        Label("Details", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .popover(isPresented: $detailsExpanded, arrowEdge: .bottom) {
                        detailsContent
                            .padding(16)
                            .frame(width: 340)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityHeaderLabel)
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
extension PassphraseView {
    /// Preview-only convenience that seeds the passphrase field so the
    /// primary action button can render in its enabled state for
    /// marketing screenshot capture. Lives here (not in the previews file)
    /// because it touches the `@State private` storage `_passphrase`.
    init(
        request: PinentryRequest,
        initialPassphrase: String,
        onSubmit: @escaping (String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self._passphrase = State(initialValue: initialPassphrase)
    }
}
#endif
