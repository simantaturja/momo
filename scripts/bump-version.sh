#!/usr/bin/env bash
#
# Sets the Momo version everywhere it lives (Info.plist, MomoCore, SmokeTests, cask)
# and increments CFBundleVersion. Does not commit or tag.
#
# Usage:  ./scripts/bump-version.sh 0.5.0
#
set -euo pipefail

cd "$(dirname "$0")/.."

NEW="${1:?usage: $0 <major.minor.patch>}"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: '$NEW' is not major.minor.patch" >&2; exit 1; }

PLIST="Sources/Momo/Info.plist"
NEXT=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))

# sed, not PlistBuddy: PlistBuddy reformats the whole file.
sed -i '' -E "s#(<key>CFBundleShortVersionString</key><string>)[^<]+#\1$NEW#" "$PLIST"
sed -i '' -E "s#(<key>CFBundleVersion</key><string>)[^<]+#\1$NEXT#" "$PLIST"
sed -i '' -E "s/(static let version = \")[^\"]+\"/\1$NEW\"/" Sources/MomoCore/MomoCore.swift
sed -i '' -E "s/(XCTAssertEqual\(MomoCore.version, \")[^\"]+\"/\1$NEW\"/" Tests/MomoCoreTests/SmokeTests.swift
sed -i '' -E "s/^(  version \")[^\"]+\"/\1$NEW\"/" packaging/homebrew/momo.rb

for f in "$PLIST" Sources/MomoCore/MomoCore.swift Tests/MomoCoreTests/SmokeTests.swift packaging/homebrew/momo.rb; do
  grep -q "$NEW" "$f" || { echo "error: version not updated in $f" >&2; exit 1; }
done

echo "==> Version set to $NEW (build $NEXT)"
git --no-pager diff --stat
