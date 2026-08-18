# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native SwiftUI/AppKit application for macOS 15+ on Apple Silicon. Impeccable's platform
vocabulary enumerates `web`, `ios`, `android`, and `adaptive`; none of those describe this
product, so the true platform is recorded here. Apple HIG applies, but for the Mac
idiom — menu bar extra, windowed Hub, floating panel, pointer and keyboard first — not the
iOS device model. Do not apply web guidance to this codebase.

## Users

People who write by speaking on their own Mac, and who will not send their voice to a
server to do it. Open-source users are the primary design target: strangers installing a
DMG or building from source on hardware, microphones, and target applications the author
has never tested. They arrive with no account, no onboarding call, and no support channel —
the app has to explain itself, survive unfamiliar setups, and fail legibly on its own.

The job: hold `fn`, speak or whisper a sentence into whatever app currently has focus,
release, and have finished text appear where the cursor was. Common situations are drafting
messages and prose, dictating into a code editor or terminal, and speaking quietly in a
shared or public space where normal-volume dictation is not socially possible.

## Product Purpose

Murmur turns speech into the text a person meant to write, entirely on their own machine.
Success is that a user stops treating dictation as a draft that needs cleanup: released
audio becomes inserted text that is correct, correction-free, and fast enough that speaking
beats typing. Failure modes it exists to prevent are invented content, visible half-finished
words, and latency that breaks the writing rhythm.

## Positioning

Three claims, ranked. Future work preserves all three in this order.

1. **Local-only.** Same job as cloud dictation tools (Wispr Flow, Superwhisper), with no
   network inference, no account, no telemetry, no subscription, no sync. Privacy is the
   frame the product is built inside, not a feature on a list. Network access exists only
   for a model download the user explicitly starts.
2. **Grounded correction.** The differentiator is the repair pipeline: it removes fillers,
   restarts, abandoned clauses, and explicit self-corrections, and it refuses to insert
   names, numbers, URLs, paths, and identifiers it cannot ground in what was actually
   spoken. Other tools transcribe; Murmur decides what the speaker meant, and declines to
   invent.
3. **Latency as proof.** A resident in-process Whisper context plus encoder-context
   truncation put a 2s utterance around 130ms from key release to insertion. Local is table
   stakes; being fast while local is the evidence the first two claims are not a compromise.

## Operating Context

- Murmur is almost never the focused application. The user is in Mail, Slack, an editor, or
  a terminal; Murmur is a menu bar extra plus a floating Flow Bar that reports state without
  stealing focus. The Hub window is for setup, review, and configuration, not for the core
  loop.
- Primary interaction is a global hold-to-talk key (`fn`), Command Mode (`fn` + `Control`),
  Escape to cancel, and a hands-free mode from the menu bar. Hands may be on the keyboard,
  on a mouse, or nowhere.
- The core loop happens while another app owns the cursor, so insertion depends on
  Accessibility permission, with a transactional clipboard fallback when the AX path fails.
- First run is a permission gauntlet: Microphone and Accessibility must be granted, and a
  multi-hundred-megabyte model must be downloaded and verified, before anything works.
- Model choice is a real user decision surfaced in the Hub: Tiny through full Large Turbo,
  trading size and speed against accuracy and multilingual support.
- Beyond dictation, the app holds encrypted local history, a multi-tab Scratchpad with
  version history, personalization (dictionary terms, snippets, styles), password-encrypted
  backup/restore, library import/export, and redacted diagnostics export.

## Capabilities and Constraints

**Confirmed capabilities.** Adaptive noise-floor calibration and whisper likelihood
detection; resident whisper.cpp inference warmed once at launch; a sensitive second pass for
likely whispers and low-quality first passes; deterministic speech repair; grounding checks;
dictionary terms, voice snippets, spoken punctuation, numbered lists; Accessibility
insertion with clipboard fallback; encrypted local history, notes, and revisions; model
install with HTTPS response validation, SHA-256 verification, cancellation, and atomic
activation; opt-in redacted diagnostics.

**Hard constraints.**

- Apple Silicon (M1+) and macOS 15 or later. No Intel path.
- No account, telemetry, cloud inference fallback, subscription, or remote sync — ever.
- Nothing provisional is displayed or inserted. The complete recording is transcribed in one
  authoritative pass after release; final text is decoded, corrected, and inserted once.
  Streaming partials are a rejected design, not a missing feature.
- Correction never fabricates. Ungroundable identifiers are rejected rather than guessed.
- The whisper.cpp runtime is staged locally, never checked in. `MURMUR_RESIDENT_WHISPER`
  guards every reference so an unstaged checkout still compiles, falling back to a
  per-dictation `whisper-cli` subprocess. That fallback is verified structurally only.
- Sensitive payloads are AES-GCM encrypted under a Keychain-protected master key; search
  uses keyed blind-index terms; raw audio is deleted after processing unless retention is
  explicitly enabled.
- MIT licensed; whisper.cpp/GGML attribution in `THIRD_PARTY_NOTICES.md` is required.

**Terminology.** *Flow Bar* (floating state panel), *Hub* (main window), *Command Mode*,
*Scratchpad*, *grounding*, *repair*, *sensitive pass*, *resident context*.

**Undecided.** No formal accessibility conformance target. No stated position on
localization or non-English UI. Signing/notarization, real-microphone word error rate, and
application-specific Accessibility behavior remain unverified by automation.

## Brand Commitments

- Name: **Murmur**. Lowercase-quiet register in copy; the product's own voice avoids hype and
  states what it does and does not do (the README is the reference tone).
- Mark and icon exist at `Assets/Brand/` — `murmur-mark.svg`, `murmur-mark-light.svg`,
  `murmur-icon-dark.svg`, `Murmur.icns`, and a full iconset. These are the established
  identity assets.
- The product never claims accuracy, privacy, or performance it has not measured. The README
  labels benchmarks as synthesized speech on one machine; that honesty is a brand rule.

## Evidence on Hand

- Measured latency table in `README.md` (M1, `ggml-small.en`, key release to insertion),
  plus a stage-by-stage baseline and validated-fix numbers in `tasks/todo.md`.
- Versioned repair acceptance corpus: `Tests/MurmurNextTests/Fixtures/repair-corpus-v1.json`.
- Real end-to-end inference test: `ResidentWhisperEngineIntegrationTests`.
- Design and implementation records under `docs/plans/`.
- Brand assets under `Assets/Brand/`.
- **Absent, and not to be fabricated:** users, testimonials, install counts, stars, press,
  real-microphone word error rate, multilingual quality claims, comparative benchmarks
  against Wispr Flow or any competitor, and any notarization or App Store status.

## Product Principles

1. **Local is the frame, not the feature.** No design or feature may introduce a network
   dependency, account, or telemetry path. If a capability needs the cloud, it is out of
   scope.
2. **Never invent.** The pipeline declines rather than guesses; the interface follows —
   no provisional text, no optimistic state, no implied certainty the system does not have.
3. **The user is elsewhere.** The core loop must work without focusing Murmur. Anything that
   demands attention during dictation is a defect.
4. **Design for a stranger's Mac.** Unknown hardware, microphones, target apps, and
   permission states are the default case. Every failure needs a legible cause and a next
   action, because there is no support channel.
5. **Claim only what is measured.** Performance, accuracy, and privacy statements trace to a
   number or a code path, and state their limits.

## Accessibility & Inclusion

No formal conformance standard has been established yet — record as undecided rather than
asserting WCAG or a VoiceOver bar the project has not committed to.

One hard requirement is confirmed: **the interface must support both light and dark
appearance.** Today `Sources/MurmurNext/DesignSystem/MurmurTheme.swift` defines a
light-only warm-paper palette with no dark tokens and no `ColorScheme` response, so this is
an open gap in the current implementation, not a satisfied requirement.
