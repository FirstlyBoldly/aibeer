#!/usr/bin/env bash
# aibeer — all WSL2/Linux verification gates in one run.
# Usage: tools/gate.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/swift/usr/bin:$HOME/tools/bin:$PATH"

step() { echo; echo "==== $1 ===="; }

step "BeerCore: swift build + swift test"
( cd "$ROOT/BeerCore" && swift test 2>&1 | grep -E "Test Suite '(BeerCoreTests|All tests)' (passed|failed)" )

step "beerctl dump-styles -> preview/styles.json"
( cd "$ROOT/BeerCore" && swift run -q beerctl dump-styles > "$ROOT/preview/styles.json" )
echo "styles.json written ($(wc -c < "$ROOT/preview/styles.json") bytes)"

step "shader: glslangValidator (GLSL ES 1.00)"
"$ROOT/tools/validate-shader.sh"

step "regenerate preview/index.html + app/index.html"
node "$ROOT/tools/embed.mjs"

step "PWA: manifest + service worker checks"
python3 -c "import json;json.load(open('$ROOT/app/manifest.webmanifest'));print('  manifest OK')"
node --check "$ROOT/app/sw.js" && echo "  sw.js syntax OK"
grep -q "__SHADER_BODY__\|__STYLES_JSON__\|__RUNTIME__" "$ROOT/app/index.html" \
  && { echo "  app/index.html has unreplaced placeholders" >&2; exit 1; } \
  || echo "  app/index.html placeholders resolved"

step "iOS sources: swiftc -parse"
find "$ROOT/aibeer" -name '*.swift' -print0 | while IFS= read -r -d '' f; do
  swiftc -parse "$f" && echo "  parse OK: ${f#"$ROOT"/}"
done

step "project.yml: YAML check"
python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('  yaml OK')" "$ROOT/project.yml"

step "swift-format lint"
if "$HOME/tools/bin/swift-format" lint --recursive --strict "$ROOT/BeerCore/Sources" "$ROOT/aibeer"; then
  echo "  format OK"
else
  echo "  format violations found" >&2
  exit 1
fi

echo
echo "ALL GATES PASSED"
