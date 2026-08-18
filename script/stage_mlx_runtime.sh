#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode-mlx"
PRODUCTS="$DERIVED_DATA/Build/Products/Release"
SOURCE_BUNDLE="$PRODUCTS/mlx-swift_Cmlx.bundle"
SOURCE_METALLIB="$SOURCE_BUNDLE/Contents/Resources/default.metallib"
DESTINATION="$ROOT_DIR/Vendor/MLX/arm64"

xcodebuild \
  -scheme MurmurMLXWorker \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Release \
  -skipPackagePluginValidation \
  build

if [[ ! -s "$SOURCE_METALLIB" ]]; then
  echo "MLX build did not produce $SOURCE_METALLIB" >&2
  exit 1
fi

rm -rf "$DESTINATION/mlx-swift_Cmlx.bundle"
mkdir -p "$DESTINATION"
cp -R "$SOURCE_BUNDLE" "$DESTINATION/"
(
  cd "$SOURCE_BUNDLE/Contents/Resources"
  shasum -a 256 default.metallib
) > "$DESTINATION/default.metallib.sha256"

echo "Staged pinned MLX Metal resources in $DESTINATION"
