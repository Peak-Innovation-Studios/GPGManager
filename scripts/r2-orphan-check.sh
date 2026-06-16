#!/usr/bin/env bash
#
# Report R2 objects under the release prefix that are NOT referenced by any
# appcast enclosure (orphans) — e.g. leftover artifacts from old or aborted
# runs. Read-only: it lists candidates for manual cleanup, never deletes.
#
# Required env: CLOUDFLARE_R2_ACCESS_KEY_ID, CLOUDFLARE_R2_SECRET_ACCESS_KEY,
# CLOUDFLARE_R2_ENDPOINT_URL, CLOUDFLARE_R2_BUCKET. Optional: R2_PREFIX
# (default "gpg-manager").

set -euo pipefail

R2_PREFIX="${R2_PREFIX:-gpg-manager}"
WORK_DIR="${RUNNER_TEMP:-/tmp}"

say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

for var in CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY \
           CLOUDFLARE_R2_ENDPOINT_URL CLOUDFLARE_R2_BUCKET; do
    [ -n "${!var:-}" ] || die "Missing required environment variable: $var"
done

export AWS_ACCESS_KEY_ID="$CLOUDFLARE_R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$CLOUDFLARE_R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

appcast_path="$WORK_DIR/appcast-orphan-check.xml"

say "Listing s3://${CLOUDFLARE_R2_BUCKET}/${R2_PREFIX}/"
objects=$(aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 ls "s3://$CLOUDFLARE_R2_BUCKET/$R2_PREFIX/" \
    | awk '{print $4}' \
    | grep -v '^$' \
    | sort -u)

say "Downloading appcast"
aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 cp "s3://$CLOUDFLARE_R2_BUCKET/${R2_PREFIX}/appcast.xml" "$appcast_path"

# Enclosure basenames referenced by the appcast.
referenced=$(grep -oE 'url="[^"]+"' "$appcast_path" \
    | sed -E 's/^url="//; s/"$//; s#.*/##' \
    | sort -u)

echo
echo "=== Referenced by appcast ==="
printf '%s\n' "$referenced" | sed 's/^/  /'

echo
echo "=== Orphans (in R2, not referenced by the appcast; appcast.xml excluded) ==="
orphan_count=0
total=0
while IFS= read -r obj; do
    [ -n "$obj" ] || continue
    total=$((total + 1))
    [ "$obj" = "appcast.xml" ] && continue
    if ! printf '%s\n' "$referenced" | grep -qxF "$obj"; then
        echo "  $obj"
        orphan_count=$((orphan_count + 1))
    fi
done <<< "$objects"
[ "$orphan_count" -eq 0 ] && echo "  (none)"

echo
echo "Objects under prefix: ${total}, orphans: ${orphan_count}"
say "Read-only report complete. Remove orphans manually (aws s3 rm) if desired."
