#!/usr/bin/env bash
set -euo pipefail

WHISPER_VERSION="1.8.4"
WHISPER_ARCHIVE_SHA256="b26f30e52c095ccb75da40b168437736605eb280de57381887bf9e2b65f31e66"
WHISPER_ARCHIVE_URL="https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v${WHISPER_VERSION}.tar.gz"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DESTINATION="${MURMUR_RUNTIME_DESTINATION:-$ROOT_DIR/Vendor/Runtimes/arm64}"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This runtime script requires an Apple Silicon Mac." >&2
  exit 1
fi

for required_command in curl shasum tar cmake install_name_tool otool; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Missing required command: $required_command" >&2
    exit 1
  fi
done

case "/$RUNTIME_DESTINATION/" in
  *"/../"*)
    echo "Refusing unsafe runtime destination: $RUNTIME_DESTINATION" >&2
    exit 1
    ;;
esac
case "$RUNTIME_DESTINATION" in
  "$ROOT_DIR/Vendor/Runtimes/"*|/tmp/murmur-*|/private/tmp/murmur-*) ;;
  *)
    echo "Runtime destination must be inside this project or a Murmur temporary directory." >&2
    exit 1
    ;;
esac

RUNTIME_WORK_DIR="$(mktemp -d /tmp/murmur-whisper-runtime.XXXXXX)"
trap 'rm -rf "$RUNTIME_WORK_DIR"' EXIT

ARCHIVE_PATH="$RUNTIME_WORK_DIR/whisper.cpp.tar.gz"
SOURCE_DIR="$RUNTIME_WORK_DIR/whisper.cpp-${WHISPER_VERSION}"
BUILD_DIR="$RUNTIME_WORK_DIR/build"
STAGE_DIR="$RUNTIME_WORK_DIR/stage"

echo "Downloading whisper.cpp v${WHISPER_VERSION}..."
curl -fsSL --proto '=https' --tlsv1.2 "$WHISPER_ARCHIVE_URL" -o "$ARCHIVE_PATH"
echo "$WHISPER_ARCHIVE_SHA256  $ARCHIVE_PATH" | shasum -a 256 -c -
tar -xzf "$ARCHIVE_PATH" -C "$RUNTIME_WORK_DIR"

cmake \
  -S "$SOURCE_DIR" \
  -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_BACKEND_DL=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_ACCELERATE=ON \
  -DGGML_CCACHE=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON
cmake --build "$BUILD_DIR" --config Release --target whisper-cli -j 4

mkdir -p "$STAGE_DIR/lib" "$STAGE_DIR/libexec"
cp "$BUILD_DIR/bin/whisper-cli" "$STAGE_DIR/whisper-cli"
cp "$BUILD_DIR/src/libwhisper.${WHISPER_VERSION}.dylib" "$STAGE_DIR/lib/libwhisper.1.dylib"
cp "$BUILD_DIR/ggml/src/libggml.0.9.8.dylib" "$STAGE_DIR/lib/libggml.0.dylib"
cp "$BUILD_DIR/ggml/src/libggml-base.0.9.8.dylib" "$STAGE_DIR/lib/libggml-base.0.dylib"
cp "$SOURCE_DIR/LICENSE" "$STAGE_DIR/LICENSE.whisper.cpp.txt"

# Murmur links libwhisper in-process so the model stays resident between dictations.
# The linker resolves -lwhisper / -lggml / -lggml-base by unversioned name, so stage
# development symlinks alongside the versioned install names the dylibs carry.
ln -sf "libwhisper.1.dylib"   "$STAGE_DIR/lib/libwhisper.dylib"
ln -sf "libggml.0.dylib"      "$STAGE_DIR/lib/libggml.dylib"
ln -sf "libggml-base.0.dylib" "$STAGE_DIR/lib/libggml-base.dylib"

plugin_count=0
for plugin in "$BUILD_DIR/bin"/libggml-*.so; do
  [[ -f "$plugin" ]] || continue
  cp "$plugin" "$STAGE_DIR/libexec/"
  plugin_count=$((plugin_count + 1))
done
if [[ "$plugin_count" -eq 0 ]]; then
  echo "The whisper.cpp build did not produce backend plugins." >&2
  exit 1
fi

remove_absolute_rpaths() {
  local target="$1"
  while IFS= read -r runtime_path; do
    [[ "$runtime_path" == /* ]] || continue
    install_name_tool -delete_rpath "$runtime_path" "$target"
  done < <(
    otool -l "$target" | awk '
      $1 == "cmd" && $2 == "LC_RPATH" {
        getline
        getline
        print $2
      }
    '
  )
}

remove_absolute_rpaths "$STAGE_DIR/whisper-cli"
install_name_tool -add_rpath "@executable_path/lib" "$STAGE_DIR/whisper-cli"

for library in "$STAGE_DIR/lib"/*.dylib; do
  # Skip the unversioned development symlinks so each real dylib is rewritten once.
  [[ -L "$library" ]] && continue
  remove_absolute_rpaths "$library"
  install_name_tool -add_rpath "@loader_path" "$library"
done

for plugin in "$STAGE_DIR/libexec"/*.so; do
  remove_absolute_rpaths "$plugin"
  install_name_tool -add_rpath "@loader_path/../lib" "$plugin"
done

chmod +x "$STAGE_DIR/whisper-cli"
file "$STAGE_DIR/whisper-cli" | grep -q 'arm64'

rm -rf "$RUNTIME_DESTINATION"
mkdir -p "$(dirname "$RUNTIME_DESTINATION")"
mv "$STAGE_DIR" "$RUNTIME_DESTINATION"

echo "Staged whisper.cpp v${WHISPER_VERSION} in $RUNTIME_DESTINATION"
