# F2.1 Versioned Session and Result Implementation Plan

**Date:** 2026-08-03

**Design:** [F2.1 versioned session and result design](2026-08-03-f2-versioned-session-results-design.md)

**Feature IDs:** HIST-003, HIST-004, REC-007

## Execution Rules

1. Keep the redesigned SwiftUI views unchanged.
2. Add no normalized plaintext SQLite tables or transcript metadata columns.
3. Start each slice with a failing test and keep every migration additive.
4. Never overwrite an existing source session or result version.
5. Never retry insertion because persistence failed.
6. Keep raw audio off by default and out of F2.1.
7. Preserve the deferred F1 compatibility check as incomplete, not passed.

## Slice 1: Lean domain contracts and projection

**Files:**

- Add `Sources/MurmurNext/Core/SessionResultModels.swift`
- Add `Tests/MurmurNextTests/SessionResultModelTests.swift`

Write failing tests for:

- constructing the approved minimal source-session and result-version records;
- rejecting or safely representing empty provider/model/language provenance;
- projecting a session plus preferred result into the existing `TranscriptRecord` shape;
- selecting the newest result deterministically; and
- preserving the legacy session ID and `legacy-unknown` markers during conversion.

Implement:

- `SourceSessionRecord` with schema version, ID, start/end dates, app/bundle, context,
  mode, and recording duration;
- `TranscriptResultVersion` with schema version, ID/session/parent IDs, creation date,
  raw/final text, provider/model/language, total processing duration, and insertion
  success; and
- a pure projection/conversion helper independent of storage and UI.

Gate: focused model tests pass without changing `TranscriptRecord` or a view.

## Slice 2: Append-only encrypted storage APIs

**Files:**

- Modify `Sources/MurmurNext/Storage/SecureRecordStore.swift`
- Extend `Tests/MurmurNextTests/SecureRecordStoreTests.swift`

Write failing tests for:

- atomically appending a source session and its first result;
- encrypted database bytes containing neither raw nor final transcript text;
- rejecting duplicate source/result IDs rather than upserting;
- rejecting a result for a missing session;
- rejecting a parent from another session;
- appending a valid child without changing its parent; and
- blind-index search across the preferred final transcript.

Implement:

- `sourceSessions` and `resultVersions` collection identifiers;
- private insert-only encrypted-record primitives;
- one atomic `append(session:firstResult:)` operation;
- one validated `append(result:)` operation; and
- fetch and projection helpers needed by History.

Do not change the generic upsert API used by mutable settings, notes, dictionary, or
snippets.

Gate: all storage tests pass and raw database inspection finds no transcript plaintext.

## Slice 3: Transactional legacy migration

**Files:**

- Modify `Sources/MurmurNext/Storage/SecureRecordStore.swift`
- Add migration cases to `Tests/MurmurNextTests/SecureRecordStoreTests.swift`

Write a version-1 database fixture through the public legacy API, then prove:

- every legacy History record produces exactly one session and one result;
- raw and final text both contain the old final text;
- unavailable provenance is `legacy-unknown`;
- legacy records remain present;
- schema version advances only after success;
- rerunning migration produces no duplicates; and
- a deliberately conflicting record rolls back the whole migration and version change.

Implement a public-to-the-module `migrateHistoryToVersionedRecordsIfNeeded()` actor
operation. Use deterministic migrated IDs and one immediate SQLite transaction. Do not
run payload migration in the synchronous store initializer.

Gate: migration tests pass against fresh, populated, repeated, and rollback cases.

## Slice 4: Dictation pipeline persistence

**Files:**

- Modify `Sources/MurmurNext/Core/DictationOrchestrator.swift`
- Modify `Sources/MurmurNext/App/AppEnvironment.swift`
- Modify test factories and orchestrator/streaming tests under `Tests/MurmurNextTests/`

Write failing tests proving:

- a completed dictation emits one session and one result with distinct raw/final text;
- model, provider (`local-whisper`), language, duration, and insertion success are kept;
- insertion failure still emits a recoverable result with `insertionSucceeded = false`;
- successful insertion followed by persistence failure does not insert twice; and
- the existing History list receives the preferred-result projection only after the
  atomic store write succeeds.

Replace the fire-and-forget legacy history persistence callback with one async terminal
record handler. Capture the raw transcript before repair and the insertion outcome after
the single insertion attempt. Persistence errors may surface a storage warning but must
not turn into an insertion retry.

On application startup, run migration before loading versioned History. Retain legacy
rows only for rollback; new dictations write only source sessions and result versions.

Gate: focused orchestrator, streaming, and application persistence tests pass with no
SwiftUI changes.

## Slice 5: Backward-compatible encrypted backups

**Files:**

- Modify `Sources/MurmurNext/Storage/LibraryTransferService.swift`
- Modify `Sources/MurmurNext/Storage/SecureRecordStore.swift`
- Extend `Tests/MurmurNextTests/LibraryTransferServiceTests.swift`
- Extend `Tests/MurmurNextTests/SecureRecordStoreTests.swift`

Write failing tests for:

- decoding an old payload with no session/result arrays;
- new encrypted backup round-trip of complete session and result versions;
- restore of an old backup followed by automatic legacy conversion;
- atomic restore of a valid new session/result graph;
- rejection of missing sessions, cross-session parents, duplicate IDs, oversized text,
  and excessive record counts; and
- absence of raw/final plaintext in the encrypted backup envelope.

Add optional `sourceSessions` and `resultVersions` arrays to `MurmurBackupPayload`, with
empty defaults for old payloads. Keep the legacy History projection in new backups for
backward compatibility. Restore versioned records when supplied; otherwise restore old
History and migrate it.

Gate: old and new backup tests pass without changing library exports, which continue to
exclude History.

## Slice 6: Documentation and full verification

**Files:**

- Update `docs/product/feature-ledger.md`
- Update `tasks/todo.md`
- Update `README.md` only if user-visible recovery behavior changed

Verify:

```bash
swift test --filter SessionResultModelTests
swift test --filter SecureRecordStoreTests
swift test --filter DictationOrchestratorTests
swift test --filter LibraryTransferServiceTests
swift build
swift test
script/quality_gate.sh
git diff --check
```

Expected F1 quality-command status remains `incomplete` only for the explicitly deferred
manual insertion evidence and the pending benchmark baseline. Any new failure blocks
F2.1 completion.

## F2.1 Exit

- Existing encrypted History is preserved and projected unchanged.
- Every new dictation has one immutable source session and append-only result history.
- Raw and final text plus minimal route provenance survive encrypted backup/restore.
- Failed insertion remains locally recoverable.
- No persistence failure can duplicate inserted text.
- HIST-003, HIST-004, and REC-007 move to Current only after all gates pass.
