# Whisper Backend Loading Fix

## Problem

Murmur passes the bundled `libexec` directory through `GGML_BACKEND_PATH`. The bundled GGML version interprets that variable as a dynamic-library file, attempts to load the directory with `dlopen`, registers no CPU device, and aborts during `whisper_init`. Murmur then maps every signal-terminated subprocess to `CancellationError`, hiding the runtime crash behind a misleading message.

The failure was reproduced with the bundled CLI and confirmed by the matching macOS crash report. Running the same CLI with `libexec` as its working directory succeeds and automatically loads the bundled BLAS, Metal, and appropriate Apple Silicon CPU backends.

## Chosen design

For every Whisper subprocess:

1. Remove any inherited `GGML_BACKEND_PATH` value.
2. Set the process working directory to the resolved bundled `libexec` directory.
3. Let GGML discover its adjacent backend plugins using its native loader.

Represent this behavior in a small, testable runtime process configuration rather than assembling it inline.

Track whether cancellation was explicitly requested. A signal termination is considered cancellation only after that request; otherwise it becomes a local runtime failure containing the exit signal and captured stderr. This prevents crashes, assertions, and operating-system kills from appearing as user cancellation.

## Alternatives considered

- Force `libggml-cpu-apple_m1.so` through `GGML_BACKEND_PATH`. This succeeds but disables Metal acceleration and is needlessly specific to one Apple Silicon generation.
- Replace or rebuild the complete runtime. This is larger, slower, and riskier than correcting the process configuration already proven against the bundled files.

## Verification

- Unit-test removal of inherited backend overrides and selection of `libexec` as the working directory.
- Unit-test genuine cancellation versus an unexpected signal crash.
- Run the full Swift test suite and arm64 release build.
- Run the bundled CLI against known audio with the installed large-v3-turbo model and confirm successful backend discovery/transcription.
- Package build 4, validate its signature and architecture, and relaunch it for the user.
