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

## Each release

1. **Bump the version** in all three places, kept in sync:
   - `Sources/Momo/Info.plist` — `CFBundleShortVersionString` (and `CFBundleVersion`)
   - `Sources/MomoCore/MomoCore.swift` — `version`
   - `Tests/MomoCoreTests/SmokeTests.swift` — asserts `MomoCore.version`; update it or `swift test` fails.

2. **Build the distributable app + zip:**
   ```sh
   ./scripts/package-app.sh
   ```
   This produces `dist/Momo.app`, `dist/Momo-<version>.zip`, and prints the **sha256**.

3. **Tag and publish a GitHub release** with the zip attached:
   ```sh
   VERSION=0.1.0
   git tag "v$VERSION" && git push origin "v$VERSION"
   gh release create "v$VERSION" "dist/Momo-$VERSION.zip" \
     --title "Momo $VERSION" --notes "See CHANGELOG."
   ```

4. **Update the cask** — edit `packaging/homebrew/momo.rb`:
   - set `version`
   - set `sha256` to the value printed in step 2
   Then copy it into the tap and push:
   ```sh
   cp packaging/homebrew/momo.rb ../homebrew-momo/Casks/momo.rb
   cd ../homebrew-momo && git add Casks/momo.rb \
     && git commit -m "momo $VERSION" && git push
   ```

5. **Verify the whole install path locally:**
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
