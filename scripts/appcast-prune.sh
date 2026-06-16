#!/usr/bin/env bash
#
# Remove a single release entry (by marketing version + build number) from the
# published Sparkle appcast on R2 and delete its enclosure object. Used to clean
# up mistaken or duplicate appcast entries.
#
# Required env: VERSION, BUILD, CLOUDFLARE_R2_ACCESS_KEY_ID,
# CLOUDFLARE_R2_SECRET_ACCESS_KEY, CLOUDFLARE_R2_ENDPOINT_URL,
# CLOUDFLARE_R2_BUCKET. Optional: R2_PREFIX (default "gpg-manager").

set -euo pipefail

R2_PREFIX="${R2_PREFIX:-gpg-manager}"
WORK_DIR="${RUNNER_TEMP:-/tmp}"

say() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
    for var in "$@"; do
        [ -n "${!var:-}" ] || die "Missing required environment variable: $var"
    done
}

require_env VERSION BUILD \
    CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY \
    CLOUDFLARE_R2_ENDPOINT_URL CLOUDFLARE_R2_BUCKET

export AWS_ACCESS_KEY_ID="$CLOUDFLARE_R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$CLOUDFLARE_R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

appcast_key="${R2_PREFIX}/appcast.xml"
appcast_path="$WORK_DIR/appcast-prune.xml"

say "Downloading appcast s3://${CLOUDFLARE_R2_BUCKET}/${appcast_key}"
aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 cp "s3://$CLOUDFLARE_R2_BUCKET/$appcast_key" "$appcast_path"

# Remove the matching <item> and report its enclosure basename(s) on stdout.
enclosures=$(/usr/bin/python3 - "$appcast_path" "$VERSION" "$BUILD" <<'PYTHON'
import os
import re
import sys

path, version, build = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
    xml = handle.read()

removed = []


def replace(match):
    item = match.group(0)
    if (
        f"<sparkle:version>{build}</sparkle:version>" in item
        and f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in item
    ):
        url = re.search(r'url="([^"]+)"', item)
        if url:
            removed.append(os.path.basename(url.group(1)))
        return ""
    return item


new_xml = re.sub(r"\s*<item>[\s\S]*?</item>", replace, xml)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(new_xml)

print("\n".join(removed))
PYTHON
)

if [ -z "$enclosures" ]; then
    say "No appcast entry matched version ${VERSION} build ${BUILD}; nothing to do."
    exit 0
fi

say "Re-uploading pruned appcast"
aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
    s3 cp "$appcast_path" "s3://$CLOUDFLARE_R2_BUCKET/$appcast_key" \
    --content-type "application/xml" \
    --cache-control "no-cache, must-revalidate"

while IFS= read -r enclosure; do
    [ -n "$enclosure" ] || continue
    say "Deleting enclosure s3://${CLOUDFLARE_R2_BUCKET}/${R2_PREFIX}/${enclosure}"
    aws --endpoint-url "$CLOUDFLARE_R2_ENDPOINT_URL" \
        s3 rm "s3://$CLOUDFLARE_R2_BUCKET/${R2_PREFIX}/${enclosure}"
done <<< "$enclosures"

say "Pruned ${VERSION} (${BUILD}) from the appcast."
