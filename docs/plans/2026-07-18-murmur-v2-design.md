# Murmur Local Voice Writing Design

**Date:** 2026-07-18  
**Status:** Approved  
**Target:** macOS 15+, Apple Silicon

## Summary

Murmur will be rewritten from the ground up as a compact native voice-writing experience. It retains the Murmur name and brand assets while focusing on fast local dictation, quiet-speech capture, and a focused desktop workflow.

The product will be strictly local-first. Audio, transcripts, cleanup, personalization, history, and notes stay on the Mac. Cloud accounts, subscriptions, referrals, remote synchronization, and hosted team collaboration are excluded. Their useful collaboration workflows will be replaced with local profiles, import/export, and shareable library bundles.

Whispered-speech recognition and invisible speech repair are the release-critical product capabilities. The application must reliably capture quiet speech and remove fillers, false starts, repetitions, and superseded corrections before text reaches the target application.

## Product Boundaries

### Included

- A compact native macOS Hub and Flow Bar
- Global dictation, hands-free dictation, and Command Mode
- Quiet-speech and true-whisper capture
- Local streaming transcription and a higher-accuracy final decoding pass
- Automatic removal of fillers, false starts, repetitions, and spoken corrections
- App-aware cleanup and writing styles
- Dictionary, snippets, custom transforms, and developer vocabulary
- Searchable history, usage statistics, and retry/copy/delete actions
- A floating, multi-tab Scratchpad with rich text, images, pinning, and versions
- Local profiles, encrypted backup and restore, and library import/export
- Onboarding, permissions, model management, settings, notifications, and diagnostics
- English-first quality with an architecture that can add evaluated languages later

### Excluded

- Windows, iOS, Android, Linux, and Intel Mac support
- Cloud transcription or cloud language models
- Accounts, billing, subscriptions, referral flows, or hosted authentication
- Remote synchronization and hosted team administration
- Claims of equivalent cleanup quality in languages without a dedicated evaluation corpus

## Rewrite Strategy

This is a ground-up rewrite. Existing source code is behavioral reference only. Murmur's brand assets and independently verified bundled runtime artifacts may be retained.

The new application will use a fresh, versioned storage namespace. It will not read, migrate, overwrite, or delete legacy Murmur data. Legacy files remain untouched on disk unless the user later removes them explicitly.

## Architecture

The application remains a native SwiftUI and AppKit macOS application. It is divided into six product areas with explicit protocol boundaries and dependency injection.

### App Shell

Owns application lifecycle, window and menu-bar coordination, onboarding, navigation, notifications, settings presentation, and the Flow Bar. AppKit provides the non-activating floating panels and system integration that SwiftUI does not express precisely.

### Dictation Core

Owns global shortcuts, microphone selection and capture, adaptive voice activity detection, focus tracking, cancellation, session state, and accessibility insertion. Session state is isolated so only one finalization can commit text or history.

### Local Intelligence

Owns embedded Whisper.cpp transcription, deterministic cleanup and commands, speech-repair parsing, grounding validation, dictionary prompting, and context-aware developer formatting. No transcription request can select a network backend.

### Personalization

Owns dictionary entries, snippets, application writing styles, cleanup preferences, command templates, language preferences, and locally learned corrections.

### Library

Owns searchable history, usage statistics, retry and recovery actions, Scratchpad documents, attachments, local versions, and diagnostics metadata.

### Storage

Owns the versioned SQLite schema, encrypted sensitive fields, atomic transactions, model inventory, import/export, backups, and schema migrations within the new rewrite.

Long-running and mutable services use actor isolation. Views interact with small feature models rather than a single application-wide coordinator. Protocol-backed services make audio, inference, insertion, storage, and time replaceable in tests.

## Primary Data Flows

Normal dictation follows this sequence:

1. A global hotkey starts a session.
2. Murmur captures the focused application, editable element, writing context, microphone, and locale.
3. The audio front end calibrates and records into a rolling buffer.
4. Voice activity and whisper-aware analysis identify speech without clipping quiet beginnings.
5. Whisper.cpp produces rolling provisional segments for internal use.
6. On release or endpoint detection, Whisper.cpp performs a final higher-accuracy pass over the complete normalized audio.
7. The repair engine removes fillers, abandoned clauses, repetitions, and superseded corrections.
8. Grounding validation rejects introduced names, numbers, or unsupported claims.
9. Dictionary, snippets, punctuation, writing style, developer formatting, and cleanup are applied.
10. Murmur revalidates the original target and inserts the final text.
11. A successful or recoverable outcome is committed to history and statistics in one transaction.
12. Temporary audio and provisional transcripts are discarded unless audio retention is explicitly enabled.

Command Mode uses the same capture and transcription stages. It adds the current selection and spoken instruction to the local transform request. The selection is changed only after grounding and target validation succeed.

## Whisper-Aware Capture

Quiet speech cannot depend on a fixed amplitude gate. Each input device receives a short calibration and maintains a moving estimate of its noise floor. The audio front end applies appropriate voice processing, denoising, high-pass filtering, safe gain normalization, and limiting.

Whisper detection combines multiple signals rather than relying only on volume:

- Energy relative to the calibrated noise floor
- Spectral distribution and change over time
- Whisper.cpp-compatible voice activity probability
- Temporal continuity across adjacent frames
- A rolling pre-buffer and post-buffer

Thresholds become more sensitive when sustained quiet-speech characteristics are present. Gain changes are bounded to avoid amplifying room noise or clipping later normal speech. Microphone changes trigger a new calibration.

## Two-Pass Transcription

Murmur embeds Whisper.cpp behind a local inference interface instead of treating a command-line process as the product boundary.

The streaming pass processes overlapping rolling windows and produces provisional timestamped segments. These segments drive endpoint detection and later reconciliation but are never inserted into the target application or shown as authoritative text.

The final pass processes the complete normalized utterance with:

- Overlapping speech segments
- Beam-search decoding
- Dictionary and application-context prompts
- Silence and hallucination rejection
- Confidence-aware retries
- Apple-Silicon Metal acceleration

Low-confidence segments may be decoded again with a larger window or alternate local decoding parameters. If the final result remains too uncertain, Murmur inserts nothing and asks the user to retry.

## Invisible Speech Repair

Repair is a distinct stage after transcription and before stylistic cleanup. It combines deterministic recognition of edit phrases with a constrained local language-model reconciliation.

The repair stage handles:

- Fillers such as "um" and "uh"
- Repeated words or phrases
- Abandoned sentence starts
- Explicit repairs such as "actually," "sorry," "I mean," and "no, wait"
- Superseded names, dates, times, quantities, and clauses
- Duplicate tokens introduced by overlapping streaming windows

Examples:

- "Meet Tuesday—sorry, Wednesday at two… actually three" becomes "Meet Wednesday at three."
- "We should, um, ship this—no, wait—test it first" becomes "We should test this first."
- "Email John… I mean Jane about the launch" becomes "Email Jane about the launch."

The reconciler receives timestamped source segments and must return both final text and an alignment to the spoken source. A grounding validator requires names, numbers, URLs, file names, and material claims to trace back to the utterance, selected text, dictionary, or active application context. When validation fails, Murmur preserves the safer source wording or requests a retry instead of guessing.

## Experience Design

Murmur uses its own name, logo, and restrained visual language across a compact desktop information architecture.

### Onboarding

Onboarding covers the local privacy promise, microphone and accessibility access, shortcut selection, local model installation, microphone calibration, and a guided first dictation. Permission and model failures remain inside a focused repair flow.

### Hub

The compact dark sidebar contains Home, Dictionary, Snippets, Style, and Scratchpad. Settings and Help are anchored at the bottom.

Home includes a statistics carousel and searchable history grouped into Today, Yesterday, and earlier dates. History entries provide copy, retry, report, and delete actions.

Dictionary and Snippets include search, creation sheets, inline editing, confirmation for destructive actions, multiselect, duplicate detection, and bulk import/export.

Styles provide application-category profiles, example previews, cleanup intensity, and custom instructions.

### Flow Bar

The non-activating Flow Bar is a bottom-centered floating pill with listening, processing, success, warning, and failure states. It supports a live waveform, cancellation, expanded actions, dragging, and screen-edge docking.

The target application never displays provisional transcription. While recording, the Flow Bar emphasizes audio feedback and state. Final text appears in the target only after transcription, repair, validation, and formatting complete.

### Scratchpad

Scratchpad is an always-on-top window with a notes sidebar, multiple tabs, rich text, images, pinning, autosave, search, and local version history.

### Settings

Settings contains General, Dictation, Languages, Microphone, Cleanup, Shortcuts, Flow Bar, Notifications, Privacy, Storage, Models, Experimental, and About sections.

### Developer Experience

Developer-aware dictation preserves syntax and supports spoken symbols, variable naming conventions, file-name recognition, terminal-safe insertion, developer vocabulary, and local workspace file tagging.

### Local Replacements for Cloud Features

- Local profiles replace accounts.
- Murmur library bundles replace team dictionary and snippet sharing.
- Encrypted backup and restore replace cloud sync.
- Local usage statistics replace hosted dashboards.

## Persistence and Privacy

Searchable metadata is stored in a versioned SQLite database. Transcript text, notes, snippets, dictionary entries, style instructions, and other sensitive payloads are encrypted with AES-GCM using a Keychain-protected master key.

Temporary audio uses randomized local files or bounded memory buffers. It is removed after successful or failed processing unless retention is explicitly enabled. History stores corrected final text by default, not raw provisional output.

Models and runtimes are versioned and checksum-verified. Activation uses an atomic pointer or manifest update so a failed install cannot replace a working runtime. Network access is limited to user-initiated application or model updates.

Library imports validate schema, limits, checksums, and duplicates before showing a preview. Backup exports can be password-encrypted and never include the Keychain master key.

## Failure Handling

- Uncertain whispered speech inserts nothing and offers an immediate retry.
- Microphone disconnection safely pauses or ends the session without submitting a truncated utterance.
- Missing or damaged models open a repair flow and never trigger a cloud fallback.
- The originally focused editable element is captured and revalidated before insertion.
- Accessibility insertion falls back to a transactional clipboard paste and restores the previous clipboard.
- Command Mode leaves selected text unchanged if transformation or grounding fails.
- Database transactions prevent half-written history and statistics.
- Atomic manifests prevent partially installed models from becoming active.
- Local logs redact dictated content by default.
- Diagnostics export requires an explicit user action and previews whether content is included.

## Verification Strategy

English whisper recognition and speech-repair quality are release gates.

### Evaluation Corpora

The audio corpus covers normal speech, true whispering, low-volume speech, microphone distance, common room noise, built-in and Bluetooth microphones, accents, and variable pacing.

The correction corpus covers fillers, repetitions, abandoned clauses, explicit repair phrases, corrected names and numbers, nested corrections, punctuation, lists, long utterances, and developer terminology.

Every confirmed transcription or repair defect becomes a permanent anonymized audio or token regression fixture when the user permits fixture retention.

### Quality Gates

- No newly invented names or numbers in the acceptance corpus
- At least 95% resolution of explicit self-corrections
- Less than 1% false activation on silence in the evaluation environments
- Separately tracked word-error rates for normal and whispered speech
- Separately tracked missed-whisper and residual-correction rates
- Final insertion latency, model warm-up, and energy usage measured on a baseline Apple Silicon Mac

Exact WER and latency release thresholds will be established from the first representative corpus rather than chosen without hardware and audio evidence. Thresholds may become stricter but cannot be relaxed merely to make a build pass.

### Automated Testing

- Unit tests for audio normalization, adaptive thresholds, repair parsing, reconciliation, grounding, formatting, snippets, dictionaries, storage, encryption, and import validation
- Contract tests for inference, microphone, insertion, storage, and model-management boundaries
- Integration tests for microphone-to-transcript, model installation, accessibility insertion, clipboard restoration, focus changes, Command Mode, and crash recovery
- Interface tests for onboarding, Hub and Flow Bar states, keyboard navigation, VoiceOver, reduced motion, empty states, and recovery paths
- Screenshot tests at supported window sizes to prevent visual drift
- Performance tests for startup, memory, model warm-up, streaming latency, final-pass latency, energy use, and long-session stability
- Privacy tests that fail if dictated content enters logs, diagnostics, analytics, or network requests

## Success Criteria

The rewrite is complete when a user can install Murmur on an Apple Silicon Mac running macOS 15 or later, finish onboarding without developer tools, whisper naturally into any supported editable application, correct themselves while speaking, and receive only the intended corrected text—all without sending audio or text off-device.

The complete desktop surface must also provide the approved Hub, Flow Bar, personalization, history, Scratchpad, settings, local sharing, model management, accessibility, privacy, and recovery workflows with consistent visual fidelity.
