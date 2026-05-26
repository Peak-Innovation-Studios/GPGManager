#!/bin/bash
# Xcode Cloud post-build hook.
#
# For the Direct Distribution / Developer ID workflow this script:
#   1. Locates the signed (and Cloud-notarized) GPGManager.app
#   2. Zips it
#   3. Signs the zip with Sparkle's sign_update (EdDSA)
#   4. Uploads zip + updated appcast.xml to Cloudflare R2 under gpg-manager/
#
# Workflow gating: $CI_WORKFLOW. Set the DevID workflow's name to include
# "Direct", "DevID", or "Developer ID" to match the regex below. Any other
# workflow (e.g. PR builds) exits cleanly without doing distribution work.
#
# Required Xcode Cloud env vars (shared with Agent Toolkit's workflow):
#   SPARKLE_PRIVATE_KEY              base64-encoded EdDSA private key
#   CLOUDFLARE_R2_ACCESS_KEY_ID      R2 S3-compatible access key
#   CLOUDFLARE_R2_SECRET_ACCESS_KEY  R2 S3-compatible secret
#   CLOUDFLARE_R2_ENDPOINT_URL       https://<account>.r2.cloudflarestorage.com
#   CLOUDFLARE_R2_BUCKET             shared updates bucket
#   APPCAST_PUBLIC_URL               https://updates.peakinnovationstudios.com/gpg-manager
#
# Per-app constants:
#   APP_NAME      → display name in zip filename
#   R2_PREFIX     → subfolder inside the shared bucket
#   CHANNEL_TITLE → appcast <title>
#
# If any required env var is missing the script logs the gap and exits 0
# so the build itself doesn't fail (Cloud has still produced the notarized
# .app — distribution can come up incrementally).

set -euo pipefail

APP_NAME="GPGManager"
R2_PREFIX="gpg-manager"
CHANNEL_TITLE="GPG Manager"

echo "=== Xcode Cloud: Post-Xcodebuild (${APP_NAME}) ==="
echo "Workflow: ${CI_WORKFLOW:-unknown}"
echo "Result:   ${CI_RESULT:-unknown}"
echo "Build:    ${CI_BUILD_NUMBER:-unknown}"

if [ "${CI_RESULT:-}" != "succeeded" ]; then
    echo "Build did not succeed — skipping distribution."
    exit 0
fi

case "${CI_WORKFLOW:-}" in
    *Direct*|*DevID*|*"Developer ID"*)
        echo "DevID workflow detected — running Sparkle/Cloudflare distribution."
        ;;
    *)
        echo "Non-DevID workflow — no distribution work."
        exit 0
        ;;
esac

# ----------------------------------------------------------------------
# Locate the signed (and notarized) .app
# ----------------------------------------------------------------------
APP_PATH=""
if [ -n "${CI_AD_HOC_SIGNED_APP_PATH:-}" ] && [ -d "$CI_AD_HOC_SIGNED_APP_PATH" ]; then
    APP_PATH="$CI_AD_HOC_SIGNED_APP_PATH"
elif [ -n "${CI_DEVELOPER_ID_SIGNED_APP_PATH:-}" ] && [ -d "$CI_DEVELOPER_ID_SIGNED_APP_PATH" ]; then
    APP_PATH="$CI_DEVELOPER_ID_SIGNED_APP_PATH"
elif [ -n "${CI_ARCHIVE_PATH:-}" ] && [ -d "$CI_ARCHIVE_PATH" ]; then
    APP_PATH=$(find "$CI_ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name "*.app" -type d | head -n1)
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "WARN: Could not locate the signed .app — skipping distribution."
    exit 0
fi
echo "App: $APP_PATH"

# ----------------------------------------------------------------------
# Required env vars
# ----------------------------------------------------------------------
MISSING=()
for var in SPARKLE_PRIVATE_KEY CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY \
           CLOUDFLARE_R2_ENDPOINT_URL CLOUDFLARE_R2_BUCKET APPCAST_PUBLIC_URL; do
    if [ -z "${!var:-}" ]; then
        MISSING+=("$var")
    fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "Skipping Sparkle/Cloudflare distribution — missing secrets:"
    for var in "${MISSING[@]}"; do
        echo "  - $var"
    done
    echo "Add these as Xcode Cloud Environment Variables (Secret) on the DevID workflow."
    exit 0
fi

# ----------------------------------------------------------------------
# Read version + build
# ----------------------------------------------------------------------
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST")
echo "Version: $VERSION ($BUILD)"

# ----------------------------------------------------------------------
# Zip the .app
# ----------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="$WORK_DIR/$ZIP_NAME"
echo "Zipping to $ZIP_PATH"
( cd "$(dirname "$APP_PATH")" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP_PATH")" "$ZIP_PATH" )
ZIP_SIZE=$(stat -f %z "$ZIP_PATH")
echo "Zip size: $ZIP_SIZE bytes"

# ----------------------------------------------------------------------
# Sign the zip with Sparkle's sign_update (EdDSA)
# ----------------------------------------------------------------------
SIGN_UPDATE=$(find "${CI_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData}" \
    -name "sign_update" -type f 2>/dev/null | head -n1)
if [ -z "$SIGN_UPDATE" ] || [ ! -x "$SIGN_UPDATE" ]; then
    echo "ERROR: sign_update binary not found. Ensure Sparkle SPM dep is resolved."
    exit 1
fi
echo "Using sign_update at: $SIGN_UPDATE"

KEY_PATH="$WORK_DIR/sparkle_priv_key"
echo "$SPARKLE_PRIVATE_KEY" | base64 -d > "$KEY_PATH"
chmod 600 "$KEY_PATH"

SIGN_OUTPUT=$("$SIGN_UPDATE" -f "$KEY_PATH" "$ZIP_PATH")
echo "Sparkle signature: $SIGN_OUTPUT"
ED_SIG=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
if [ -z "$ED_SIG" ]; then
    echo "ERROR: Could not parse EdDSA signature from sign_update output."
    exit 1
fi

# ----------------------------------------------------------------------
# Upload zip to R2 (under per-app prefix)
# ----------------------------------------------------------------------
export AWS_ACCESS_KEY_ID="$CLOUDFLARE_R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$CLOUDFLARE_R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

R2_ZIP_KEY="${R2_PREFIX}/${ZIP_NAME}"
echo "Uploading $ZIP_NAME to R2: s3://${CLOUDFLARE_R2_BUCKET}/${R2_ZIP_KEY}"
aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 cp "$ZIP_PATH" "s3://$CLOUDFLARE_R2_BUCKET/$R2_ZIP_KEY" \
    --content-type application/zip

# ----------------------------------------------------------------------
# Patch appcast.xml (download → prepend new <item> → upload back)
# ----------------------------------------------------------------------
R2_APPCAST_KEY="${R2_PREFIX}/appcast.xml"
APPCAST_PATH="$WORK_DIR/appcast.xml"
aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 cp "s3://$CLOUDFLARE_R2_BUCKET/$R2_APPCAST_KEY" "$APPCAST_PATH" 2>/dev/null || {
        echo "No existing appcast.xml found — creating a new one."
        cat > "$APPCAST_PATH" <<APPCAST_HEADER
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${CHANNEL_TITLE}</title>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
  </channel>
</rss>
APPCAST_HEADER
    }

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
NEW_ITEM=$(cat <<ITEM
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <enclosure
        url="$APPCAST_PUBLIC_URL/$ZIP_NAME"
        length="$ZIP_SIZE"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIG" />
    </item>
ITEM
)

/usr/bin/python3 - "$APPCAST_PATH" <<PYTHON
import sys
path = sys.argv[1]
new_item = """$NEW_ITEM"""
with open(path, "r", encoding="utf-8") as f:
    xml = f.read()
if "</channel>" in xml:
    xml = xml.replace("</channel>", new_item + "\n  </channel>", 1)
else:
    print("ERROR: malformed appcast.xml — no </channel> tag", file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as f:
    f.write(xml)
print(f"Appcast patched with version $VERSION ($BUILD)")
PYTHON

aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 cp "$APPCAST_PATH" "s3://$CLOUDFLARE_R2_BUCKET/$R2_APPCAST_KEY" \
    --content-type "application/xml" \
    --cache-control "no-cache, must-revalidate"

echo "Distribution complete:"
echo "  Zip:     $APPCAST_PUBLIC_URL/$ZIP_NAME"
echo "  Appcast: $APPCAST_PUBLIC_URL/appcast.xml"

rm -rf "$WORK_DIR"
echo "=== Post-Xcodebuild Complete ==="
