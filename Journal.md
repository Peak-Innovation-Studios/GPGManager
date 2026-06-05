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

### The keyboxd race that swallowed a key

User reported one of their two secret keys was missing from the Overview. The earlier code ran `gpg --list-keys` and `gpg --list-secret-keys` concurrently via `async let` — fast, elegant, and broken under gpg 2.5's new `keyboxd` storage backend. Two simultaneous reads can race and one returns empty. Worse, the failing call was being silently swallowed (`try?`). Fix: serialize the two calls, and re-throw errors from `--list-secret-keys` so future regressions surface loudly. The performance hit is unmeasurable; the correctness win is total.

### The `gpg.program` global-only rule, redux

When the per-repo signing-config feature shipped, the user noticed signing-related fields scoped per-repo were correctly *not* writing `gpg.program`. Good. But the inverse — when applying Global, were we still leaving stale per-repo `gpg.program` overrides behind? Audit said yes. Added an active `--unset` pass: applying any scope now unsets any per-repo `gpg.program` it finds, then writes `gpg.program` only at `--global`. The rule is now defended on three sides: never written at non-global scope, actively removed when found there, and surfaced inline as a code comment explaining the *why* so the next refactor doesn't undo it.

### "Why does GnuPG keep showing up as my User ID?"

A user-created key was appearing with `GnuPG` as the UID name instead of "David Peak <dppeak@yahoo.com>". The cause: when our batch-mode parameter file is missing or empty for `Name-Real`, gpg silently substitutes "GnuPG" rather than failing. Three things were wrong: (1) the batch-file generator wasn't quoting Name-Real consistently, (2) the create-key view's draft state wasn't passing the full name through, and (3) we weren't validating the name at the UI boundary. Fix: tightened the batch-file template, added `GPGCreateKeyParameters.validate()` (now tested), and made the create form's Name field required before the Create button enables.

### The "Enable Touch ID" button that wouldn't disappear

After successfully enabling Touch ID on a key, the button stayed visible until the next app launch. The card's visibility check was async (re-querying the Keychain after each refresh), so the UI state lagged behind the underlying truth. Fix: added a synchronous `hasKeychainEntry(for:)` that consults the cached `key.primaryKeygrip` (now populated at list time via `--with-keygrip`). The button conditional became `if !appState.hasKeychainEntry(for: key)` — flips immediately the moment the SecItemAdd returns success.

### The Test Display incident

While debugging UID editing, one of our test commands set "Test Display" as the user's Yahoo key's primary UID. The user then tried to set it back to "David Peak" via Edit User ID, which appeared to silently swallow the error. Two bugs in one: (a) the `gpg --quick-add-uid` call returned an error saying "user ID already exists" because the original "David Peak" UID was still on the key, just not primary; (b) `EditUserIDSheet` was catching the error but then calling `refreshKeys()` which cleared `errorMessage` before the sheet could render it. Fix: `updateUserID` now detects the "already exists" case and skips the add step (just calling `--quick-set-primary-uid` on the existing UID), and the sheet stops refreshing on error so the message stays visible. Apologies were issued.

### The pinentry that picked the wrong screen

`NSWindow.center()` always centers on the main display, which is wrong when Terminal or VS Code is on a secondary monitor — the passphrase dialog would silently land on the user's main screen behind whatever else was up there. Fix: compute the active screen from `NSEvent.mouseLocation` (the best proxy without Accessibility permissions to query other apps' window frames) and center within that screen's `visibleFrame`. Comment in the code calls out why we don't try to be smarter.

### The ad-hoc-signed Touch ID dead end

In debug builds, adding a Keychain item with `kSecAttrAccessControl = userPresence` returns `errSecAuthFailed` because the binary is signed ad-hoc (no Team ID). The original code logged and bailed, leaving the user with no Keychain entry at all. Fix: catch that specific failure and re-add the item without the access-control flag — the passphrase is still saved (so future lookups work), it just won't prompt Touch ID. The `SaveOutcome` enum now distinguishes `.userPresence` from `.withoutBiometric` so the UI can communicate this honestly to the user. Real Developer ID signing in release builds restores Touch ID without code changes.

### The Save-in-Keychain label

Items written by both targets started life with the generic service name `GnuPG` and the keygrip as account — perfectly interoperable with pinentry-mac, but the user's Keychain Access app showed a wall of identical-looking rows. Fix: every SecItemAdd / SecItemUpdate path in both the main app's and the helper's KeychainPassphraseStore now sets `kSecAttrLabel` to something human ("David Peak <dppeak@yahoo.com> (D4F8B2FD…)"). The label is threaded from the create-key flow through `savePassphrase(label:)`. Existing entries get re-labeled the next time they're touched.

### Accessibility + Dynamic Type pass on the prompt helper

The pinentry passphrase and confirm windows looked fine at default text size but clipped at AX large. Two fixes per view: (1) `@ScaledMetric(relativeTo: .largeTitle)` on the icon size so it tracks Dynamic Type, and (2) wrap the body in `ScrollView(.vertical, showsIndicators: false)` so growth at huge sizes pushes content scrollable rather than off-window. VoiceOver: header now combines into a single element with a sentence-like label ("Unlock Secret Key. GPG Manager."), error text is announced via `AccessibilityNotification.Announcement` on change, the strength bar exposes a single value ("Strong"/"Good"/"Fair"/"Weak") instead of letting VO read a meaningless 0–100 progress number, and the icon is `.accessibilityHidden` since the title text conveys context. Focus order was already correct via `@FocusState` — primary → confirm → submit on Return.

### The Xcode Cloud export trap

Xcode Cloud's archive phase was green, which is the kind of green that still leaves a banana peel on the floor. The actual failure lived later, in `xcodebuild -exportArchive`, where signing assets are re-evaluated for each distribution method. Locally, development export worked because the Mac had a wildcard development profile; Developer ID and App Store export failed because distribution profiles/certificates for both `GPGManager` and the embedded `PinentryGPGManager` were missing. While cleaning up the build issues, we also added the app category directly to `Info.plist` and marked pure helper functions `nonisolated` so Swift's default MainActor isolation stops treating Assuan decoding and passphrase scoring like UI work.

### The Mac App Store sandbox fork in the road

App Store Connect accepted the archive far enough to inspect it, then handed back two classic macOS receipts: `LSApplicationCategoryType` was missing in the delivered binary, and both executables needed `com.apple.security.app-sandbox = true`. The category key now lives directly in `Info.plist`, but the sandbox entitlement was intentionally **not** kept because this app is not shipping through the Mac App Store. Direct Developer ID distribution lets GPGManager keep doing its real job: running `gpg`, `git`, and `gh`, reading repo paths, and cooperating with the user's existing GnuPG setup instead of living inside an App Store container.

### The day the app grew a manual

Help in macOS apps usually means one of three things: a stub Help menu item with nothing under it, an HTML help book wired up via `HelpBookName` (powerful but heavy to author), or a deflection link to a marketing site. We took none of those routes. The app needed a manual you could actually read — covering every tab, every field, every weird state — and the manual needed to live *in the app*, because the app has features you wouldn't think to Google for.

The architecture that emerged is a tiny data model — `HelpTopic` with categorized topics, each topic a list of `HelpSection`s, each section a list of `HelpBlock`s (paragraph / bullets / steps / code / tip / note / warning / key-value). Twelve topic files in `Models/`, three render views in `Views/Help/`, one Window scene, one `CommandGroup(replacing: .help)`. Total weight under a thousand lines for the framework — the bulk is the actual content.

Two design choices paid off:
- **`Text(LocalizedStringKey(text))`** for paragraph rendering. SwiftUI's free Markdown support handles bold, italic, and backtick `code` — so the topic files can stay text-only with no inline view trees.
- **`@AppStorage("help.selectedTopic")` for selection.** When you pick "Git Signing" from the Help menu, the menu handler sets the UserDefaults key and opens the window. `HelpView`'s sidebar selection is bound to the same key, so it lands exactly on that topic. Two unrelated entry points, one source of truth.

The Swift compiler had one opinion about the design: an `init(_ heading: String? = nil, _ blocks: [HelpBlock])` initializer doesn't work. When you call `HelpSection([.paragraph("…")])` with one positional argument, Swift can't decide whether the array literal is meant for the second parameter (with the first defaulting) or whether you're attempting to pass an array as the first parameter. It refused to infer `[HelpBlock]` from leading-dot enum cases without a type context. Fix: two explicit initializers — `init(_ blocks:)` and `init(_ heading:_ blocks:)`. Cleaner anyway.

The About tab got the same evening's polish — hero icon with a soft shadow, version pill with a one-click "copy version + runtime info" button (handy for bug reports), three bordered link buttons (Website / GitHub / Issues), and a runtime GroupBox showing the GPG installation kind, version, and path. The copy footer cites GnuPG as the separate GPL project it is.

The whole help framework portable enough that we wrote a [reusable prompt for it](./docs/help-system-prompt.md), aimed at lifting the same architecture into other Peak Innovation Studios projects without dragging GPG specifics along.

### The Homebrew tap lag

The release robot learned a small but important timing trick: shipping a new zip is not the same as updating the Homebrew Cask. Xcode Cloud was uploading the GitHub Release asset, then the separate `homebrew-tap` repo waited for its hourly schedule to notice the changed SHA. That's fine for a sleepy package, but confusing when you're watching a release roll out live. Fix: after the GitHub Release asset upload succeeds, the Cloud script now dispatches the tap repo's `bump-cask.yml` workflow with the released version. Think of it like ringing the kitchen bell after plating the dish instead of waiting for the server's next lap through the room. The dispatch is still best-effort and token-gated, so R2/Sparkle distribution does not fail just because GitHub Actions is grumpy.

June 3 added the missing map legend: GitHub Releases should track public versions, not every Cloud build. R2 plus Sparkle is the highway users actually drive on; GitHub Releases are the roadside sign with the version history and the zip Homebrew can checksum; the Homebrew tap is the valet that only gets called once that zip is definitely parked. The docs now say this out loud so future-us doesn't accidentally flood GitHub Releases with build-number confetti or wonder why the tap skipped itself after a GitHub upload hiccup.

June 4 gave the pinentry window a proper Xcode preview set: unlock, create-passphrase, and retry-error. The funny bit was that the helper's `main.swift` is not a normal app entry point; it starts an Assuan session on stdin and quits when stdin ends. Xcode previews give it no Assuan conversation, so the process immediately exited and looked like a crash. The fix was to detect `XCODE_RUNNING_FOR_PREVIEWS` and skip only the stdin session while still letting `NSApplication` run. In production, the helper still behaves like pinentry; in Xcode, the window finally sits still long enough to inspect.

June 5 split the release kitchen across two counters. Xcode Cloud remains the Apple-native path, but GitHub Actions can now do the lunch rush too: public CI runs build + tests and turns `.xcresult` into a readable Actions summary plus JUnit, while the release workflow imports a Developer ID cert, signs the app, notarizes the app, builds a DMG like Agent Toolkit's polished installer, notarizes that DMG, signs it for Sparkle, uploads to R2, publishes the GitHub Release asset, and rings the Homebrew tap bell. The gotcha was entitlements: `codesign --entitlements` does **not** expand `$(AppIdentifierPrefix)` the way Xcode does, so the script writes temporary expanded entitlements before re-signing. Tiny placeholder, giant Keychain consequence.

The Touch ID sheet had one more identity wrinkle: even though the helper bundle's `CFBundleDisplayName` said "GPG Manager", LocalAuthentication was still pulling the bold app name from the helper process (`PinentryGPGManager`). The fix is delightfully blunt: set `ProcessInfo.processInfo.processName = "GPG Manager"` at helper startup before `NSApplication` spins up. The sheet still receives our concise verb phrase ("unlock the GPG key for..."), but the system-owned app-name prefix now uses the brand instead of the internal target name.

## Session log — 2026-05-23 through 2026-05-24

This session reshaped the UI substantially:

- Renamed the **Tools** tab to **Signing**, the **Password** Settings tab to **Passphrase**, and removed the standalone **Agent** / **General** / **GPG Executable** tabs (each merged into the more relevant place).
- Moved the **My Keys** panel from a separate Keys tab to the **Overview** page — your secret keys are the home screen now. The full public-key list still exists but lives in its own window opened from a button.
- Built out **GitHub key management** end-to-end: list registered keys per account, add / delete / rename / replace, with multi-account support that routes through `GH_TOKEN` set from `gh auth token --user <account>`. The "stale on GitHub" detection now correctly handles "never expires" keys by treating `registered.isExpired && !local.isExpired` as the stale signal (not blind `expiresAt` field equality).
- Added an **algorithm classifier** (`GPGKeyAlgorithm`) that turns gpg's numeric code + bit length / curve name into a friendly display ("RSA 4096" / "Ed25519" / "ECDSA (nistp256)"), a strength bucket (.strong / .acceptable / .weak / .deprecated), and an upgrade-suggestion string. RSA-1024 shows up as Weak; DSA / Elgamal show up as Deprecated.
- Implemented **Edit User ID** as a sheet that adds a new UID, sets it primary, then revokes the old one. The implementation has to handle the "UID already exists" case (skip the add step) and surface errors inline rather than auto-dismissing.
- Implemented **Delete Key** via a confirmation dialog that runs `--delete-secret-keys` then `--delete-keys` (secret first — gpg refuses to delete the public key while a secret is present).
- Implemented **Enable Touch ID** with two flavors: a "fresh write" that asks for the passphrase once and stores it with `userPresence` ACL, and a "migrate" path for keys whose passphrase is already in the Keychain from pinentry-mac (reads the existing entry under the GnuPG service, re-writes it under our service with biometric access control).
- Added **SHA-256 digest logging** (CryptoKit) at the Keychain hit / user-submitted boundaries in both the helper and the main app. Doesn't leak the passphrase, but lets us correlate "user typed X" with "we stored Y" if a mismatch ever surfaces again.
- The pinentry helper now **centers on the active screen** (via mouse-location), and its prompt views got the accessibility + Dynamic Type pass described above.
- First **git init + initial commit** on the project, later pushed to [github.com/Peak-Innovation-Studios/GPGManager](https://github.com/Peak-Innovation-Studios/GPGManager).

The next planned work is a release-build notarization smoke test (#5) — both as a distribution dry-run and to verify whether proper Developer ID signing fixes the ad-hoc-signing Touch ID limitation.

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

*Last updated: 2026-05-29 — see [`CLAUDE.md`](./CLAUDE.md) for project memory and [`README.md`](./README.md) for the user-facing overview.*
