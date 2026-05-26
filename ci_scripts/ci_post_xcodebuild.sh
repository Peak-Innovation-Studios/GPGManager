#!/bin/sh
#
# ci_post_xcodebuild.sh — runs in Xcode Cloud after xcodebuild finishes
# (whether it succeeded or failed).
#
# For our Developer ID + Notarize workflow there's nothing custom to do
# here: Xcode Cloud's "Notarize" post-action handles the signing and
# notary submission natively when the workflow's archive action is
# configured for Direct Distribution. We keep this script so the slot
# is available for future automation (uploading the .dmg to GitHub
# Releases, posting a Slack message, etc.) without another commit just
# to add it.

set -euo pipefail

echo "▸ ci_post_xcodebuild: status=${CI_XCODEBUILD_EXIT_CODE:-unknown}"
echo "  CI_ARCHIVE_PATH:           ${CI_ARCHIVE_PATH:-unset}"
echo "  CI_APP_STORE_SIGNED_APP_PATH:   ${CI_APP_STORE_SIGNED_APP_PATH:-unset}"
echo "  CI_DEVELOPER_ID_SIGNED_APP_PATH: ${CI_DEVELOPER_ID_SIGNED_APP_PATH:-unset}"

if [ -n "${CI_DEVELOPER_ID_SIGNED_APP_PATH:-}" ] && [ -d "${CI_DEVELOPER_ID_SIGNED_APP_PATH}" ]; then
    echo "▸ Developer ID signed output:"
    codesign -dvv "${CI_DEVELOPER_ID_SIGNED_APP_PATH}" 2>&1 | grep -E "Authority|Identifier" | head -4 || true
fi

echo "▸ ci_post_xcodebuild: done"
