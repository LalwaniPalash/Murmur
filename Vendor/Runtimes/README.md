# Bundled Runtimes

Place prebuilt runtime binaries here before packaging Murmur. The packaging script copies this directory into:

```text
Murmur.app/Contents/Resources/Runtimes/
```

Expected layout:

```text
Vendor/Runtimes/
  arm64/
    whisper-cli
    llama-cli
  x86_64/
    whisper-cli
    llama-cli
  universal/
    whisper-cli
    llama-cli
```

Use `arm64` and `x86_64` for architecture-specific builds. `universal` is optional and is used as a fallback. Any adjacent dynamic libraries required by the binaries should live in the same architecture folder and be built with runtime-relative library paths.

These files are intentionally not committed by default because the binaries are large and should be produced as release artifacts.
