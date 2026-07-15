# Homebrew Cask for Momo — the maintained copy.
# On release, this file is synced to the tap repo (OWNER/homebrew-momo) at Casks/momo.rb.
# Replace OWNER with your GitHub username (e.g. simantaturja) throughout.
cask "momo" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ZIP_SHA256"

  url "https://github.com/OWNER/momo/releases/download/v#{version}/Momo-#{version}.zip"
  name "Momo"
  desc "Fast native clipboard-history manager for the menu bar"
  homepage "https://github.com/OWNER/momo"

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
