# Murmur

**Private, local-first voice writing for Apple Silicon Macs.** Hold `fn`, speak, release. Murmur transcribes on-device, removes the phrases you spoke and then took back, verifies that no name or number was invented, and inserts only the finished text.

[![License: MIT](https://img.shields.io/badge/License-MIT-black.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2015%2B%20·%20Apple%20Silicon-black)
[![Release](https://img.shields.io/github/v/release/LalwaniPalash/Murmur?color=black)](https://github.com/LalwaniPalash/Murmur/releases/latest)

No account. No subscription. No telemetry. No hosted relay. The only network traffic is a model download you start yourself, or a rewrite request to a provider whose key you supplied.

## Install

Download `Murmur.dmg` from the [latest release](https://github.com/LalwaniPalash/Murmur/releases/latest), drag it to Applications, and open it. Onboarding walks through Microphone and Accessibility permission and installs a verified Whisper model.

The build is ad-hoc signed rather than notarized, so the first launch needs right-click then Open. If you would rather compile it yourself, see [Build and test](#build-and-test).

## Why this exists

Cloud dictation is fast and good, and it works by sending your voice, and often your screen context, to someone else's server. The open-source alternatives keep your audio on your machine, which solves the privacy problem and leaves a second one untouched: they hand you what the model heard, and what the model heard is not what you meant.

You say "meet Tuesday, sorry, Wednesday." You get "meet Tuesday, sorry, Wednesday." You then fix it by hand, which is the typing you were trying to avoid.

Murmur treats the transcript as raw material rather than output. Between the model and your cursor sits a correction pipeline that runs entirely on-device.

### What that means concretely

**Spoken corrections are resolved, deterministically.** Not with an LLM that might rephrase your sentence, but with a rule engine tested against a versioned acceptance corpus (`Tests/MurmurNextTests/Fixtures/repair-corpus-v1.json`).

| you say | Murmur inserts |
|---|---|
| "Meet Tuesday, sorry, Wednesday" | Meet Wednesday. |
| "Send it at two, actually three" | Send it at three. |
| "We should ship, no wait, test it first" | We should test it first. |
| "The first idea is ready. Scratch that. The second idea is ready." | The second idea is ready. |

**Nothing gets invented.** Optional rewriting (professional email tone, semantic commands) can run through your own OpenAI key or a local MLX model. Every candidate passes a grounding check before insertion: names, numbers, URLs, file paths, and identifiers must trace back to what you actually said. A rewrite that hallucinates a detail is discarded and the verbatim local result is kept. This is `TransformationValidator`, and it is the reason optional cloud rewriting is safe to offer at all.

**You can dictate quietly.** Adaptive noise-floor calibration, a whisper-likelihood classifier, and bounded quiet-speech gain mean actual whispering transcribes, with a second verification pass for utterances the classifier flags as low-confidence. Useful in a shared office, a library, or a house with a sleeping person in it.

**Nothing provisional is ever shown or inserted.** Murmur decodes the complete recording in one authoritative pass after you release the key. It does not assemble final text from independently decoded streaming chunks, because a chunk can look perfectly plausible while silently dropping a word, and you will not catch it. The Flow Bar reports listening, whisper detection, correction, and insertion state without exposing unfinished words.

**It is fast because of a specific optimization.** Whisper pads every inference window to 30 seconds regardless of how long you spoke. Murmur truncates the encoder context to the true recording length, worth roughly 4-10x on short utterances, with output verified identical to running at full context. Combined with a Whisper context that stays resident in-process (no subprocess spawn, no Metal re-initialization, no model reload per dictation), a two-second utterance lands in about 130ms.

**Your history is encrypted at rest.** AES-GCM with a Keychain-protected master key, keyed blind-index search so searchable plaintext is never stored beside records, and raw-audio retention off by default. Most dictation tools either store transcripts in plaintext or discard them entirely; Murmur keeps them and encrypts them.

### Honest limitations

This is a personal side project, maintained by one person, and the comparison above is about design choices rather than maturity. Where the established open-source options are ahead:

- **Platform.** Murmur is Apple Silicon and macOS 15+ only. [VoiceInk](https://github.com/Beingpax/VoiceInk) and [VoiceTypr](https://github.com/moinulmoin/voicetypr) cover more ground, and VoiceInk has a far larger contributor base and community.
- **Distribution.** The DMG is ad-hoc signed, not notarized.
- **Language.** English is the default and the best-tested path. Multilingual models are installable but not what the correction pipeline was tuned against.
- **Evidence.** Latency figures below are synthesized-speech benchmarks on one M1. Real microphone accuracy and whispered word-error rate on hardware I do not own are unverified, and the test suite deliberately records missing prerequisites as skips rather than passes.

If you want the largest community and the widest platform support, use VoiceInk. If you want a transcript that reflects what you meant instead of what you said, that is what this is for.

## What works

- Adaptive noise-floor calibration, whisper likelihood, high-pass filtering, bounded quiet-speech gain, limiting, and 16 kHz mono resampling
- Local Whisper.cpp inference through a resident in-process runtime: the model is loaded once at launch and stays in memory, so dictation costs inference alone rather than reloading the model and re-initializing Metal every time
- A sensitive verification pass for likely whispers and low-quality first-pass transcripts
- Deterministic removal of fillers, repetitions, restarts, abandoned clauses, and explicit self-corrections
- Grounding checks that reject invented names, numbers, URLs, paths, and identifiers
- Dictionary terms, voice snippets, spoken punctuation, and numbered lists
- Push-to-talk with `fn`, Command Mode with `fn` + `Control`, Escape to cancel, and menu-bar hands-free dictation
- Focus-safe Accessibility insertion with a transactional clipboard fallback
- Encrypted local history with immutable raw/final transcript versions, plus encrypted
  personalization, settings, notes, and note revisions
- Password-encrypted backup/restore and preview-first library import/export
- Searchable, pinned, multi-tab Scratchpad notes with local version history
- Model installation with HTTPS response validation, SHA-256 verification, cancellation, and atomic activation
- Redacted diagnostics export with an explicit opt-in before private writing can be included
- Optional professional Email and semantic Command rewriting through an OpenAI BYOK key,
  a Responses-compatible BYOK endpoint, or a separately installed local MLX model. Every
  candidate is validated before insertion; failures preserve the complete local result.

Murmur has no account, telemetry, hosted inference relay, subscription, or remote synchronization
path. Network access is limited to a model download the user explicitly starts or a writing request
sent directly to the provider the user configured and consented to.

## Performance

Measured on an M1 with `ggml-small.en`, from key release to insertion:

| utterance | time |
|---|---|
| 0.5s | ~80ms |
| 2s | ~130ms |
| 2.4s | ~180ms |
| 4.7s | ~320ms |
| 6.8s | ~500ms |
| ~14s, spoken with pauses | ~1.65s |

Launch pays a one-time background warmup of roughly 340ms to load the backends and the model. After that, dictation costs inference only.

Two things make this work. The Whisper context is resident in-process, so no dictation reloads the model, re-initializes Metal, or spawns a subprocess. Because Whisper pads every inference window to 30 seconds, the encoder context is truncated to the actual length of what was recorded — worth roughly 4-10x on short utterances, with output verified identical to running at full context.

The complete recording is transcribed in one authoritative pass after release. Murmur does not assemble final text from independently decoded chunks, because a plausible-looking chunk can still omit words without producing an error. Nothing provisional is shown or inserted while you speak; the complete transcript is decoded, corrected, and inserted once.

These are synthesized-speech benchmarks on one machine. Real microphone accuracy and latency will vary.

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 15 or later
- Microphone and Accessibility permission
- A verified local Whisper model; onboarding recommends Small English and the Models page offers faster and multilingual alternatives

## Build and test

Stage the pinned Whisper runtime first. Murmur links `libwhisper` into the application, so
this is a build input, not only a packaging step:

```bash
brew install cmake
script/stage_whisper_runtime.sh
```

Then:

```bash
swift build
swift test
swift build -c release --arch arm64
```

### F1 quality evidence

Run the non-destructive local quality gate with:

```bash
script/quality_gate.sh
```

It validates the licensed corpus manifest, builds, runs unit and resident-engine tests,
checks privacy/network surfaces, evaluates transcript completeness, summarizes latency,
and evaluates the declared insertion matrix. Versioned JSON and readable logs are written
under `.build/quality`; no telemetry or hosted Murmur service is involved.

An exit code of `0` means every declared gate passed, `1` means at least one gate failed,
and `3` means the evidence is incomplete. A fresh F1 checkout is expected to remain
incomplete until the manual application matrix has recorded real app versions and a
compatible multi-run benchmark baseline has been checked in. Details and the content-free
manual record format are in [`quality/README.md`](quality/README.md).

The staging script downloads whisper.cpp v1.8.4 over HTTPS, verifies the source archive checksum, builds portable Apple Silicon backends, and writes them to the ignored `Vendor/Runtimes/arm64` directory. The Swift package builds an executable named `Murmur`. Compiled runtime binaries and model files are intentionally not checked in; the whisper.cpp public headers are vendored under `Sources/CWhisper/include/` so the package can compile against them.

`Package.swift` detects the staged runtime when the manifest is evaluated and defines `MURMUR_RESIDENT_WHISPER` only when it is present. Every reference to the linked runtime is behind that flag, so a checkout without a staged runtime is intended to still compile and fall back to running `whisper-cli` as a subprocess once per dictation — correct, and much slower.

Two caveats worth knowing. SwiftPM caches the manifest, so after staging you may need to `touch Package.swift` for the change to be picked up. And the fallback configuration has been verified only structurally (all runtime references are guarded); it has not been exercised by a full clean build, so treat it as a safety net rather than a supported path.

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

Optional writing intelligence is configured under Engine. Transcription stays on the Mac. Remote
writing requires the user's own key in macOS Keychain and separate consent for completed Email text
and selected Command text. Local writing requires a separate 351 MB experimental model download.

Murmur does not show or insert provisional text. The Flow Bar reports listening, whisper detection, correction, and insertion state without exposing unfinished words.

## Repository status

This repository is a ground-up v2 rewrite targeting macOS 15 and later. The active application is `Sources/MurmurNext`. Legacy source under `Sources/Murmur` is retained as non-building reference and its data is never read, migrated, overwritten, or deleted by v2.

## Privacy and storage

Application data lives under `Application Support/Murmur/v2`.

- Sensitive database payloads use AES-GCM with a random Keychain-protected master key.
- Search uses keyed blind-index terms; searchable plaintext is not stored beside records.
- Raw audio retention is Off by default. Optional 1-day, suggested 7-day, 30-day, and
  Until Deleted policies use a random per-recording key and authenticated encrypted chunks.
- Encryption runs on a background serial writer during capture; final transcription does
  not wait for the encrypted recording to finish sealing.
- Expiration, disabling retention, purging, or deleting History removes the wrapped key
  before deleting ciphertext. Legacy plaintext retained WAV files migrate into the vault.
- Interrupted captures and failed transcriptions appear in Record with explicit Retry,
  Keep, Copy, or Delete actions. Launch recovery never inserts text automatically.
- Retained recordings can be played or retranscribed with an installed local model without
  creating a persistent plaintext audio file. Every result remains immutable; any version
  can be selected as preferred or compared with another using aligned word differences.
- Issue bundles are previewed before export. Environment and timing metadata are content-free
  by default; transcript and retained audio are separate, off-by-default choices.
- Backups are encrypted with a separate password-derived key and never contain the database Keychain key.
- Encrypted backups preserve immutable result history and preferred-result selection, but
  normal backups and library exports never contain retained audio.
- Library exports contain dictionary entries, snippets, and styles—not history or notes.
- Provider keys are device-only Keychain items and are excluded from settings, History, diagnostics,
  issue bundles, library exports, and encrypted backups. `store=false` is requested from OpenAI, but
  provider/account retention policies still apply.

## Architecture

- `App`: lifecycle, dependency ownership, permissions, settings integration, and background engine warmup at launch
- `Audio`: microphone capture, preprocessing, adaptive speech and whisper detection
- `CWhisper`: vendored whisper.cpp public headers, exposed to Swift as a C module
- `Intelligence`: resident Whisper runtime, model installation, repair, grounding, personalization, and local commands
- `Insertion`: target capture, revalidation, Accessibility insertion, and clipboard fallback
- `Storage`: encrypted SQLite records, backups, and library transfer
- `Features`: Hub, onboarding, Flow Bar, personalization, Scratchpad, and settings
- `Support`: privacy-safe diagnostics

## Verification boundaries

The unit suite covers state transitions, whisper/noise classifiers, audio normalization, correction acceptance, grounding, insertion orchestration, encrypted storage, model integrity, imports, backups, revisions, and diagnostics redaction.

`ResidentWhisperEngineIntegrationTests` additionally runs real inference through the resident context — every other engine test uses a stub, so nothing else proves `whisper_full` is reachable or that the context survives between calls. `AudioCorpusIntegrationTests` runs the versioned F1 corpus through that same resident engine and writes completeness, WER/CER, and benchmark artifacts when the quality gate requests them. Missing runtime/model prerequisites are recorded as explicit skips, never as corpus success. The inference suites are serialized because two resident contexts loading the same model contend for the GPU and turn latency assertions into noise.

Real microphone accuracy, application-specific Accessibility behavior, Bluetooth input changes, multi-display placement, signing, and notarization still require hardware/UI verification. Automated corpus success must not be presented as a real-world whispered word-error-rate result.

## Models

The Models page can download, verify, activate, and delete Tiny, Base, Small, compact Large Turbo, and full Large Turbo variants. Downloads come from the public whisper.cpp model repository and are activated only after their complete SHA-256 digest matches Murmur's manifest.

Small English is the default because it is much faster than the 1.6 GB Large Turbo model on an M1 while retaining useful English dictation quality. Existing model choices are not changed automatically.

## Runtime acknowledgements and license

Murmur bundles a local runtime built from [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and GGML. The current v2 dictation path uses Whisper.cpp plus Murmur's deterministic grounded correction pipeline.

Murmur is available under the [MIT License](LICENSE). Upstream runtime attribution is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
