---
name: install-momo
description: Use when asked to build Momo as an app, install it locally, put it in /Applications, or try the current working tree as the real app (not a release).
---

# Installing Momo locally

`./scripts/install-app.sh` builds the working tree as a universal, ad-hoc-signed `Momo.app`
(via `scripts/package-app.sh`), quits the running Momo, replaces `/Applications/Momo.app`,
clears quarantine, and launches it.

## Steps

1. `swift test` green first — don't install a red tree.
2. `./scripts/install-app.sh`
3. Verify: `pgrep -lf /Applications/Momo.app` shows a process, and
   `lipo -archs /Applications/Momo.app/Contents/MacOS/Momo` shows `x86_64 arm64`.

## Gotchas

- It overwrites a Homebrew-installed copy. Brew still records the old cask version;
  `brew reinstall --cask momo` restores the released build.
- The version shown is whatever Info.plist says — unreleased commits still read as the last
  released version. Don't bump just to install; bumping is part of a release (`release-momo`).
- Each ad-hoc-signed build has a new code hash, so macOS may ask for **Accessibility** again
  (needed for auto-paste). If auto-paste stops working: System Settings → Privacy & Security →
  Accessibility, remove Momo, re-add it.
