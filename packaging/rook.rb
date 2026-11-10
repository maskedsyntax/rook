# Homebrew cask. Lives in a tap repo (e.g. maskedsyntax/homebrew-tap, as
# Casks/rook.rb); then: brew install --cask maskedsyntax/tap/rook
#
# Per release: bump the version in Resources/Info.plist, `make notarize`,
# upload build/Rook-<version>.zip to a GitHub release tagged v<version>,
# and paste the printed sha256 below.
cask "rook" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_MAKE_NOTARIZE"

  url "https://github.com/maskedsyntax/rook/releases/download/v#{version}/Rook-#{version}.zip"
  name "rook"
  desc "Keyboard window snapping and saved layouts"
  homepage "https://github.com/maskedsyntax/rook"

  depends_on macos: ">= :sonoma"

  app "Rook.app"

  uninstall quit:       "dev.maskedsyntax.rook",
            login_item: "Rook"

  zap trash: "~/.config/rook"
end
