#!/usr/bin/env bash
#
# Build NoNap.icns from the 1024x1024 master PNG.
#
# Regenerates the master via make_icon.py, slices it into the standard macOS
# .iconset sizes with `sips`, and compiles NoNap.icns with `iconutil`. The
# result lands at Resources/NoNap.icns, which make_app.sh copies into the bundle.
#
#   ./Scripts/make_iconset.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

MASTER="Resources/Assets/icon_1024.png"
ICONSET="Resources/Assets/NoNap.iconset"
ICNS="Resources/NoNap.icns"

echo "==> Rendering master icon..."
python3 Scripts/make_icon.py "$MASTER"

echo "==> Slicing $ICONSET ..."
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# size  scale  filename
gen() {
    local px="$1" name="$2"
    sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name" >/dev/null
}

gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

echo "==> Compiling $ICNS ..."
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Done: $ICNS"
