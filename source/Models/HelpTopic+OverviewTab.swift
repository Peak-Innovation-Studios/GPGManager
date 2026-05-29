import Foundation

extension HelpTopic {
    static let overviewTab = HelpTopic(
        id: "overview-tab",
        title: "The Overview Tab",
        summary: "GPG installation, setup checklist, and managing your secret keys.",
        systemImage: "house",
        category: .features,
        sections: [
            HelpSection([
                .paragraph("The Overview tab is the home base. It shows which `gpg` binary is in use, a checklist of what's set up, and the keys whose secret half lives on this Mac.")
            ]),
            HelpSection("GPG Executable", [
                .paragraph("Shows the binary GPG Manager will invoke for everything (`gpg --list-keys`, `--gen-key`, signing, etc.) and its version."),
                .bullets([
                    "**Change** → pick from any auto-discovered installation (Homebrew, MacPorts, GPG Suite, etc.).",
                    "**Choose Custom Executable…** → manually point at a `gpg` binary anywhere on disk."
                ]),
                .note("The chosen path is what Git's `gpg.program` config is set to when you Apply signing changes — so swapping installations here propagates to your shell, too.")
            ]),
            HelpSection("Setup Checklist", [
                .paragraph("A traffic-light view of how ready you are to sign:"),
                .keyValue([
                    ("Signing key", "✅ if a default key is set, ⚠️ if it's expiring within 30 days, ❌ if expired or unset."),
                    ("Passphrase prompt", "✅ if a GUI prompt (GPG Manager, pinentry-mac) is configured. ⚠️ for *system default*, which can fail in GUI apps like Xcode."),
                    ("Git signing", "✅ if `git` is configured to sign commits with your key."),
                    ("GitHub status", "✅ if the default key is registered with the active GitHub account. ⚠️ if it isn't, or if `gh` needs the `admin:gpg_key` scope.")
                ]),
                .tip("Each row links you mentally to where to fix things — the *passphrase* row's resolution lives in **Settings → Passphrase**; the *git* row's in the **Signing** tab; the *GitHub* row in the **GitHub** card on the Signing tab.")
            ]),
            HelpSection("My Keys", [
                .paragraph("One card per secret key on this Mac. Each card shows the User ID, fingerprint, algorithm, creation date, and expiry — plus action buttons."),
                .keyValue([
                    ("Set as Default", "Writes `default-key` in `~/.gnupg/gpg.conf` to this key. Shown only on non-default keys."),
                    ("Edit User ID", "Opens a sheet to change the Name / Email / Comment. Adds a new UID and marks it primary; the original UID stays for history."),
                    ("Enable Touch ID", "Imports an existing pinentry-mac Keychain entry and re-protects it with Touch ID + the GPG Manager access group. Shown when a Keychain entry exists but isn't biometric."),
                    ("Copy Public Key", "Copies the armored public block to the clipboard — paste into GitHub, GitLab, or send to a collaborator."),
                    ("Add to GitHub", "Uploads to the active GitHub account. Shown only when the key isn't already registered there."),
                    ("⋯ menu", "**Delete Key…** — confirms, then removes both the secret and public halves locally. Past commits keep their signatures; you just can't sign new ones with that key.")
                ])
            ]),
            HelpSection("Key badges", [
                .keyValue([
                    ("DEFAULT", "Your default signing key — used by `gpg --sign` and `git commit -S` when no key is specified."),
                    ("EXPIRED", "Past its expiration date. Won't sign anymore — extend the expiry or roll a new key."),
                    ("EXPIRING SOON", "Less than 30 days until expiry."),
                    ("NOT ON GITHUB", "The active GitHub account doesn't have a copy of this key. Commits signed with it won't show Verified on github.com."),
                    ("STALE ON GITHUB", "GitHub considers this key expired but your local copy isn't. Usually means you extended the expiry locally — use **Refresh** in the GitHub card to push the update.")
                ])
            ]),
            HelpSection("Info popover (ⓘ)", [
                .paragraph("Click the ⓘ on any key card to see the full fingerprint, keygrip, algorithm, capabilities, trust, all User IDs, and subkeys — useful when debugging or cross-referencing what GPG sees.")
            ])
        ]
    )
}
