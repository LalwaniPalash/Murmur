# Murmur Local Voice Writing Implementation Plan

**Date:** 2026-07-18  
**Design:** `docs/plans/2026-07-18-murmur-v2-design.md`
**Strategy:** Ground-up rewrite in a new target; retain legacy sources as non-building reference until replacement is verified

## Delivery Principles

- Build vertical slices that compile and remain usable after every milestone.
- Write behavioral tests before production code for audio-independent logic.
- Put hardware and UI behavior behind protocols so automated tests do not require a microphone or Accessibility permission.
- Treat whispered-speech quality, repair correctness, grounding, privacy, and insertion safety as release gates.
- Do not delete or migrate legacy application data.
- Do not introduce any cloud inference path.
- Review the diff and run the relevant verification suite at every milestone.

## Milestone 0: Clean Rewrite Boundary

### Changes

- Add a new `MurmurNext` executable target and `MurmurNextTests` test target.
- Point the existing `Murmur` product at the new target.
- Leave `Sources/Murmur` and `Tests/MurmurTests` untouched as reference and exclude them from the new build.
- Establish folders for App, Core, Audio, Intelligence, Insertion, Storage, Features, DesignSystem, and Support.
- Add a minimal application entry point and dependency container.
- Add build and test commands to the README.

### Verification

- A clean `swift build` succeeds.
- A clean `swift test` succeeds.
- The produced executable is still named `Murmur`.
- The app launches without reading legacy stores.

## Milestone 1: Domain Model and Encrypted Storage

### Tests first

- Session state-transition tests, including duplicate finalization prevention.
- SQLite schema creation and transaction rollback tests.
- AES-GCM payload round-trip and tamper-detection tests.
- History search and date-grouping tests.
- Dictionary and snippet duplicate-validation tests.
- Backup manifest and import-preview validation tests.

### Changes

- Define domain identifiers and value types independently of SwiftUI.
- Add the versioned `Murmur/v2` application-support namespace.
- Add a SQLite actor using the system SQLite library.
- Encrypt sensitive payload columns with a Keychain-backed master key.
- Implement repositories for settings, history, personalization, profiles, notes, attachments, model inventory, and diagnostics metadata.
- Implement atomic backup/export and preview-first import.
- Leave legacy `SecureStore` files untouched.

### Verification

- Repository contract suites pass against temporary databases.
- Concurrent writes serialize without corruption.
- Search does not require decrypting unrelated records.
- Tampered ciphertext produces a recoverable error and never partial plaintext.

## Milestone 2: App Shell and Design System

### Tests first

- Sidebar destination and route tests.
- Feature-model empty/loading/error state tests.
- Design-token snapshot tests.

### Changes

- Create color, typography, spacing, radius, material, shadow, icon, and motion tokens from the approved visual reference.
- Build the compact Hub shell and sidebar.
- Add Home, Dictionary, Snippets, Style, Scratchpad, Settings, and Help routes.
- Add the menu-bar experience and application activation-policy coordination.
- Build reusable list rows, cards, segmented controls, search fields, sheets, banners, confirmation dialogs, and empty states.
- Add keyboard focus, VoiceOver labels, reduced-motion behavior, and contrast support at the component level.

### Verification

- Hub screenshots pass at minimum and default supported sizes.
- Every destination is keyboard reachable.
- The app uses no generic default SwiftUI styling in user-facing primary surfaces.

## Milestone 3: Audio Front End and Whisper Detection

### Tests first

- Noise-floor calibration tests using recorded PCM fixtures.
- Adaptive threshold and hysteresis tests.
- Pre-roll and post-roll preservation tests.
- Gain-boundary, limiter, and clipping tests.
- Normal, quiet, whisper, noise, and silence classification fixtures.
- Microphone-change recalibration tests.

### Changes

- Add `AudioInput` and `AudioFrameStream` protocols.
- Implement AVAudioEngine capture at the inference format.
- Add voice processing, high-pass filtering, bounded adaptive gain, and limiting.
- Implement an actor-owned rolling buffer.
- Add calibrated noise-floor tracking and whisper-aware speech likelihood.
- Integrate a supported local VAD model as an additional signal.
- Preserve sufficient pre-roll to retain whispered consonant onsets.
- Add input-device discovery, selection, monitoring, and hot-swap failure handling.

### Verification

- Silence false activations remain below the approved corpus threshold.
- Whisper fixtures are not clipped or rejected by endpoint detection.
- Normal speech after whispering does not clip due to stale gain.
- Capture remains stable for a 20-minute session.

## Milestone 4: Embedded Two-Pass Whisper Inference

### Tests first

- Local inference protocol contract tests with deterministic fixtures.
- Rolling-window overlap and segment-deduplication tests.
- Confidence retry-decision tests.
- Cancellation and stale-session rejection tests.
- Model checksum and atomic-activation tests.

### Changes

- Add an embedded Whisper.cpp bridge target suitable for Apple Silicon and Metal.
- Add model loading, warm-up, memory-pressure handling, and unloading policies.
- Implement rolling provisional decoding with timestamped segments.
- Implement final full-utterance decoding with beam search and context prompts.
- Reject silence, blank-audio tokens, repeated hallucinations, and stale results.
- Retry only low-confidence segments with alternate local parameters.
- Build model installation, verification, activation, repair, and removal services.

### Verification

- No inference request can resolve to a network backend.
- Provisional text never reaches insertion or history.
- Normal and whispered WER are reported separately from the versioned corpus.
- Cancellation releases active inference work and cannot commit late output.

## Milestone 5: Speech Repair, Grounding, and Formatting

### Tests first

- Table-driven filler, repetition, false-start, and explicit-repair tests.
- Corrected name, number, date, time, and clause tests.
- Nested and ambiguous correction tests.
- Segment-overlap deduplication tests.
- Grounding tests that reject invented entities and claims.
- Dictionary, snippet, punctuation, list, style, and developer-formatting tests.
- Property tests asserting that protected entities originate in an allowed source.

### Changes

- Implement deterministic repair-marker parsing over timestamped tokens.
- Implement a constrained local reconciliation stage.
- Return source alignment and edit provenance with reconciled text.
- Validate names, numbers, URLs, paths, identifiers, and material claims against allowed sources.
- Fall back to the safest grounded candidate when model output fails validation.
- Apply dictionary and snippets before context-aware polish where required by their semantics.
- Add formatting for prose, messages, email, browser forms, code, and terminals.

### Verification

- Explicit self-correction resolution meets or exceeds 95% on the approved corpus.
- No new names or numbers appear in the acceptance corpus.
- Repair failures preserve source meaning and never silently invent text.
- Code and terminal fixtures preserve protected syntax.

## Milestone 6: Session Orchestration, Shortcuts, and Safe Insertion

### Tests first

- Push-to-talk, hands-free, command, cancel, retry, and failure state-machine tests.
- Focus capture and target-revalidation tests.
- Accessibility insertion and clipboard-restore tests.
- App-switch, secure-field, unsupported-field, and target-loss tests.
- Duplicate completion and crash-recovery transaction tests.

### Changes

- Implement global configurable shortcuts with press, hold, release, and escape semantics.
- Build the actor-isolated dictation session orchestrator.
- Capture frontmost application and focused editable element at session start.
- Revalidate the target immediately before commit.
- Implement Accessibility replacement and transactional clipboard fallback.
- Add Command Mode for selections and inline commands without selections.
- Save history and statistics only after a final insertion outcome is known.

### Verification

- A session can finalize at most once.
- The wrong application never receives text after a focus change.
- Clipboard contents are restored after fallback insertion.
- Failed commands cannot alter the original selection.

## Milestone 7: Flow Bar and Onboarding

### Tests first

- Flow Bar state and transition tests.
- Docking and multi-display placement tests.
- Onboarding progress and recovery tests.
- Permission-state matrix tests.

### Changes

- Build the non-activating compact Flow Bar panel.
- Add listening waveform, processing, success, warning, failure, retry, cancel, expansion, drag, and docking states.
- Keep provisional text out of the authoritative UI and target application.
- Build onboarding for privacy, permissions, hotkeys, model setup, microphone calibration, and first dictation.
- Add focused repair flows for denied permissions and invalid models.

### Verification

- The panel never steals focus from the target field.
- Placement works across displays, Spaces, and full-screen applications.
- A fresh installation reaches a successful whispered first dictation without developer tools.

## Milestone 8: Hub Features

### Tests first

- History grouping, search, copy, retry, report, and delete tests.
- Statistics calculation tests based on recorded session duration.
- Dictionary and snippet CRUD, matching, collision, bulk-selection, and import tests.
- Style resolution and preview tests.
- Local-profile isolation and library-sharing tests.

### Changes

- Build the Home statistics carousel and date-grouped history.
- Build Dictionary and Snippets with search, sheets, inline editing, multiselect, and bulk import/export.
- Build app-category Styles with previews, intensity, and custom instructions.
- Build local profiles and shareable Murmur library bundles.
- Add all approved empty, loading, permission, model, and failure states.

### Verification

- Hub UI screenshots match the approved references.
- Search and bulk operations remain responsive with at least 10,000 history items and 1,000 imported entries.
- Import collisions are deterministic and previewed before commit.

## Milestone 9: Scratchpad, Settings, and Diagnostics

### Tests first

- Scratchpad autosave, tab, pin, attachment, search, and version-history tests.
- Settings validation and side-effect tests.
- Diagnostics redaction tests.
- Backup and restore end-to-end tests.

### Changes

- Build the floating always-on-top Scratchpad with sidebar, tabs, rich text, images, pinning, search, autosave, and versions.
- Build all approved settings sections.
- Add granular local notifications and reduced-interruption behavior.
- Add redacted and content-inclusive diagnostics previews.
- Add encrypted backup and restore interfaces.

### Verification

- Scratchpad survives forced termination without losing committed edits.
- Attachments remain inside the local versioned namespace.
- Redacted diagnostics contain no dictated or note content.

## Milestone 10: Release Hardening and Parity Audit

### Changes

- Run a complete feature-parity audit against the approved design.
- Run accessibility, localization-readiness, performance, energy, memory, and privacy audits.
- Exercise microphone, headphone, Bluetooth, display, Space, and application-switch edge cases.
- Package verified Apple-Silicon runtimes and recommended English models.
- Add signing, entitlements, notarization, update verification, and release documentation.
- Remove no legacy files; decide their later repository removal in a separate reviewed change.

### Release gates

- Clean build, unit, integration, interface, visual, performance, and privacy suites pass.
- Explicit correction resolution is at least 95% on the versioned corpus.
- The corpus contains no newly invented names or numbers.
- Silence false activation remains below 1% in the evaluation environments.
- Normal and whispered WER stay within thresholds established from the representative baseline corpus.
- A clean Mac can install, onboard, whisper into supported applications, self-correct naturally, and receive only final grounded text while offline.

## Verification Commands

The exact commands may expand as targets are added, but every milestone ends with at least:

```bash
swift build
swift test
git diff --check
```

Hardware-dependent corpus, UI, performance, privacy, signing, and notarization checks will be exposed through deterministic scripts under `script/` and documented before their milestone is considered complete.
