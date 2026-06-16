#!/usr/bin/env bash
#
# Build, sign, notarize, package, and publish GPGManager from GitHub Actions.

set -euo pipefail

APP_NAME="GPGManager"
VOLUME_NAME="GPG Manager"
CHANNEL_TITLE="GPG Manager"
PROJECT="GPGManager.xcodeproj"
SCHEME="GPGManager"
CONFIGURATION="Release"
TEAM_ID="${TEAM_ID:-Z2R2L2TJ7Y}"
R2_PREFIX="${R2_PREFIX:-gpg-manager}"
GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-Peak-Innovation-Studios/GPGManager}}"
PUBLISH_RELEASE="${PUBLISH_RELEASE:-false}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
WORK_DIR="${RUNNER_TEMP:-$REPO_ROOT/scripts/build/github-release}"
ARCHIVE_PATH="$WORK_DIR/${APP_NAME}.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
APP_PATH="$EXPORT_PATH/${APP_NAME}.app"
DMG_DIR="$WORK_DIR/dmg"
DMG_PATH=""

mkdir -p "$WORK_DIR" "$EXPORT_PATH" "$DMG_DIR"

say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
    local missing=()
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing required environment variables:\n' >&2
        for var in "${missing[@]}"; do
            printf '  - %s\n' "$var" >&2
        done
        exit 1
    fi
}

stapler_validate_with_retry() {
    local path="$1"
    local attempt
    local delay=5
    for attempt in 1 2 3; do
        if xcrun stapler validate "$path"; then
            return 0
        fi
        if [ "$attempt" != "3" ]; then
            say "stapler validate failed; retrying in ${delay}s"
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    echo "WARN: stapler validate failed after retries; continuing because stapler staple already completed."
}

install_signing_certificate() {
    local cert_base64="${DEVELOPER_ID_CERT_P12_BASE64:-${DEVELOPER_ID_CERTIFICATE_P12_BASE64:-${DEVELOPER_ID_CERTIFICATE_P12:-}}}"
    local cert_password="${DEVELOPER_ID_CERT_PASSWORD:-${DEVELOPER_ID_CERT_P12_PASSWORD:-${DEVELOPER_ID_CERTIFICATE_PASSWORD:-}}}"
    [ -n "$cert_base64" ] || die "Set DEVELOPER_ID_CERT_P12_BASE64 or DEVELOPER_ID_CERTIFICATE_P12_BASE64."
    [ -n "$cert_password" ] || die "Set DEVELOPER_ID_CERT_PASSWORD or DEVELOPER_ID_CERT_P12_PASSWORD."

    say "Importing Developer ID certificate into a temporary keychain"
    CERT_DIR="$WORK_DIR/cert"
    CERT_PATH="$CERT_DIR/DeveloperID.p12"
    KEYCHAIN_PATH="$CERT_DIR/codesign.keychain-db"
    KEYCHAIN_PASSWORD=$(uuidgen)
    mkdir -p "$CERT_DIR"

    printf '%s' "$cert_base64" | base64 --decode > "$CERT_PATH"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

    EXISTING_KEYCHAINS=$(security list-keychains -d user \
        | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' \
        | tr '\n' ' ')
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS

    security import "$CERT_PATH" \
        -k "$KEYCHAIN_PATH" \
        -P "$cert_password" \
        -T /usr/bin/codesign \
        -T /usr/bin/xcodebuild
    security set-key-partition-list \
        -S "apple-tool:,apple:,codesign:" \
        -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

    SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')
    [ -n "$SIGNING_IDENTITY" ] || die "Imported P12 does not expose a Developer ID Application identity."
    say "Using signing identity: $SIGNING_IDENTITY"
}

cleanup() {
    if [ -n "${KEYCHAIN_PATH:-}" ]; then
        security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
    fi
}
trap cleanup EXIT

notary_key_path() {
    require_env ASC_API_KEY_ID ASC_API_ISSUER_ID ASC_API_PRIVATE_KEY
    local dir="$WORK_DIR/notary"
    mkdir -p "$dir"
    local path="$dir/AuthKey_${ASC_API_KEY_ID}.p8"
    printf '%s' "$ASC_API_PRIVATE_KEY" | base64 --decode > "$path"
    chmod 600 "$path"
    printf '%s\n' "$path"
}

# Submits an artifact to the notary service, prints the detailed notarization
# log, and fails fast unless the status is Accepted. `notarytool submit --wait`
# exits 0 even for an Invalid result, so we must inspect the status ourselves —
# and the log lists exactly which binaries (if any) the notary rejected.
submit_to_notary() {
    local artifact="$1" label="$2"
    local p8_path submit_json submission_id status
    p8_path=$(notary_key_path)
    say "Submitting $label to Apple notary service"
    submit_json=$(xcrun notarytool submit "$artifact" \
        --key "$p8_path" \
        --key-id "$ASC_API_KEY_ID" \
        --issuer "$ASC_API_ISSUER_ID" \
        --wait \
        --timeout 30m \
        --output-format json)
    printf '%s\n' "$submit_json"
    submission_id=$(printf '%s' "$submit_json" \
        | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))')
    status=$(printf '%s' "$submit_json" \
        | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin).get("status",""))')
    if [ -n "$submission_id" ]; then
        say "Notarization log for $label ($submission_id)"
        xcrun notarytool log "$submission_id" \
            --key "$p8_path" \
            --key-id "$ASC_API_KEY_ID" \
            --issuer "$ASC_API_ISSUER_ID" || true
    fi
    [ "$status" = "Accepted" ] || die "Notarization of $label failed with status: ${status:-unknown}"
}

notarize_app() {
    local notary_zip="$WORK_DIR/${APP_NAME}-notary.zip"
    (cd "$(dirname "$APP_PATH")" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP_PATH")" "$notary_zip")
    submit_to_notary "$notary_zip" "app"
    xcrun stapler staple "$APP_PATH"
    stapler_validate_with_retry "$APP_PATH"
}

notarize_dmg() {
    submit_to_notary "$DMG_PATH" "DMG"
    xcrun stapler staple "$DMG_PATH"
    stapler_validate_with_retry "$DMG_PATH"
}

archive_app() {
    say "Archiving ${APP_NAME} ${VERSION} (${BUILD_NUMBER})"
    # Archive unsigned. The Release entitlements declare a keychain-access-group,
    # which makes xcodebuild demand a provisioning profile at archive time even
    # for Developer ID — and CI has no profile. resign_app() below re-signs the
    # app and every nested bundle with the Developer ID identity, hardened
    # runtime, and the correct entitlements, so the archive's signature is
    # throwaway. Disabling signing here keeps the archive profile-free.
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

    local source_app="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
    [ -d "$source_app" ] || die "Archive did not produce $source_app."
    rm -rf "$APP_PATH"
    /usr/bin/ditto "$source_app" "$APP_PATH"
}

resign_app() {
    say "Re-signing nested bundles and app with Developer ID"
    local app_entitlements="$WORK_DIR/GPGManager.entitlements"
    local pinentry_entitlements="$WORK_DIR/PinentryGPGManager.entitlements"
    sed "s/\$(AppIdentifierPrefix)/${TEAM_ID}./g" \
        "$REPO_ROOT/source/GPGManager.entitlements" > "$app_entitlements"
    sed "s/\$(AppIdentifierPrefix)/${TEAM_ID}./g" \
        "$REPO_ROOT/PinentryGPGManager/PinentryGPGManager.entitlements" > "$pinentry_entitlements"

    while IFS= read -r nested; do
        case "$nested" in
            "$APP_PATH") continue ;;
        esac
        if [[ "$nested" == *"PinentryGPGManager.app" ]]; then
            codesign --force --sign "$SIGNING_IDENTITY" \
                --options runtime \
                --timestamp \
                --entitlements "$pinentry_entitlements" \
                "$nested"
        else
            codesign --force --sign "$SIGNING_IDENTITY" \
                --options runtime \
                --timestamp \
                "$nested"
        fi
    done < <(find "$APP_PATH/Contents" -type d \( -name "*.framework" -o -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) | sort -r)

    codesign --force --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$app_entitlements" \
        "$APP_PATH"

    codesign --verify --verbose=2 --deep --strict "$APP_PATH"
}

install_dmg_tools() {
    if ! command -v rsvg-convert >/dev/null 2>&1; then
        say "Installing librsvg"
        HOMEBREW_NO_AUTO_UPDATE=1 brew install librsvg
    fi
    if ! command -v appdmg >/dev/null 2>&1; then
        say "Installing node and appdmg"
        if ! command -v npm >/dev/null 2>&1; then
            HOMEBREW_NO_AUTO_UPDATE=1 brew install node
        fi
        npm install -g appdmg
    fi
}

build_dmg() {
    install_dmg_tools
    local bg_path="$DMG_DIR/bg.png"
    local bg_2x_path="$DMG_DIR/bg@2x.png"
    local spec_path="$DMG_DIR/appdmg.json"

    say "Rendering DMG background"
    rsvg-convert -w 660 -h 400 "$REPO_ROOT/AppStore/dmg-background.svg" -o "$bg_path"
    rsvg-convert -w 1320 -h 800 "$REPO_ROOT/AppStore/dmg-background.svg" -o "$bg_2x_path"

    /usr/bin/python3 - "$spec_path" "$VOLUME_NAME" "$bg_path" "$APP_PATH" <<'PYTHON'
import json
import sys

spec_path, title, background, app_path = sys.argv[1:]
spec = {
    "title": title,
    "background": background,
    "icon-size": 100,
    "window": {"size": {"width": 660, "height": 400}},
    "contents": [
        {"x": 165, "y": 200, "type": "file", "path": app_path},
        {"x": 495, "y": 200, "type": "link", "path": "/Applications"},
    ],
}
with open(spec_path, "w", encoding="utf-8") as handle:
    json.dump(spec, handle, indent=2)
PYTHON

    say "Building DMG"
    appdmg "$spec_path" "$DMG_PATH"
    codesign --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$DMG_PATH"
    DMG_SIZE=$(stat -f %z "$DMG_PATH")
}

sign_sparkle_update() {
    require_env SPARKLE_PRIVATE_KEY
    local sign_update
    sign_update=$(find "$WORK_DIR" "$HOME/Library/Developer/Xcode/DerivedData" \
        -name "sign_update" -type f 2>/dev/null | head -n1)
    [ -n "$sign_update" ] && [ -x "$sign_update" ] || die "Sparkle sign_update was not found."

    local key_path="$WORK_DIR/sparkle_priv_key"
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$key_path"
    chmod 600 "$key_path"
    local output
    output=$("$sign_update" -f "$key_path" "$DMG_PATH")
    echo "$output"
    ED_SIG=$(echo "$output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    [ -n "$ED_SIG" ] || die "Could not parse Sparkle EdDSA signature."
}

ensure_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        say "Installing aws-cli"
        HOMEBREW_NO_AUTO_UPDATE=1 brew install awscli
    fi
}

upload_r2_and_appcast() {
    require_env CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY CLOUDFLARE_R2_ENDPOINT_URL CLOUDFLARE_R2_BUCKET APPCAST_PUBLIC_URL
    ensure_aws_cli

    export AWS_ACCESS_KEY_ID="$CLOUDFLARE_R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$CLOUDFLARE_R2_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="auto"

    local r2_dmg_key="${R2_PREFIX}/${DMG_NAME}"
    say "Uploading DMG to R2: s3://${CLOUDFLARE_R2_BUCKET}/${r2_dmg_key}"
    aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
        s3 cp "$DMG_PATH" "s3://$CLOUDFLARE_R2_BUCKET/$r2_dmg_key" \
        --content-type application/x-apple-diskimage

    local appcast_key="${R2_PREFIX}/appcast.xml"
    local appcast_path="$WORK_DIR/appcast.xml"
    aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
        s3 cp "s3://$CLOUDFLARE_R2_BUCKET/$appcast_key" "$appcast_path" 2>/dev/null || {
            cat > "$appcast_path" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${CHANNEL_TITLE}</title>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
  </channel>
</rss>
APPCAST
        }

    local pub_date
    pub_date=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
    local new_item
    new_item=$(cat <<ITEM
    <item>
      <title>Version $VERSION</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <enclosure
        url="$APPCAST_PUBLIC_URL/$DMG_NAME"
        length="$DMG_SIZE"
        type="application/x-apple-diskimage"
        sparkle:edSignature="$ED_SIG" />
    </item>
ITEM
)

    /usr/bin/python3 - "$appcast_path" "$VERSION" "$BUILD_NUMBER" "$new_item" <<'PYTHON'
import re
import sys

path, version, build, new_item = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
    xml = handle.read()

def matches_release(match):
    item = match.group(0)
    return (
        f"<sparkle:version>{build}</sparkle:version>" in item
        and f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in item
    )

xml = re.sub(
    r"\s*<item>[\s\S]*?</item>",
    lambda match: "" if matches_release(match) else match.group(0),
    xml,
)

match = re.search(r"\n(\s*)<item>", xml)
if match:
    xml = xml[:match.start()] + "\n" + new_item + xml[match.start():]
elif "</channel>" in xml:
    xml = xml.replace("</channel>", new_item + "\n  </channel>", 1)
else:
    raise SystemExit("Malformed appcast.xml: missing </channel>")

with open(path, "w", encoding="utf-8") as handle:
    handle.write(xml)
PYTHON

    aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
        s3 cp "$appcast_path" "s3://$CLOUDFLARE_R2_BUCKET/$appcast_key" \
        --content-type "application/xml" \
        --cache-control "no-cache, must-revalidate"

    say "R2 distribution complete"
    echo "DMG: $APPCAST_PUBLIC_URL/$DMG_NAME"
    echo "Appcast: $APPCAST_PUBLIC_URL/appcast.xml"
}

publish_github_release() {
    [ "$PUBLISH_RELEASE" = "true" ] || return 0
    require_env GITHUB_TOKEN

    local tag="v${VERSION}"
    local release_name="GPG Manager ${VERSION}"
    local api="https://api.github.com/repos/${GITHUB_REPO}"
    local uploads="https://uploads.github.com/repos/${GITHUB_REPO}"
    local auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
    local accept_header="Accept: application/vnd.github+json"
    local api_version_header="X-GitHub-Api-Version: 2022-11-28"
    local asset_name="${APP_NAME}-${VERSION}.dmg"
    local curl_retry=(--retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 10 --max-time 90)

    say "Publishing GitHub Release ${tag}"
    local release_json release_id
    release_json=$(curl -sS "${curl_retry[@]}" -H "$auth_header" -H "$accept_header" -H "$api_version_header" \
        "${api}/releases/tags/${tag}" 2>/dev/null || echo "")
    release_id=$(echo "$release_json" | /usr/bin/python3 -c \
        'import json,sys; d=json.load(sys.stdin); print(d.get("id","")) if isinstance(d,dict) else print("")' 2>/dev/null || echo "")

    if [ -z "$release_id" ]; then
        local body_json
        body_json=$(/usr/bin/python3 - "$tag" "$release_name" "$BUILD_NUMBER" <<'PYTHON'
import json
import sys

tag, name, build = sys.argv[1:]
print(json.dumps({
    "tag_name": tag,
    "name": name,
    "body": f"Automated GitHub Actions release build {build}.",
    "draft": False,
    "prerelease": False,
}))
PYTHON
)
        release_json=$(curl -sS "${curl_retry[@]}" -X POST \
            -H "$auth_header" -H "$accept_header" -H "$api_version_header" \
            -H "Content-Type: application/json" \
            -d "$body_json" \
            "${api}/releases")
        release_id=$(echo "$release_json" | /usr/bin/python3 -c \
            'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))' 2>/dev/null || echo "")
    fi
    [ -n "$release_id" ] || die "Could not create or find GitHub Release ${tag}."

    local existing_asset_id
    existing_asset_id=$(curl -sS "${curl_retry[@]}" \
        -H "$auth_header" -H "$accept_header" -H "$api_version_header" \
        "${api}/releases/${release_id}/assets" \
        | /usr/bin/python3 -c \
            "import json,sys; d=json.load(sys.stdin); print(next((a['id'] for a in d if a.get('name')=='${asset_name}'), ''))" 2>/dev/null || echo "")
    if [ -n "$existing_asset_id" ]; then
        curl -sS "${curl_retry[@]}" -X DELETE \
            -H "$auth_header" -H "$accept_header" -H "$api_version_header" \
            "${api}/releases/assets/${existing_asset_id}" >/dev/null
    fi

    local upload_response asset_url
    upload_response=$(curl -sS --retry 5 --retry-delay 3 --retry-all-errors \
        --connect-timeout 10 --max-time 300 -X POST \
        -H "$auth_header" -H "$accept_header" -H "$api_version_header" \
        -H "Content-Type: application/x-apple-diskimage" \
        --data-binary "@${DMG_PATH}" \
        "${uploads}/releases/${release_id}/assets?name=${asset_name}")
    asset_url=$(echo "$upload_response" | /usr/bin/python3 -c \
        'import json,sys; d=json.load(sys.stdin); print(d.get("browser_download_url",""))' 2>/dev/null || echo "")
    [ -n "$asset_url" ] || die "GitHub Release asset upload failed: $upload_response"
    RELEASE_ASSET_URL="$asset_url"
    say "GitHub Release asset: $RELEASE_ASSET_URL"
}

dispatch_homebrew_tap() {
    [ "$PUBLISH_RELEASE" = "true" ] || return 0
    [ -n "${RELEASE_ASSET_URL:-}" ] || return 0

    local token="${HOMEBREW_TAP_TOKEN:-${GITHUB_TOKEN:-}}"
    [ -n "$token" ] || return 0

    local tap_repo="${HOMEBREW_TAP_REPO:-Peak-Innovation-Studios/homebrew-tap}"
    local tap_workflow="${HOMEBREW_TAP_WORKFLOW:-bump-cask.yml}"
    local tap_ref="${HOMEBREW_TAP_REF:-main}"
    local payload
    payload=$(/usr/bin/python3 - "$tap_ref" "$VERSION" <<'PYTHON'
import json
import sys

ref, version = sys.argv[1:]
print(json.dumps({"ref": ref, "inputs": {"version": version}}))
PYTHON
)

    say "Dispatching Homebrew tap refresh"
    local status
    status=$(curl -sS --retry 5 --retry-delay 3 --retry-all-errors \
        --connect-timeout 10 --max-time 60 \
        -o "$WORK_DIR/homebrew-dispatch-response.json" \
        -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://api.github.com/repos/${tap_repo}/actions/workflows/${tap_workflow}/dispatches" || echo "000")

    if [ "$status" != "204" ]; then
        echo "WARN: Homebrew tap dispatch failed with HTTP ${status}."
        sed 's/^/      /' "$WORK_DIR/homebrew-dispatch-response.json" 2>/dev/null || true
    fi
}

VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
    if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
        VERSION="${GITHUB_REF#refs/tags/v}"
    else
        VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings \
            | awk -F'= ' '/MARKETING_VERSION/ {print $2; exit}')
    fi
fi
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"

require_env VERSION BUILD_NUMBER
DMG_NAME="${APP_NAME}-${VERSION}-${BUILD_NUMBER}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"
export DMG_NAME DMG_PATH
echo "DMG_PATH=$DMG_PATH" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
echo "DMG_NAME=$DMG_NAME" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

install_signing_certificate
archive_app
resign_app
notarize_app
build_dmg
notarize_dmg
if [ "$PUBLISH_RELEASE" = "true" ]; then
    sign_sparkle_update
    upload_r2_and_appcast
    publish_github_release
    dispatch_homebrew_tap
else
    say "PUBLISH_RELEASE=false — skipping Sparkle signing, R2, GitHub Release, and Homebrew tap updates."
fi

say "Release pipeline complete"
