# Isolated Multi-Model MLX Implementation Plan

**Date:** 2026-08-06  
**Design:** [Isolated Multi-Model MLX Design](2026-08-06-isolated-multi-model-mlx-design.md)  
**Status:** Implemented; packaged field verification remains

## Slice 1 — Worker Protocol and Crash Boundary

- [x] Define versioned Codable request/response envelopes with strict byte limits and content-free errors.
- [x] Add a `MurmurMLXWorker` executable target with no Whisper dependency.
- [x] Add a main-app worker client with timeout, cancellation, stderr redaction, exit-code mapping, and
  deterministic Email/unchanged Command fallback.
- [x] Prove an intentional worker abort cannot terminate Murmur.

Release product verified 2026-08-06. The worker intentionally returns `runtime.not-enabled` until
Slice 2 packages and probes the matching MLX Metal resources.

## Slice 2 — MLX Resource Packaging

- [x] Obtain/build the MLX metallib matching the pinned MLX Swift version.
- [x] Bundle the worker and metallib under validated fixed paths and sign them with the app.
- [x] Add build integrity checks; fail packaging when resources are absent or mismatched.
- [x] Keep local inference fail-closed when the worker or resources are unavailable.

## Slice 3 — Curated Model Manifest

- [x] Extend the writing manifest for architecture, task support, memory, tier, quality, and immutable assets.
- [x] Pin fastest, balanced, and highest-quality candidates with explicit licenses and checksums.
- [x] Reuse resumable transfer, verification, activation, pause/resume, cancellation, speed, and ETA behavior.

Only Qwen3 0.6B has a measured real-model result in this checkout. The other tiers remain clearly
experimental and must not receive published performance claims until their opt-in qualification runs.

## Slice 4 — Session-Level Selection

- [x] Add Automatic, Preferred, and Fixed settings with backward-compatible decoding.
- [x] Capture one selection at session start using deterministic content-free inputs.
- [x] Permit at most one stronger installed retry in Automatic/Preferred; never substitute in Fixed.
- [x] Persist model ID, reason code, latency, retry, worker availability, and fallback provenance.

## Slice 5 — Resident Worker and Health

- [x] Keep one model resident across compatible requests.
- [x] Replace a resident model only at a request boundary.
- [x] Mark three repeated failures unhealthy for the launch and restart a wedged worker safely.
- [x] Ensure app shutdown and cancellation terminate the worker; model removal cannot invalidate an in-flight captured session.

## Slice 6 — Engine UI

- [x] Render all curated writing models through the existing shared inline transfer presentation.
- [x] Show transfer speed/ETA, tier, memory, size, license, installed/verified state, and selection mode.
- [x] Explain deterministic fallback and that Automatic uses only installed models.

## Slice 7 — Qualification and Release

- [ ] Benchmark every candidate on the versioned correctness corpus and representative hardware.
- [x] Run real resident Whisper and the installed pinned Qwen worker model.
- [x] Exercise worker abort, timeout, malformed JSON, missing worker/resources, relaunch,
  cancellation, model removal, and command transformation in automated harnesses.
- [x] Run full tests, privacy/source audits, release build, package, and signature verification.
- [ ] Complete signed-app Mail, Gmail, command, memory-pressure, and DMG field checks before changing defaults.

## Exit Criteria

- No MLX failure can terminate or corrupt the main app.
- Deterministic Email fallback always preserves the complete source.
- Fixed selection never switches models; Automatic/Preferred switch only as documented.
- All curated models meet published correctness, latency, and memory thresholds.
- Packaged Mail/Gmail and command-mode manual checks pass on the signed app.
