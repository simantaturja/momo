# Homebrew Cask for Momo — the maintained copy.
# On release, this file is synced to the tap repo (simantaturja/homebrew-momo) at Casks/momo.rb.
# `sha256` is written by CI (.github/workflows/release.yml) on each release — never hand-edit it.
cask "momo" do
  version "0.8.0"
  sha256 "39104ddca04567adb17716ddde93fe14d8d2503971b30549e39bfc85cea66a09"

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
