# GPGManager — Development Journal

## The Big Picture

Picture this: you're a developer on macOS who signs Git commits with GPG, and the only GUI that's vaguely cared about your workflow in fifteen years is GPG Suite — which still looks and feels like a 2010 prefpane. You can read [the screenshot from May 21, 2026 where GPGManager was just a prompt-generated shell of an app](#) and you'd see exactly that: a window with a flat dark sidebar, no Liquid Glass, no `@Observable`, no Touch ID, no real personality.

This journal is the story of turning that shell into a real macOS app — modern Swift 6, sidebar Settings that match System Settings, a custom passphrase prompt that pops in from a process *we wrote from scratch*, and Git/GitHub integration that figures out what's already configured and doesn't make you re-do work.

It's also a story about GPG itself being a niche that some of us refuse to let die. Encryption may have left email, but Git commit signing has only grown — every "Verified" badge on GitHub is a tiny vote for keeping this craft alive.

## Architecture Deep Dive

Think of GPGManager as a **restaurant with two staff members who share the same building**:

- **GPGManager.app** is the host — talks to the customer (the user), runs the SwiftUI views, holds state in `@Observable` `GPGAppState`, shells out to `gpg` and `git` and `gh` as needed.
- **PinentryGPGManager** is the line cook in the back — a separate command-line binary that lives in `Contents/MacOS/` of the same building. It doesn't talk to the user directly; gpg-agent (the maître d') passes orders to it via stdin, and the cook plates up a SwiftUI passphrase window when it needs to.

These two staff share the same uniform (signed with the same Developer ID, share the app icon), but they have **separate kitchens (Swift modules)** — code in one isn't visible in the other. That's why some files like `PassphraseStrengthBar` are deliberately duplicated with a sync-note comment: we'd rather have two recipes than build a third kitchen just to share one.

### How a passphrase request flows

1. User runs `git commit -S` in Terminal
2. Git asks gpg-agent for a signature
3. gpg-agent realizes it needs the passphrase, spawns `PinentryGPGManager` (because we wrote our path into `~/.gnupg/gpg-agent.conf`)
4. Our helper boots NSApp as `.accessory` (no Dock icon), reads `SETDESC` / `SETKEYINFO` / `GETPIN` from stdin
5. If the keygrip already has a passphrase saved in macOS Keychain, Touch ID prompts — passphrase returned via stdout, no dialog
6. Otherwise, a SwiftUI sheet floats on top of Terminal with the GPGManager icon, you type the passphrase, click OK
7. Helper returns `D <passphrase>\nOK\n` to gpg-agent
8. gpg-agent decrypts the secret key, signs the commit
9. Helper waits for `BYE`, exits cleanly

The whole exchange is **Assuan protocol** — a tiny line-oriented text protocol from the GnuPG team, ~40 years old in spirit if not in years.

### State container

`GPGAppState` is a single `@Observable` `@MainActor` class that holds everything UI-related. It's split across these files to stay under our 250-line-per-file rule:

- `GPGAppState.swift` — properties + bootstrap/refresh + agent/keys
- `GPGAppState+Password.swift` — passphrase provider picker logic + pinentry-mac detection
- `GPGAppState+Pinentry.swift` — installer status + install/uninstall
- `GPGAppState+Git.swift` — git config + remembered repos + GitHub check
- `GPGAppState+Preview.swift` — sample data for SwiftUI Previews

## The Codebase Map

```
GPGManager/
├─ GPGManager/                      # Main app target
│  ├─ App/GPGManagerApp.swift      # SwiftUI App entry + AppDelegate
│  ├─ Models/                       # Pure data: GPGKey, GitSigningConfiguration, GitConfigScope, …
│  ├─ Services/                     # I/O wrappers: GPGCommandRunner, GitConfigService, GitHubGPGService, …
│  ├─ Stores/                       # @Observable state container (split by feature extension)
│  ├─ Views/                        # SwiftUI views, organized by feature
│  │   ├─ Settings/                 # One file per Settings tab
│  │   └─ Tools/                    # GitSigningCard + ManageRepositoriesView
│  └─ Resources/                    # Icon, Info.plist, asset catalog
├─ GPGManagerTests/                 # Swift Testing tests for the main app
├─ PinentryGPGManager/              # Helper CLI target
│  ├─ Assuan/                       # Codec, command/response, line reader, session
│  ├─ Prompt/                       # SwiftUI passphrase + confirm UIs, controller
│  └─ Security/                     # KeychainPassphraseStore (Touch ID-backed read)
├─ PinentryGPGManagerTests/         # Swift Testing for the helper
├─ Design/                          # Icon Composer SVG sources
└─ GPGManager.icon                  # Compiled Icon Composer document
```

## Tech Stack & Why

- **Swift 6 with strict concurrency** — because Sendable + actor isolation catches whole classes of bugs at compile time. We use `@MainActor` on `GPGAppState`, and any `async let` in the service layer is properly resolved before being read.
- **SwiftUI exclusively** — no UIKit interop. We even threw away the original AppKit Settings scene and built a per-tab self-measuring `TabView` with `.onGeometryChange`.
- **`@Observable`, not `ObservableObject`** — fewer recompiles, finer-grained updates, and it lets us use plain `@State` for the root state container in the App.
- **Swift Testing** (`#expect`, `@Test`) — not XCTest. Faster, less ceremony, parameterized tests are first-class.
- **No third-party dependencies.** Everything (Assuan, diceware generator, keychain wrapper, gpg invocation) is in-tree.
- **Custom pinentry instead of bundling pinentry-mac** — pinentry-mac is GPL v2+ and would block any future Mac App Store distribution. Writing our own Assuan-speaking helper was 7 source files in the helper target's `Assuan/` folder. Worth it.
- **`gh` CLI for GitHub instead of OAuth** — zero new credential handling. The user's existing `gh auth login` is the auth boundary.

## The Journey

### The 250-line rule

Two sessions in, the user said: *"let's keep file sizes to approx. 250 lines or less."* I saved it as a feedback memory and then immediately violated it on the very next file I touched. Now every significant edit pauses to `wc -l` the file and split if needed. The cleanup forced the codebase into a much better shape: small files that do one thing, each one of them readable in a single screen.

### The phantom passphrase argument

When wiring up create-key, I returned a `String` from `GPGKeyService.createKey(...)`. Then later when adding "Save in Keychain", I needed the new key's keygrip. So I changed the return type to a struct `GPGCreateKeyResult(fingerprint:, output:)` — extracted the fingerprint from gpg's stderr regex on the revocation-cert path, then ran a second `gpg --list-secret-keys --with-keygrip` to find the keygrip. Two-step lookup, but reliable.

### The duplicate words

The first version of the diceware wordlist had a self-imposed rule: 256 unique English words across 8 categories of 32 (animals, nature, food, objects, adjectives, verbs, places, music). The wordlist-has-no-duplicates test failed on the first run because **march** and **echo** appeared in both Verbs and Music. The test caught it before any user did. Replaced with "alto" and "anthem." Lesson: write the obvious sanity tests for self-imposed invariants, even when you "know" you got it right.

### The long key ID that wouldn't die

User reported: *"this got written to Agent Toolkit repo: 4F8B2FD859C40ECF"*. That's a 16-char long key ID — not the 40-char fingerprint we'd promised. Trace:

1. App reads git config → `signingKey = "4F8B2FD859C40ECF"`
2. Picker binding's getter resolves it to a fingerprint for *display*
3. User clicks Apply *without touching the picker* → `draft.signingKey` is still the long ID
4. We write it back unchanged → **bug**

The fix was defense-in-depth normalization: resolve on both read AND apply. Now `draft.signingKey` becomes a fingerprint the moment we load the config, AND we normalize again before writing. The reorder of bootstrap (refresh keys *before* refreshing git config) makes the matcher have its data when the normalization runs.

### `gpg.program` in two places

While building per-repo signing config, I happily applied `gpg.program` at whatever scope the user picked. The user caught it: *"does the gpg path need to be set for each repo?"* No, of course not — it's a machine-wide setting. Fixed by always writing `gpg.program` at `--global` regardless of the picked target, and actively `--unset`ting any per-repo override. Wrote a comment explaining why so future-me doesn't re-introduce the bug.

### The Settings window that wouldn't resize

The new `Tab` API in macOS 15+ is cleaner than `tabItem`, but it doesn't auto-resize the window when you switch tabs. First fix: hardcoded `idealHeight` per tab — magic numbers, brittle. Better fix: `.fixedSize(vertical: true)` each tab's content + `.onGeometryChange` to measure + apply the measured height to the outer frame + `.windowResizability(.contentSize)` to propagate. Now the window animates smoothly to the tab's actual content size.

### The `gh` scope error

After wiring the GitHub registered-key check, the user's first run showed: *"gh: Not Found (HTTP 404) — needs admin:gpg_key scope."* The raw stderr is technically helpful, but it's noisy. Fix: detect that specific error in our service layer, surface a new typed `.scopeRequired(command:)` case, and render a friendly badge with the exact `gh auth refresh -h github.com -s admin:gpg_key` command in a monospaced pill plus a **Copy** button. The user reads the badge, clicks Copy, pastes into Terminal, done.

### The pinentry helper that lost track of its app

Twice during development, the icon in the pinentry dialog was the SF Symbol fallback instead of the real app icon. First time: running the standalone `Products/Debug/PinentryGPGManager` instead of the embedded `GPGManager.app/Contents/MacOS/PinentryGPGManager` — there was no parent `.app` to walk up to. Second time: the macOS icon services cache. Fix: read `Contents/Resources/*.icns` directly via `NSImage(contentsOf:)` instead of `NSWorkspace.shared.icon(forFile:)` — bypasses the cache.

### The multi-target XCTest dance

When the pinentry helper test target was first added, `@testable import PinentryGPGManager` produced 15 linker errors. Swift command-line tools don't export their internal symbols the way frameworks do. Fix: each Assuan source file is compiled into BOTH the helper target and the test target (multi-target membership via Xcode's File Inspector). The tests then reference types directly — no import needed. Same trick later for `PassphraseStrength.swift`.

### Sunsetting GPG Suite from the recommended install path

When designing the "GPG isn't installed yet" empty state, the obvious first instinct was *of course* point users at gpgtools.org — that's where everyone in the GPG-on-Mac scene has gone for a decade. But auditing what GPG Suite actually bundles, four of its five components are either *already replaced by GPGManager* (Keychain GUI, pinentry-mac) or *outside our mission* (GPG Mail — paid plugin for Apple Mail; GPGServices — right-click encrypt in Finder). The fifth, MacGPG2, is just gnupg with a slower release cadence than Homebrew. So the empty state recommends `brew install gnupg` exclusively — with a brew-presence detector that tells the user whether they need to install Homebrew first. Cleaner story, less recommend-then-regret. The only real cost is right-click Services-menu encryption, which our target audience (Git committers) rarely uses.

## Engineer's Wisdom

- **Save what's surprising, not what's documented.** Memory entries should capture *why* a decision was made when the code can't tell you. The fact that `gpg.program` is always global isn't obvious from reading `GitConfigService.apply` — but the inline comment that explains why is what catches future-me.
- **Tests for self-imposed invariants are worth their weight in dignity.** A "no duplicates in this wordlist" test takes 4 lines and would have saved you from shipping `march-echo-march-aria-…` to a user.
- **Defense in depth at module boundaries.** The signing-key normalization happens at read AND write, not just one. If a value somehow slips past one layer, the other catches it.
- **Module isolation in Swift is a feature, not a bug.** The fact that the pinentry helper can't accidentally pull in the main app's state container forces a clean line between them. We had to duplicate one ~70-line file to share code; vs. accidentally coupling the helper to the app's UI (which would break the helper's standalone use), it's the right trade.
- **Prefer "explicit and small" over "clever and abstract."** Three Settings + Tools + Pinentry extensions on `GPGAppState` is more files than a single fat class, but each one is a screen long and tells one story.
- **`async let` is your friend.** All those `currentConfiguration(scope:)` calls fan out 4-6 reads in parallel; sequential awaits would have made the Tools tab visibly slow.

## If I Were Starting Over

- **Spin up a `Shared` Swift Package on day one.** Even one file's worth of shared code (the strength bar) immediately runs into module isolation. A local SPM target for shared models + utilities would have made the duplication unnecessary and the test target dance simpler.
- **Don't use `FileSystemSynchronizedRootGroup` for the helper target.** It auto-includes any file in the folder, which is convenient until you need multi-target membership — at which point you fight Xcode's exception-set mechanism. A plain old group + explicit references would be friendlier for sharing files.
- **Set up the design tokens (colors, spacing) before building views.** We have a few magic numbers (the 0.18s animation duration, the 56pt icon size, the 540pt sheet width) sprinkled in. A `DesignSystem` enum with named constants would catch drift earlier.
- **Decide on persistence strategy for "lists of stuff" once.** Remembered repos use `UserDefaults` JSON. Selected GPG path uses `UserDefaults` directly as a string. Pinentry install state uses `UserDefaults` plus a typed status struct. Three slightly different patterns; a single `Codable`-backed `Preferences` store would have been cleaner.

The good news: none of these are blocking. They're "I'd refactor next pass" things. The current shape ships.

---

*Last updated: 2026-05-23 — see [`CLAUDE.md`](./CLAUDE.md) for project memory and [`README.md`](./README.md) for the user-facing overview.*
