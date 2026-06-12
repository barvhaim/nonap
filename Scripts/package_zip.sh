#!/usr/bin/env bash
#
# Build NoNap.app and zip it for sharing with others.
#
# This produces NoNap.zip, which you can send to friends. Because the app is
# only ad-hoc signed (not notarized by Apple), the recipient must bypass
# Gatekeeper the first time — see the printed instructions / README.
#
#   ./Scripts/package_zip.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

# Build the .app first.
"${SCRIPT_DIR}/make_app.sh"

ZIP="${ROOT}/NoNap.zip"
echo "==> Zipping NoNap.app -> ${ZIP}"
rm -f "${ZIP}"
# ditto preserves the bundle structure and resource forks correctly.
ditto -c -k --sequesterRsrc --keepParent "${ROOT}/NoNap.app" "${ZIP}"

echo "==> Done: ${ZIP}"
echo ""
echo "    Send NoNap.zip to whoever you like. On first launch they must:"
echo "      1. Unzip it, then RIGHT-CLICK NoNap.app -> Open -> Open."
echo "         (A plain double-click is blocked because it isn't notarized.)"
echo "    Or, in Terminal:  xattr -dr com.apple.quarantine /path/to/NoNap.app"
