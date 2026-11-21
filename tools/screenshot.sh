#!/usr/bin/env bash
# Captures preview screenshots for all styles at two tilt angles via headless
# Chromium (Playwright). Output lands in preview/screenshots/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/preview/screenshots"
PW="${PW:-npx --yes playwright@1.49.1}"
mkdir -p "$OUT"

shot() { # name style deg extra-params
  local name="$1" style="$2" deg="$3" extra="${4:-}"
  # shellcheck disable=SC2086
  $PW screenshot --viewport-size=390,700 --wait-for-timeout=1500 \
    "file://$ROOT/preview/index.html?style=$style&fill=0.72&deg=$deg&wobble=0.035&freeze=1&clean=1&$extra" \
    "$OUT/$name.png" > /dev/null
  echo "  $OUT/$name.png"
}

# slosh action shots: kick=1 starts the surface off-level; no freeze →
# the screenshot catches the spring-damper mid-oscillation.
action() { # name style deg waitms
  local name="$1" style="$2" deg="$3" waitms="$4"
  $PW screenshot --viewport-size=390,700 --wait-for-timeout="$waitms" \
    "file://$ROOT/preview/index.html?style=$style&fill=0.72&deg=$deg&kick=1&clean=1" \
    "$OUT/$name.png" > /dev/null
  echo "  $OUT/$name.png"
}

echo "capturing screenshots..."
shot lager-flat        lager      0
shot lager-tilt        lager      35
shot brownAle-flat     brownAle   0
shot brownAle-tilt     brownAle   35
shot blackStout-flat   blackStout 0
shot blackStout-tilt   blackStout 35
shot rainbow-flat      rainbow    0
shot rainbow-tilt      rainbow    35
action slosh-lager     lager      60 900
action slosh-rainbow   rainbow    -55 1250
echo "done"
