# Xcode Cloud setup

GPGManager is set up to build and notarize via Xcode Cloud. The workflow
configuration lives in App Store Connect (not in the repo) — what's
versioned here is the `ci_scripts/` directory that Xcode Cloud runs as
part of every build.

## What's automated

A successful Xcode Cloud build of the `GPGManager` scheme produces a
**Developer ID-signed `GPGManager.app`** ready to be packaged for direct
distribution. The post-build hook then prepares that app for public
distribution:

1. Finds the signed `.app` produced by the Direct Distribution workflow.
2. Notarizes and staples it in-script when App Store Connect API
   credentials are available.
3. Zips the app and signs the zip for Sparkle.
4. Uploads the zip and updated `appcast.xml` to Cloudflare R2.
5. Optionally publishes or updates the matching GitHub Release.
6. Optionally dispatches the Homebrew tap workflow so the Cask points at
   the fresh GitHub Release asset.
7. Optionally dispatches the website changelog workflow
   (`peak-innovation-studios-web/update-changelog.yml`), which turns the
   release-note bullets from the annotated `vX.Y.Z` tag into a version card
   on `peakinnovationstudios.com/gpg-manager/changelog/`.

R2/Sparkle is the primary update channel. GitHub Releases are the public
version history and the stable asset source for Homebrew. Homebrew tap
updates are best-effort and should not block R2/Sparkle distribution.

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

The script's in-script notarization is the key piece for shipped zips.
Xcode Cloud post-actions run after `ci_post_xcodebuild.sh`; without
in-script notarization, the uploaded zip could contain a pre-notarization
app even though a later Cloud Notarize post-action succeeds. Keep the
Cloud Notarize post-action enabled as a useful workflow artifact, but do
not rely on it for the bytes uploaded to R2 or GitHub Releases.

## What's in the repo (`ci_scripts/`)

These run automatically on every Xcode Cloud build:

- **`ci_post_clone.sh`** — surfaces env diagnostics (Xcode version,
  macOS version, workflow variables) into the build log. Helps when a
  build fails on Cloud but works locally.
- **`ci_post_xcodebuild.sh`** — handles the distribution path for Direct
  Distribution / Developer ID workflows. It zips the app, signs the
  update with Sparkle, uploads to R2, updates the appcast, optionally
  publishes GitHub Releases (with the annotated tag's `- ` bullets as the
  release body), and optionally dispatches the Homebrew tap and the
  website changelog workflows.

No `ci_pre_xcodebuild.sh` is needed — the project's archive action
already produces a correctly-signed bundle thanks to the entitlements
and `SKIP_INSTALL=YES` configuration baked into the project.

### Distribution environment variables

Required for R2/Sparkle distribution:

| Variable | Purpose |
|---|---|
| `SPARKLE_PRIVATE_KEY` | Base64-encoded Sparkle EdDSA private key. |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 S3-compatible access key. |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 S3-compatible secret. |
| `CLOUDFLARE_R2_ENDPOINT_URL` | R2 endpoint URL. |
| `CLOUDFLARE_R2_BUCKET` | Shared updates bucket. |
| `APPCAST_PUBLIC_URL` | Public appcast base URL, usually `https://updates.peakinnovationstudios.com/gpg-manager`. |

Required for in-script notarization:

| Variable | Purpose |
|---|---|
| `ASC_API_KEY_ID` | App Store Connect API key ID. |
| `ASC_API_ISSUER_ID` | App Store Connect issuer UUID. |
| `ASC_API_PRIVATE_KEY` | Base64-encoded `AuthKey_<KEYID>.p8` contents. |

Optional GitHub Releases publishing:

| Variable | Purpose |
|---|---|
| `GITHUB_TOKEN` | Fine-grained PAT with Contents read/write on `GITHUB_REPO`. |
| `GITHUB_REPO` | Target repo, defaults to `Peak-Innovation-Studios/GPGManager`. |

Optional Homebrew tap refresh:

| Variable | Purpose |
|---|---|
| `HOMEBREW_TAP_TOKEN` | Fine-grained PAT with Actions write on `HOMEBREW_TAP_REPO`; defaults to `GITHUB_TOKEN` if unset. |
| `HOMEBREW_TAP_REPO` | Tap repo, defaults to `Peak-Innovation-Studios/homebrew-tap`. |
| `HOMEBREW_TAP_WORKFLOW` | Workflow file, defaults to `bump-cask.yml`. |
| `HOMEBREW_TAP_REF` | Branch/ref to dispatch, defaults to `main`. |

Optional website changelog refresh:

| Variable | Purpose |
|---|---|
| `WEBSITE_DISPATCH_TOKEN` | Fine-grained PAT with Actions write on `WEBSITE_REPO`; falls back to `HOMEBREW_TAP_TOKEN`, then `GITHUB_TOKEN` (note: those are scoped to other repos, so set this one explicitly). Optional: the site workflow also self-heals hourly from the latest GitHub Release, so a skipped dispatch only delays the changelog, never loses it. |
| `WEBSITE_REPO` | Site repo, defaults to `Peak-Innovation-Studios/peak-innovation-studios-web`. |
| `WEBSITE_CHANGELOG_WORKFLOW` | Workflow file, defaults to `update-changelog.yml`. |
| `WEBSITE_REF` | Branch/ref to dispatch, defaults to `master`. |

If a required distribution variable is missing, the script logs the gap
and exits successfully. That keeps archive builds useful while allowing
distribution credentials to be added incrementally.

## Release policy

Do publish GitHub Releases for public versioned releases. Do not publish
one GitHub Release per Xcode Cloud build number. The automation uses
`v${VERSION}` tags and replaces the versioned zip asset on reruns, which
keeps the public release list readable while still allowing rebuilds of
the same version.

Homebrew depends on the GitHub Release asset being present. If GitHub
publishing is skipped or fails, the Homebrew tap dispatch is skipped too;
R2/Sparkle remains the source of truth for app updates.

## Downloading a build

In Xcode → **Integrate → Cloud → Builds**, pick a successful build →
**Manage** → download the artifacts. The notarized, stapled
`GPGManager.app` is in the **Direct Distribution** asset.

Alternatively, in App Store Connect: **Xcode Cloud → GPGManager → Builds**
→ pick a build → Download.

For public downloads, use the R2 URL from the build log or the stable
redirect:

```text
https://updates.peakinnovationstudios.com/gpg-manager/GPGManager.dmg
```

For Homebrew installs:

```sh
brew tap peak-innovation-studios/tap
brew install --cask gpg-manager
```

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

## GitHub Actions fallback

This public repo also has GitHub Actions workflows:

- **`.github/workflows/ci.yml`** — builds and tests the `GPGManager`
  scheme on `macos-26`, writes a GitHub job-summary test report, and
  uploads the `.xcresult`, JSON summary, Markdown summary, and JUnit XML.
- **`.github/workflows/release.yml`** — manual or `v*` tag-triggered
  Developer ID release pipeline. It imports a Developer ID Application
  certificate from secrets, archives the app, re-signs nested bundles
  with expanded keychain-access-group entitlements, notarizes and staples
  the app, builds a styled DMG, signs/notarizes/staples the DMG, signs
  the DMG for Sparkle, uploads the DMG plus `appcast.xml` to R2,
  publishes a GitHub Release asset, and dispatches the Homebrew tap.

Required GitHub secrets mirror the Xcode Cloud names:

| Secret | Purpose |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | Base64-encoded Developer ID Application `.p12`. |
| `DEVELOPER_ID_CERT_PASSWORD` | Password for the `.p12`. |
| `ASC_API_KEY_ID` | App Store Connect API key ID. |
| `ASC_API_ISSUER_ID` | App Store Connect issuer UUID. |
| `ASC_API_PRIVATE_KEY` | Base64-encoded `AuthKey_<KEYID>.p8` contents. |
| `SPARKLE_PRIVATE_KEY` | Base64-encoded Sparkle EdDSA private key. |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 S3-compatible access key. |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 S3-compatible secret. |
| `CLOUDFLARE_R2_ENDPOINT_URL` | R2 endpoint URL. |
| `CLOUDFLARE_R2_BUCKET` | Shared updates bucket. |
| `HOMEBREW_TAP_TOKEN` | Optional fine-grained PAT with Actions write on the tap repo. |

Use `scripts/set-github-actions-secrets.sh` to populate these as Actions
secrets from the local Developer ID `.p12` and App Store Connect `.p8`
files. The helper skips existing Actions secrets, prompts only for missing
passwords, R2 credentials, the Sparkle key, and the optional Homebrew tap
token, then writes each value with `gh secret set --app actions`. Run with
`FORCE_SECRETS=true` when you intentionally want to overwrite existing
secrets.

The Developer ID certificate values also accept aliases: use
`DEVELOPER_ID_CERTIFICATE_P12_BASE64` or `DEVELOPER_ID_CERTIFICATE_P12`
instead of `DEVELOPER_ID_CERT_P12_BASE64`, and
`DEVELOPER_ID_CERT_P12_PASSWORD` or `DEVELOPER_ID_CERTIFICATE_PASSWORD`
instead of `DEVELOPER_ID_CERT_PASSWORD`.

Manual runs default to `publish: false` so you can dry-run signing and
notarization without touching R2 or GitHub Releases. Tag pushes publish
automatically.

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
