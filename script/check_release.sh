#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash local changes before checking a release." >&2
  exit 1
fi

swift test
swift build -c release --arch arm64
script/build_and_run.sh package

codesign --verify --deep --strict dist/Murmur.app
file dist/Murmur.app/Contents/MacOS/Murmur | grep -q arm64
test -x dist/Murmur.app/Contents/Resources/Runtimes/arm64/whisper-cli
test -f dist/Murmur.app/Contents/Resources/Murmur-LICENSE.txt
test -f dist/Murmur.app/Contents/Resources/THIRD_PARTY_NOTICES.md
hdiutil verify dist/Murmur.dmg

# The packaged app must launch with no build directory to fall back on. SwiftPM's
# Bundle.module for an executable target searches a hardcoded absolute .build path, so a
# resource missing from the .app stays invisible on the machine that built it and the app
# only breaks once that directory is cleaned.
test -d dist/Murmur.app/Contents/Resources/Murmur_MurmurNext.bundle

BUILD_PRODUCTS="$ROOT_DIR/.build/arm64-apple-macosx/release"
HIDDEN_BUILD_PRODUCTS="$BUILD_PRODUCTS.launch-gate-hidden"
restore_build_products() {
  if [[ -d "$HIDDEN_BUILD_PRODUCTS" ]]; then
    rm -rf "$BUILD_PRODUCTS"
    mv "$HIDDEN_BUILD_PRODUCTS" "$BUILD_PRODUCTS"
  fi
}
trap restore_build_products EXIT
rm -rf "$HIDDEN_BUILD_PRODUCTS"
mv "$BUILD_PRODUCTS" "$HIDDEN_BUILD_PRODUCTS"

LAUNCH_LOG="$(mktemp -t murmur-launch-gate)"
dist/Murmur.app/Contents/MacOS/Murmur >"$LAUNCH_LOG" 2>&1 &
LAUNCH_PID=$!
sleep 15
if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
  echo "The packaged app exited during launch:" >&2
  cat "$LAUNCH_LOG" >&2
  exit 1
fi
kill "$LAUNCH_PID"
wait "$LAUNCH_PID" 2>/dev/null || true
rm -f "$LAUNCH_LOG"

restore_build_products
trap - EXIT

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The release build changed tracked files." >&2
  exit 1
fi

echo
shasum -a 256 dist/Murmur.dmg
echo "Local release check passed."
