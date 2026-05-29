import Foundation

extension HelpTopic {
    static let gitSigning = HelpTopic(
        id: "git-signing",
        title: "Git Signing",
        summary: "Configure git to sign commits globally or per repository.",
        systemImage: "signature",
        category: .features,
        sections: [
            HelpSection([
                .paragraph("The Signing tab's **Git Signing** card is a GUI for the handful of `git config` keys that control commit signing. Changes don't take effect until you click **Apply**.")
            ]),
            HelpSection("Target: Global vs Repository", [
                .paragraph("All Git config is layered. The **Target** picker chooses which layer GPG Manager edits:"),
                .keyValue([
                    ("Global (~/.gitconfig)", "Applies to every repository that doesn't have its own override. The default and best choice for most setups."),
                    ("A remembered repository", "Edits `<repo>/.git/config` only. Lets you sign in one project and not in another, or use a different key.")
                ]),
                .paragraph("To work with a specific repo, choose **Add Repository…** from the picker and pick a folder. It stays in the list until you click **Forget Repository**."),
                .note("Per-repo configs *override* the global one. When you're viewing a repo target, captions like *Inherited from global* or *Set in this repo* tell you which layer each field is coming from.")
            ]),
            HelpSection("The fields", [
                .keyValue([
                    ("Signing Key", "Sets `user.signingKey` to the full 40-character fingerprint of the selected key."),
                    ("Sign commits by default", "Sets `commit.gpgsign=true`. Equivalent to adding `-S` to every `git commit`."),
                    ("Sign tags by default", "Sets `tag.gpgSign=true`. Equivalent to `-s` on every `git tag`."),
                    ("Show signature info in git log", "Sets `log.showSignature=true`. `git log` will print whether each commit is signed and verified.")
                ]),
                .tip("**Signing Key** is always stored as a full fingerprint, never a short key ID. Short IDs are vulnerable to collisions, and modern Git wants the long form anyway.")
            ]),
            HelpSection("GPG path", [
                .paragraph("`gpg.program` tells Git which binary to invoke for signing. GPG Manager always sets this **globally** — even when you're editing a per-repo config — so all your repos use the same `gpg`."),
                .note("Per-repo `gpg.program` overrides are silently unset by GPG Manager. If you need a non-standard binary for one repo, set it manually via `git config` and GPG Manager will leave it alone until you next Apply.")
            ]),
            HelpSection("Git identity", [
                .paragraph("Shows your effective `user.name` and `user.email`. Read-only here — set it from Terminal if it's missing:"),
                .code("git config --global user.name \"Your Name\"\ngit config --global user.email \"you@example.com\""),
                .warning("Git refuses to commit if either is unset. The card flags this in orange when you're targeting a repo without an inherited identity.")
            ]),
            HelpSection("Examples", [
                .paragraph("**Sign everything from this machine.** Target = Global. Pick your key. Turn on **Sign commits** (and **Sign tags** if you cut release tags). Apply."),
                .paragraph("**Sign only one work repo with a different key.** Target = Add Repository… and pick the work folder. Choose the work key. Turn on **Sign commits**. Apply. Your other repos stay unaffected."),
                .paragraph("**Stop signing temporarily without losing config.** Toggle off **Sign commits by default** and Apply. The signing key stays selected so you can re-enable later with one click.")
            ])
        ]
    )
}
