import Foundation

extension HelpTopic {
    static let welcome = HelpTopic(
        id: "welcome",
        title: "Welcome to GPG Manager",
        summary: "A quick tour of what the app does and where things live.",
        systemImage: "sparkles",
        category: .gettingStarted,
        sections: [
            HelpSection([
                .paragraph("GPG Manager is a native macOS app for managing OpenPGP keys, configuring `gpg-agent`, and signing your Git commits — all from a clean SwiftUI interface."),
                .paragraph("It wraps the standard `gpg` command-line tool, so the keys it creates work everywhere — Terminal, Xcode, GitHub Desktop, `git`, and any other OpenPGP-aware tool on your machine.")
            ]),
            HelpSection("What you can do", [
                .bullets([
                    "**Create and manage keys** — generate new OpenPGP key pairs and view, edit, or delete existing ones.",
                    "**Sign Git commits** — wire up `git` to sign automatically, globally or per repository.",
                    "**Sync with GitHub** — see which of your keys are registered, upload new ones, and remove old ones.",
                    "**Touch ID unlock** — store passphrases in Keychain and approve signatures with your fingerprint.",
                    "**Replace or supplement `pinentry-mac`** — use the bundled passphrase prompt or keep the one you already trust.",
                    "**Manage downloaded public keys** — browse signature-verification keys and prune the ones you don't need."
                ])
            ]),
            HelpSection("Where to find things", [
                .keyValue([
                    ("Overview tab", "GPG installation, setup checklist, and your secret keys."),
                    ("Signing tab", "Git signing configuration and GitHub-registered keys."),
                    ("Public Keys window", "Imported and downloaded public keys (open from the Overview)."),
                    ("Settings → Passphrase", "Pinentry provider, passphrase caching, Keychain access."),
                    ("Settings → Key Server", "Keyserver choice and downloaded-key cleanup."),
                    ("Settings → About", "App and GPG runtime info, links, credits.")
                ]),
                .tip("New here? Open **Getting Started** in the sidebar for a walkthrough from install to your first signed commit.")
            ])
        ]
    )
}
