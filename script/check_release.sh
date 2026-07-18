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

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The release build changed tracked files." >&2
  exit 1
fi

echo
shasum -a 256 dist/Murmur.dmg
echo "Local release check passed."
