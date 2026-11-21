#!/usr/bin/env bash
# Generates the icon set: PWA icons (app/icons/*.png) and the NATIVE iOS app
# icon (aibeer/Assets.xcassets/AppIcon.appiconset/icon-1024.png) — all from
# tools/icon.html via headless Chromium (Playwright).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/app/icons"
ASSETS="$ROOT/aibeer/Assets.xcassets/AppIcon.appiconset"
PW="${PW:-npx --yes playwright@1.49.1}"
mkdir -p "$OUT" "$ASSETS"
PAGE="file://$ROOT/tools/icon.html"

shot() { # px output-path extra
  local px="$1" dest="$2" extra="${3:-}"
  # shellcheck disable=SC2086
  $PW screenshot --viewport-size="$px,$px" --wait-for-timeout=400 \
    "$PAGE$extra" "$dest" > /dev/null 2>&1
  echo "  $dest"
}

echo "generating icons..."
shot 180 "$OUT/icon-180.png"                       # apple-touch-icon
shot 192 "$OUT/icon-192.png"                       # manifest any
shot 512 "$OUT/icon-512.png"                       # manifest any
shot 512 "$OUT/icon-maskable-512.png" "?maskable"  # manifest maskable
shot 1024 "$ASSETS/icon-1024.png"                  # native iOS app icon
echo "done"
