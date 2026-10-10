#!/bin/bash
#
# Assembles Mac7zip.app from the SwiftPM build product and bundles the
# official 7-Zip engine (Vendor/7zz) into Contents/Resources.
#
# Usage: Scripts/build_app.sh [debug|release]   (default: release)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="Mac7zip"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

if [ ! -f "$ROOT/Vendor/7zz" ]; then
    echo "error: Vendor/7zz is missing. Run Scripts/fetch_engine.sh first." >&2
    exit 1
fi
cp "$ROOT/Vendor/7zz" "$APP/Contents/Resources/7zz"
chmod +x "$APP/Contents/Resources/7zz"

# App icon + localization tables.
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Resources/en.lproj" "$APP/Contents/Resources/"
cp -R "$ROOT/Resources/zh-Hans.lproj" "$APP/Contents/Resources/"

cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so the bundled engine runs without quarantine prompts.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "warning: ad-hoc codesign failed (app still runnable locally)"

echo "==> Done: $APP"
