#!/bin/bash
#
# swiftlint.sh — runs SwiftLint for GPGManager.
#
# Used two ways:
#   1. As the Xcode "SwiftLint" Run Script build phase (no args → lint).
#   2. On demand from a terminal:
#        scripts/swiftlint.sh          # lint, print violations
#        scripts/swiftlint.sh --fix    # autocorrect the fixable rules in place
#        scripts/swiftlint.sh --strict # fail on warnings too (CI / pre-commit gate)
#
# Keeping the logic here (rather than inline in project.pbxproj) means tweaks
# never require editing the Xcode project file.

set -euo pipefail

# Resolve the repo root from this script's location so it works regardless of the
# build phase's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Homebrew on Apple Silicon installs to /opt/homebrew/bin, which isn't on the
# minimal PATH Xcode hands build phases.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "warning: SwiftLint not installed. Install it with: brew install swiftlint"
  exit 0
fi

CONFIG="${REPO_ROOT}/.swiftlint.yml"

# --fix is its own SwiftLint mode (autocorrect), not a flag on `lint`. Route it
# accordingly; pass everything else (e.g. --strict) straight through to lint.
mode="lint"
passthrough=()
for arg in "$@"; do
  case "${arg}" in
    --fix) mode="fix" ;;
    *) passthrough+=("${arg}") ;;
  esac
done

# Note: macOS ships bash 3.2, where "${arr[@]}" on an empty array trips `set -u`.
# The "${arr[@]+...}" form expands to nothing when the array is empty.
if [ "${mode}" = "fix" ]; then
  exec swiftlint --fix --config "${CONFIG}" ${passthrough[@]+"${passthrough[@]}"}
else
  exec swiftlint lint --config "${CONFIG}" ${passthrough[@]+"${passthrough[@]}"}
fi
