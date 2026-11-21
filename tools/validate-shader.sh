#!/usr/bin/env bash
# Validates shaders/beer-liquid.fsh as GLSL ES 1.00 — the same profile both
# WebGL1 (preview) and SpriteKit's GLSL-ES-style SKShader source use.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer an explicit override, then whatever is on PATH (CI: apt glslang-tools),
# then the local rootless install from setup.sh.
: "${HOME:=$(getent passwd "$(id -u)" | cut -d: -f6)}"
GLSLANG="${GLSLANG:-$(command -v glslangValidator || true)}"
if [ -z "$GLSLANG" ]; then
  GLSLANG="$HOME/tools/bin/glslangValidator"
fi

TMP="$(mktemp /tmp/beer-liquid-XXXXXX.frag)"
trap 'rm -f "$TMP"' EXIT
{
  echo '#version 100'
  echo 'precision mediump float;'
  cat "$ROOT/shaders/beer-liquid.fsh"
} > "$TMP"

"$GLSLANG" "$TMP"
echo "shader OK (GLSL ES 1.00)"
