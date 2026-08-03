# F2 Recovery and Trust Design

**Status:** Approved by Palash on 2026-08-03

**Scope:** F2.2 encrypted recording retention, F2.3 recovery journal, F2.4 playback /
retranscription / comparison, and F2.5 redacted issue bundles. F2.1 immutable session and
result storage is already complete.

## Principles

1. Completeness and correctness remain first, followed by latency, privacy, then breadth.
2. Murmur hosts no user data. Recovery is local; F2 retranscription uses installed local
   models. Remote BYOK routing remains F3.
3. Retention is disabled by default. The available policies are Off, 1 day, 7 days
   (suggested), 30 days, and Until Deleted.
4. Normal backup and library export never contain retained audio.
5. Recovery never automatically inserts text into another application.
6. F2 extends the redesigned Record and Settings surfaces; it adds no navigation area.

## Architecture

### Encrypted audio vault

Every retained recording receives a random 256-bit data-encryption key. The recording is
stored as independently authenticated AES-GCM chunks. Each chunk authenticates the format
version, session ID, monotonically increasing chunk index, sample rate, and sample format
as associated data. Reordered, missing, truncated, or modified chunks are rejected.

The data key is wrapped with Murmur's Keychain-backed master key. The wrapped key and audio
metadata are themselves stored in the encrypted record store. The audio directory contains
only ciphertext. Deleting the wrapped key first makes crypto-shredding immediate; an orphan
sweep subsequently removes ciphertext left by an interrupted cleanup.

Encryption runs on a background serial writer while capture continues. The authoritative
complete in-memory recording still enters final transcription immediately. Retention Off
does not create a writer, file, or metadata. Expiration and orphan cleanup never run on the
dictation critical path.

The existing `retainRawAudio` setting migrates to a retention policy. Existing `false`
becomes Off; existing `true` becomes the suggested seven-day policy. Adding the policy must
not make old encrypted settings undecodable.

### Durable recovery journal

An encrypted `RecoveryJournalRecord` captures the last safe phase for a session:
Capturing, Finalizing, Inserting, or Cleaning Up. It records content-free target metadata,
timestamps, retained-audio availability, an optional result ID, and a stable failure code.
It never stores credentials, clipboard contents, or a duplicate plaintext transcript.

Journal transitions are atomic. On launch, Murmur reconciles journals, encrypted-audio
metadata, partial chunk files, source sessions, and result versions. A partial recording is
recoverable through its last complete authenticated chunk. Cleanup is idempotent and resumes
after interruption.

An advisory app-instance lock is held for the process lifetime. A second instance may show
the app, but cannot register global shortcuts or start another capture session.

### Recovery behavior

- Interrupted capture: Retry transcription, Retain, or Delete.
- Failed transcription: Retry with an installed model, Retain, or Delete.
- Failed insertion: Copy final text or Delete. Murmur never inserts it automatically.
- Completed retained session: Play, Retranscribe, Compare, select preferred result, or
  Delete.

Disabling retention requires confirmation before purging existing recordings. Expiration
and manual deletion remove the wrapped key before ciphertext and metadata. Damaged audio is
never played or transcribed.

### Playback, retranscription, and comparison

Playback stream-decrypts authenticated chunks directly into an audio player without a
persistent plaintext file. Retranscription streams decrypted samples to an installed local
model and appends an immutable child `TranscriptResultVersion`; it never overwrites an
earlier result.

A separate preferred-result record controls the History projection. Selecting an older
version changes only that pointer. Comparison uses the deterministic F1 alignment engine to
show insertions, deletions, and substitutions plus model, language, latency, and text. No
provider-cost UI is shown when no remote provider participated.

### Redacted issue bundles

Issue bundles start with content-free environment, app/runtime/model versions and hashes,
session timings, stable failure codes, and consent metadata. The preview enumerates every
field. Transcript and audio are separate, off-by-default selections.

The exported `.murmur-issue.json` is a self-contained JSON document. Explicitly selected
audio is encoded only in that user-chosen export; default bundles contain neither audio nor
transcript. Keychain material, wrapped keys, provider credentials, clipboard content, and
unselected sessions are never eligible.

## Latency rules

- Retention Off has no audio encryption or disk-write path.
- Retention On encrypts during capture on a background serial writer.
- Transcription does not wait for expiration, orphan cleanup, playback preparation, issue
  generation, or the completed encrypted file rename.
- Small durable journal writes may occur at phase boundaries, but are measured.
- A retention Off-versus-On p95 release-latency regression that exceeds the checked F2
  tolerance blocks completion.

## Failure handling

- Authentication, version, path, and graph failures are typed and content-free.
- A failed audio write disables recovery for that session but must not abort authoritative
  transcription or insertion.
- A failed journal update is surfaced in local diagnostics and must not cause duplicate
  insertion.
- A crash after insertion can leave an Inserting journal; launch recovery offers Copy and
  Delete only, never automatic retry insertion.
- Purge and expiration are safe to repeat and tolerate missing files or metadata.

## Completion gates

1. Ciphertext contains no WAV header, transcript, or fixture canary.
2. Wrong keys, tampering, reordering, truncation, duplicate chunks, and unsafe paths fail.
3. Retention Off creates no file or metadata; every approved preset expires correctly with
   an injected clock.
4. Purge crypto-shreds before deleting ciphertext and resumes after interruption.
5. Launch recovery covers Capturing, Finalizing, Inserting, and cleanup journals.
6. A second process lock owner cannot begin a shortcut session.
7. Recovery never automatically inserts text.
8. Playback and retranscription create no persistent plaintext audio.
9. Retranscription appends a parented immutable result; preferred-result selection preserves
   all versions.
10. Comparison passes deterministic F1 alignment fixtures.
11. Issue bundles exclude every private field unless that field was explicitly selected.
12. Retention latency benchmarks pass, followed by the complete build, test, privacy,
    network, real-corpus, and quality verification loop.

The existing deferred F1 manual insertion matrix and statistically valid baseline remain
visible and cannot be represented as passing merely because F2 completes.
