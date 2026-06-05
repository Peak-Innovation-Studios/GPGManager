#if DEBUG
import SwiftUI

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

private struct PinentryWindowPreview: View {
    let request: PinentryRequest
    var initialPassphrase: String?

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
