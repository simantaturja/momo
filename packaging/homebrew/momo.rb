# Homebrew Cask for Momo — the maintained copy.
# On release, this file is synced to the tap repo (simantaturja/homebrew-momo) at Casks/momo.rb.
# Set `sha256` per release to the sha of the exact zip attached to the GitHub release.
cask "momo" do
  version "0.1.0"
  sha256 "88831acb24dc1db95ff607037d988c8ce9a43be1177da292dfcd58c9acffb010"

  url "https://github.com/simantaturja/momo/releases/download/v#{version}/Momo-#{version}.zip"
  name "Momo"
  desc "Fast native clipboard-history manager for the menu bar"
  homepage "https://github.com/simantaturja/momo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Momo.app"

  zap trash: [
    "~/Library/Application Support/Momo",
  ]

  caveats <<~EOS
    Momo is not notarized yet, so Gatekeeper may block the first launch. Either:
      brew install --cask --no-quarantine momo
    or right-click Momo.app in /Applications and choose Open once.

    Momo needs Accessibility permission to paste automatically:
      System Settings > Privacy & Security > Accessibility > enable Momo.
  EOS
end
