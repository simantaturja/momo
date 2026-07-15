# Pastal — Design Spec

**Date:** 2026-07-15
**Status:** Approved (brainstorming)

## Summary

Pastal is a native macOS clipboard-history manager built as a fast alternative to
Maccy. It is a menubar app written in Swift + AppKit. The single design principle
driving every decision: **do zero slow work on the hot paths (popup open, search
typing).** All heavy work — clipboard polling, reading, persistence, image handling —
runs off the hot path on background queues.

The two latency pains that motivated this project (popup open delay, search typing
lag) are architected out: the panel is pre-warmed and reused rather than rebuilt on
open, and search runs over an in-memory index off the main thread rather than
filtering on the main thread.

## Goals

- Popup open → first render feels instant (< 50ms).
- Typing to filter feels instant (< 16ms per keystroke over ~1000 items).
- Negligible idle CPU/memory when not in use.
- Full content parity with Maccy: plain text, rich text/HTML, images, files/paths.
- Respect clipboard privacy (never store secrets from password managers).

## Non-Goals (YAGNI)

- No cloud sync.
- No web/Electron/Tauri UI.
- No cross-platform support (macOS only).
- No plugin system.
- No full-UI automation test suite (fragile); manual smoke + perf harness instead.

## Content Types

All four, at full parity:

- **Plain text** — core case.
- **Rich text / HTML** — preserve RTF/HTML so paste keeps formatting.
- **Images** — screenshots and copied images; stored as disk blobs with cached
  thumbnails, lazy-loaded in the list.
- **Files / paths** — copied Finder items stored as file references, pasted as files.

## Architecture — Performance Tactics

These tactics *are* the product; they are the difference from Maccy.

- **Pre-warmed panel.** `NSPanel` + `NSTableView` are built once at launch and never
  torn down. The hotkey handler only calls `orderFront` and focuses the search field —
  no allocation, no layout rebuild on open. Open delay ≈ 0.
- **Non-activating panel.** The panel floats over the active app. The previously
  frontmost app is stashed on open so focus can be restored on paste.
- **Global hotkey** via Carbon `RegisterEventHotKey` — lowest-overhead, reliable.
- **Clipboard monitor.** NSPasteboard emits no change notifications, so poll
  `changeCount` on a background timer (~250ms). Read pasteboard contents *only* when
  `changeCount` changes. Idle cost is negligible.
- **In-memory search index.** The recent N items (~1000) are held as lightweight
  structs (id, preview text, kind, timestamp). Fuzzy matching runs over this array —
  microseconds for 1000 items — so typing stays instant. The table diff-updates rather
  than reloading.
- **Storage.** SQLite via GRDB. Text, rich text, and metadata live in the DB. Images
  are written as blob files on disk in Application Support with a cached thumbnail, so
  images never bloat the search path.
- **Virtualized render.** View-based `NSTableView` reuses cells; only visible rows
  render; thumbnails load lazily.

### Data Flow

```
poll(bg) → changeCount changed? → read pasteboard → drop concealed/secret
        → dedupe (identical = move to top) → persist SQLite → prepend to index
hotkey  → show pre-warmed panel → focus search field → table = full history
type    → fuzzy filter in-memory (bg) → diff update table
enter   → write item to pasteboard → hide panel → restore prev app → synth ⌘V
```

## Components

Each unit has one job and is testable in isolation.

| Unit | Job | Depends on |
|---|---|---|
| `ClipboardMonitor` | Poll `changeCount` on bg timer; read pasteboard; apply privacy filter; emit new item | NSPasteboard |
| `PrivacyFilter` | Drop items marked `org.nspasteboard.ConcealedType` / `TransientType`; pure function | — |
| `Store` | SQLite persist/load/dedupe/prune; image blob + thumbnail file mgmt | GRDB, disk |
| `HistoryIndex` | In-memory model of recent items; fuzzy search + ranking (match quality × recency); diffable snapshots | — |
| `HotkeyManager` | Register/unregister global hotkey; fire callback | Carbon |
| `PanelController` | Own the pre-warmed NSPanel; show/hide; stash + restore prev frontmost app | AppKit |
| `HistoryView` | NSTableView + search field; cell render; lazy thumbnails; keyboard nav | HistoryIndex |
| `Paster` | Write chosen item to pasteboard; restore focus; synth ⌘V via CGEvent | AppKit, CGEvent |
| `AppCoordinator` | Wire units; menubar item; settings (hotkey, retention, launch-at-login) | all |

### Key Boundaries

`HistoryIndex` and `Store` are the two units that matter most:

- **`HistoryIndex` = speed.** In-memory only; never touches disk. `HistoryView` reads
  only from the index.
- **`Store` = durability.** Never on a hot path; all access on background queues.

`ClipboardMonitor` writes to both. `HistoryView` reads only the index. This seam keeps
every unit testable headless.

## Retention Defaults

- Keep 1000 items.
- Images pruned past 30 days OR 500MB total cap, whichever comes first.
- Pinned/favorited items are exempt from pruning.

## Privacy

- Honor `org.nspasteboard.ConcealedType` and transient-type markers (set by 1Password
  and similar). These items are never stored.

## Testing

### Unit tests (fast, headless, in-memory SQLite)

- **`PrivacyFilter`** — concealed/transient dropped, normal kept.
- **`Store`** — dedupe moves item to top (no duplicate row); prune respects count +
  size + pin exemption; image blob round-trips.
- **`HistoryIndex`** — fuzzy `gh` → `github`; ranking puts better + more-recent matches
  first; diff snapshot correctness.
- **`ClipboardMonitor`** — unchanged `changeCount` = no read; changed = exactly one
  emit (inject a fake pasteboard).

### Performance assertions (guard against regressing into Maccy)

- open → first render < 50ms (pre-warmed panel).
- keystroke → table update < 16ms over 1000 items (one frame).
- idle CPU ≈ 0 between polls.

### Manual smoke

- Hotkey open, type-to-filter, paste into 3 apps covering rich text, image, and file.
- Focus restore to previous app is correct after paste.
