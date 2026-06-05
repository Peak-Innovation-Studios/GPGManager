#!/usr/bin/env bash
#
# Populate GitHub Actions repository secrets for the release workflow.

set -euo pipefail

DEFAULT_ASC_KEY_PATH="/Users/dpeak/Library/Mobile Documents/com~apple~CloudDocs/Peak Innovation Studios/CI:CD Auth/AuthKey_H8U8643C3P.p8"
DEFAULT_DEVELOPER_ID_P12_PATH="/Users/dpeak/Library/Mobile Documents/com~apple~CloudDocs/Peak Innovation Studios/CI:CD Auth/DeveloperID[!lvK3rry].p12"

say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

prompt() {
    local label="$1"
    local default_value="${2:-}"
    local value
    if [ -n "$default_value" ]; then
        read -r -p "$label [$default_value]: " value
        printf '%s' "${value:-$default_value}"
    else
        read -r -p "$label: " value
        printf '%s' "$value"
    fi
}

prompt_secret() {
    local label="$1"
    local required="${2:-required}"
    local value
    while true; do
        read -r -s -p "$label: " value
        printf '\n' >&2
        if [ -n "$value" ] || [ "$required" != "required" ]; then
            printf '%s' "$value"
            return 0
        fi
        warn "Value is required."
    done
}

prompt_required() {
    local label="$1"
    local default_value="${2:-}"
    local value
    while true; do
        value=$(prompt "$label" "$default_value")
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
        warn "Value is required."
    done
}

base64_file() {
    local path="$1"
    [ -f "$path" ] || die "File not found: $path"
    base64 < "$path" | tr -d '\n'
}

set_secret() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        warn "Skipping $name because no value was provided."
        return 0
    fi
    if secret_exists "$name" && [ "${FORCE_SECRETS:-false}" != "true" ]; then
        say "Skipping $name because it already exists. Set FORCE_SECRETS=true to overwrite."
        return 0
    fi
    printf '%s' "$value" | gh secret set "$name" \
        --app actions \
        --repo "$REPO" >/dev/null
    say "Set $name"
}

secret_exists() {
    local name="$1"
    printf '%s\n' "$EXISTING_ACTIONS_SECRETS" | grep -qx "$name"
}

should_set_secret() {
    local name="$1"
    [ "${FORCE_SECRETS:-false}" = "true" ] || ! secret_exists "$name"
}

skip_existing_secret() {
    local name="$1"
    say "Skipping $name because it already exists. Set FORCE_SECRETS=true to overwrite."
}

infer_asc_key_id() {
    local path="$1"
    local filename
    filename=$(basename "$path")
    case "$filename" in
        AuthKey_*.p8) printf '%s' "${filename#AuthKey_}" | sed 's/\.p8$//' ;;
        *) printf '' ;;
    esac
}

require_command gh
require_command base64

gh auth status >/dev/null || die "gh is not authenticated. Run: gh auth login"

REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
    REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
fi
REPO=$(prompt_required "GitHub repository" "$REPO")

say "Configuring GitHub Actions secrets for $REPO"
if [ "${FORCE_SECRETS:-false}" = "true" ]; then
    warn "FORCE_SECRETS=true; existing Actions secrets will be overwritten."
fi

EXISTING_ACTIONS_SECRETS=$(gh secret list \
    --app actions \
    --repo "$REPO" \
    | awk '{print $1}')

say "Writing missing secrets to GitHub Actions"

if should_set_secret DEVELOPER_ID_CERT_P12_BASE64; then
    developer_id_p12_path=$(prompt_required "Developer ID .p12 path" "$DEFAULT_DEVELOPER_ID_P12_PATH")
    set_secret DEVELOPER_ID_CERT_P12_BASE64 "$(base64_file "$developer_id_p12_path")"
else
    skip_existing_secret DEVELOPER_ID_CERT_P12_BASE64
fi

if should_set_secret DEVELOPER_ID_CERT_PASSWORD; then
    set_secret DEVELOPER_ID_CERT_PASSWORD "$(prompt_secret "Developer ID .p12 password")"
else
    skip_existing_secret DEVELOPER_ID_CERT_PASSWORD
fi

if should_set_secret ASC_API_PRIVATE_KEY; then
    asc_key_path=$(prompt_required "App Store Connect AuthKey .p8 path" "$DEFAULT_ASC_KEY_PATH")
    set_secret ASC_API_PRIVATE_KEY "$(base64_file "$asc_key_path")"
else
    skip_existing_secret ASC_API_PRIVATE_KEY
fi

if should_set_secret ASC_API_KEY_ID; then
    asc_key_id_default=$(infer_asc_key_id "${asc_key_path:-$DEFAULT_ASC_KEY_PATH}")
    set_secret ASC_API_KEY_ID "$(prompt_required "App Store Connect API key ID" "$asc_key_id_default")"
else
    skip_existing_secret ASC_API_KEY_ID
fi

if should_set_secret ASC_API_ISSUER_ID; then
    set_secret ASC_API_ISSUER_ID "$(prompt_required "App Store Connect issuer ID")"
else
    skip_existing_secret ASC_API_ISSUER_ID
fi

if should_set_secret SPARKLE_PRIVATE_KEY; then
    set_secret SPARKLE_PRIVATE_KEY "$(prompt_secret "Sparkle private key (base64 string from generate_keys)" optional)"
else
    skip_existing_secret SPARKLE_PRIVATE_KEY
fi

if should_set_secret CLOUDFLARE_R2_ACCESS_KEY_ID; then
    set_secret CLOUDFLARE_R2_ACCESS_KEY_ID "$(prompt_required "Cloudflare R2 access key ID")"
else
    skip_existing_secret CLOUDFLARE_R2_ACCESS_KEY_ID
fi

if should_set_secret CLOUDFLARE_R2_SECRET_ACCESS_KEY; then
    set_secret CLOUDFLARE_R2_SECRET_ACCESS_KEY "$(prompt_secret "Cloudflare R2 secret access key")"
else
    skip_existing_secret CLOUDFLARE_R2_SECRET_ACCESS_KEY
fi

if should_set_secret CLOUDFLARE_R2_ENDPOINT_URL; then
    set_secret CLOUDFLARE_R2_ENDPOINT_URL "$(prompt_required "Cloudflare R2 endpoint URL")"
else
    skip_existing_secret CLOUDFLARE_R2_ENDPOINT_URL
fi

if should_set_secret CLOUDFLARE_R2_BUCKET; then
    set_secret CLOUDFLARE_R2_BUCKET "$(prompt_required "Cloudflare R2 bucket")"
else
    skip_existing_secret CLOUDFLARE_R2_BUCKET
fi

if should_set_secret HOMEBREW_TAP_TOKEN; then
    set_secret HOMEBREW_TAP_TOKEN "$(prompt_secret "Homebrew tap token (optional, press Return to skip)" optional)"
else
    skip_existing_secret HOMEBREW_TAP_TOKEN
fi

say "Done. Run the Release workflow with publish=false for the first verification pass."
