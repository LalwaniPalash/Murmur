# Bundled Runtimes

Runtime binaries are generated locally and ignored by Git. Build and stage the pinned Apple Silicon Whisper runtime with:

```bash
script/stage_whisper_runtime.sh
```

The script downloads the pinned whisper.cpp source archive over HTTPS, verifies its SHA-256 digest, builds it with CMake, and stages the result here. It requires Xcode Command Line Tools and CMake.

The packaging script copies this directory into:

```text
Murmur.app/Contents/Resources/Runtimes/
```

Expected layout:

```text
Vendor/Runtimes/
  arm64/
    whisper-cli
    lib/
    libexec/
```

Murmur v2 targets Apple Silicon only. Dynamic libraries live under `arm64/lib`, use runtime-relative library paths, and place GGML backend plugins under `arm64/libexec`.

These generated files are not committed. Models are separate and are downloaded by the app only after the user chooses one.
