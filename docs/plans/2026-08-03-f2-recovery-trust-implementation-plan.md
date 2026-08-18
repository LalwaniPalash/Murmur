# F2 Recovery and Trust Implementation Plan

**Date:** 2026-08-03

**Design:** [F2 recovery and trust design](2026-08-03-f2-recovery-trust-design.md)

**Feature IDs:** REC-002–010, HIST-005–007, SEC-004, TRN-012

**Status:** Completed for the approved local-only F2 scope on 2026-08-03. Verification passes
200 tests in 49 suites and every executable quality check. Remote BYOK comparison remains F3;
the separately tracked F1 manual insertion evidence and checked benchmark baseline remain pending.

## Execution rules

1. Work test-first in small slices; do not redesign unrelated UI.
2. Retention remains disabled by default and normal dictation remains authoritative.
3. Never persist plaintext audio, raw keys, credentials, or clipboard contents.
4. Never retry text insertion from launch recovery.
5. Keep deletion, expiration, and crash reconciliation idempotent.
6. Keep F2 local-only; remote provider routing remains F3.
7. Preserve the pending F1 manual compatibility matrix and latency baseline as incomplete.

## Slice 1: Retention policy and backward-compatible settings

**Files:**

- Modify `Sources/MurmurNext/Core/DomainModels.swift`
- Modify `Sources/MurmurNext/Features/Settings/SettingsFeatureView.swift`
- Extend `Tests/MurmurNextTests/SettingsMutationTests.swift`

Start with tests for all five policies, expiration calculation with an injected date,
default Off behavior, and decoding legacy settings with only `retainRawAudio`. Add a custom
settings decoder that maps legacy false to Off and legacy true to seven days. Replace the
boolean UI with one compact policy picker and an explicit purge confirmation.

Gate: old settings decode, new settings round-trip, and no retention is enabled implicitly.

## Slice 2: Chunked encrypted audio container

**Files:**

- Add `Sources/MurmurNext/Storage/EncryptedAudioVault.swift`
- Add `Tests/MurmurNextTests/EncryptedAudioVaultTests.swift`

Start with deterministic-key tests for round-trip, random per-recording keys, ciphertext
privacy, associated-data binding, tamper detection, wrong-key rejection, reordering,
duplicates, truncation, partial-tail recovery, and unsafe identifiers/paths. Implement a
versioned length-prefixed AES-GCM chunk container and master-key wrapping. Keep the raw data
key in memory only.

Gate: no encrypted file contains a WAV header or fixture canary, and every malformed
container fails closed.

## Slice 3: Audio metadata, crypto-shredding, and expiration

**Files:**

- Add audio models to `Sources/MurmurNext/Core/RecoveryModels.swift`
- Modify `Sources/MurmurNext/Storage/SecureRecordStore.swift`
- Extend `Tests/MurmurNextTests/SecureRecordStoreTests.swift`
- Add `Tests/MurmurNextTests/RetentionCoordinatorTests.swift`

Add encrypted retained-audio metadata and insert/fetch/delete operations. Build a retention
coordinator with an injected clock and file system root. Test every preset, deletion order,
missing files, interrupted cleanup, unknown ciphertext orphan sweeping, and cascading
session deletion. Remove metadata/wrapped keys before deleting ciphertext.

Gate: expiration and purge are safe to repeat, and backups contain no audio metadata or
ciphertext.

## Slice 4: Background capture encryption and latency evidence

**Files:**

- Modify `Sources/MurmurNext/Core/DictationOrchestrator.swift`
- Modify `Sources/MurmurNext/App/AppEnvironment.swift`
- Extend orchestrator and streaming tests
- Extend F1 benchmark reporting only as needed for an Off-versus-On comparison

Inject an audio-retention session factory into the orchestrator. With retention Off, do not
instantiate it. With retention On, enqueue ordered chunks during capture and finalize in the
background without delaying complete-buffer transcription. Audio-write failure becomes a
background recovery warning, not a transcription or insertion failure.

Test no-work Off behavior, ordered capture, final partial chunk, cancellation, write failure,
and one insertion only. Add a repeatable retention latency comparison; establish a tolerance
from measured local noise before declaring the gate.

Gate: completeness is unchanged and retention On does not produce a meaningful p95 release
latency regression.

## Slice 5: Recovery journal and launch reconciliation

**Files:**

- Add journal models to `Sources/MurmurNext/Core/RecoveryModels.swift`
- Add `Sources/MurmurNext/Recovery/RecoveryCoordinator.swift`
- Modify `Sources/MurmurNext/Storage/SecureRecordStore.swift`
- Modify orchestrator/application startup wiring
- Add `Tests/MurmurNextTests/RecoveryCoordinatorTests.swift`

Write state-transition and crash-fixture tests for Capturing, Finalizing, Inserting, and
Cleaning Up. Store only content-free state plus record references. Reconcile journals,
partial encrypted files, metadata, sessions, and results on launch. An Inserting recovery
may offer Copy/Delete but must never call the insertion service.

Gate: every interrupted phase reaches a deterministic recovery action without overwriting an
artifact or inserting text.

## Slice 6: Single-instance capture lock

**Files:**

- Add `Sources/MurmurNext/App/AppInstanceLock.swift`
- Modify `Sources/MurmurNext/App/AppEnvironment.swift`
- Add `Tests/MurmurNextTests/AppInstanceLockTests.swift`

Implement a process-lifetime advisory lock at one narrow path. Test first owner, competing
owner, release, and stale-process recovery. A non-owner does not register global shortcuts
or start capture, but may continue to show a window and explanation.

Gate: two lock clients cannot both become the shortcut/capture owner.

## Slice 7: Recovery and retained-session application API

**Files:**

- Modify `Sources/MurmurNext/App/AppEnvironment.swift`
- Modify `Sources/MurmurNext/Features/Record/RecordFeatureView.swift`
- Add pure recovery/presentation tests where possible

Expose recovery items and retained-audio state without publishing keys or paths. Extend the
existing Record ledger with accessible actions for Retry, Retain, Copy, Delete, and recovery
errors. Add the retention picker and immediate-purge confirmation in Settings. Keep the
current panel visual system and navigation intact.

Gate: each recovery state offers only its approved actions and destructive operations require
confirmation where data remains recoverable.

## Slice 8: Streamed playback

**Files:**

- Add `Sources/MurmurNext/Audio/RetainedAudioPlayback.swift`
- Wire playback through `AppEnvironment` and the Record detail UI
- Add `Tests/MurmurNextTests/RetainedAudioPlaybackTests.swift`

Inject an audio output seam. Authenticate and decrypt chunks into bounded in-memory buffers,
then schedule them directly for playback. Test ordering, cancellation, authentication failure,
and absence of plaintext temporary files.

Gate: playback never writes a plaintext audio file and damaged chunks produce no audio.

## Slice 9: Retranscription, preferred results, and comparison

**Files:**

- Add preferred-result and comparison models under `Sources/MurmurNext/Core/`
- Modify `SecureRecordStore`, `AppEnvironment`, and Record UI
- Reuse `MurmurQualityCore/TranscriptAlignment.swift`
- Add result-version/retranscription/comparison tests

Add a separate preferred-result collection and make History projection honor it. Decrypt
retained samples in memory, transcribe with a user-selected installed local model, run the
normal final pipeline, and append a parented result. Compute deterministic alignment on
demand. Test immutable parents, failed retries, selection persistence, deletion, model
provenance, and all alignment operation types.

Gate: retranscription never mutates an old result, comparison is deterministic, and selecting
any version preserves the complete graph.

## Slice 10: Preview-first issue bundles

**Files:**

- Add `Sources/MurmurNext/Diagnostics/IssueBundleService.swift`
- Wire export preview into the Record/Diagnostics surfaces
- Add `Tests/MurmurNextTests/IssueBundleServiceTests.swift`
- Extend repository privacy canaries

Build a bounded, versioned JSON payload with content-free metadata by default. Transcript and
audio are independent explicit options. Validate sizes and identifiers, compute hashes without
including secrets, and write only to a user-selected destination with file protection.

Gate: default bundles exclude transcript/audio canaries, selected fields are exact, and keys,
credentials, clipboard content, unrelated sessions, and internal paths are impossible to add.

## Slice 11: Documentation, security review, and F2 exit

Update `README.md`, `docs/product/feature-ledger.md`, `docs/product/competitor-parity.md`, and
`tasks/todo.md` from evidence. Run:

```bash
swift test --filter EncryptedAudioVaultTests
swift test --filter RetentionCoordinatorTests
swift test --filter RecoveryCoordinatorTests
swift test --filter AppInstanceLockTests
swift test --filter RetainedAudioPlaybackTests
swift test --filter IssueBundleServiceTests
swift build
swift test
script/quality_gate.sh
git diff --check
```

Review input/path validation, key lifetimes, logs, diagnostics, preferences, exports, backup
exclusion, and network surfaces. F2 completes only when every new gate passes. The existing F1
command may remain `incomplete` solely for its explicitly deferred manual insertion evidence
and missing statistically valid baseline.
