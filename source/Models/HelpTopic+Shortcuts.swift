import Foundation

extension HelpTopic {
    static let menusAndShortcuts = HelpTopic(
        id: "menus-shortcuts",
        title: "Menus & Shortcuts",
        summary: "Keyboard shortcuts and menu commands available throughout the app.",
        systemImage: "command",
        category: .reference,
        sections: [
            HelpSection("Application menu", [
                .keyValue([
                    ("⌘ ,", "Open Settings."),
                    ("⌘ Q", "Quit GPG Manager. (`gpg-agent` keeps running — it's a system daemon.)"),
                    ("Check for Updates…", "Sparkle-powered update check.")
                ])
            ]),
            HelpSection("GPG menu", [
                .keyValue([
                    ("⌘ R", "Refresh — re-discover GPG installations and reload your keyring."),
                    ("⇧ ⌘ K", "Restart `gpg-agent` — clears its cache, picks up new `gpg-agent.conf`. Equivalent to `gpgconf --kill gpg-agent`.")
                ]),
                .tip("Restart Agent is the fix for most \"why isn't `gpg-agent` doing what I told it to\" moments — config changes, stuck sessions, frozen prompts.")
            ]),
            HelpSection("Toolbar buttons", [
                .keyValue([
                    ("New Key", "Open the key-generation sheet."),
                    ("Import Key", "File picker for `.asc` / `.gpg` / `.key` files."),
                    ("Refresh", "Same as ⌘ R."),
                    ("Restart Agent", "Same as ⇧ ⌘ K.")
                ])
            ]),
            HelpSection("Window-specific", [
                .keyValue([
                    ("View Public Keys…", "Opens the Public Keys window. Available from the Overview tab once you have at least one downloaded public key.")
                ])
            ]),
            HelpSection("Help menu", [
                .keyValue([
                    ("⌘ ?", "Open this Help window."),
                    ("Per-topic items", "Jump straight to a specific topic.")
                ])
            ])
        ]
    )
}
