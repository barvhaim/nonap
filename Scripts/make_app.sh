#!/usr/bin/env bash
#
# Build NoNap and assemble a runnable NoNap.app bundle.
#
#   ./Scripts/make_app.sh            # release build (default)
#   CONFIG=debug ./Scripts/make_app.sh
#
set -euo pipefail

# Resolve the project root (parent of this script's directory).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP="$ROOT/NoNap.app"

echo "==> Building NoNap ($CONFIG)..."
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/NoNap"
if [[ ! -x "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/NoNap"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# App icon. Build it on demand if the compiled .icns is missing.
ICNS="$ROOT/Resources/NoNap.icns"
if [[ ! -f "$ICNS" ]]; then
    echo "==> NoNap.icns missing; building it..."
    "$SCRIPT_DIR/make_iconset.sh"
fi
cp "$ICNS" "$APP/Contents/Resources/NoNap.icns"

echo "==> Ad-hoc codesigning ..."
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Launch with:  open \"$APP\""
