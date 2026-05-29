import Foundation

extension HelpTopic {
    static let creatingKeys = HelpTopic(
        id: "creating-keys",
        title: "Creating Keys",
        summary: "Every field in the New Key form, explained.",
        systemImage: "key.fill",
        category: .features,
        sections: [
            HelpSection([
                .paragraph("Click **New Key** in the main toolbar to open the key-generation sheet. Every field maps directly to a property of the OpenPGP key being created — here's what each one does.")
            ]),
            HelpSection("Identity", [
                .keyValue([
                    ("Name", "Your real name. Shown next to signed commits and on GitHub."),
                    ("Email", "Your email address. The User ID is constructed as `Name <email>`."),
                    ("Comment", "Optional. Useful for distinguishing keys (e.g. *Work*, *2026*). Appears in parentheses in the User ID.")
                ]),
                .tip("Use the email you've verified on GitHub. GitHub only shows the **Verified** badge when the commit's email matches one in your account."),
                .note("These values are embedded in the key. You can edit them later from **Edit User ID** on the key card, but the original UID stays in the key's history.")
            ]),
            HelpSection("Key", [
                .keyValue([
                    ("Algorithm", "Cryptographic algorithm and key size. **Ed25519** is recommended for new keys — fast, small, and modern. **RSA 4096** is the conservative choice if you need compatibility with very old GPG installs."),
                    ("Expires", "When the primary key (and its signing subkey) become invalid. Setting an expiration is good practice — even if your private key leaks, the damage is bounded. You can extend the expiry later from Terminal with `gpg --edit-key <fpr>` → `expire`.")
                ])
            ]),
            HelpSection("Passphrase", [
                .paragraph("The passphrase encrypts the private key on disk. Every time something needs to sign or decrypt, `gpg-agent` asks for it (or pulls it from cache / Keychain)."),
                .bullets([
                    "**Suggest strong passphrase** — generates an 8-word random passphrase (~64 bits of entropy). Strong enough that brute force is infeasible.",
                    "**Strength** bar — a rough quality estimate while you type.",
                    "**Save in Keychain** — stores the passphrase in macOS Keychain protected by Touch ID. Future signatures unlock with a fingerprint instead of typing."
                ]),
                .warning("There's no recovery if you lose your passphrase **and** don't have a Keychain copy. The private key is encrypted with it and cannot be opened any other way.")
            ]),
            HelpSection("GitHub", [
                .paragraph("Optional — adds the new public key to your GitHub account in the same step."),
                .keyValue([
                    ("Upload to GitHub after creation", "If on, GPG Manager runs the `gh` CLI to register the key after generation succeeds."),
                    ("Title", "A short label shown in your GitHub key list. Defaults to your Name. Purely cosmetic — independent of the key's User ID.")
                ]),
                .note("Requires the `gh` CLI installed and authenticated with the `admin:gpg_key` scope. If anything is missing, key creation still succeeds locally — you'll just see an upload error and can re-try from the Signing tab.")
            ]),
            HelpSection("What happens behind the scenes", [
                .paragraph("When you click **Create Key**, GPG Manager:"),
                .steps([
                    "Builds a batch parameter file for `gpg --batch --generate-key`.",
                    "Runs the generation, which creates a primary key and a signing subkey.",
                    "If **Save in Keychain** is on, stores the passphrase under service `GnuPG` with the **keygrip** as account — interoperable with `pinentry-mac` entries.",
                    "Refreshes the secret-key list so the new key shows in **My Keys**.",
                    "If **Upload to GitHub** is on, runs `gh api -X POST /user/gpg_keys` with the armored public block."
                ])
            ])
        ]
    )
}
