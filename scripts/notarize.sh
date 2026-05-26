#!/usr/bin/env bash
#
# notarize.sh — archive, sign, notarize, and staple GPGManager.app.
#
# ────────────────────────────────────────────────────────────────
# FIRST-TIME SETUP (run once)
# ────────────────────────────────────────────────────────────────
#
#   1. Confirm a Developer ID Application certificate exists:
#
#        security find-identity -v -p codesigning | grep "Developer ID Application"
#
#      If nothing comes back: in Xcode → Settings → Accounts → select your
#      Apple ID → Manage Certificates → + → Developer ID Application.
#
#   2. Create an app-specific password for notarytool:
#
#        Visit https://appleid.apple.com → Sign-In and Security →
#        App-Specific Passwords → "+" → name it "notarytool".
#        Copy the generated password.
#
#   3. Store credentials in the keychain under a notarytool profile.
#      Pick any profile name you like — this script defaults to "gpgmanager":
#
#        xcrun notarytool store-credentials gpgmanager \
#            --apple-id you@example.com \
#            --team-id Z2R2L2TJ7Y \
#            --password <app-specific-password-from-step-2>
#
#      You will be asked for the password on stdin if you omit --password.
#
# ────────────────────────────────────────────────────────────────
# USAGE
# ────────────────────────────────────────────────────────────────
#
#   scripts/notarize.sh                  # uses NOTARY_PROFILE=gpgmanager
#   NOTARY_PROFILE=myprofile scripts/notarize.sh
#
# Output: scripts/build/GPGManager-<timestamp>.zip (notarized + stapled)
#

set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────
SCHEME="GPGManager"
CONFIGURATION="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-gpgmanager}"

# Resolve script and project paths regardless of where this is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/GPGManager.xcodeproj"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_DIR="$SCRIPT_DIR/build/$TIMESTAMP"
ARCHIVE_PATH="$BUILD_DIR/GPGManager.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

mkdir -p "$BUILD_DIR"

# ─── Helpers ───────────────────────────────────────────────────
say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ─── Preflight ─────────────────────────────────────────────────
say "Preflight checks"

IDENTITY="Developer ID Application"
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    die "No '$IDENTITY' certificate in the login keychain. See FIRST-TIME SETUP above."
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "notarytool profile '$NOTARY_PROFILE' not configured. See FIRST-TIME SETUP step 3 above."
fi

# ─── Archive ───────────────────────────────────────────────────
# Archive with whatever signing the scheme is configured for. We re-sign
# below with Developer ID directly, so the original signing doesn't matter.
say "Archiving ($CONFIGURATION)"
xcodebuild archive \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    | xcbeautify 2>/dev/null || xcodebuild archive \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -destination 'generic/platform=macOS'

# ─── Re-sign with Developer ID Application ─────────────────────
# Skip xcodebuild -exportArchive: it expects provisioning profiles even for
# Developer ID, which isn't how Developer ID distribution actually works.
# Direct codesign is simpler and matches what `notarytool` cares about.
say "Re-signing .app and embedded helper with Developer ID"
mkdir -p "$EXPORT_PATH"
SRC_APP="$ARCHIVE_PATH/Products/Applications/GPGManager.app"
[[ -d "$SRC_APP" ]] || die "Missing app in archive: $SRC_APP"
APP_PATH="$EXPORT_PATH/GPGManager.app"
ditto "$SRC_APP" "$APP_PATH"

# Sign innermost-out so the outer signatures cover the inner ones.
HELPER_PATH="$APP_PATH/Contents/PlugIns/PinentryGPGManager.app/Contents/MacOS/PinentryGPGManager"
HELPER_BUNDLE="$APP_PATH/Contents/PlugIns/PinentryGPGManager.app"
[[ -x "$HELPER_PATH" ]] || die "Embedded helper missing at $HELPER_PATH"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$HELPER_PATH"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$HELPER_BUNDLE"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP_PATH"

say "Verifying signature"
codesign --verify --verbose=2 --deep --strict "$APP_PATH"

# ─── Zip for notary submission ─────────────────────────────────
ZIP_PATH="$BUILD_DIR/$(basename "$APP_PATH" .app).zip"
say "Zipping for notarization → $ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ─── Submit ────────────────────────────────────────────────────
say "Submitting to Apple notary service (this can take 1–10 minutes)"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# ─── Staple ────────────────────────────────────────────────────
say "Stapling ticket to .app"
xcrun stapler staple "$APP_PATH"

# Re-zip the stapled .app for distribution.
FINAL_ZIP="$SCRIPT_DIR/build/GPGManager-$TIMESTAMP.zip"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

# ─── Gatekeeper assessment ─────────────────────────────────────
say "Gatekeeper assessment"
spctl -a -vvv -t exec "$APP_PATH" || true

printf '\n\033[1;32m✓ Done.\033[0m\nNotarized + stapled app: %s\nDistribution zip:       %s\n' \
    "$APP_PATH" "$FINAL_ZIP"
