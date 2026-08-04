import Foundation

extension HelpTopic {
    static let passphraseAndTouchID = HelpTopic(
        id: "passphrase-touchid",
        title: "Passphrase & Touch ID",
        summary: "How GPG prompts for passphrases, caching, and unlocking with your fingerprint.",
        systemImage: "lock",
        category: .configuration,
        sections: [
            HelpSection([
                .paragraph("Every signing or decryption operation needs to decrypt your private key. That happens via `gpg-agent`, which asks a **pinentry** program for the passphrase. GPG Manager lets you pick which pinentry runs and how long the agent caches the result.")
            ]),
            HelpSection("Passphrase Prompt provider", [
                .paragraph("In **Settings → Passphrase**, the **Provider** picker chooses your pinentry:"),
                .keyValue([
                    ("System default", "Whatever pinentry shipped with `gpg`. Often the curses/TTY one, which **fails inside GUI apps** like Xcode and GitHub Desktop. Avoid unless you only sign from Terminal."),
                    ("GPG Manager", "The bundled pinentry helper. Recommended. Native SwiftUI prompt that works system-wide and supports Touch ID. See the **Pinentry Helper** topic."),
                    ("pinentry-mac", "The Homebrew classic. Works if you already have it set up. Auto-detected when installed."),
                    ("Custom", "An arbitrary path you've set in `~/.gnupg/gpg-agent.conf`. Shown only when one is configured.")
                ]),
                .note("Switching providers updates `pinentry-program` in `~/.gnupg/gpg-agent.conf` and reloads the agent so the change takes effect immediately.")
            ]),
            HelpSection("Touch ID — what it actually is", [
                .paragraph("\"Touch ID for GPG\" works by storing the passphrase in your macOS Keychain, behind a biometric ACL. When `gpg-agent` asks for the passphrase, the pinentry helper:"),
                .steps([
                    "Computes the **keygrip** of the secret subkey being unlocked.",
                    "Looks up Keychain item with service `GnuPG` and that keygrip as the account.",
                    "Asks the Secure Enclave to release the passphrase, which prompts a Touch ID sheet.",
                    "Hands the passphrase back to `gpg-agent`, which decrypts the private key."
                ]),
                .paragraph("From your perspective: a Touch ID prompt appears instead of a passphrase prompt, and a fingerprint approves the operation."),
                .tip("Keychain items live in an access group `Z2R2L2TJ7Y.com.peakinnovationstudios.GPGManager`. They aren't shown in Keychain Access by default; that's normal and intentional.")
            ]),
            HelpSection("Enabling Touch ID for a key", [
                .paragraph("Two paths:"),
                .bullets([
                    "**At key creation** — tick *Save in Keychain* in the New Key sheet. The just-typed passphrase gets stored automatically.",
                    "**Later** — on the Overview tab's My Keys card, click **Enable Touch ID**. This imports an existing non-biometric Keychain entry (e.g. one pinentry-mac saved) and re-protects it with Touch ID."
                ]),
                .warning("Touch ID doesn't work in Debug builds. Xcode's `get-task-allow` entitlement is mutually exclusive with biometric Keychain ACLs. Build in Release or use the shipped app for testing.")
            ]),
            HelpSection("Cache: \"Remember for X seconds\"", [
                .paragraph("`gpg-agent` can hold a passphrase in memory after a successful unlock so subsequent operations skip the prompt. The cache duration is set here."),
                .keyValue([
                    ("Off", "Prompt every signature. The most secure setting; the most annoying for fast loops like rebases."),
                    ("Short (e.g. 600s)", "10-minute window. Good middle ground."),
                    ("Long (e.g. 28800s = 8 hours)", "Type once at the start of the day. Less secure if your machine is shared.")
                ]),
                .paragraph("This maps to `default-cache-ttl` (and `max-cache-ttl`) in `~/.gnupg/gpg-agent.conf`.")
            ]),
            HelpSection("Recovery", [
                .paragraph("There is **no way** to recover a forgotten passphrase from the encrypted private key itself."),
                .paragraph("If you saved the passphrase in the macOS Keychain, GPG Manager can show it to you: on the Overview tab's **My Keys** card, open the **⋯** menu on the key and choose **Reveal Passphrase…**. Touch ID (or your login password) approves the read, then you can reveal or copy the passphrase."),
                .paragraph("Entries created by pinentry-mac can also be read in **Keychain Access** — click **Open Keychain Access…** in the Recovery section and search for *GnuPG*. Entries saved by GPG Manager live in a private access group and only appear inside the app — use **Reveal Passphrase…** for those."),
                .note("If the key isn't in Keychain and you can't remember the passphrase, the key is effectively lost. Revoke it via a previously generated revocation certificate (if you have one) and create a new key.")
            ])
        ]
    )
}
