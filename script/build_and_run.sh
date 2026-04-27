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
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/Brand/Murmur.icns"
VENDORED_RUNTIMES="$ROOT_DIR/Vendor/Runtimes"
APP_VERSION="0.1.0"
APP_BUILD="1"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift "$ROOT_DIR/script/generate_brand_assets.swift"
swift build -c "$BUILD_CONFIGURATION" --arch arm64 --arch x86_64
BUILD_PRODUCTS_DIR="$(swift build -c "$BUILD_CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
BUILD_BINARY="$BUILD_PRODUCTS_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/Murmur.icns"
fi
if [[ -d "$VENDORED_RUNTIMES" ]]; then
  mkdir -p "$APP_RESOURCES/Runtimes"
  rsync -a "$VENDORED_RUNTIMES"/ "$APP_RESOURCES/Runtimes"/
  find "$APP_RESOURCES/Runtimes" -type f \( -name "whisper-cli" -o -name "llama-cli" \) -exec chmod +x {} \;
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
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Murmur uses the microphone for local dictation.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Murmur uses on-device speech recognition to turn speech into text.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign \
  --force \
  --sign - \
  --deep \
  --timestamp=none \
  --identifier "$BUNDLE_ID" \
  -r="designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
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
