import Foundation

extension HelpTopic {
    static let publicKeysWindow = HelpTopic(
        id: "public-keys-window",
        title: "Public Keys Window",
        summary: "Browse keys whose secret half you don't have — collaborators, downloaded for verification, etc.",
        systemImage: "list.bullet.rectangle",
        category: .features,
        sections: [
            HelpSection([
                .paragraph("From the Overview tab, click **View Public Keys…** to open a dedicated window listing every public key in your GPG keyring whose secret half *isn't* on this Mac.")
            ]),
            HelpSection("Where these keys come from", [
                .bullets([
                    "Manually imported (drag-and-drop or **Import Key** in the toolbar) — for example, a colleague's public key.",
                    "Auto-downloaded from a keyserver when GPG encounters a signature it can't verify (see **Key Servers** topic).",
                    "Imported as part of someone else's signed file or message."
                ]),
                .note("Your own secret keys don't appear here — they live on the Overview tab's *My Keys* panel. This window is exclusively the *public-only* set.")
            ]),
            HelpSection("Layout", [
                .keyValue([
                    ("Left table", "User ID, key ID, expiry. Click a row to inspect."),
                    ("Right pane", "Full fingerprint, algorithm, capabilities, trust, creation/expiry dates, and all User IDs.")
                ])
            ]),
            HelpSection("Toolbar actions", [
                .keyValue([
                    ("Import Key", "Opens a file picker. Supports `.asc`, `.gpg`, `.key`, and any armored or binary public-key file."),
                    ("Copy Public Key", "Copies the armored block for the selected key to the clipboard — handy for sharing with a service or another tool.")
                ])
            ]),
            HelpSection("Pruning the list", [
                .paragraph("If auto-key-retrieve is on, this list can grow over time. Open **Settings → Key Server → Clean…** to bulk-remove downloaded keys you no longer need.")
            ])
        ]
    )
}
