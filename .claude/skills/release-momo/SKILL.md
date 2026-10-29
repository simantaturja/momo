---
name: release-momo
description: Use when cutting a new Momo release, publishing the app, bumping its version, or creating/updating the Homebrew cask or tap for Momo.
---

# Releasing Momo

Releases are automated by `.github/workflows/release.yml`: pushing a tag `vX.Y.Z` tests,
packages, publishes the GitHub release, and updates the cask in the tap
(`simantaturja/homebrew-momo`) and in this repo's `master`. Your job is the local half:
bump, gate, merge, tag. `RELEASING.md` is the source of truth.

## Steps

1. **Pick the version** with the user (semver: feature → minor, fix → patch). Don't guess.
2. **Bump:** `./scripts/bump-version.sh X.Y.Z` — sets Info.plist (short version + build),
   `MomoCore.version`, `SmokeTests`, and the cask `version`. Never edit these by hand.
3. **Gate:** `swift test` green. Show the output.
4. **Commit** on the working branch: `release: bump to X.Y.Z` (author-only, no trailer).
5. **Merge:** `git checkout master && git merge --ff-only <branch>`.
6. **Confirm with the user, then publish** (outward-facing, hard to undo):
   `git push origin master && git tag vX.Y.Z && git push origin vX.Y.Z`
7. **Watch:** `gh run watch -R simantaturja/momo $(gh run list -R simantaturja/momo --workflow release.yml --branch vX.Y.Z -L1 --json databaseId -q '.[0].databaseId')`
   (if empty, the run hasn't registered yet — retry after a few seconds).
8. **After green:** `git pull --ff-only` (CI committed the cask sha to `master`), then verify:
   `brew update && brew upgrade --cask momo` (or `brew install --cask momo`).

## Gotchas

- CI fails fast if the tag ≠ Info.plist version. Fix by bumping, not by retagging blindly.
- The cask `sha256` is written by CI only — the zip isn't byte-reproducible, so a local
  sha never matches the released asset. Don't hand-edit it.
- Tap push needs repo secret `TAP_GITHUB_TOKEN` (fine-grained PAT, Contents read/write on
  `simantaturja/homebrew-momo`). If that step fails, the release is still published; set the
  secret and re-run the job (the release step re-uploads the asset so the sha stays matched).
  Only re-run when the tap step failed — a re-run rebuilds the zip and changes its sha.
- Never publish by hand (`gh release create`) — the tag push already triggers CI and the two race.
- Users of the unsigned app need `brew trust simantaturja/momo` and
  `xattr -r -d com.apple.quarantine /Applications/Momo.app` (Homebrew 6.x removed
  `--no-quarantine`). Both go away once notarized — see `RELEASING.md`.
- To try a build locally without releasing, use the `install-momo` skill instead.
