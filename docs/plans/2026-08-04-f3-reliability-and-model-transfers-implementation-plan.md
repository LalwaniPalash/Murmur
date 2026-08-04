# F3 Reliability and Unified Model Transfers Implementation Plan

**Date:** 2026-08-04
**Design:** [F3 reliability and unified model transfers](2026-08-04-f3-reliability-and-model-transfers-design.md)
**Status:** Ready for implementation
**Priority:** completeness/correctness, latency, privacy, feature breadth

## Outcome

Ship the approved field-repair slice without OpenAI dependency: deterministic Email paragraphs,
order-independent pre-speech Command chords, timestamp-grounded transcript completeness, and one
persistent resumable transfer system presented through the existing inline Whisper model UI for
both Whisper and local-writing models.

## Constraints

1. Preserve the existing Whisper model rows and inline progress bar.
2. Do not add network or local-LLM work to ordinary deterministic dictation.
3. Do not automatically resume network transfers on launch.
4. Never activate partial or unverified model bytes.
5. Never insert a transcript still known to have uncovered speech after retry.
6. Preserve the complete deterministic Email source on every model/provider failure.
7. Do not require or perform OpenAI testing.
8. Keep all field checks pending until Palash physically repeats them.

## Slice 1 — Field Regressions and Stable Contracts

**Modify:**

- `tasks/todo.md`
- `docs/product/feature-ledger.md`
- `quality/insertion-matrix.json` only after real checks

Record the four reported failures without marking them fixed. Add failing tests before production
changes for: realistic Fn→Control delay, post-speech upgrade rejection, deterministic Email
paragraphs, missing-final-region retry/blocking, and shared transfer persistence/state semantics.

## Slice 2 — Speech Regions and Whisper Timing Coverage

**Modify:**

- `Sources/MurmurNext/Audio/DictationAudioProcessor.swift`
- `Sources/MurmurNext/Core/DomainModels.swift`
- `Sources/MurmurNext/Intelligence/LocalWhisperEngine.swift`
- `Sources/MurmurNext/Intelligence/ResidentWhisperEngine.swift`
- transcription test doubles and integration tests

Add bounded speech-region metadata derived from the existing speech detector. Extend local
transcription results additively with decoded segment timing coverage. The resident adapter reads
Whisper segment timestamps after `whisper_full`; the CLI fallback parses timing only when its
contract can do so safely and otherwise reports timing unavailable rather than inventing coverage.

Create a deterministic coverage evaluator with tolerances grounded in frame/timestamp resolution.
It compares meaningful detected speech regions with decoded segments and reports beginning,
middle, or final uncovered regions using content-free reason codes.

## Slice 3 — Completeness Retry and Recoverable Blocking

**Modify:**

- `Sources/MurmurNext/Core/DictationOrchestrator.swift`
- `Sources/MurmurNext/Intelligence/LocalWhisperEngine.swift`
- result/recovery models and tests as required

After the optimized authoritative pass, evaluate timestamp coverage when available. Uncovered
speech requests the existing stronger full-context decode. Choose only among coverage-complete
candidates. If meaningful speech remains uncovered, persist a failed/recoverable result and do
not call insertion. Timing-unavailable engines retain the existing duration-density safety gate.

Tests must prove complete recordings still decode once, suspicious tails retry, unresolved tails
never insert, and ordinary short dictation adds no retry or latency stage.

## Slice 4 — Speech-Gated Command Upgrade

**Modify:**

- `Sources/MurmurNext/Core/GlobalShortcutMonitor.swift`
- `Sources/MurmurNext/Core/DictationOrchestrator.swift`
- `Tests/MurmurNextTests/GlobalShortcutMonitorTests.swift`
- `Tests/MurmurNextTests/DictationOrchestratorTests.swift`

Remove the fixed 200 ms correctness boundary. The chord resolver requests an upgrade whenever Fn
and Control become jointly held during the same Fn capture. The orchestrator accepts it only while
the active audio processor has not detected speech. A rejected late request stays ordinary
dictation and releases through the correct action.

## Slice 5 — Deterministic Email Formatter

**Create:**

- `Sources/MurmurNext/Intelligence/DeterministicEmailFormatter.swift`
- `Tests/MurmurNextTests/DeterministicEmailFormatterTests.swift`

**Modify:**

- `Sources/MurmurNext/Core/DictationOrchestrator.swift`
- transformation fixtures as needed

Format the complete grounded deterministic result for Email context before optional generative
polishing. Preserve normalized words and their order exactly. Isolate dictated greeting/sign-off,
honor explicit paragraph boundaries already emitted by spoken formatting, and group body sentences
through bounded deterministic rules. On formatter failure, use the unchanged complete source.

## Slice 6 — Persistent Shared Transfer Core

**Create:**

- `Sources/MurmurNext/Intelligence/ModelTransferController.swift`
- `Sources/MurmurNext/Core/ModelTransferModels.swift`
- `Tests/MurmurNextTests/ModelTransferControllerTests.swift`

Implement a transport-injected byte-range transfer controller with a versioned sidecar manifest.
State includes queued/downloading/paused/verifying/installed/failed, aggregate bytes, expected
bytes, moving-average speed, bounded ETA, and active model identity. Validate HTTPS, status,
Content-Range, validators, expected length, destination containment, and cancellation races.

Pause closes active requests after atomically recording completed bytes. Resume reconstructs state
from disk after launch but performs no network call until explicit action. Cancel removes only the
validated partial files and sidecar. A changed source identity safely restarts the selected transfer.

## Slice 7 — Whisper and Local-Writing Transfer Adapters

**Modify:**

- `Sources/MurmurNext/Intelligence/ModelInstaller.swift`
- `Sources/MurmurNext/Intelligence/LocalWritingModelInstaller.swift`
- `Sources/MurmurNext/Intelligence/HuggingFaceLocalWritingModelDownloader.swift`
- model catalog tests and privacy allowlists

Adapt every Whisper manifest as one transfer item and the pinned local-writing snapshot as nine
manifest items. Aggregate multi-file progress while preserving per-file exact size/SHA-256 checks.
Keep existing atomic activation and verified-install contracts. Remove the hidden Hub download
path once the reviewed shared transport owns all bytes.

## Slice 8 — Existing Inline UI, Extended for Every Model

**Modify:**

- `Sources/MurmurNext/Features/Models/EngineFeatureView.swift`
- `Sources/MurmurNext/App/AppEnvironment.swift`
- focused UI/state tests where feasible

Keep the Whisper row layout and `TransferBar`. Extend the inline transfer presentation with
downloaded/total size, speed, ETA, and Pause/Resume/Cancel. Render the local writing model using
the same row and transfer component inside Writing. Relaunch shows Paused without network access.
Clarify that deterministic Email formatting is available without a model and that model-based
polishing requires an installed local model or configured BYOK route.

## Slice 9 — Verification, Packaging, and Permanent Records

**Modify:**

- `Tests/MurmurNextTests/RepositoryPrivacyTests.swift`
- `script/quality_gate.sh` if the reviewed network surface changes
- `README.md`
- `tasks/todo.md`
- `docs/product/feature-ledger.md`
- `docs/product/competitor-parity.md`

Run:

1. focused red/green suites per slice;
2. `swift test`;
3. `swift build`;
4. `swift build -c release --arch arm64`;
5. `script/quality_gate.sh`;
6. `git diff --check`;
7. `script/build_and_run.sh package` without launching.

Audit persisted transfer sidecars, preferences, logs, database records, diagnostics, backups, and
app resources for transcript/key canaries. Record exact automated counts and leave every manual
row below pending.

## Manual Checks — Pending

- [ ] Deterministic Email paragraphs in Apple Mail with no writing model or OpenAI.
- [ ] Deterministic Email paragraphs in Gmail on Brave with no writing model or OpenAI.
- [ ] Fn→Control and Control→Fn both enter Command mode before speech.
- [ ] A Control press after speech begins does not reinterpret ordinary dictation.
- [ ] The reported long UI-download sentence retains its final clause.
- [ ] Every Whisper download shows inline progress, bytes, speed, ETA, Pause, Resume, and Cancel.
- [ ] A paused Whisper download survives relaunch and resumes explicitly.
- [ ] Local writing download uses the same inline presentation and survives pause/relaunch/resume.
- [ ] Cancel removes partial model data; verification and activation remain distinct.
- [ ] Installed local model formats Email and performs semantic Command mode while offline.

## Exit

Implementation may be marked complete when automated gates and packaging pass. The field failures
remain open until Palash runs the focused manual list and reports each outcome.
