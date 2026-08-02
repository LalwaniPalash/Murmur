# Murmur Gold-Standard Implementation Plan

**Date:** 2026-08-02

**Design:** [Gold-standard platform design](2026-08-02-gold-standard-platform-design.md)

**Scope control:** [Feature ledger](../product/feature-ledger.md)

**Parity control:** [Competitor parity register](../product/competitor-parity.md)

## Execution Rules

1. Implement milestones in order. A later milestone may be researched, but it cannot
   bypass an earlier release gate.
2. Reference stable feature IDs in implementation plans, tests, pull requests, and
   release notes.
3. Start each feature with a failing test, fixture, or measurable acceptance case.
4. Preserve the complete recording as the only authoritative final transcription input.
5. Never add an undeclared network route or automatic provider fallback.
6. Every confirmed defect becomes a permanent regression artifact.
7. Keep the current dirty application changes separate from roadmap-document commits.
8. A capability remains Partial until behavior, failure handling, privacy, accessibility,
   documentation, and metrics are complete.

## Release Branch Baseline

Before new milestone work:

- Review and commit the current resident-runtime, authoritative-transcription, ordered
  capture, and insertion changes as focused commits.
- Run `swift build`, `swift test`, the resident Whisper integration suite, release build,
  packaging checks, and `script/check_release.sh` where its prerequisites are available.
- Record baseline test counts, binary size, startup, resident memory, model warmup, and
  finalization latency by duration bucket.
- Confirm the no-runtime fallback build and the network-denied local path.
- Tag or record the baseline commit used by every later benchmark.

This baseline closes existing work; it must not absorb new F1 features.

## Milestone F1: Foundation and Evidence

### F1.1 Corpus manifest and runner

**Feature IDs:** EVAL-001, EVAL-003, EVAL-005

Create a versioned corpus format containing fixture ID, audio path or synthesis recipe,
consent/license metadata, expected transcript, required phrases, protected tokens,
language, speech condition, microphone class, and tags.

Implementation shape:

- Add `Tests/MurmurNextTests/Fixtures/AudioCorpus/manifest.json` for checked-in fixtures.
- Add typed manifest decoding and validation under a new test-support directory.
- Reject missing files, path traversal, duplicate IDs, invalid languages, unlicensed
  fixtures, and unsupported sample formats.
- Support deterministic macOS synthesized-speech recipes for text that does not require
  a real human recording.
- Run local Whisper through the real resident context in a serialized suite.
- Emit machine-readable JSON results without adding a telemetry path.

Tests and gates:

- Manifest round-trip and invalid-input tests.
- Reproducible fixture hashes.
- Per-model WER/CER output grouped by language and audio condition.
- Corpus runner skips unavailable models explicitly rather than reporting false success.

### F1.2 Transcript alignment and completeness

**Feature IDs:** TRN-004, TRN-005, EVAL-002

Add a deterministic token/phrase alignment engine independent of the UI and transcription
provider. It should normalize only comparison-irrelevant differences and retain a mapping
back to original spans.

Required outputs:

- Word substitutions, insertions, and deletions.
- Required beginning, middle, and ending phrase coverage.
- Protected-token preservation.
- Longest missing source span.
- A structured completeness result with explainable reasons.

Tests and gates:

- Synthetic omission cases for beginning, middle, and end.
- Punctuation/case changes do not masquerade as omissions.
- Repeated phrases align deterministically.
- A fluent non-empty partial transcript still fails when a required region is absent.
- Zero known silent phrase omissions in the release corpus.

### F1.3 Performance benchmark harness

**Feature IDs:** EVAL-006, EVAL-009

Measure warmup, capture drain, transcription, repair, grounding, insertion, and total
release latency separately. Store baseline hardware and model metadata beside results.

Required duration buckets: under 1 second, 1–3 seconds, 3–10 seconds, 10–30 seconds,
30–120 seconds, and meeting-scale when F5 exists.

Tests and gates:

- Serialize GPU benchmarks.
- Separate liveness timeouts from latency assertions.
- Report p50/p95 and sample count; do not compare single runs.
- Fail on statistically meaningful regression against the checked baseline tolerance.

### F1.4 Application insertion matrix

**Feature IDs:** INS-009, INS-010, EVAL-007

Create a declarative compatibility matrix for native AppKit, SwiftUI, Chromium/Electron,
browser content-editable, terminals, Java/Qt, Office, remote-desktop, and secure-input
controls.

Implementation shape:

- Unit-test every insertion policy decision without launching third-party apps.
- Add an opt-in manual matrix runner that records app/version, control type, strategy,
  verification result, recovery result, and notes without dictated content.
- Convert reproducible failures into local test hosts where possible.
- Publish Supported, Recoverable, Unsupported, and Untested states.

Gate: at least 99.5% successful or recoverable results in the declared supported matrix.

### F1.5 Privacy and diagnostics regression suite

**Feature IDs:** SEC-001–003, SEC-008, EVAL-010

- Inject canary transcript, audio, API-key, and context strings.
- Exercise logging, diagnostics, history, exports, crashes, and provider-disabled paths.
- Assert canaries are absent from logs, default diagnostics, preferences, and network
  requests.
- Add a network-denied local end-to-end test.
- Add a local quality report containing aggregates only.

### F1.6 Release quality command

Create one non-destructive command that runs formatting checks, build, unit tests,
integration tests when prerequisites exist, corpus evaluation, privacy checks, and
benchmark comparison. It must produce a human summary plus versioned JSON artifacts.

**F1 exit:** the command can prove or disprove every initial release gate in the design.

## Milestone F2: Recovery and Trust

### F2.1 Versioned session/result schema

**Feature IDs:** HIST-003, HIST-004, REC-007

- Add immutable source-session and result-version records.
- Keep raw transcript, final transcript, alignment, model/provider, language, profile,
  timing, insertion outcome, transform provenance, and result parentage.
- Write additive, tested storage migrations.
- Preserve existing encrypted history and blind-index behavior.
- Make reprocessing append a result; never update an earlier result in place.

### F2.2 Encrypted recording retention

**Feature IDs:** REC-001–003, SEC-004, HIST-007

- Keep retention disabled by default.
- Add explicit onboarding/settings consent with a suggested seven-day duration.
- Encrypt each recording with a random data key; wrap the data key with the Keychain
  master key.
- Store only encrypted audio on disk.
- Add expiration, immediate purge, retention changes, and crypto-shredding.
- Prevent audio from entering normal exports or backups without separate selection.

### F2.3 Recovery journal

**Feature IDs:** REC-004–006

- Journal session state atomically at safe transition points.
- Detect interrupted Capturing, Finalizing, and Inserting sessions at launch.
- Offer retry, retain, copy, or delete based on available artifacts.
- Do not auto-insert recovered text into an application.
- Ensure a second app instance cannot create duplicate shortcut sessions.

### F2.4 Playback, retranscription, and comparison

**Feature IDs:** HIST-005–006, REC-007–009, TRN-012

- Stream-decrypt retained audio for playback without a persistent plaintext file.
- Allow local or explicit BYOK retranscription.
- Show raw/final text, model/provider, language, latency, and optional provider cost data.
- Use the F1 aligner for a side-by-side and inline diff.
- Allow selecting an older result as the preferred version without deleting newer ones.

### F2.5 Issue bundles

**Feature ID:** REC-010

- Generate a previewable, redacted bundle with environment, model/runtime hashes,
  session timings, failure codes, and optional explicitly selected transcript/audio.
- Never include Keychain material or provider credentials.
- Add fixture-consent metadata when a user chooses to contribute a regression sample.

**F2 exit:** a failed, interrupted, or low-quality result is recoverable and comparable
when the user enabled retention, and no retained audio survives its declared policy.

## Milestone F3: Gold-Standard Writing

### F3.1 Non-authoritative live preview

**Feature IDs:** CAP-008, FLOW-003–005

- Create a separate preview session that cannot commit History or insertion.
- Prefer local preview even when a profile selects BYOK final transcription unless the
  user explicitly enables remote streaming.
- Label preview state visually and discard its authority on stop.
- Always run the sealed complete recording through the final route.
- Add omission regression tests proving a plausible preview cannot bypass final decoding.

### F3.2 Provider capability protocol

**Feature IDs:** BYOK-001–008, TRN-008–010, MOD-004

- Define capabilities for batch audio, streaming, timestamps, language hints,
  translation, prompts, structured output, cancellation, idempotency, and usage metadata.
- Implement OpenAI first, then a configurable OpenAI-compatible adapter.
- Store credentials only in Keychain.
- Require HTTPS remotely and permit HTTP only on loopback.
- Add endpoint probing, request-scope preview, strict response validation, and contract
  fixtures for partial, malformed, oversized, timeout, cancellation, and rate-limit cases.
- Capture the route at session start so settings changes cannot reroute an active session.

### F3.3 Profiles and routing

**Feature IDs:** PROF-001–007

- Implement deterministic precedence for combined app/site, site, app, and fallback rules.
- Store transcription route, transformation route, language/model, context scopes,
  formatting, fallback order, and auto-submit behavior.
- Provide an inspector explaining why a profile matched and what leaves the device.
- Add preview-first import/export.

### F3.4 Context boundary

**Feature IDs:** CTX-001–006

- Add application identity and domain context first.
- Add selected text, bounded nearby text, and approved workspace vocabulary separately.
- Require an independent permission for each remote context category.
- Do not implement whole-screen capture as the default context mechanism.
- Redact context from diagnostics and History unless the user explicitly asks to retain it.

### F3.5 Modes and transformations

**Feature IDs:** MODE-001–008, CORR-007, PERS-003

- Ship Message, Email, Document, AI Prompt, Developer, and user-defined modes.
- Keep plain dictation deterministic by default.
- Store transformation input class, provider/model, instruction version, and output.
- Run grounding after transformation and fail safe to the grounded source text.
- Require confirmation before auto-submit is enabled per target.

### F3.6 Correction learning

**Feature IDs:** CORR-008–010

- Observe post-insertion edits only when target identity, focused element, surrounding
  text, and temporal window make attribution reliable.
- Learn only localized high-confidence substitutions.
- Put candidates in a review queue with source, replacement, scope, confidence, and
  examples.
- Never learn broad rewrites or deletions automatically.

### F3.7 Multilingual tiers

**Feature IDs:** LANG-001–005, TRN-006–007

- Expose languages supported by the active route.
- Label every route/language combination Verified, Community-tested, or Experimental.
- Build language-specific normalization, repair, punctuation, and grounding modules.
- Promote a language only through corpus results and native-speaker review.

### F3.8 Device and compatibility hardening

**Feature IDs:** CAP-006–007, INS-008/010, PLAT-003/006

- Add microphone selection and route-change recovery.
- Expand terminal-safe and per-app insertion strategies from F1 evidence.
- Complete VoiceOver, keyboard navigation, contrast, reduced-motion, localization, and
  signed-update work.

**F3 exit:** Murmur reaches direct voice-writing parity while preserving the F1/F2 gates.

## Milestone F4: Transcription Studio

### F4.1 Import and batch pipeline

**Feature IDs:** FILE-001–003

- Add bounded audio/video decoding behind a media-source protocol.
- Reuse the authoritative session/result schema.
- Add a persistent, cancelable, restartable batch queue with resource limits.

### F4.2 Editor and synchronized playback

**Feature IDs:** FILE-004–007

- Add transcript versions, timestamp-preserving edits, audio/video playback, word and
  segment seeking, and manual speaker assignment.
- Preserve original source and raw transcription independently from edits.

### F4.3 Translation and export

**Feature IDs:** FILE-009, EXP-001–007, TRN-011

- Link every translated result to its source version.
- Implement TXT, Markdown, JSON, CSV, SRT, and VTT before PDF and DOCX.
- Version machine-readable schemas and validate subtitle timing.
- Render and visually verify PDF; structurally and visually verify DOCX.
- Require separate consent for audio in portable session packages.

**F4 exit:** Murmur matches file-oriented transcription suites without creating a second,
lower-quality transcription stack.

## Milestone F5: Meetings and Automation

### F5.1 Meeting capture

**Feature IDs:** CAP-009–011, MEET-001–005

- Add ScreenCaptureKit/system-audio permission and capture.
- Mix microphone/system sources with drift correction and bounded gain.
- Journal long sessions and recover after interruption.
- Show provisional live notes but reconcile the complete saved recording before finalizing.

### F5.2 Speakers and evidence-linked intelligence

**Feature IDs:** FILE-008, MEET-006–007

- Evaluate diarization separately by speaker count and acoustic condition.
- Keep speaker edits versioned.
- Link summaries and action items to supporting transcript spans.
- Do not present unsupported summary claims as grounded facts.

### F5.3 Local automation surface

**Feature IDs:** AUTO-001–009

- Define one versioned local command schema reused by CLI, Shortcuts, URL scheme, API,
  watch folders, integrations, webhooks, and MCP.
- Bind API/MCP only to loopback, disable by default, generate credentials, enforce scopes,
  rate-limit, and provide request logs without content.
- Require explicit endpoint and payload preview for webhooks.

**F5 exit:** meetings and automation inherit session provenance, recovery, security, and
quality gates rather than operating as privileged shortcuts.

## Milestone F6: Ecosystem and Platforms

### F6.1 Plugin SDK

**Feature IDs:** PLUG-001–004

- Stabilize provider, post-processor, exporter, and action protocols before publishing.
- Version the API and capability manifest.
- Require signing or explicit approval.
- Enforce declared network, filesystem, audio, transcript, and context scopes.
- Keep final grounding enabled unless a user explicitly chooses an unsafe workflow.

### F6.2 Community and user-owned sharing

**Feature IDs:** LANG-006, PERS-004, SYNC-001–004

- Define reproducible language pack and evaluation contribution formats.
- Add signed, preview-first profile/dictionary/policy bundles.
- Implement encrypted selected-folder and iCloud Drive synchronization.
- Design a documented end-to-end encrypted self-hosted protocol only after local conflict
  semantics are proven.

### F6.3 Later platforms

**Feature IDs:** PLAT-004–005

- Extract shared provider, session, evaluation, and schema contracts without flattening
  the native Mac experience.
- Treat macOS as the reference implementation.
- Start iOS or Windows only after F3 release gates remain stable across two releases.

## Cross-Milestone Documentation

For every shipped feature:

- Update `docs/product/feature-ledger.md` status and evidence links.
- Update `docs/product/competitor-parity.md` only after quality gates pass.
- Document data flow, provider transmission, storage, retention, and deletion.
- Add accessibility behavior and keyboard paths.
- Add user-facing recovery and known limitations.
- Add release notes with stable feature IDs.

## Immediate Next Plan

The first implementation slice should be **F1.1 Corpus manifest and runner** followed by
**F1.2 Transcript alignment and completeness**. Together they create the evidence needed
to decide and verify every subsequent transcription feature.

Before coding that slice, write a focused TDD task plan covering the exact corpus schema,
fixture policy, alignment normalization, test cases, and report format. Do not combine it
with UI work, provider support, retention, or storage migration.
