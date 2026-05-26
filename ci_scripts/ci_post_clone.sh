#!/bin/sh
#
# ci_post_clone.sh — runs in Xcode Cloud after the repo is checked out,
# before any xcodebuild action.
#
# Use this script to install build-time dependencies or surface
# environment context that helps debug failed runs. Xcode Cloud runs
# this from the repo root regardless of the working directory it
# invokes the script with, so use $CI_WORKSPACE for repo-relative paths.

set -euo pipefail

echo "▸ ci_post_clone: environment"
echo "  Xcode:         $(xcodebuild -version | tr '\n' ' ')"
echo "  Swift:         $(swift --version | head -1)"
echo "  macOS:         $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
echo "  Hostname:      $(hostname)"

# Xcode Cloud predefines these. Surface them so build logs make the
# context obvious if/when something goes wrong.
echo "▸ Xcode Cloud variables"
echo "  CI_WORKFLOW:           ${CI_WORKFLOW:-unset}"
echo "  CI_BUILD_NUMBER:       ${CI_BUILD_NUMBER:-unset}"
echo "  CI_COMMIT:             ${CI_COMMIT:-unset}"
echo "  CI_BRANCH:             ${CI_BRANCH:-unset}"
echo "  CI_XCODE_SCHEME:       ${CI_XCODE_SCHEME:-unset}"
echo "  CI_XCODE_PROJECT:      ${CI_XCODE_PROJECT:-unset}"

echo "▸ ci_post_clone: done"
