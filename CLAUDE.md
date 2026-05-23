# GPGManager — Project Memory

A modern macOS-native GUI for managing GPG keys, gpg-agent settings, and Git signing — with a bundled custom **pinentry helper** that handles passphrase prompts system-wide.

## Project overview

**Two targets in one app bundle:**
1. **GPGManager** — the SwiftUI macOS app (the user-facing UI: Overview / Keys / Agent / Tools / Settings)
2. **PinentryGPGManager** — a command-line Swift binary that speaks the Assuan protocol over stdin/stdout, pops a SwiftUI passphrase dialog, and lives at `Contents/MacOS/PinentryGPGManager` inside the main app bundle

Both targets ship as one signed app.

## Key architecture decisions

- **macOS 15+ deployment target.** Swift 6 with strict concurrency. SwiftUI everywhere; `@Observable` (no Combine, no `ObservableObject`).
- **State container:** single `GPGAppState` (`@MainActor @Observable`) with feature-specific extensions (`GPGAppState+Git.swift`, `+Pinentry.swift`, `+Password.swift`, `+Preview.swift`).
- **Pinentry is our own Assuan-protocol implementation**, not a re-skin or bundle of pinentry-mac. License-clean and brand-controlled. See `PinentryGPGManager/Assuan/` for the protocol layer.
- **Touch ID + Keychain** for passphrase persistence. Items stored under service `"GnuPG"` with the **keygrip** as account — interoperable with pinentry-mac entries.
- **gpg.program is a global-only git config.** Per-repo overrides get unset automatically — see `GitConfigService.apply(_:scope:)`.
- **Signing keys persisted as full 40-char fingerprints.** Never short or long key IDs. Normalization happens on both read and write paths.
- **GitHub registered-key check via `gh` CLI** at bootstrap, in background. Needs `admin:gpg_key` scope; UI offers a Copy Command button when the scope is missing.

## Important conventions

- **Keep source files ≤ 250 lines.** Split by functionality when they grow.
- Swift idioms: `foregroundStyle`, `clipShape(.rect(cornerRadius:))`, `Tab` over `tabItem`, modern URL APIs (`appending(path:directoryHint:)`), `bold()` over `fontWeight(.bold)`, prefer `Button(_:systemImage:action:)`.
- No GCD. No Combine. No `ObservableObject`. No force unwraps. No `AnyView` unless necessary.
- For SwiftUI on macOS, the new `Tab` API and `.windowResizability(.contentSize)` are required for our Settings tab sizing trick — see `SettingsView.swift`'s `.onGeometryChange` measurement.

## Build / run

- Open `GPGManager.xcodeproj` in Xcode 26+ on macOS 15+.
- Active scheme: **GPGManager**. Build runs both targets; the helper is embedded automatically via the GPGManager target's **Copy Files** build phase (destination: Executables, with `CodeSignOnCopy`).
- Tests: ⌘U runs both target test suites (`GPGManagerTests` + `PinentryGPGManagerTests`). 27 + 19 passing as of 2026-05-22.

## Files added to PinentryGPGManager/

The folder is a `PBXFileSystemSynchronizedRootGroup` — anything added to disk automatically joins the helper target. To make a file also a member of `PinentryGPGManagerTests`, use the File Inspector → Target Membership in Xcode (an `PBXFileSystemSynchronizedBuildFileExceptionSet` entry gets added).

## Quirks / gotchas

- **Pinentry helper module isolation:** Swift modules are target-scoped. Types defined in `PinentryGPGManager` aren't visible to `GPGManager` and vice versa. We duplicate `PassphraseStrengthBar` between targets with a sync-note. Don't try to share via `@testable import` — won't work cross-target.
- **CLI executables can't host XCTest bundles.** `PinentryGPGManagerTests` is hosted by `GPGManager.app`. Test files compile the helper's source directly (multi-target membership) rather than via `@testable import`.
- **Editing the .pbxproj while Xcode is open will crash Xcode.** Always ask the user to make pbxproj changes in the Xcode UI.
- **First-launch GitHub check:** if `gh` is missing or unauthenticated, we silently fall back to "Copy & Open GitHub" (no error spam). Only when `gh` returns a scope-missing error do we show the actionable "Copy Command" UI.
- **Settings tab heights are measured at runtime** via `.onGeometryChange` and `@AppStorage`-persisted across launches. If a tab feels cropped/oversized, the issue is almost always a `.fixedSize` missing somewhere in the tab's content tree.

## Where to look first

| When you need to… | Open |
|---|---|
| Add a git config field | `Services/GitConfigService.swift` + `Models/GitSigningConfiguration.swift` |
| Modify pinentry behavior | `PinentryGPGManager/Prompt/PinentryController.swift` |
| Touch a passphrase flow | `Views/CreateKeyView.swift` (main app) or `Prompt/PassphraseView.swift` (helper) |
| Add a Settings tab | `Views/Settings/` (one file per tab); register in `SettingsView.swift` |
| Read or write GPG itself | `Services/GPGKeyService.swift` + `Services/GPGCommandRunner.swift` |

## Documentation pointers

- `Journal.md` — running history with bug war stories and aha moments
- `README.md` — public-facing entrypoint for the repo
- This file — project memory for AI assistants
