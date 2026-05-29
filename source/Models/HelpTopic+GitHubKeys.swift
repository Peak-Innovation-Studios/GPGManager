import Foundation

extension HelpTopic {
    static let gitHubKeys = HelpTopic(
        id: "github-keys",
        title: "GitHub Keys",
        summary: "View, upload, replace, rename, and remove the keys GitHub uses to verify your commits.",
        systemImage: "checkmark.shield",
        category: .features,
        sections: [
            HelpSection([
                .paragraph("The **GitHub** card on the Signing tab mirrors the keys registered on your GitHub account. GitHub uses these to verify the signatures on your commits — without an uploaded public key, your commits show as *Unverified*.")
            ]),
            HelpSection("How it talks to GitHub", [
                .paragraph("GPG Manager uses the official `gh` CLI to authenticate. There's no separate token to manage; whatever account you're signed into with `gh auth login` is what GPG Manager talks to."),
                .keyValue([
                    ("Required scope", "`admin:gpg_key` — gh's default scope set doesn't include this. If missing, you'll see a yellow *Grant access* prompt with a copy-able `gh auth refresh` command."),
                    ("Multi-account", "If `gh` is logged into more than one account, an account picker appears in the card header. Switching accounts re-checks against the newly selected account.")
                ])
            ]),
            HelpSection("Per-key actions", [
                .paragraph("Each row shows the key's name, email, key ID, expiry, and whether it matches one of your local secret keys. The action menu varies by state:"),
                .keyValue([
                    ("Add to GitHub", "(Shown next to local keys not yet uploaded.) Uploads the armored public block to the active account."),
                    ("Refresh", "Re-uploads the local copy when GitHub's version is stale — typically because you extended the expiry locally."),
                    ("Replace", "Swaps an old GitHub-registered key for a different local one. Uploads the new key first; only removes the old one if the upload succeeded."),
                    ("Rename", "GitHub's API doesn't allow editing the name, so this deletes + re-uploads the key under the new name. Past commits keep their Verified badge — GitHub stores the signature at sign time, not by lookup."),
                    ("Remove from GitHub", "Deletes the registration. Past commits remain Verified; future commits signed with this key won't.")
                ])
            ]),
            HelpSection("Verified badges across orgs", [
                .paragraph("GitHub matches signed commits against your account's GPG keys regardless of which repository the commit lands in — personal or organizational. You don't need to upload the key separately for each org you contribute to.")
            ]),
            HelpSection("If GitHub status is unavailable", [
                .paragraph("If `gh` isn't installed or isn't logged in, the card explains and offers no actions. Install with:"),
                .code("brew install gh\ngh auth login --scopes admin:gpg_key"),
                .tip("This is optional. The rest of the app works fine without `gh`; you'll just have to upload public keys to GitHub manually via the website.")
            ])
        ]
    )
}
