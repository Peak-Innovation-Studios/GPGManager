# GPGManager

A modern macOS GUI for managing GPG keys, gpg-agent, and Git signing — with a bundled Assuan-speaking pinentry that integrates with Touch ID and the macOS Keychain.

> Built because GPG GUIs on macOS have felt stuck in 2008.

## Features

- **Overview** — your secret keys front and center, each card showing the user ID, algorithm + strength advice, expiry, default-key + GitHub registration badges, and inline actions: Set as Default, Edit User ID, Enable Touch ID, Copy Public Key, Add to GitHub, Delete Key. A separate "All Public Keys" window opens on demand for keys imported from contacts.
- **Create new keys** — ECC ed25519 / RSA 4096 / RSA 3072, with diceware passphrase suggestion, a SETREPEAT-style confirm-new-passphrase field, strength meter, and one-click Save to Keychain (Touch ID-backed).
- **Signing** — one-shot Git + GitHub signing setup:
  - Pick signing key, toggle sign-commits / sign-tags / show-signature-in-log
  - Target: Global or any remembered repo (with editable named labels, persisted across launches)
  - Inheritance-aware Apply: per-repo Apply unsets local overrides that match Global; Apply only enables when the draft differs from the saved state
  - GitHub key management via `gh` CLI: list registered keys, add/delete/rename/replace, multi-account routing via `GH_TOKEN`, refresh button to pick up out-of-band changes
- **Settings** — Passphrase (Keychain provider toggle + cache TTLs), Key Server, About. Each tab measures its own height at runtime so the window resizes cleanly as you switch.
- **Custom pinentry helper** — `PinentryGPGManager` is bundled into the app at `Contents/MacOS/`. When installed as the system pinentry, every GPG operation (Git signing from Terminal, Mail decryption, …) gets our native SwiftUI passphrase dialog with the app icon, Touch ID for previously-saved passphrases, "Save in Keychain" checkbox, passphrase strength meter, SETREPEAT-aware confirm-new-passphrase flow, full VoiceOver labelling, and Dynamic Type scaling.
- **Touch ID migration** — for keys whose passphrase is already in the Keychain from pinentry-mac, "Enable Touch ID" reads the existing entry and re-stores it under our service with `userPresence` access control. Interoperable with pinentry-mac's existing items (service: `GnuPG`, account: keygrip).
- **In-app Help** — twelve documentation topics covering Getting Started, every feature, configuration, and troubleshooting, with deep-link items in the Help menu (⌘?). Paragraphs render Markdown, code blocks have copy buttons, and tips/notes/warnings get distinct callouts. The redesigned About tab includes a hero icon, version pill with copy-info, and Website / GitHub / Issues links.

## Install

### Homebrew

```sh
brew tap peak-innovation-studios/tap
brew install --cask gpg-manager
brew install gnupg
```

### Direct Download

Download the latest notarized build from:

https://updates.peakinnovationstudios.com/gpg-manager/GPGManager.zip

After installing the app, make sure GnuPG itself is installed:

```sh
brew install gnupg
```

## Requirements

- macOS 15 (Sequoia) or later
- GPG itself installed via Homebrew (`brew install gnupg`)

Optional:
- [`gh`](https://cli.github.com/) CLI authenticated with `admin:gpg_key` scope for the GitHub key listing / add / delete features

## Build

Requires Xcode 26+.

```sh
git clone git@github.com:Peak-Innovation-Studios/GPGManager.git
cd GPGManager
open GPGManager.xcodeproj
# Build & Run (⌘R) — scheme: GPGManager
```

The build embeds the pinentry helper into the app bundle automatically via a Copy Files build phase.

### Tests

```sh
# In Xcode: ⌘U
# Or from the command line:
xcodebuild -project GPGManager.xcodeproj -scheme GPGManager -destination 'platform=macOS' test
```

76 tests across the two test targets cover the Assuan codec, command parsing, session loop, config stores, key parsing, key matching, user-ID parsing, algorithm classification, GitHub account parsing, Homebrew discovery, passphrase generation, passphrase strength, and create-key parameter rendering.

## Architecture

Two Xcode targets, one signed app:

```
GPGManager.app/
└─ Contents/
   ├─ MacOS/
   │  ├─ GPGManager                  SwiftUI app
   │  └─ PinentryGPGManager          Assuan-speaking CLI helper (signed, embedded)
   └─ Resources/
      └─ GPGManager.icns
```

The helper is a separate Swift module — it speaks the Assuan protocol over stdin/stdout, presents a SwiftUI passphrase window when gpg-agent sends `GETPIN` / `CONFIRM` / `MESSAGE`, and supports Touch ID via Keychain ACLs on stored passphrase items.

State management is `@Observable` (no Combine, no `ObservableObject`). All views read state via `@Environment(GPGAppState.self)`.

See [`CLAUDE.md`](./CLAUDE.md) for a deeper architecture brief, [`Journal.md`](./Journal.md) for the development history and war stories, and [`docs/xcode-cloud.md`](./docs/xcode-cloud.md) for the CI/notarize setup.

## Notes

The app is intentionally not sandboxed. It needs direct access to your local GPG binaries, `~/.gnupg`, your Git configuration, and the macOS Keychain for passphrase storage.

## License

[GNU General Public License v3.0](./LICENSE). If you distribute a modified version of this app, you must release your changes under the same license.

## Author

[Peak Innovation Studios](https://github.com/Peak-Innovation-Studios) (`com.peakinnovationstudios.GPGManager`)
