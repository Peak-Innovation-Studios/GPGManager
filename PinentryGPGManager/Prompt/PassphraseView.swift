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

    /// First quoted substring from the description (typically the
    /// OpenPGP user-id: "Name (Comment) <email>").
    private var parsedUserID: String? {
        guard let description = request.description else { return nil }
        if let match = description.firstMatch(of: /"([^"]+)"/) {
            return String(match.1)
        }
        return nil
    }

    private struct ParsedKeyMetadata {
        let bitLength: String
        let algorithm: String
        let fullKeyID: String
        let createdDate: String

        var shortKeyID: String {
            fullKeyID.count > 8 ? String(fullKeyID.prefix(8)) : fullKeyID
        }
    }

    private var parsedKeyMetadata: ParsedKeyMetadata? {
        guard let description = request.description else { return nil }
        let pattern = /(\d+)-bit (\w+) key, ID ([0-9A-Fa-f]+),\s*created (\d{4}-\d{2}-\d{2})/
        if let match = description.firstMatch(of: pattern) {
            return ParsedKeyMetadata(
                bitLength: String(match.1),
                algorithm: String(match.2),
                fullKeyID: String(match.3),
                createdDate: String(match.4)
            )
        }
        return nil
    }

    /// gpg's algorithm/ID/created summary, compacted. Long key ID is
    /// truncated to the first 8 hex chars (the short ID developers
    /// actually recognize); full fingerprint stays in Details.
    private var parsedMetadata: String? {
        guard let m = parsedKeyMetadata else { return nil }
        return "\(m.algorithm) · ID \(m.shortKeyID) · created \(m.createdDate)"
    }

    /// Falls back to the first meaningful line of description when no
    /// user-id was quoted (covers SETDESC text that doesn't follow
    /// gpg's standard unlock template).
    private var primaryDetailLine: String? {
        if let userID = parsedUserID { return userID }
        guard let description = request.description, !description.isEmpty else { return nil }
        for line in description.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("please enter") { continue }
            if lower.hasPrefix("enter ") { continue }
            return trimmed
        }
        return description
    }

    private var hasDetails: Bool {
        let hasFullDescription = (request.description?.isEmpty == false)
        let hasKeyInfo = (request.keyInfo?.isEmpty == false)
        return hasFullDescription || hasKeyInfo
    }

    @ViewBuilder
    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = parsedKeyMetadata {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    detailRow(label: "Algorithm", value: "\(m.bitLength)-bit \(m.algorithm)")
                    detailRow(label: "Key ID", value: m.fullKeyID, monospaced: true)
                    detailRow(label: "Created", value: m.createdDate)
                }
            } else if let description = request.description, !description.isEmpty {
                // Parse failed — show the raw SETDESC with the prompt
                // preamble and the user-id quote line filtered out (both
                // duplicated by the header).
                let filtered = filteredFallbackDescription(description)
                if !filtered.isEmpty {
                    Text(filtered)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let keyInfo = request.keyInfo, !keyInfo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keygrip")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(keyInfo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func filteredFallbackDescription(_ description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return nil }
                let lower = trimmed.lowercased()
                if lower.hasPrefix("please enter") { return nil }
                if lower.hasPrefix("enter ") { return nil }
                if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") { return nil }
                return trimmed
            }
            .joined(separator: "\n")
    }

    private var accessibilityHeaderLabel: Text {
        var components = [request.effectiveTitle]
        if let primary = primaryDetailLine { components.append(primary) }
        if let metadata = parsedMetadata { components.append(metadata) }
        return Text(components.joined(separator: ". "))
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

/// Compact strength indicator that lives inside the SecureField's row,
/// so revealing it doesn't push other content down (the pinentry host
/// window doesn't auto-resize on SwiftUI content growth).
private struct StrengthPill: View {
    let passphrase: String
    let tooltip: String?

    private var score: Int { PassphraseStrength.score(passphrase) }
    private var bucket: String { PassphraseStrength.bucketLabel(forScore: score) }
    private var color: Color {
        switch score {
        case ..<25:  .red
        case ..<50:  .orange
        case ..<75:  .yellow
        default:     .green
        }
    }

    var body: some View {
        Text(bucket)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: .capsule)
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
            .help(tooltip ?? "Passphrase strength: \(bucket)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Passphrase strength: \(bucket)"))
            // Animate bucket boundary crossings so color/label settle smoothly.
            .animation(.easeInOut(duration: 0.15), value: bucket)
    }
}

#if DEBUG
private extension PinentryRequest {
    static let previewUnlock = PinentryRequest(
        title: "Unlock Secret Key",
        description: "Please enter the passphrase to unlock the OpenPGP secret key:\n\"David Peak (Studios) <david@peakinnovationstudios.com>\"\n255-bit EDDSA key, ID EC9EC663E46AD1DA, created 2026-05-23.",
        prompt: "Passphrase",
        keyInfo: "n/99C467344C53512B95145F844823FADE86C2D6FA",
        allowKeychainSave: true
    )

    static let previewNewPassphrase = PinentryRequest(
        title: "Create Passphrase",
        description: "Enter a passphrase for your new OpenPGP key:\n\"David Peak <david@peakinnovationstudios.com>\"\nThis passphrase protects your secret key and will be required for signing.",
        prompt: "New passphrase",
        okLabel: "Create Key",
        repeatPrompt: "Confirm passphrase",
        repeatError: "Those passphrases don't match.",
        qualityBarLabel: "Passphrase strength",
        qualityBarTooltip: "Use a longer passphrase with several uncommon words for stronger protection.",
        allowKeychainSave: true
    )

    static let previewRetry = PinentryRequest(
        title: "Unlock Secret Key",
        description: "Please enter the passphrase to unlock the OpenPGP secret key:\n\"Signing Key <git@peakinnovationstudios.com>\"\n255-bit EDDSA key, ID 84F2B5F4C970A6E2, created 2026-05-24.",
        prompt: "Passphrase",
        keyInfo: "n/819A5AD9604D43DAB597E7E984F2B5F4C970A6E2",
        errorMessage: "Bad passphrase. Try again.",
        allowKeychainSave: true
    )

    /// Synthetic data for marketing screenshot capture. No real key info —
    /// uses the same "Demo User" / "demo@example.com" pattern as the
    /// sibling gpg-manager-screenshots project.
    static let captureUnlock = PinentryRequest(
        title: "Unlock Secret Key",
        description: "Please enter the passphrase to unlock the OpenPGP secret key:\n\"Demo User <demo@example.com>\"\n255-bit EDDSA key, ID A1B2C3D4E5F67890, created 2026-05-23.",
        prompt: "Passphrase",
        keyInfo: "n/8F2A1B4C9D5E7F03C6A8B1D2E4F60593A1C8B7D5",
        allowKeychainSave: true
    )
}

extension PassphraseView {
    /// Preview-only convenience that seeds the passphrase field so the
    /// primary action button can render in its enabled state for
    /// marketing screenshot capture.
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

private struct PinentryWindowPreview: View {
    let request: PinentryRequest
    var initialPassphrase: String? = nil

    var body: some View {
        Group {
            if let initialPassphrase {
                PassphraseView(
                    request: request,
                    initialPassphrase: initialPassphrase,
                    onSubmit: { _, _ in },
                    onCancel: {}
                )
            } else {
                PassphraseView(
                    request: request,
                    onSubmit: { _, _ in },
                    onCancel: {}
                )
            }
        }
        .frame(width: 540)
    }
}

#Preview("Unlock") {
    PinentryWindowPreview(request: .previewUnlock)
}

#Preview("Create Passphrase") {
    PinentryWindowPreview(request: .previewNewPassphrase)
}

#Preview("Retry Error") {
    PinentryWindowPreview(request: .previewRetry)
}

#Preview("Capture — Unlock") {
    PinentryWindowPreview(
        request: .captureUnlock,
        initialPassphrase: "correcthorsebatterystaple"
    )
}
#endif
