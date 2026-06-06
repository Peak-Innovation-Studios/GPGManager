# GPGManager — Project Memory

A modern macOS-native GUI for managing GPG keys, gpg-agent settings, and Git signing — with a bundled custom **pinentry helper** that handles passphrase prompts system-wide.

## Project overview

**Two targets in one app bundle:**
1. **GPGManager** — the SwiftUI macOS app (sidebar: Overview / Signing; Settings: Passphrase / Key Server / About; public keys and Help open in their own windows)
2. **PinentryGPGManager** — a command-line Swift binary that speaks the Assuan protocol over stdin/stdout, pops a SwiftUI passphrase dialog, and lives at `Contents/MacOS/PinentryGPGManager` inside the main app bundle

Both targets ship as one signed app.

## Key architecture decisions

- **macOS 15+ deployment target.** Swift 6 with strict concurrency. SwiftUI everywhere; `@Observable` (no Combine, no `ObservableObject`).
- **State container:** single `GPGAppState` (`@MainActor @Observable`) with feature-specific extensions (`GPGAppState+Git.swift`, `+Pinentry.swift`, `+Password.swift`, `+KeyCleanup.swift`, `+Installations.swift`, `+Keys.swift`, `+Keychain.swift`, `+Configuration.swift`, `+Preview.swift`). The core `GPGAppState.swift` holds only stored properties, the service instances, computed accessors, and `bootstrap`/`refreshAll`. Service instances and the `appStateLog` logger are declared **internal** (plain `let`, not `private`) precisely so these sibling extensions can reach them.
- **Pinentry is our own Assuan-protocol implementation**, not a re-skin or bundle of pinentry-mac. License-clean and brand-controlled. See `PinentryGPGManager/Assuan/` for the protocol layer.
- **Touch ID + Keychain** for passphrase persistence. Items stored under service `"GnuPG"` with the **keygrip** as account — interoperable with pinentry-mac entries. Every SecItemAdd/Update sets `kSecAttrLabel` to a human description threaded from create-key (`"Name <email> (fingerprint8…)"`).
- **gpg.program is a global-only git config.** Per-repo overrides get unset automatically — see `GitConfigService.apply(_:scope:)`.
- **Signing keys persisted as full 40-char fingerprints.** Never short or long key IDs. Normalization happens on both read and write paths.
- **GitHub registered-key check via `gh` CLI** at bootstrap, in background. Needs `admin:gpg_key` scope; UI offers a Copy Command button when the scope is missing. Multi-account routing: `GitHubGPGService.environment(for:)` resolves `gh auth token --user <login>` and sets `GH_TOKEN`.
- **gpg key list calls are serialized.** `--list-keys` and `--list-secret-keys` cannot run concurrently under gpg 2.5's keyboxd backend — one will race and return empty. Errors from `--list-secret-keys` re-throw (no silent `try?`).
- **Dependency injection for testability.** Process execution is abstracted behind the `CommandRunning` protocol (in `GPGCommandRunner.swift`); the four IO services (`GPGKeyService`, `GitConfigService`, `GitHubGPGService`, `GPGAgentService`) take an injected runner with a production default (`= GPGCommandRunner()`). Tests inject `FakeCommandRunner` (in `GPGManagerTests/Fakes.swift`) to assert the exact command line built and feed back canned stdout / exit codes. `GPGAppState` likewise has a DI init taking the services + an `any KeychainPassphraseStoring` (so the keychain branches use `FakeKeychainStore` instead of the real Keychain). The protocol carries the full argument list and convenience overloads supply the defaults, so existing call sites (`runner.run(executablePath:arguments:)`) are unchanged. `HomebrewDiscoveryService` and `GitHubGPGService` also inject their executable-probe as an `@Sendable` closure.
- **`--with-keygrip` on list-keys** so `key.primaryKeygrip` is populated; needed by the synchronous `hasKeychainEntry(for:)` used to drive "Enable Touch ID" visibility.
- **In-app help is a data model, not a doc bundle.** `HelpTopic` / `HelpSection` / `HelpBlock` (in `Models/HelpTopic.swift`) plus one `HelpTopic+<Name>.swift` extension file per topic. `HelpView` is a `NavigationSplitView`; selection persists via `@AppStorage("help.selectedTopic")` so Help-menu deep links (in `HelpCommands` inside `GPGManagerApp.swift`) work. Adding a topic: write a new extension file, add `.<name>` to `HelpContent.allTopics`.
- **Release distribution has three layers.** R2/Sparkle is the primary update channel, GitHub Releases are the public version history and Homebrew asset source, and the Homebrew tap refresh is dispatched only after the GitHub Release asset is confirmed. Publish GitHub Releases for public versioned releases, not every CI build number. Xcode Cloud and GitHub Actions now share the same distribution shape; GitHub Actions packages the public artifact as a notarized, stapled DMG.

## Important conventions

- **Keep source files ≤ 250 lines.** Split by functionality when they grow.
- Swift idioms: `foregroundStyle`, `clipShape(.rect(cornerRadius:))`, `Tab` over `tabItem`, modern URL APIs (`appending(path:directoryHint:)`), `bold()` over `fontWeight(.bold)`, prefer `Button(_:systemImage:action:)`.
- No GCD. No Combine. No `ObservableObject`. No force unwraps. No `AnyView` unless necessary.
- For SwiftUI on macOS, the new `Tab` API and `.windowResizability(.contentSize)` are required for our Settings tab sizing trick — see `SettingsView.swift`'s `.onGeometryChange` measurement.

## Build / run

- Open `GPGManager.xcodeproj` in Xcode 26+ on macOS 15+.
- Active scheme: **GPGManager**. Build runs both targets; the helper is embedded automatically via the GPGManager target's **Copy Files** build phase (destination: Executables, with `CodeSignOnCopy`).
- **SwiftLint runs locally** as a Run Script build phase on the GPGManager target, which just calls `scripts/swiftlint.sh` (resolves the repo root, adds `/opt/homebrew/bin` to PATH, lints against `.swiftlint.yml`). Install once with `brew install swiftlint`. Run by hand with `scripts/swiftlint.sh` (lint), `--fix` (autocorrect), or `--strict` (fail on warnings). The config is intentionally lenient: `line_length` 325, `identifier_name`/`type_name`/`force_cast` disabled, `file_length` warns at 800. The ≤250-line file rule below is a *project convention*, not a lint rule — don't expect SwiftLint to flag it.
- Tests: ⌘U runs both target test suites (`GPGManagerTests` + `PinentryGPGManagerTests`). 81 + 26 = 107 passing as of 2026-06-05. Service-layer and `GPGAppState` orchestration tests use the `CommandRunning`/`KeychainPassphraseStoring` injection seams (see the DI bullet under Key architecture decisions).
- GitHub Actions: `.github/workflows/ci.yml` builds and tests on public macOS runners, uploads the `.xcresult`, emits `summary.md`, `summary.json`, and `junit.xml`; `.github/workflows/release.yml` is the manual/tag fallback for Developer ID signing, app + DMG notarization, Sparkle/R2 upload, GitHub Release asset publishing, and Homebrew tap dispatch.

## Files added to PinentryGPGManager/

The folder is a `PBXFileSystemSynchronizedRootGroup` — anything added to disk automatically joins the helper target. To make a file also a member of `PinentryGPGManagerTests`, use the File Inspector → Target Membership in Xcode (an `PBXFileSystemSynchronizedBuildFileExceptionSet` entry gets added).

## Quirks / gotchas

- **Pinentry helper module isolation:** Swift modules are target-scoped. Types defined in `PinentryGPGManager` aren't visible to `GPGManager` and vice versa. We duplicate `PassphraseStrengthBar` between targets with a sync-note. Don't try to share via `@testable import` — won't work cross-target.
- **CLI executables can't host XCTest bundles.** `PinentryGPGManagerTests` is hosted by `GPGManager.app`. Test files compile the helper's source directly (multi-target membership) rather than via `@testable import`.
- **Editing the .pbxproj while Xcode is open will crash Xcode.** Always ask the user to make pbxproj changes in the Xcode UI. Two carve-outs: (1) the `xcode-tools` MCP `XcodeWrite`/`XcodeUpdate`/`XcodeMV`/`XcodeRM` tools mutate the project *safely* through Xcode itself — use them to add new main-target source files. Note `XcodeWrite`'s param is `content` (singular), not `contents`. (2) Files dropped into `PinentryGPGManager/` auto-join via the synchronized group, so plain `Write` is fine there. There is no MCP tool to add a **build phase** or change a **build setting** — those still need the Xcode UI.
- **SwiftLint build phase needs `ENABLE_USER_SCRIPT_SANDBOXING = No`.** The Run Script phase that calls `scripts/swiftlint.sh` reads source files across the project; with user-script sandboxing on (the Xcode default for new projects) the phase fails with a permission error. Setting is per-target in Build Settings ("User Script Sandboxing").
- **First-launch GitHub check:** if `gh` is missing or unauthenticated, we silently fall back to "Copy & Open GitHub" (no error spam). Only when `gh` returns a scope-missing error do we show the actionable "Copy Command" UI.
- **Settings tab heights are measured at runtime** via `.onGeometryChange` and `@AppStorage`-persisted across launches. If a tab feels cropped/oversized, the issue is almost always a `.fixedSize` missing somewhere in the tab's content tree.
- **Touch ID doesn't work in Debug builds.** Xcode auto-adds `com.apple.security.get-task-allow` to Debug builds so the debugger can attach, and that entitlement is mutually exclusive with `kSecAttrAccessControl = .userPresence`. `SecItemAdd` returns `errSecSuccess` but **silently fails to persist the item** — no error surfaced anywhere. `KeychainPassphraseStore.save()` defends against this with a post-add `SecItemCopyMatching` verification: if the item isn't findable after add, we log "phantom-success" and fall through to the non-biometric recovery path so the passphrase still lands. To test Touch ID locally, switch the scheme's Run config to Release or use the archive + Developer ID re-sign flow in `scripts/notarize.sh`.
- **Keychain entries live in a custom access group** (`Z2R2L2TJ7Y.com.peakinnovationstudios.GPGManager`), declared by both targets in their **Release** `.entitlements`. Required because `userPresence` ACL needs the `keychain-access-groups` entitlement. Side effects: items are **not visible in Keychain Access.app** by default (it filters to the user's default group), and `security` CLI without the entitlement can't see them. `KeychainPassphraseStore.exists/read` check both our group AND the default group as a fallback so legacy pinentry-mac entries remain readable.
- **Debug entitlements must stay empty.** Both targets have a separate `*.Debug.entitlements` file with an empty `<dict/>`, wired via per-configuration `CODE_SIGN_ENTITLEMENTS`. Xcode Cloud's build-for-testing path uses ad-hoc signing (`codesign --sign -`), which cannot authorize `keychain-access-groups` — declaring it in Debug makes AMFI kill the test host with `SIGKILL (Code Signature Invalid)` and the test runner can't launch. Touch ID already doesn't work in Debug (see the `get-task-allow` note above), so the Debug entitlements have nothing useful to declare.
- **Don't pass `kSecAttrAccessGroup` together with `kSecAttrAccessControl = .userPresence`** in the same `SecItemAdd` dictionary. The combination silently no-ops — `SecItemAdd` returns success but the item isn't persisted. With the entitlement declared, items implicitly land in the first declared group when no group attribute is specified.
- **Delete a key with `--delete-secret-keys` first, then `--delete-keys`.** gpg refuses to delete the public key while a secret is present. Order matters.
- **Edit User ID handles "UID already exists"** by skipping the add step and only setting primary on the matching existing UID. Without that path, repeat-editing a key to a previously-used name fails.
- **Pinentry window placement:** `NSWindow.center()` uses the main display, which is wrong when Terminal lives on a secondary monitor. `PromptWindowHost.centerOnActiveScreen(_:)` picks the screen under `NSEvent.mouseLocation` instead.

## Where to look first

| When you need to… | Open |
|---|---|
| Add a git config field | `Services/GitConfigService.swift` + `Models/GitSigningConfiguration.swift` |
| Modify pinentry behavior | `PinentryGPGManager/Prompt/PinentryController.swift` |
| Touch a passphrase flow | `Views/CreateKeyView.swift` (main app) or `Prompt/PassphraseView.swift` (helper) |
| Add a Settings tab | `Views/Settings/` (one file per tab); register in `SettingsView.swift` |
| Read or write GPG itself | `Services/GPGKeyService.swift` + `Services/GPGCommandRunner.swift` |
| Modify the secret-key cards (badges, actions, menus) | `Views/Overview/MyKeysPanel.swift` |
| Add a GitHub key action (delete/rename/refresh/replace) | `Views/Signing/GitHubKeysCard.swift` + `GitHubKeyRow.swift`; service in `Services/GitHubGPGService.swift` |
| Add an algorithm strength rule | `Models/GPGKeyAlgorithm.swift` (covered by `GPGKeyAlgorithmTests`) |
| Edit / migrate / delete keychain entries | `Services/KeychainPassphraseStore.swift` (main) + `PinentryGPGManager/Security/KeychainPassphraseStore.swift` (helper) |
| Add or edit a Help topic | `Models/HelpTopic+<Name>.swift` (one per topic); register in `HelpContent.allTopics`; renderers in `Views/Help/` |
| Tweak the About surface | `Views/Settings/AboutSettingsTab.swift` |

## Documentation pointers

- `Journal.md` — running history with bug war stories and aha moments
- `README.md` — public-facing entrypoint for the repo
- `docs/xcode-cloud.md` — how the Xcode Cloud workflow is configured and what `ci_scripts/` does
- `docs/help-system-prompt.md` — portable prompt for reproducing the in-app help architecture in other projects
- This file — project memory for AI assistants
