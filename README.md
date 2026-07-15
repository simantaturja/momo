# Momo

A fast, native macOS clipboard-history manager that lives in the menu bar. Momo
keeps a searchable history of what you copy — text, files, and images — and pastes
any past item back with a keystroke. It is built in plain Swift + AppKit (no Electron,
no SwiftUI) so the popup opens instantly and typing filters with zero lag.

> Momo was formerly named **Pastal**.

## Features

- **Instant popup** — a pre-warmed floating panel, built once at launch.
- **Instant fuzzy search** — filtering runs over an in-memory index, never the disk.
- **Dedupe** — re-copying the same text, file, or image moves it to the top instead of
  duplicating it.
- **Images & files** — thumbnails for images (stored as blobs on disk), file paths for files.
- **Privacy filter** — items marked concealed/transient by the source app
  (1Password, etc.) are never stored.
- **Pin** frequently used items; **delete** single items or **clear** all history.
- **Auto-paste** — picks an item, restores your previous app, and presses ⌘V for you.

## Requirements

- macOS 13 or later
- Xcode / Swift toolchain (Swift 5.9+)

## Build & run

```sh
swift build           # compile
swift run Momo        # launch the menu-bar app
swift test            # run the MomoCore test suite
```

There is no Dock icon — Momo runs as a menu-bar accessory. Look for its icon in the
menu bar; the menu offers **Show Momo**, **Launch at Login**, and **Clear History**.

## Permissions

- **Accessibility** — required for automatic paste (Momo synthesizes ⌘V). On first run
  it prompts; grant Momo under *System Settings ▸ Privacy & Security ▸ Accessibility*.
  Without it, the item is still placed on the clipboard — you can press ⌘V yourself.

## Shortcut

- **⌘⇧V** — open/close the history panel. (If another app already owns ⌘⇧V, use
  **Show Momo** from the menu-bar icon.)
- In the panel: type to search, ↑/↓ to move, ↵ to paste, **⌘P** to pin, **⌘⌫** to delete,
  **Esc** to dismiss.

## Data & privacy

History is stored locally in `~/Library/Application Support/Momo/` (a SQLite database
plus an `images/` folder). Data never leaves your machine. It is not encrypted at rest;
at-rest protection relies on your macOS account and FileVault. Non-pinned items are
capped by count, and images additionally by total size and age.

## Layout

- `Sources/MomoCore` — pure, testable core (store, clipboard monitor, index, fuzzy match,
  privacy filter) behind a `PasteboardReading` protocol.
- `Sources/Momo` — the AppKit shell (menu bar, panel, hotkey, paste).
- `Tests/MomoCoreTests` — unit tests for the core.
