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
    whisper-cli            # fallback engine only
    lib/
      libwhisper.1.dylib
      libwhisper.dylib     # unversioned symlink, for the linker
      libggml.0.dylib
      libggml.dylib
      libggml-base.0.dylib
      libggml-base.dylib
    libexec/               # GGML backend plugins (.so)
```

Murmur v2 targets Apple Silicon only. Dynamic libraries live under `arm64/lib`, use runtime-relative library paths, and place GGML backend plugins under `arm64/libexec`.

## Why this directory affects the build, not just packaging

Murmur links `libwhisper` into the app and keeps the Whisper model resident in memory
across dictations. `Package.swift` therefore probes for `arm64/lib/libwhisper.dylib` at
manifest-evaluation time:

- **Present** — the package links the runtime and defines `MURMUR_RESIDENT_WHISPER`, which
  compiles in `ResidentWhisperEngine`.
- **Absent** — the package still builds and the full test suite still passes, but it falls
  back to `WhisperCLITranscriptionEngine`, which shells out to `whisper-cli` once per
  dictation. That path is dramatically slower and exists only so a fresh clone compiles
  before the runtime has been staged.

So a clean checkout should run `script/stage_whisper_runtime.sh` before `swift build`, and
must re-run `swift build` after staging so the manifest is re-evaluated.

The unversioned `.dylib` symlinks exist because the dylibs carry versioned install names
while the linker resolves `-lwhisper` by unversioned name. The staging script creates them
and skips them when rewriting rpaths, so each real dylib is rewritten exactly once.

The GGML backends are built with `GGML_BACKEND_DL=ON`, meaning they are discovered as
plugins at runtime rather than linked. `ResidentWhisperEngine` loads them explicitly from
`arm64/libexec` via `ggml_backend_load_all_from_path`. Running `whisper-cli` by hand from
an arbitrary working directory will abort with `GGML_ASSERT(device) failed` for this
reason — it only finds its backends relative to its own directory.

These generated files are not committed. Models are separate and are downloaded by the app only after the user chooses one.

## Optional MLX writing runtime

The MLX writing runtime is resolved through Swift Package Manager and is not staged in this
directory. Its separately installed model weights live under Murmur's Application Support
`Models/Writing` directory. Generation loads only an integrity-verified local directory; the
Hugging Face downloader is used solely by an explicit install action and is never called by the
generation path.
