#!/usr/bin/env bash
#
# Build NoNap.app and package it into a drag-to-install NoNap.dmg.
#
# Uses only hdiutil (built into macOS), so it needs no Homebrew dependency and
# works as-is on GitHub Actions macOS runners.
#
#   ./Scripts/make_dmg.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

# Build the .app first.
"${SCRIPT_DIR}/make_app.sh"

DMG="${ROOT}/NoNap.dmg"
STAGE="$(mktemp -d)"
VOLNAME="NoNap"

echo "==> Staging DMG contents in ${STAGE}"
cp -R "${ROOT}/NoNap.app" "${STAGE}/NoNap.app"
# Drag-to-Applications shortcut.
ln -s /Applications "${STAGE}/Applications"

echo "==> Building ${DMG}"
rm -f "${DMG}"
hdiutil create \
    -volname "${VOLNAME}" \
    -srcfolder "${STAGE}" \
    -ov \
    -format UDZO \
    "${DMG}"

rm -rf "${STAGE}"

echo "==> Done: ${DMG}"
echo "    Open it, then drag NoNap into Applications."
