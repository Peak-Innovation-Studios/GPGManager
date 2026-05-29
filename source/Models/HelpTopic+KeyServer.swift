import Foundation

extension HelpTopic {
    static let keyServer = HelpTopic(
        id: "key-server",
        title: "Key Servers",
        summary: "Pick a keyserver, control auto-download, and tidy up keys you've collected.",
        systemImage: "network",
        category: .configuration,
        sections: [
            HelpSection([
                .paragraph("Keyservers are distributed directories of public keys. GPG can fetch a key from one when it needs to verify a signature it doesn't recognize. **Settings → Key Server** controls which one is used and whether downloads happen automatically.")
            ]),
            HelpSection("Choosing a server", [
                .paragraph("The **Key server** picker offers a few common presets:"),
                .keyValue([
                    ("keys.openpgp.org", "Verified-email-only — keys are vetted before serving. Recommended default."),
                    ("Ubuntu keyserver", "Mirror of the older SKS network. Wider history but no verification of identities."),
                    ("Custom", "A specific URL you've put in `~/.gnupg/gpg.conf` shows as an extra option.")
                ]),
                .paragraph("Writes `keyserver` to `~/.gnupg/gpg.conf`. Affects `gpg --recv-keys`, `gpg --send-keys`, and auto-key-retrieve.")
            ]),
            HelpSection("Automatically download public keys", [
                .paragraph("When on, GPG attempts to fetch any signing key it doesn't already have from the configured keyserver during verification — so commands like `git log --show-signature` don't fail on a missing key."),
                .keyValue([
                    ("Setting", "`auto-key-retrieve` in `~/.gnupg/gpg.conf`."),
                    ("Side effect", "Your keyring will steadily collect public keys from people whose signed work you've encountered.")
                ]),
                .tip("Leave this on if you frequently look at commits from external collaborators. Turn it off if you'd rather not auto-leak your interest to a keyserver every time you verify.")
            ]),
            HelpSection("Cleaning downloaded keys", [
                .paragraph("Over time, the **public-only** half of your keyring (keys without a matching secret half) can pile up. The **Clean…** button on this tab opens a sheet showing every such key with a checkbox."),
                .steps([
                    "Tick the keys you want to remove.",
                    "Optionally use **Select all expired** to bulk-select stale entries.",
                    "Click **Delete Selected**."
                ]),
                .note("Deletion is local — it just removes the keys from your GPG keyring. The keyserver still has them; you can re-fetch any one if you change your mind.")
            ]),
            HelpSection("Manual fetch from Terminal", [
                .code("gpg --recv-keys 0xABCDEF0123456789",
                      caption: "Download a specific key by ID"),
                .code("gpg --keyserver keys.openpgp.org --send-keys YOURFINGERPRINT",
                      caption: "Publish your public key — keys.openpgp.org will email you to verify ownership")
            ])
        ]
    )
}
