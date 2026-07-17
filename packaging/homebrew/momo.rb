# Homebrew Cask for Momo — the maintained copy.
# On release, this file is synced to the tap repo (simantaturja/homebrew-momo) at Casks/momo.rb.
# Set `sha256` per release to the sha of the exact zip attached to the GitHub release.
cask "momo" do
  version "0.3.4"
  sha256 "c515688b6a1593032f699df10b8e44311459c1e6978ff38d054dad4526fd93f5"

  url "https://github.com/simantaturja/momo/releases/download/v#{version}/Momo-#{version}.zip"
  name "Momo"
  desc "Fast native clipboard-history manager for the menu bar"
  homepage "https://github.com/simantaturja/momo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Momo.app"

  zap trash: "~/Library/Application Support/Momo"

  caveats <<~EOS
    Momo is not notarized yet, so macOS quarantines it on install. To run it, either clear
    the quarantine once:
      xattr -r -d com.apple.quarantine /Applications/Momo.app
    or right-click Momo.app in Finder and choose Open the first time.
  EOS
end
