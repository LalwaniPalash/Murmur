#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Murmur"
BUNDLE_ID="com.murmur.app"
MIN_SYSTEM_VERSION="15.0"
BUILD_CONFIGURATION="release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/Brand/Murmur.icns"
RUNTIME_SOURCE_ROOT="${MURMUR_RUNTIME_ROOT:-$ROOT_DIR/Vendor/Runtimes}"
MLX_RUNTIME_ROOT="${MURMUR_MLX_RUNTIME_ROOT:-$ROOT_DIR/Vendor/MLX/arm64}"
MLX_RESOURCE_BUNDLE="$MLX_RUNTIME_ROOT/mlx-swift_Cmlx.bundle"
MLX_METALLIB="$MLX_RESOURCE_BUNDLE/Contents/Resources/default.metallib"
ARM64_RUNTIME="$RUNTIME_SOURCE_ROOT/arm64"
APP_VERSION="0.2.0"
APP_BUILD="5"

# Ad-hoc signatures get a new code hash on every build, so macOS asks again before the
# rebuilt app may read its existing Keychain item. Prefer a stable Apple Development
# identity when the machine has one, while preserving the ad-hoc fallback for clean clones
# and CI. MURMUR_SIGNING_IDENTITY can select a specific identity explicitly.
SIGNING_IDENTITY="${MURMUR_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
      | head -n 1
  )"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

required_runtime_files=(
  "$ARM64_RUNTIME/whisper-cli"
  "$ARM64_RUNTIME/lib/libwhisper.1.dylib"
  "$ARM64_RUNTIME/lib/libggml.0.dylib"
  "$ARM64_RUNTIME/lib/libggml-base.0.dylib"
  "$ARM64_RUNTIME/libexec/libggml-metal.so"
)
for runtime_file in "${required_runtime_files[@]}"; do
  if [[ ! -f "$runtime_file" ]]; then
    echo "Missing bundled Whisper runtime: $runtime_file" >&2
    echo "Run script/stage_whisper_runtime.sh first." >&2
    exit 1
  fi
done
if ! compgen -G "$ARM64_RUNTIME/libexec/libggml-cpu*.so" >/dev/null; then
  echo "Missing bundled Whisper CPU backend in $ARM64_RUNTIME/libexec" >&2
  echo "Run script/stage_whisper_runtime.sh first." >&2
  exit 1
fi
if [[ ! -s "$MLX_METALLIB" ]]; then
  echo "Missing pinned MLX Metal library: $MLX_METALLIB" >&2
  echo "Run script/stage_mlx_runtime.sh first." >&2
  exit 1
fi
MLX_EXPECTED_SHA256="$(awk 'NR == 1 { print $1 }' "$MLX_RUNTIME_ROOT/default.metallib.sha256")"
MLX_ACTUAL_SHA256="$(shasum -a 256 "$MLX_METALLIB" | awk '{ print $1 }')"
if [[ -z "$MLX_EXPECTED_SHA256" || "$MLX_ACTUAL_SHA256" != "$MLX_EXPECTED_SHA256" ]]; then
  echo "Pinned MLX Metal library failed its integrity check." >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift "$ROOT_DIR/script/generate_brand_assets.swift"
swift build -c "$BUILD_CONFIGURATION" --arch arm64
BUILD_PRODUCTS_DIR="$(swift build -c "$BUILD_CONFIGURATION" --arch arm64 --show-bin-path)"
BUILD_BINARY="$BUILD_PRODUCTS_DIR/$APP_NAME"
MLX_WORKER_BINARY="$BUILD_PRODUCTS_DIR/MurmurMLXWorker"

if [[ ! -x "$MLX_WORKER_BINARY" ]]; then
  echo "Missing MLX worker build product: $MLX_WORKER_BINARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_HELPERS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$MLX_WORKER_BINARY" "$APP_HELPERS/MurmurMLXWorker"
chmod +x "$APP_HELPERS/MurmurMLXWorker"
cp "$MLX_METALLIB" "$APP_HELPERS/mlx.metallib"
cp -R "$MLX_RESOURCE_BUNDLE" "$APP_RESOURCES/"
# The bundled Archivo Condensed legend face travels in a SwiftPM resource bundle.
# It goes in Contents/Resources because codesign rejects a .bundle inside Contents/MacOS.
# Note SwiftPM's Bundle.module does NOT search there for an executable target; MurmurFace
# resolves the bundle itself. See Sources/MurmurNext/DesignSystem/MurmurTheme.swift.
for resource_bundle in "$BUILD_PRODUCTS_DIR"/*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  rm -rf "$APP_RESOURCES/$(basename "$resource_bundle")"
  cp -R "$resource_bundle" "$APP_RESOURCES/"
done
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/Murmur.icns"
fi
cp "$ROOT_DIR/LICENSE" "$APP_RESOURCES/Murmur-LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
if [[ -d "$RUNTIME_SOURCE_ROOT" ]]; then
  mkdir -p "$APP_RESOURCES/Runtimes"
  rsync -a "$RUNTIME_SOURCE_ROOT"/ "$APP_RESOURCES/Runtimes"/
  find "$APP_RESOURCES/Runtimes" -type f -name "whisper-cli" -exec chmod +x {} \;
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
 <key>CFBundleExecutable</key>
 <string>$APP_NAME</string>
 <key>CFBundleIdentifier</key>
 <string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleIconFile</key>
  <string>Murmur</string>
 <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>LSUIElement</key>
  <true/>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Murmur uses the microphone for local dictation.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --deep \
  --timestamp=none \
  --identifier "$BUNDLE_ID" \
  -r="designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE"

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

create_dmg() {
  rm -rf "$DMG_ROOT" "$DMG_PATH"
  mkdir -p "$DMG_ROOT"
  cp -R "$APP_BUNDLE" "$DMG_ROOT/"
  ln -s /Applications "$DMG_ROOT/Applications"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  hdiutil verify "$DMG_PATH"
  ls -lh "$DMG_PATH"
}

case "$MODE" in
  run)
    open_app
    ;;
  dmg|package|--dmg|--package)
    create_dmg
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|dmg|package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
