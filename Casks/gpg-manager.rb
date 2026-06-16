# Homebrew Cask for GPG Manager.
#
# This file is intended for submission to the official Homebrew/homebrew-cask
# repository, which is the ONLY way to appear in the search at formulae.brew.sh.
# In a homebrew-cask PR it lives at:  Casks/g/gpg-manager.rb
#
# Before opening the PR, fill in the two release-specific values below:
#   1. `version` — the marketing version of the GitHub Release you are shipping.
#   2. `sha256`  — the SHA-256 of that release's DMG. Compute it with:
#
#        VERSION=X.Y.Z
#        curl -fSL -o /tmp/GPGManager.dmg \
#          "https://github.com/Peak-Innovation-Studios/GPGManager/releases/download/v${VERSION}/GPGManager-${VERSION}.dmg"
#        shasum -a 256 /tmp/GPGManager.dmg
#
# NOTE: formulae.brew.sh indexes only Homebrew/homebrew-core and
# Homebrew/homebrew-cask. A private tap will never appear in that search.
# Acceptance also requires clearing Homebrew's self-submission notability
# bar (currently ~225 GitHub stars / 90 forks / 90 watchers).

cask "gpg-manager" do
  version "X.Y.Z"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Peak-Innovation-Studios/GPGManager/releases/download/v#{version}/GPGManager-#{version}.dmg",
      verified: "github.com/Peak-Innovation-Studios/GPGManager/"
  name "GPG Manager"
  desc "Manager for GPG keys, gpg-agent settings, and Git commit signing"
  homepage "https://github.com/Peak-Innovation-Studios/GPGManager"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "GPGManager.app"

  zap trash: [
    "~/Library/Application Support/com.peakinnovationstudios.GPGManager",
    "~/Library/Caches/com.peakinnovationstudios.GPGManager",
    "~/Library/HTTPStorages/com.peakinnovationstudios.GPGManager",
    "~/Library/Preferences/com.peakinnovationstudios.GPGManager.plist",
    "~/Library/Saved Application State/com.peakinnovationstudios.GPGManager.savedState",
  ]
end
