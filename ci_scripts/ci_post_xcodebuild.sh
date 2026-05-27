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
# Optional Xcode Cloud env vars (enable GitHub Releases publishing):
#   GITHUB_TOKEN                     fine-grained PAT, Contents: read+write on GITHUB_REPO
#   GITHUB_REPO                      owner/repo, e.g. Peak-Innovation-Studios/GPGManager
#                                    (defaults to Peak-Innovation-Studios/GPGManager)
#
# Per-app constants:
#   APP_NAME      → display name in zip filename
#   R2_PREFIX     → subfolder inside the shared bucket
#   CHANNEL_TITLE → appcast <title>
#
# If any required env var is missing the script logs the gap and exits 0
# so the build itself doesn't fail (Cloud has still produced the notarized
# .app — distribution can come up incrementally). GitHub Releases
# publishing is independent: if GITHUB_TOKEN is set, the release happens
# after R2; if not, R2 distribution still completes and we just skip
# the Releases step.

set -euo pipefail

APP_NAME="GPGManager"
R2_PREFIX="gpg-manager"
CHANNEL_TITLE="GPG Manager"

echo "=== Xcode Cloud: Post-Xcodebuild (${APP_NAME}) ==="
echo "Workflow: ${CI_WORKFLOW:-unknown}"
echo "Build:    ${CI_BUILD_NUMBER:-unknown}"
echo "Exit:     ${CI_XCODEBUILD_EXIT_CODE:-unset}"

# CI_RESULT is the workflow-level result and isn't populated at the
# post-xcodebuild hook. CI_XCODEBUILD_EXIT_CODE is the exit code of the
# build/archive step that just finished — that's what tells us whether
# distribution work should run.
if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
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

echo "R2 distribution complete:"
echo "  Zip:     $APPCAST_PUBLIC_URL/$ZIP_NAME"
echo "  Appcast: $APPCAST_PUBLIC_URL/appcast.xml"

# ----------------------------------------------------------------------
# Optional: publish to GitHub Releases
# ----------------------------------------------------------------------
#
# We only publish if a GITHUB_TOKEN is configured on the workflow. The
# token needs Contents: read+write on the target repo. If the release
# tag already exists (e.g. for a re-run on the same version), we reuse
# it and just upload the asset.
GITHUB_REPO="${GITHUB_REPO:-Peak-Innovation-Studios/GPGManager}"
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN not set — skipping GitHub Releases publishing."
else
    TAG="v${VERSION}"
    RELEASE_NAME="GPG Manager ${VERSION}"
    API="https://api.github.com/repos/${GITHUB_REPO}"
    UPLOAD_BASE="https://uploads.github.com/repos/${GITHUB_REPO}"
    AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
    ACCEPT_HEADER="Accept: application/vnd.github+json"
    API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"

    echo "Publishing GitHub Release ${TAG} to ${GITHUB_REPO}"

    # Look up an existing release for this tag; create one if absent.
    RELEASE_JSON=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
        "${API}/releases/tags/${TAG}" || true)
    RELEASE_ID=$(echo "$RELEASE_JSON" | /usr/bin/python3 -c \
        'import json,sys;d=json.load(sys.stdin);print(d.get("id","")) if isinstance(d,dict) else print("")' 2>/dev/null || echo "")

    if [ -z "$RELEASE_ID" ]; then
        echo "No existing release for ${TAG} — creating."
        BODY_JSON=$(/usr/bin/python3 -c "import json; print(json.dumps({\"tag_name\": \"${TAG}\", \"name\": \"${RELEASE_NAME}\", \"body\": \"Automated release from Xcode Cloud build ${CI_BUILD_NUMBER:-unknown}.\", \"draft\": False, \"prerelease\": False}))")
        RELEASE_JSON=$(curl -sS -X POST \
            -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
            -H "Content-Type: application/json" \
            -d "$BODY_JSON" \
            "${API}/releases")
        RELEASE_ID=$(echo "$RELEASE_JSON" | /usr/bin/python3 -c \
            'import json,sys;d=json.load(sys.stdin);print(d.get("id",""))')
    fi

    if [ -z "$RELEASE_ID" ]; then
        echo "WARN: Could not create or find a GitHub Release for ${TAG}. Skipping asset upload."
        echo "      API response: $RELEASE_JSON"
    else
        # Remove any prior asset with the same name (allows re-runs to replace the zip).
        EXISTING_ASSET_ID=$(curl -sS \
            -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
            "${API}/releases/${RELEASE_ID}/assets" \
            | /usr/bin/python3 -c \
                "import json,sys; d=json.load(sys.stdin); print(next((a['id'] for a in d if a.get('name')=='${ZIP_NAME}'), ''))")
        if [ -n "$EXISTING_ASSET_ID" ]; then
            echo "Deleting existing asset ${ZIP_NAME} (id=${EXISTING_ASSET_ID}) before re-upload"
            curl -sS -X DELETE \
                -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
                "${API}/releases/assets/${EXISTING_ASSET_ID}" >/dev/null
        fi

        echo "Uploading ${ZIP_NAME} to release id ${RELEASE_ID}"
        UPLOAD_RESPONSE=$(curl -sS -X POST \
            -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
            -H "Content-Type: application/zip" \
            --data-binary "@${ZIP_PATH}" \
            "${UPLOAD_BASE}/releases/${RELEASE_ID}/assets?name=${ZIP_NAME}")
        ASSET_URL=$(echo "$UPLOAD_RESPONSE" | /usr/bin/python3 -c \
            'import json,sys;d=json.load(sys.stdin);print(d.get("browser_download_url",""))')
        if [ -n "$ASSET_URL" ]; then
            echo "GitHub Release asset: $ASSET_URL"
        else
            echo "WARN: GitHub asset upload may have failed."
            echo "      API response: $UPLOAD_RESPONSE"
        fi
    fi
fi

rm -rf "$WORK_DIR"
echo "=== Post-Xcodebuild Complete ==="
