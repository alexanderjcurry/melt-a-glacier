#!/bin/bash
# Renders art/icon/app_icon.svg (and the splash) to the PNGs the exports use.
# Needs Node + Playwright's Chromium:  bash art/icon/make_icons.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=ui/icons
mkdir -p "$OUT"
node art/icon/render.js
echo "Icons written to $OUT/"
