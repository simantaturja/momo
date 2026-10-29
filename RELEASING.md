# Releasing Momo (Homebrew cask via a custom tap)

Momo ships as a **custom Homebrew tap** — you host the cask, no approval gate. The app
is currently distributed **unsigned** (ad-hoc signed only), so users see a one-time
Gatekeeper prompt. Notarization can be added later once a paid Apple Developer account
and a *Developer ID Application* certificate are available.

Owner is **`simantaturja`**: app repo `simantaturja/momo`, tap repo `simantaturja/homebrew-momo`.

## One-time setup

1. **App repo** — done: pushed to `github.com/simantaturja/momo` (master).
2. **Create the tap repo** — Homebrew taps must be named `homebrew-<name>`:
   ```sh
   gh repo create simantaturja/homebrew-momo --public --clone
   mkdir -p homebrew-momo/Casks
   ```
3. **Tap token for CI** — create a fine-grained PAT with *Contents: read/write* on
   `simantaturja/homebrew-momo` only, then:
   ```sh
   gh secret set TAP_GITHUB_TOKEN -R simantaturja/momo
   ```

## Each release (automated)

`.github/workflows/release.yml` runs on any pushed `vX.Y.Z` tag: checks the tag matches
Info.plist, runs `swift test`, packages, publishes the GitHub release, then writes the new
`version` + `sha256` into the cask in the tap and back onto `master`.

```sh
./scripts/bump-version.sh 0.5.0          # Info.plist, MomoCore, SmokeTests, cask version
swift test
git commit -am "release: bump to 0.5.0"  # on your branch, then ff-merge into master
git push origin master
git tag v0.5.0 && git push origin v0.5.0  # triggers the release
gh run watch -R simantaturja/momo         # then: git pull --ff-only (CI committed the sha)
```

If the tap step fails (e.g. missing secret), the release is already out; fix it and re-run
the job — the release step re-uploads the asset so the cask sha stays correct. Only re-run
when the tap step failed: a re-run rebuilds the zip, so its sha changes.

Don't publish by hand while the workflow is enabled — pushing the tag already triggers it,
and a hand-made zip's sha won't match the asset CI uploads.

## Verify the install path

After the release run is green:

```sh
brew untap simantaturja/momo 2>/dev/null; brew tap simantaturja/momo
brew trust simantaturja/momo
brew audit --cask --strict momo   # catches cask style/URL/sha problems
brew install --cask momo
xattr -r -d com.apple.quarantine /Applications/Momo.app && open -a Momo
```

## Users install with

```sh
brew tap simantaturja/momo
brew trust simantaturja/momo          # Homebrew 6.0+ requires trusting third-party taps
brew install --cask momo
xattr -r -d com.apple.quarantine /Applications/Momo.app   # unsigned: clear Gatekeeper once
```

Notes: `--no-quarantine` was removed in Homebrew 6.x with no replacement, so the unsigned app
is quarantined on install — clear it with the `xattr` line above, or right-click Momo.app →
Open the first time. Third-party taps are no longer trusted by default (`brew trust`).

## Later: notarization (smooth, no Gatekeeper prompt)

Requires a paid Apple Developer Program membership + a *Developer ID Application* cert.
Then, in `scripts/package-app.sh`, replace the ad-hoc `codesign --sign -` with your
Developer ID identity and add:

```sh
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" dist/Momo.app
xcrun notarytool submit dist/Momo-$VERSION.zip \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW --wait
xcrun stapler staple dist/Momo.app
# re-zip after stapling
```

Once notarized, drop the `xattr` quarantine-clearing step from the install instructions.
