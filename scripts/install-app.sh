#!/usr/bin/env bash
#
# Builds Momo.app from the working tree and installs it into /Applications,
# replacing any existing copy (including a Homebrew-installed one), then launches it.
#
# Usage:  ./scripts/install-app.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

DEST="/Applications/Momo.app"

./scripts/package-app.sh

echo "==> Quitting running Momo (if any)"
osascript -e 'quit app "Momo"' 2>/dev/null || pkill -x Momo || true
for _ in {1..20}; do pgrep -xq Momo || break; sleep 0.25; done
pkill -9 -x Momo || true

echo "==> Installing to $DEST"
rm -rf "$DEST"
/usr/bin/ditto "dist/Momo.app" "$DEST"
xattr -r -d com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"
echo "==> Installed and launched $DEST"
