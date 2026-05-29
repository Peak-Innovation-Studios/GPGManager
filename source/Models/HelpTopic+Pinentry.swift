import Foundation

extension HelpTopic {
    static let pinentryHelper = HelpTopic(
        id: "pinentry-helper",
        title: "The Pinentry Helper",
        summary: "What the bundled passphrase prompt is, why it exists, and how it works.",
        systemImage: "rectangle.dashed.badge.record",
        category: .configuration,
        sections: [
            HelpSection([
                .paragraph("**PinentryGPGManager** is the small command-line program tucked inside the GPG Manager app bundle that handles passphrase prompts. It's a native, license-clean replacement for `pinentry-mac` — and it ships with GPG Manager so there's nothing extra to install.")
            ]),
            HelpSection("Why bundle a pinentry at all", [
                .bullets([
                    "**No second install.** `pinentry-mac` is a separate Homebrew package; bundling avoids the install dance.",
                    "**Native SwiftUI.** The prompt looks and behaves like every other macOS dialog and respects system settings.",
                    "**Touch ID built in.** The helper knows how to authenticate against Keychain entries with biometric ACLs.",
                    "**Surface trust.** The prompt is signed by Peak Innovation Studios with the same identity as GPG Manager."
                ])
            ]),
            HelpSection("How GPG finds it", [
                .paragraph("When you pick **GPG Manager** as the passphrase provider, the app:"),
                .steps([
                    "Resolves the helper's absolute path: `…/GPGManager.app/Contents/MacOS/PinentryGPGManager`.",
                    "Writes that path as `pinentry-program` in `~/.gnupg/gpg-agent.conf`.",
                    "Reloads `gpg-agent` so the next signing operation uses the helper."
                ]),
                .paragraph("From then on, any tool that goes through `gpg-agent` — `git commit -S`, Xcode, GitHub Desktop, `gpg --encrypt`, etc. — will get our prompt.")
            ]),
            HelpSection("If you move the app", [
                .paragraph("If you move GPG Manager (e.g. from Downloads to Applications) after enabling it, the path in `gpg-agent.conf` becomes stale and signing will fail until the path is updated."),
                .paragraph("GPG Manager detects this on launch and shows an **Update Path to This App** button in **Settings → Passphrase**. Click it to rewrite the config to the new location."),
                .tip("Install GPG Manager into `/Applications` before enabling — the path stays stable across updates that way.")
            ]),
            HelpSection("Switching back", [
                .paragraph("Pick another provider in **Settings → Passphrase**. GPG Manager restores the previous `pinentry-program` value (shown under **Previous** when you're on GPG Manager) so nothing is lost.")
            ]),
            HelpSection("Inside the prompt", [
                .keyValue([
                    ("Title bar", "Shows what GPG is asking for — sign, decrypt, or unlock — and the key's User ID."),
                    ("Touch ID", "If a biometric Keychain entry exists for the key, the helper shows a fingerprint glyph and authenticates with that instead of asking you to type."),
                    ("Show / Hide", "Reveal toggle so you can verify a long passphrase as you type."),
                    ("Strength bar", "On new-passphrase prompts (create / change), gives a rough estimate of strength."),
                    ("Save to Keychain", "On new-passphrase prompts, optionally persist the result to Keychain for future Touch ID unlock.")
                ])
            ])
        ]
    )
}
