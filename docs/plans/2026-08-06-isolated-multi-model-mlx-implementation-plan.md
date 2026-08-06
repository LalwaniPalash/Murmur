# Isolated Multi-Model MLX Implementation Plan

**Date:** 2026-08-06  
**Design:** [Isolated Multi-Model MLX Design](2026-08-06-isolated-multi-model-mlx-design.md)  
**Status:** Ready for implementation

## Slice 1 — Worker Protocol and Crash Boundary

- Define versioned Codable request/response envelopes with strict byte limits and content-free errors.
- Add a `MurmurMLXWorker` executable target with no Whisper dependency.
- Add a main-app worker client with timeout, cancellation, stderr redaction, exit-code mapping, and
  deterministic Email/unchanged Command fallback.
- Prove an intentional worker abort cannot terminate Murmur.

## Slice 2 — MLX Resource Packaging

- Obtain/build the MLX metallib matching the pinned MLX Swift version.
- Bundle the worker and metallib under validated fixed paths and sign them with the app.
- Add build and runtime startup probes; fail packaging when resources are absent or mismatched.
- Keep local inference disabled when the probe fails.

## Slice 3 — Curated Model Manifest

- Extend the writing manifest for architecture, prompt template, task support, memory, speed, quality,
  and benchmark metadata.
- Select and pin fastest, balanced, and highest-quality candidates only after license and real-model
  qualification.
- Reuse shared resumable transfer, verification, activation, pause/resume, and cancellation behavior.

## Slice 4 — Session-Level Selection

- Add Automatic, Preferred, and Fixed settings with backward-compatible decoding.
- Capture one selection at session start using deterministic content-free inputs.
- Permit at most one stronger retry in Automatic/Preferred; never substitute in Fixed.
- Persist model ID, reason code, latency, retry, health, and fallback provenance.

## Slice 5 — Resident Worker and Health

- Keep one model resident across compatible sessions.
- Replace models only between sessions and respect a measured memory ceiling.
- Mark repeated failures unhealthy for the launch and restart a wedged worker safely.
- Ensure app quit, model removal, and cancellation terminate or drain the worker correctly.

## Slice 6 — Engine UI

- Render all curated writing models through the existing shared inline transfer presentation.
- Show speed, quality, memory, size, tasks, installed/verified/healthy state, and active selection mode.
- Explain deterministic fallback and never imply that Automatic downloads models.

## Slice 7 — Qualification and Release

- Benchmark every candidate on the versioned correctness corpus and representative hardware.
- Run real resident Whisper followed by each real worker model.
- Exercise worker abort, timeout, malformed JSON, missing metallib, memory pressure, relaunch,
  cancellation, model removal, Mail, Gmail, and command mode.
- Run full tests, release build, quality gate, privacy audit, package, signature verification, and DMG
  verification before enabling local inference by default.

## Exit Criteria

- No MLX failure can terminate or corrupt the main app.
- Deterministic Email fallback always preserves the complete source.
- Fixed selection never switches models; Automatic/Preferred switch only as documented.
- All curated models meet published correctness, latency, and memory thresholds.
- Packaged Mail/Gmail and command-mode manual checks pass on the signed app.
