#!/usr/bin/env bash
# Regenerates the two README screenshots (preview/screenshots/) via headless
# Chromium (Playwright). Everything else visual is verified live in the
# preview (see README "Browser preview" for the URL params).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/preview/screenshots"
PW="${PW:-npx --yes playwright@1.49.1}"
mkdir -p "$OUT"

shot() { # name style deg
  local name="$1" style="$2" deg="$3"
  # shellcheck disable=SC2086
  $PW screenshot --viewport-size=390,700 --wait-for-timeout=1500 \
    "file://$ROOT/preview/index.html?style=$style&fill=0.72&deg=$deg&wobble=0.035&freeze=1&clean=1" \
    "$OUT/$name.png" > /dev/null
  echo "  $OUT/$name.png"
}

echo "capturing README screenshots..."
shot lager-tilt   lager   35
shot rainbow-tilt rainbow 35
echo "done"
