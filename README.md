# GPGManager

A modern macOS GUI for managing GPG keys, gpg-agent, and Git signing — with a bundled Assuan-speaking pinentry that integrates with Touch ID and the macOS Keychain.

> Built because GPG GUIs on macOS have felt stuck in 2008.

## Features

- **Keys** — list public + secret keys with a filter (All / Secret / Public), counts per filter, a visual badge on your own secret keys, import, copy public key, and **create new** keys (ECC ed25519 / RSA 4096 / RSA 3072) with diceware passphrase suggestion and one-click macOS Keychain save
- **Agent** — view and edit `gpg-agent.conf` (cache TTLs, pinentry program, preserved extra lines)
- **Settings** — Default Key, Password (Keychain + cache TTL), Key Server, GPG Executable picker, About — all in a content-aware sidebar window that resizes per tab
- **Tools** — one-shot Git + GitHub signing setup:
  - Pick signing key, toggle sign-commits / sign-tags / show-signature-in-log
  - Target: Global or any remembered repo (with editable named labels, persisted across launches)
  - Inheritance-aware Apply: per-repo Apply unsets local overrides that match Global
  - GitHub check via `gh` CLI: detects whether the selected key is already registered and gates the "Add to GitHub" button
- **Custom pinentry helper** — `PinentryGPGManager` is bundled into the app at `Contents/MacOS/`. When installed as the system pinentry, every GPG operation (Git signing from Terminal, Mail decryption, …) gets our native SwiftUI passphrase dialog with the app icon, Touch ID for previously-saved passphrases, "Save in Keychain" checkbox, passphrase strength meter, and SETREPEAT-aware confirm-new-passphrase flow

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 26+ to build
- GPG itself installed via Homebrew (`brew install gnupg`) or GPG Suite

Optional:
- [`gh`](https://cli.github.com/) CLI authenticated with `admin:gpg_key` scope for the "Already on GitHub" detection

## Build

```sh
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

46 tests across the two test targets cover the Assuan codec, command parsing, session loop, config stores, key parsing, key matching, passphrase generation, passphrase strength, and create-key parameter rendering.

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

The helper is a separate Swift module — it speaks the Assuan protocol over stdin/stdout, presents a SwiftUI passphrase window when gpg-agent sends `GETPIN` / `CONFIRM` / `MESSAGE`, and supports Touch ID via Keychain ACLs on stored passphrase items (interoperable with pinentry-mac's existing entries).

State management is `@Observable` (no Combine, no `ObservableObject`). All views read state via `@Environment(GPGAppState.self)`.

See [`CLAUDE.md`](./CLAUDE.md) for a deeper architecture brief, and [`Journal.md`](./Journal.md) for the development history and war stories.

## Notes

The app is intentionally not sandboxed. It needs direct access to your local GPG binaries, `~/.gnupg`, your Git configuration, and the macOS Keychain for passphrase storage.

## License

TBD — not yet published.

## Author

Peak Innovation Studios (`com.peakinnovationstudios.GPGManager`)
