# Murmur

Murmur is a private, local-first voice-writing app for Apple Silicon Macs. Hold `fn`, speak normally or whisper, correct yourself naturally, and release. Murmur transcribes locally, removes superseded phrases and speech artifacts, verifies protected details against what was spoken, and inserts only the final text.

This repository contains a ground-up v2 rewrite targeting macOS 15 and later. The active application is `Sources/MurmurNext`. Legacy source under `Sources/Murmur` is retained as non-building reference and its data is never read, migrated, overwritten, or deleted by v2.

This is a personal side project. It works on my Mac, has a real test suite, and probably still has rough edges on hardware and applications I have not tried.

## What works

- Adaptive noise-floor calibration, whisper likelihood, high-pass filtering, bounded quiet-speech gain, limiting, and 16 kHz mono resampling
- Local Whisper.cpp inference through the bundled Apple Silicon runtime
- A sensitive verification pass for likely whispers and low-quality first-pass transcripts
- Deterministic removal of fillers, repetitions, restarts, abandoned clauses, and explicit self-corrections
- Grounding checks that reject invented names, numbers, URLs, paths, and identifiers
- Dictionary terms, voice snippets, spoken punctuation, and numbered lists
- Push-to-talk with `fn`, Command Mode with `fn` + `Control`, Escape to cancel, and menu-bar hands-free dictation
- Focus-safe Accessibility insertion with a transactional clipboard fallback
- Encrypted local history, personalization, settings, notes, and note revisions
- Password-encrypted backup/restore and preview-first library import/export
- Searchable, pinned, multi-tab Scratchpad notes with local version history
- Model installation with HTTPS response validation, SHA-256 verification, cancellation, and atomic activation
- Redacted diagnostics export with an explicit opt-in before private writing can be included

Murmur has no account, telemetry, cloud inference fallback, subscription, or remote synchronization path. Network access is limited to a model download the user explicitly starts.

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 15 or later
- Microphone and Accessibility permission
- A verified local Whisper model; onboarding recommends Small English and the Models page offers faster and multilingual alternatives

## Build and test

```bash
swift build
swift test
swift build -c release --arch arm64
```

The Swift package builds an executable named `Murmur`. Runtime binaries and model files are intentionally not checked in.

Before packaging, install CMake and stage the pinned Whisper runtime:

```bash
brew install cmake
script/stage_whisper_runtime.sh
```

The staging script downloads whisper.cpp v1.8.4 over HTTPS, verifies the source archive checksum, builds portable Apple Silicon backends, and writes them to the ignored `Vendor/Runtimes/arm64` directory.

To create an ad-hoc signed local app bundle and DMG without launching the app:

```bash
script/build_and_run.sh package
```

Use `script/build_and_run.sh run` only when you intentionally want to build and open the application.

Before uploading a DMG manually to GitHub Releases, commit your changes and run:

```bash
script/check_release.sh
```

## First use

1. Open Murmur and review the local-processing privacy explanation.
2. Grant Microphone and Accessibility access.
3. Install and verify the recommended English model.
4. Focus an editable field in another app.
5. Hold `fn`, speak or whisper, and release.

Murmur does not show or insert provisional text. The Flow Bar reports listening, whisper detection, correction, and insertion state without exposing unfinished words.

## Spoken corrections

Natural corrections are removed from the final result. Examples:

- “Meet Tuesday, sorry, Wednesday” becomes “Meet Wednesday.”
- “Send it at two, actually three” becomes “Send it at three.”
- “We should ship—no wait—test it first” becomes “We should test it first.”
- “The first idea is ready. Scratch that. The second idea is ready.” keeps only the second sentence.

The versioned repair acceptance corpus is in `Tests/MurmurNextTests/Fixtures/repair-corpus-v1.json`.

## Privacy and storage

Application data lives under `Application Support/Murmur/v2`.

- Sensitive database payloads use AES-GCM with a random Keychain-protected master key.
- Search uses keyed blind-index terms; searchable plaintext is not stored beside records.
- Raw audio is deleted after processing unless retention is explicitly enabled.
- Deleting a retained history item also deletes its matching retained audio file.
- Backups are encrypted with a separate password-derived key and never contain the database Keychain key.
- Library exports contain dictionary entries, snippets, and styles—not history or notes.

## Architecture

- `App`: lifecycle, dependency ownership, permissions, and settings integration
- `Audio`: microphone capture, preprocessing, adaptive speech and whisper detection
- `Intelligence`: Whisper runtime, model installation, repair, grounding, personalization, and local commands
- `Insertion`: target capture, revalidation, Accessibility insertion, and clipboard fallback
- `Storage`: encrypted SQLite records, backups, and library transfer
- `Features`: Hub, onboarding, Flow Bar, personalization, Scratchpad, and settings
- `Support`: privacy-safe diagnostics

## Verification boundaries

The unit suite covers state transitions, whisper/noise classifiers, audio normalization, correction acceptance, grounding, insertion orchestration, encrypted storage, model integrity, imports, backups, revisions, and diagnostics redaction.

Real microphone accuracy, application-specific Accessibility behavior, Bluetooth input changes, multi-display placement, signing, and notarization still require hardware/UI verification. Automated corpus success must not be presented as a real-world whispered word-error-rate result.

## Models

The Models page can download, verify, activate, and delete Tiny, Base, Small, compact Large Turbo, and full Large Turbo variants. Downloads come from the public whisper.cpp model repository and are activated only after their complete SHA-256 digest matches Murmur's manifest.

Small English is the default because it is much faster than the 1.6 GB Large Turbo model on an M1 while retaining useful English dictation quality. Existing model choices are not changed automatically.

## Runtime acknowledgements and license

Murmur bundles a local runtime built from [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and GGML. The current v2 dictation path uses Whisper.cpp plus Murmur's deterministic grounded correction pipeline.

Murmur is available under the [MIT License](LICENSE). Upstream runtime attribution is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
