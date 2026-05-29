import Foundation

extension HelpTopic {
    static let troubleshooting = HelpTopic(
        id: "troubleshooting",
        title: "Troubleshooting",
        summary: "Solutions to the issues that come up most often.",
        systemImage: "stethoscope",
        category: .reference,
        sections: [
            HelpSection("GPG isn't detected", [
                .paragraph("On launch, the Overview shows *No GPG selected* and a card with install instructions. Causes and fixes:"),
                .bullets([
                    "**Not installed.** Run `brew install gnupg` and click **Rescan**.",
                    "**Installed somewhere unusual.** Click **Choose Executable…** and point at the `gpg` binary.",
                    "**`PATH` not picked up.** GUI apps inherit `PATH` differently than Terminal. The discovery service still checks standard Homebrew and MacPorts paths, but for non-standard locations use Choose Executable."
                ])
            ]),
            HelpSection("Touch ID isn't offered or doesn't work", [
                .bullets([
                    "**Running a Debug build.** Touch ID is mutually exclusive with Xcode's `get-task-allow` entitlement. Use Release or the shipped app.",
                    "**No Keychain entry for the key.** Click **Enable Touch ID** on the key card to import or create one.",
                    "**You denied biometric authentication.** macOS may fall back to a password prompt; click the fingerprint glyph to re-trigger Touch ID.",
                    "**Keychain Access doesn't show the items.** Expected. Items live in a custom access group filtered out of the default Keychain Access view."
                ])
            ]),
            HelpSection("Commits show as Unverified on GitHub", [
                .bullets([
                    "**Key not on GitHub.** Click **Add to GitHub** on the key card.",
                    "**Mismatched email.** GitHub checks the commit's email against your account-verified emails. Make sure `git config user.email` matches an email tied to your GitHub account.",
                    "**Stale GitHub entry.** If the registered key shows EXPIRED on GitHub but is fine locally, use **Refresh** in the GitHub card.",
                    "**Not actually signed.** Run `git log --show-signature -1` to confirm. If empty, recheck **Sign commits by default** on the Signing tab."
                ])
            ]),
            HelpSection("Signing fails silently in Xcode / GitHub Desktop", [
                .paragraph("Almost always the passphrase prompt: the system default pinentry is a TTY program and GUI apps can't render it."),
                .steps([
                    "Open **Settings → Passphrase**.",
                    "Pick **GPG Manager** (or **pinentry-mac**) as the provider.",
                    "Run the failing operation again — the GUI prompt should appear."
                ])
            ]),
            HelpSection("\"GitHub status unavailable\"", [
                .paragraph("Means `gh` isn't installed or isn't authenticated. This is *optional* — everything else works. To enable:"),
                .code("brew install gh\ngh auth login --scopes admin:gpg_key")
            ]),
            HelpSection("\"Grant GitHub GPG-keys access\"", [
                .paragraph("Your `gh` install is authenticated but missing the `admin:gpg_key` scope. Copy the suggested command and run it:"),
                .code("gh auth refresh --scopes admin:gpg_key"),
                .paragraph("Then click **Refresh** in the GitHub card.")
            ]),
            HelpSection("\"Helper points at a different path\"", [
                .paragraph("The pinentry helper config in `gpg-agent.conf` references a copy of GPG Manager that isn't this one. Common after moving the app or running multiple builds."),
                .paragraph("Click **Update Path to This App** in **Settings → Passphrase** to rewrite the config.")
            ]),
            HelpSection("Default key is expired", [
                .paragraph("Two options:"),
                .bullets([
                    "**Extend expiry.** Open Terminal and run `gpg --edit-key <fingerprint>`, then `expire`, set a new date, then `save`. Refresh GPG Manager.",
                    "**Roll a new key.** Generate a new key, set it as default, upload to GitHub, and update any services that reference the old key ID."
                ])
            ]),
            HelpSection("gpg-agent feels stuck", [
                .paragraph("**⇧ ⌘ K** (Restart Agent) kills `gpg-agent` and starts it fresh. This clears the passphrase cache and reloads `gpg-agent.conf`. Equivalent to:"),
                .code("gpgconf --kill gpg-agent")
            ]),
            HelpSection("Still stuck?", [
                .paragraph("File an issue with the output of `gpg --version` and a description of what you were trying to do. The Settings → About tab has a quick way to grab the GPG version and path.")
            ])
        ]
    )
}
