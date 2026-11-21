#!/usr/bin/env bash
# aibeer — rootless Linux/WSL2 tooling installer (idempotent).
# Installs: Swift toolchain, glslangValidator, swift-format, Playwright Chromium.
set -euo pipefail

echo "== Swift toolchain (swift.org) =="
if [ -x "$HOME/swift/usr/bin/swift" ]; then
  echo "already installed: $("$HOME/swift/usr/bin/swift" --version 2>&1 | head -1)"
else
  VERSION="6.4.3"
  URL="https://download.swift.org/swift-${VERSION}-release/ubuntu2204/swift-${VERSION}-RELEASE/swift-${VERSION}-RELEASE-ubuntu22.04.tar.gz"
  mkdir -p "$HOME/tmp" "$HOME/swift"
  curl -L --retry 3 -o "$HOME/tmp/swift.tar.gz" "$URL"
  tar xzf "$HOME/tmp/swift.tar.gz" -C "$HOME/swift" --strip-components 1
  "$HOME/swift/usr/bin/swift" --version
fi

echo "== glslangValidator =="
if [ -x "$HOME/tools/bin/glslangValidator" ]; then
  echo "already installed"
else
  GLSLANG_VERSION="16.6.0"
  mkdir -p "$HOME/tools/bin" "$HOME/tmp"
  curl -sL "https://github.com/KhronosGroup/glslang/releases/download/${GLSLANG_VERSION}/glslang-${GLSLANG_VERSION}-linux-x86_64-release.tar.gz" \
    -o "$HOME/tmp/glslang.tgz"
  tar xzf "$HOME/tmp/glslang.tgz" -C "$HOME/tmp"
  cp "$HOME/tmp/bin/glslangValidator" "$HOME/tools/bin/"
fi

echo "== swift-format =="
if [ -x "$HOME/tools/bin/swift-format" ]; then
  echo "already installed"
else
  export PATH="$HOME/swift/usr/bin:$PATH"
  git clone --depth 1 https://github.com/swiftlang/swift-format.git "$HOME/tmp/swift-format"
  ( cd "$HOME/tmp/swift-format" && swift build -c release )
  cp "$HOME/tmp/swift-format/.build/release/swift-format" "$HOME/tools/bin/"
fi

echo "== Playwright Chromium =="
npx --yes playwright@1.49.1 install chromium

echo
echo "Tooling ready. Add to PATH when needed:"
echo '  export PATH="$HOME/swift/usr/bin:$HOME/tools/bin:$PATH"'
