# Momo — AI working guide

Fast native macOS clipboard-history manager (menu-bar accessory). Swift + AppKit, SwiftPM.
User docs: `README.md`. Design deep-dive: `docs/jargon-and-improvements.md`.

## Architecture (the one invariant)

Two targets, one hard boundary:

- **MomoCore** — pure, testable logic, no AppKit: `Store` (GRDB/SQLite), `ClipboardMonitor`,
  `HistoryIndex`, `FuzzyMatch`, `PrivacyFilter`, `ClipboardItem`. The clipboard is abstracted
  behind the `PasteboardReading` protocol so it can be faked in tests.
- **Momo** — thin AppKit shell (menu bar, panel, hotkey, paste). Side-effects only; "humble objects".

**Rule: logic lives in MomoCore and is tested; the shell stays dumb and untested.** When adding
behavior, put the decision in MomoCore behind a testable seam and keep
`Paster`/`Settings`/`PanelController`/`HotkeyManager` as thin adapters.

**Speed thesis:** do zero expensive work on the two paths a human waits on — the panel *opening*
and a *search keystroke*. The panel is pre-warmed; search runs over an in-memory index; DB writes
and image decoding are background-only. Don't move work onto those two paths.

## Commands

- `swift build` — compile
- `swift test` — run the MomoCore suite (all logic tests live here)
- `swift run Momo` — launch the app
- `./scripts/package-app.sh` — build a distributable universal `Momo.app` + zip
- Release → `RELEASING.md`, or the `release-momo` skill

**Gotcha:** after renaming/moving the repo directory, `rm -rf .build` first. SwiftPM bakes the
absolute path into the module cache; a stale cache fails with
`PCH was compiled with module cache path …`.

## Testing

- **TDD for MomoCore** (`superpowers:test-driven-development`): failing test first, then minimal
  code. Assert real behavior against a real in-memory `Store(path: ":memory:")` — no mocks beyond
  the `PasteboardReading` fake.
- **Do NOT add a test harness or DI to the shell.** `Paster`/`Settings`/`PanelController`/
  `HotkeyManager` touch AppKit / `UserDefaults` / `NSPasteboard.general` directly by design; there
  is no logic in them worth a seam. App-target changes are compile+build verified, not unit-tested.
- Baseline: **30 tests, all green.** Keep them green; show the output before claiming done.

## Data model & invariants (don't break these)

- **Dedupe by content, not location.** `ClipboardItem.contentHash` keys on text / file paths /
  **image bytes** (`imageHash(_:)`) — never the blob filename (a random UUID). On a dedupe hit,
  `Store.upsert` bumps recency and reclaims the redundant incoming blob.
- **Retention:** non-pinned items capped by count (`Settings.maxItems`); images also by total
  bytes and age. Pins are exempt. `prune` returns the number deleted; callers skip the UI refresh
  when it's 0. Blobs are deleted with their rows; orphaned blobs are reaped on launch.
- **Privacy:** `PrivacyFilter` drops pasteboards flagged concealed/transient/auto-generated at
  ingest. Never persist anything that bypasses it.

## Working style (agent loop)

Non-trivial changes go through a **build → check loop**, not one agent acting alone. The loop
is **driven by the top-level session (or you), not self-running** — subagents don't nest, so
something at the top must dispatch each step:

1. Dispatch **`momo-developer`** — implements the task test-first (TDD for MomoCore logic) and
   gets `swift build` + `swift test` green. It does not self-approve or commit.
2. Dispatch **`momo-reviewer`** — independently attacks the diff in fresh context; never writes code.
3. Feed findings back to `momo-developer`; re-dispatch both until the reviewer is clean. Then
   a human commits.

To automate steps 1–3, run the saved workflow:
`Workflow({ name: "momo-build-review", args: "<task>" })` (or `args: { task, maxRounds }`).
It loops build → review → fix until the reviewer is clean (or maxRounds, default 3), leaving
a reviewed, green working tree for you to commit. It never commits.

The developer and reviewer are peers: the developer never grades its own work; the reviewer
never fixes what it flags. Caveat worth remembering — the developer authors *both* the code and
its tests, so a green suite is not an independent gate on its own. The reviewer must judge test
**adequacy** (does the test actually pin the invariant / would it catch a regression?), not just
that a test exists.

## Conventions

- **Simplicity first.** Minimum code that solves the problem; nothing speculative. Match existing
  style. Surgical changes — every changed line traces to the task. Flag over-engineering as
  readily as bugs.
- **Commits are author-only** (no `Co-Authored-By` trailer). Work on a branch, then `--ff-only`
  merge into `master` (this repo's trunk). Commit only when asked.

## Don'ts (hard-won)

- **Don't sandbox the app** — it breaks the Carbon global hotkey and the CGEvent paste.
- **Don't half-wire `.richText`** — the case is reserved and only passively handled (grouped with
  `.text` in `Paster`, given an icon in `HistoryRowView`); `ClipboardMonitor` never produces it.
  Either wire RTF capture end-to-end or leave it as-is — don't extend the dead path further.
- **Don't abstract the shell** for "testability" (see Testing).
- Auto-paste needs **Accessibility** permission (synthesized ⌘V). The app prompts and degrades
  gracefully (item still lands on the clipboard) — keep it that way.

## Distribution

Unsigned custom Homebrew tap. `packaging/homebrew/momo.rb` is the cask; `RELEASING.md` is the
runbook. Notarization is a later step (needs a paid Apple Developer account). Data lives in
`~/Library/Application Support/Momo/` and never leaves the machine.
