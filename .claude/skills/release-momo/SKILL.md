---
name: release-momo
description: Use when cutting a new Momo release, publishing the app, or creating/updating the Homebrew cask or tap for Momo.
---

# Releasing Momo

Repo-specific runbook for shipping Momo via its custom, unsigned Homebrew tap.
`RELEASING.md` at the repo root is the source of truth — this skill sequences it and flags the
easy-to-miss steps. Repo: `simantaturja/momo`; tap: `simantaturja/homebrew-momo`.

## Steps

1. **Bump the version in all three places, kept in sync:**
   - `Sources/Momo/Info.plist` → `CFBundleShortVersionString` (and `CFBundleVersion`)
   - `Sources/MomoCore/MomoCore.swift` → `version`
   - `Tests/MomoCoreTests/SmokeTests.swift` asserts `MomoCore.version` — update it or the suite fails.
2. **Gate:** `swift test` green.
3. **Package:** `./scripts/package-app.sh` → produces `dist/Momo-<version>.zip` and prints its sha256.
4. **Publish:** `git tag v<version>` and `gh release create v<version> dist/Momo-<version>.zip`.
5. **Cask:** in `packaging/homebrew/momo.rb` set `version` + `sha256`, then copy it to the tap
   repo (`simantaturja/homebrew-momo` → `Casks/momo.rb`) and push.
6. **Verify:** `brew audit --cask --strict momo` and a real `brew install --cask --no-quarantine momo`.

## Gotchas

- The version must match in Info.plist, `MomoCore.swift`, and `SmokeTests` — the test enforces it.
- The cask `sha256` must be the sha of the exact zip attached to the release; regenerate per
  release (the package script prints it).
- Unsigned build → users need `--no-quarantine`. Drop it only after notarization (see the
  bottom of `RELEASING.md`; needs a paid Apple Developer account + Developer ID cert).
