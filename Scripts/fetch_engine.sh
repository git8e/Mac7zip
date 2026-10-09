#!/bin/bash
#
# Downloads the official 7-Zip macOS console build and installs the `7zz`
# binary into Vendor/. See https://www.7-zip.org/download.html

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-2604}"

# The release tag is like 26.04 while the file is 7z2604-mac.tar.xz.
MAJOR_MINOR="${VERSION%??}.${VERSION: -2}"
URL="https://github.com/ip7z/7zip/releases/download/${MAJOR_MINOR}/7z${VERSION}-mac.tar.xz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading $URL"
curl -fL -o "$TMP/7z-mac.tar.xz" "$URL"
tar -xf "$TMP/7z-mac.tar.xz" -C "$TMP"

mkdir -p "$ROOT/Vendor"
cp "$TMP/7zz" "$ROOT/Vendor/7zz"
cp "$TMP/License.txt" "$ROOT/THIRD_PARTY/7-Zip-License.txt" 2>/dev/null || true
chmod +x "$ROOT/Vendor/7zz"

echo "==> Installed $("$ROOT/Vendor/7zz" 2>&1 | head -1)"
