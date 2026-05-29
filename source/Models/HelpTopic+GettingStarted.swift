import Foundation

extension HelpTopic {
    static let gettingStarted = HelpTopic(
        id: "getting-started",
        title: "Getting Started",
        summary: "From a fresh install to a verified-signed commit on GitHub.",
        systemImage: "flag.checkered",
        category: .gettingStarted,
        sections: [
            HelpSection("1. Install GPG", [
                .paragraph("GPG Manager needs the `gpg` binary somewhere on your system. The easiest way to get it on macOS is Homebrew."),
                .code("brew install gnupg", caption: "Run in Terminal"),
                .paragraph("If you don't already have Homebrew, GPG Manager will show a card with a link to **brew.sh** and the install command."),
                .tip("Already use GPG Suite or a custom build? GPG Manager will auto-discover any `gpg` in your `PATH` and let you pick one from **Overview → GPG Executable → Change**.")
            ]),
            HelpSection("2. Create your first key", [
                .paragraph("Click **New Key** in the toolbar (top right) and fill in the form. There's a step-by-step breakdown in the **Creating Keys** topic, but the short version:"),
                .steps([
                    "Enter your **Name** and **Email** — these become the User ID embedded in the key.",
                    "Pick an **Algorithm** (Ed25519 is recommended) and an **Expiration** (2 years is a sensible default).",
                    "Set a strong **Passphrase**, or click *Suggest strong passphrase* for an 8-word random one.",
                    "Tick **Save in Keychain** to enable Touch ID unlock for future signatures.",
                    "Optionally tick **Upload to GitHub after creation** to register the new key on github.com.",
                    "Click **Create Key**."
                ])
            ]),
            HelpSection("3. Set it as the default signing key", [
                .paragraph("New keys are added to your keyring but aren't automatically the default. On the Overview tab, find the key in **My Keys** and click **Set as Default**. This writes `default-key` into `~/.gnupg/gpg.conf` so every signing tool — including Git — picks it up.")
            ]),
            HelpSection("4. Configure Git signing", [
                .paragraph("Switch to the **Signing** tab. Under **Git Signing**:"),
                .steps([
                    "Confirm **Target** is **Global** (default for new setups).",
                    "Pick your new key from the **Signing Key** picker.",
                    "Turn on **Sign commits by default**.",
                    "Click **Apply**."
                ]),
                .paragraph("Under the hood this runs the right `git config --global` commands and sets `gpg.program` to the `gpg` binary GPG Manager is using."),
                .note("Want signing only in a particular repository? Use **Add Repository…** from the Target picker and configure it there instead. See **Git Signing** for details.")
            ]),
            HelpSection("5. Tell GitHub about your key", [
                .paragraph("So commits show as **Verified** on github.com, GitHub needs the public half of your key."),
                .paragraph("If you ticked *Upload to GitHub* when creating the key, it's already there. Otherwise:"),
                .steps([
                    "On the **Signing** tab, find the **GitHub** card.",
                    "If you see a *Grant admin:gpg_key* prompt, click **Copy** and run the command in Terminal.",
                    "Click **Upload current default key**, or click **Add to GitHub** next to a specific key in **My Keys**."
                ]),
                .tip("Once your key is uploaded, every signed commit you push will show up with a green Verified badge — including commits to org repositories. GitHub matches on key ID across all your repos.")
            ]),
            HelpSection("6. Try it out", [
                .code("cd ~/your-repo\ngit commit --allow-empty -m \"test: signed commit\"\ngit log --show-signature -1",
                      caption: "Make a signed commit and inspect the signature"),
                .paragraph("If you get a Touch ID prompt or your pinentry shows up, you're set. Push the commit and look for the **Verified** badge on github.com.")
            ])
        ]
    )
}
