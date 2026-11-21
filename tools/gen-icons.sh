#!/usr/bin/env bash
# Generates the PWA icon set (app/icons/*.png) from tools/icon.html via
# headless Chromium screenshots.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/app/icons"
PW="${PW:-npx --yes playwright@1.49.1}"
mkdir -p "$OUT"
PAGE="file://$ROOT/tools/icon.html"

shot() { # size extra
  local px="$1" extra="${2:-}"
  $PW screenshot --viewport-size="$px,$px" --wait-for-timeout=400 \
    "$PAGE$extra" "$OUT/icon-$px.png" > /dev/null 2>&1
  mv "$OUT/icon-$px.png" "$OUT/icon-$px.png.tmp" 2>/dev/null || true
  $PW screenshot --viewport-size="$px,$px" --wait-for-timeout=400 \
    "$PAGE$extra" "$OUT/icon-$px.png" > /dev/null
  rm -f "$OUT/icon-$px.png.tmp"
  echo "  $OUT/icon-$px.png"
}

echo "generating icons..."
shot 180            # apple-touch-icon
shot 192            # manifest any
shot 512            # manifest any
$PW screenshot --viewport-size=512,512 --wait-for-timeout=400 \
  "$PAGE?maskable" "$OUT/icon-maskable-512.png" > /dev/null
echo "  $OUT/icon-maskable-512.png"
echo "done"
