# Xcode Cloud setup

GPGManager is set up to build and notarize via Xcode Cloud. The workflow
configuration lives in App Store Connect (not in the repo) — what's
versioned here is the `ci_scripts/` directory that Xcode Cloud runs as
part of every build.

## What's automated

A successful Xcode Cloud build of the `GPGManager` scheme produces a
**Developer ID-signed, notarized, stapled `GPGManager.app`** ready for
direct distribution. Trigger conditions and notifications are
configurable per workflow.

## One-time configuration (App Store Connect)

You only need to do this once per project. Subsequent runs use the
existing workflow.

1. In Xcode, open `GPGManager.xcodeproj`.
2. **Product → Xcode Cloud → Create Workflow** (or, if you already
   started: **Integrate → Manage Workflows**).
3. Xcode walks you through:
   - Granting Xcode Cloud access to the GitHub repo
     ([Peak-Innovation-Studios/GPGManager](https://github.com/Peak-Innovation-Studios/GPGManager)).
   - Creating an App Store Connect record for the macOS app. Use the
     project's bundle ID `com.peakinnovationstudios.GPGManager`.
4. Edit the resulting workflow either in Xcode or at
   [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
   Xcode Cloud:

### Workflow settings

| Section | Value |
|---|---|
| **Name** | `GPGManager — Direct Distribution` |
| **Start Conditions** | Branch Changes: `main`; Manual: enabled |
| **Environment** | Xcode latest (or pin to your local Xcode version); macOS latest |
| **Actions** | Add **Archive** action |
| ↳ Platform | macOS |
| ↳ Scheme | `GPGManager` |
| ↳ Destination | macOS (Universal — adjust if you need arm64-only) |
| ↳ Distribution Preparation | **Direct Distribution** (Developer ID) |
| **Post-Actions** | Add **Notarize** post-action |
| ↳ Distribution Method | Direct Distribution |
| **Notifications** | Email on failure (recommended) |

The **Notarize** post-action is the key piece: Xcode Cloud sends the
signed archive to Apple's notary service, waits for the result, then
staples the ticket back onto the `.app` automatically. You don't need
to provide `notarytool` credentials separately — Xcode Cloud uses your
Apple Developer Program team's notary access.

## What's in the repo (`ci_scripts/`)

These run automatically on every Xcode Cloud build:

- **`ci_post_clone.sh`** — surfaces env diagnostics (Xcode version,
  macOS version, workflow variables) into the build log. Helps when a
  build fails on Cloud but works locally.
- **`ci_post_xcodebuild.sh`** — placeholder that logs the paths of
  signed outputs. Available for future automation (upload to GitHub
  Releases, post to Slack, etc.) without another commit.

No `ci_pre_xcodebuild.sh` is needed — the project's archive action
already produces a correctly-signed bundle thanks to the entitlements
and `SKIP_INSTALL=YES` configuration baked into the project.

## Downloading a build

In Xcode → **Integrate → Cloud → Builds**, pick a successful build →
**Manage** → download the artifacts. The notarized, stapled
`GPGManager.app` is in the **Direct Distribution** asset.

Alternatively, in App Store Connect: **Xcode Cloud → GPGManager → Builds**
→ pick a build → Download.

## Local backup workflow

If Xcode Cloud is down, unavailable, or you need a build before the
workflow runs, `scripts/notarize.sh` does the same thing locally. It
relies on:

1. A `Developer ID Application` certificate in your login keychain.
2. A `notarytool` keychain profile named `gpgmanager` (see the FIRST-TIME
   SETUP block in the script).

The script archives, re-signs each layer with Developer ID
(`codesign --force --sign … --options runtime --timestamp`), submits to
`xcrun notarytool`, staples, and emits a zipped `.app`.

## Troubleshooting

- **"Failed to install ApplicationProperties" in the archive log** —
  some other target lost its `SKIP_INSTALL=YES`. Only the main app
  should appear at `Products/Applications/` in the archive.
- **Notarize step times out** — Apple's notary service is occasionally
  slow under load (10+ minutes). Watch the build's log; Xcode Cloud will
  surface the notary status as soon as it returns.
- **"developer-id" method rejected** — that error means the archive is
  malformed and `IDEDistribution` can't enumerate valid methods. The
  underlying cause is almost always a top-level secondary product in
  the archive (helper without `SKIP_INSTALL`, missed `CodeSignOnCopy`,
  etc.). Audit `archive/Products/Applications/`.
