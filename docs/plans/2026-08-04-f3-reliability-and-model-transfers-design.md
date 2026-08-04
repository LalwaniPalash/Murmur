# F3 Reliability and Unified Model Transfers Design

**Date:** 2026-08-04
**Status:** Approved by Palash on 2026-08-04
**Priority:** completeness/correctness, latency, privacy, feature breadth

## Purpose

Repair four field failures found in the first packaged F3 writing build:

1. Email mode silently produced unformatted text when neither a BYOK route nor a local writing
   model was available.
2. Fn followed by Control failed on physical hardware even though Control followed by Fn worked.
3. The local writing-model download UI did not match the established inline Whisper model rows.
4. A longer dictation lost its final clause even though Murmur used the complete recording as the
   authoritative input.

The repair must preserve the existing Whisper model-row layout and inline progress bar, add the
same richer transfer controls to every model, and avoid adding inference or network work to normal
deterministic dictation.

## Approved Product Behavior

### Unified model-transfer experience

The current Whisper model list and its inline progress bar remain visually intact. Whisper and
local-writing downloads share one transfer state and the same inline presentation. Every active
or paused model download shows:

- downloaded bytes and total bytes;
- a short moving-average download speed;
- estimated remaining time when it can be computed honestly;
- Pause, Resume, and Cancel controls;
- a distinct checksum-verification state.

Pause preserves a validated partial download across app termination. Relaunch shows the transfer
as Paused and performs no automatic network request. Resume is explicit. Cancel removes the
partial payload and its transfer metadata. Removing an installed model remains a separate,
confirmed action.

Transfer metadata records only public model identity, source URL, expected size/checksum,
revision, validator such as ETag or Last-Modified, completed byte ranges, and timing counters.
It contains no dictated content or credentials. If the server identity, pinned revision, expected
size, or validator changes, Murmur discards only the incompatible partial data and restarts that
selected transfer safely after the user-requested Resume/Install action.

Whisper remains a single-file transfer. The pinned local writing snapshot is a manifest-backed
multi-file transfer, with aggregate progress and speed across its required files. Activation still
occurs only after exact size and SHA-256 verification and remains atomic.

## Deterministic Email Formatting

Email mode must provide useful, safe formatting without OpenAI and before the local writing model
is installed. The deterministic Email formatter runs after authoritative transcription, repair,
dictionary replacement, snippets, and spoken formatting.

It may:

- preserve an explicitly dictated greeting as its own paragraph;
- preserve an explicitly dictated sign-off as its own paragraph;
- honor explicit paragraph commands;
- group completed sentences into short readable paragraphs using deterministic boundaries;
- add only punctuation already permitted by the grounded deterministic pipeline.

It may not paraphrase, summarize, remove, reorder, or invent words, facts, names, recipients,
commitments, greetings, or sign-offs. A configured and available BYOK or local route may improve
wording after this deterministic baseline, subject to the existing protected-detail validator.
Failure always falls back to the complete deterministically formatted source.

The Engine UI must not imply that professional generative rewriting is active when no writing
engine is available. It distinguishes safe deterministic formatting from optional model-based
polishing.

## Order-Independent Command Chord

Fn begins capture immediately so opening audio is never clipped. Control may upgrade that same
capture to Command mode regardless of modifier order only until actual speech begins. Once the
audio processor has detected speech, a later Control press cannot reinterpret ordinary dictation.

This replaces the fixed 200 ms hardware assumption. The shortcut resolver requests an upgrade
while both modifiers are held; the orchestrator is the authoritative gate because it knows whether
the active recording has begun receiving speech. No second recording starts and the captured
target does not change.

## Timestamp-Grounded Completeness

The complete sample buffer remains the only authoritative transcription input. The audio processor
also records bounded speech regions, including the beginning and final voiced sample. The Whisper
adapter returns content-free timing coverage alongside text: decoded segment start/end timestamps,
not token probabilities or provisional text.

After the normal optimized full-buffer pass, Murmur compares decoded segment coverage with detected
speech regions. A meaningful speech region—especially the final region—with no overlapping decoded
coverage triggers the existing stronger full-context retry. The retry result is accepted only if
its coverage is complete and the existing transcript-quality scoring does not prefer a demonstrably
weaker candidate.

If meaningful speech remains uncovered after the retry, Murmur does not insert the suspected
partial transcript. It persists the result as recoverable, displays an explicit incomplete-
transcription error, and never represents the partial output as success. When encrypted retained
audio exists, the existing Retry action remains available. This favors correctness over silently
inserting plausible but incomplete text.

Coverage metadata is content-free and may be used in local diagnostics and benchmarks. Raw audio,
timestamps tied to transcript words, and dictated content do not enter logs or telemetry.

## Failure Handling

- Pausing preserves partial model bytes; cancelling deletes them.
- A server that ignores or invalidates a byte-range request cannot cause duplicated or mismatched
  model bytes.
- A transfer or verification failure never activates a partial model.
- Email formatting failure preserves the complete deterministic source.
- Generative Email failure preserves the deterministic Email paragraphs.
- Command failure leaves the selection unchanged and never inserts the spoken instruction.
- Unresolved speech-coverage failure blocks insertion and creates a recoverable result.

## Verification

Automated coverage must include:

- Fn then Control after realistic human delay but before speech;
- rejection of a Control upgrade after speech begins;
- identical capture and target across a successful upgrade;
- deterministic Email greeting/body/sign-off and multi-paragraph fixtures;
- proof that deterministic Email formatting preserves the normalized word sequence;
- beginning, middle, and final uncovered-speech fixtures;
- strong-retry success and unresolved-coverage insertion blocking;
- range resume across reconstructed installer state and process relaunch;
- changed ETag/revision/size handling;
- pause, resume, cancel, checksum, and atomic activation for Whisper and local writing models;
- aggregate multi-file progress, speed smoothing, and bounded ETA;
- UI state proving both model types use the shared inline transfer presentation;
- privacy/network allowlists and absence of content or credentials in transfer metadata.

Manual verification uses local transcription and the local writing route only; OpenAI is not
required. It covers Mail, Gmail in Brave, both shortcut orders, a deliberately failed completeness
case if reproducible, pause/relaunch/resume, cancellation cleanup, displayed speed, local-model
verification, offline Email polishing, and offline semantic Command mode.

## Scope Boundaries

- Do not redesign or relocate the existing Whisper model rows.
- Do not add automatic network resume at launch.
- Do not add cloud transcription or require OpenAI testing.
- Do not make a permanent partial download cache after Cancel.
- Do not use a larger always-on model or unconditional second transcription pass.
- Do not mark the field regressions fixed until the owner repeats the focused manual checks.
