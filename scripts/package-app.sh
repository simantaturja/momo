#!/usr/bin/env bash
#
# Builds Momo.app (universal arm64 + x86_64) and a distributable zip for the
# Homebrew cask. Ad-hoc signs the bundle so its Accessibility grant persists
# across launches, then prints the sha256 you paste into the cask.
#
# Usage:  ./scripts/package-app.sh
# Output: dist/Momo.app  and  dist/Momo-<version>.zip
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Momo"
PLIST="Sources/Momo/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_DIR=".build/apple/Products/Release"     # universal build output
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

echo "==> Building $APP_NAME $VERSION (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

echo "==> Assembling $APP"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "==> Done"
echo "    app:    $APP"
echo "    asset:  $ZIP"
echo "    version:$VERSION"
echo "    sha256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
