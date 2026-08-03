# F2.1 Versioned Session and Result Design

**Date:** 2026-08-03

**Status:** Approved

**Feature IDs:** HIST-003, HIST-004, REC-007

**Parent design:** [Gold-standard platform design](2026-08-02-gold-standard-platform-design.md)

## Objective

Make dictation history append-only and recoverable without redesigning the current UI or
expanding into F2 recording retention. Every dictation receives one immutable source
session and one or more immutable transcript results. Retranscription appends a result;
it never overwrites an earlier result.

The user explicitly approved automatic migration of existing encrypted History and
encrypted storage of both raw Whisper text and corrected final text. Raw audio remains
off by default and outside F2.1.

## Scope

F2.1 adds two encrypted record types to the existing `secure_records` store. It does not
add normalized SQLite tables, UI, recording retention, recovery journaling, profiles,
rich transformation graphs, or timestamp alignment.

### Source session

`SourceSessionRecord` contains only:

- schema version and stable session ID;
- start and end timestamps;
- source application and optional bundle identifier;
- writing context and dictation mode; and
- recording duration.

The record is written once. F2.3 will own in-progress recovery state rather than mutating
this terminal source record.

### Result version

`TranscriptResultVersion` contains only:

- schema version, unique result ID, session ID, creation time, and optional parent ID;
- raw transcript and corrected final transcript;
- provider, model, and language identifiers;
- total processing duration; and
- insertion success.

Unavailable migrated metadata is represented explicitly as `legacy-unknown`. Fields for
profiles, retained audio, detailed transformation provenance, alignment payloads, and
persisted per-stage timings are deferred. Optional additive fields can be introduced
when their owning features exist.

## Storage Architecture

The current encrypted `secure_records` and blind-index tables remain authoritative. Two
new collection identifiers store encrypted Codable payloads:

- `sourceSessions`
- `resultVersions`

No plaintext transcript, provider metadata, or relationship metadata moves into a new
SQLite table. A dedicated append-only API uses `INSERT`, not upsert, and rejects attempts
to overwrite an existing session or result.

The first session and result are committed in one immediate transaction. A later result
is appended in its own transaction only after its session exists. Parent IDs must refer
to a result in the same session.

The current History interface receives a `TranscriptRecord` projection from the preferred
result, initially the newest result. SwiftUI views continue consuming the existing type;
F2.1 has no visual scope.

## Dictation Data Flow

For each finalized transcription:

1. Preserve the authoritative raw Whisper transcript.
2. Run deterministic repair and grounding to produce the final transcript.
3. Attempt insertion once.
4. Create a terminal source session and first result containing the insertion outcome.
5. Commit both encrypted records atomically.
6. Project the preferred result into the existing History UI and search index.

An insertion failure still produces a result with `insertionSucceeded = false`, so the
text is locally recoverable. Murmur never automatically reinserts a recovered result.

If insertion succeeds but persistence fails, Murmur must not retry insertion. It reports
the storage problem separately so a persistence failure cannot duplicate delivered text.

## Legacy Migration

Migration is additive, transactional, and idempotent:

1. Read every encrypted legacy `TranscriptRecord`.
2. Use its existing ID as the stable session ID and deterministic first-result ID.
3. Copy legacy final text into both raw and final fields because the historical raw text
   does not exist.
4. Mark provider, model, and language as `legacy-unknown` when unavailable.
5. Insert the source session, result, and blind-search terms.
6. Advance the schema version only after all records succeed.

Legacy History rows remain during the transition for rollback. New dictations write only
the new schema. Any migration error rolls back all new records and leaves the version and
legacy data untouched so the next launch can retry safely.

## Backup Compatibility

The password-encrypted backup payload gains optional session and result arrays. Existing
backup versions remain readable:

- a new backup preserves the complete versioned records;
- an old backup restores legacy History and then runs the same migration; and
- a restore commits the supplied session/result graph atomically with other collections.

Library exports remain unchanged because they intentionally exclude History.

## Error Handling and Invariants

- Source sessions and result versions are immutable after insertion.
- A first result and its session either both commit or neither commits.
- A result cannot reference a missing session.
- A parent result must belong to the same session.
- A migration or restore never deletes legacy data before replacement data commits.
- Failed insertion remains recoverable in encrypted History.
- Failed persistence never causes a second insertion attempt.
- Raw and final transcript text never enters plaintext schema columns, logs, diagnostics,
  or preferences.

## Verification

F2.1 is complete only when tests prove:

- encrypted session/result round trips do not expose plaintext in the database;
- appending a child result cannot modify its parent;
- duplicate and invalid graphs roll back atomically;
- a version-1 database migrates every History item exactly once;
- migration can be rerun without duplicates or data loss;
- blind-index search and the current History projection remain correct;
- insertion failure persists a recoverable result;
- storage failure after successful insertion cannot insert twice;
- old and new encrypted backups restore correctly; and
- the complete build, test suite, privacy audit, and F1 quality command remain healthy.

## Deferred Work

- F2.2: encrypted retained-audio keys, expiration, and crypto-shredding.
- F2.3: in-progress recovery journal and interrupted-session detection.
- F2.4: playback, retranscription UI, result selection, and aligned comparison.
- F3: profiles, provider capabilities, detailed transformation provenance, and context.

The F1 manual application compatibility check remains explicitly deferred by the owner.
F2 work may proceed, but the F1 machine report must continue to show that evidence as
incomplete rather than passed.
