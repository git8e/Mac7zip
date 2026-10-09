#!/bin/bash
#
# Creates a distributable DMG containing Mac7Zip.app and an Applications
# symlink. Requires build/Mac7Zip.app (run `make app` first).
#
# Usage: Scripts/make_dmg.sh [version-tag]   (default: 1.0)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0}"
APP="$ROOT/build/Mac7Zip.app"
STAGE="$ROOT/build/dmg-staging"
DMG="$ROOT/build/Mac7Zip-$VERSION.dmg"

if [ ! -d "$APP" ]; then
    echo "error: build/Mac7Zip.app not found. Run 'make app' first." >&2
    exit 1
fi

echo "==> Staging DMG contents"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create -volname "Mac7Zip" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DMG"