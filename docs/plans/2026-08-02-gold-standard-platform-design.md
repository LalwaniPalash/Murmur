# Murmur Gold-Standard Platform Design

**Date:** 2026-08-02

**Status:** Approved

**Target:** macOS first; iOS and Windows later

**License:** MIT, fully free and open source

## Objective

Murmur will become the industry gold standard for voice writing: a quality-gated
platform that matches the useful breadth of leading open- and closed-source products
while establishing stronger guarantees for completeness, correctness, latency, privacy,
and recoverability.

The product priority is fixed:

1. Completeness and correctness
2. Latency
3. Privacy
4. Feature breadth

Feature parity determines what Murmur must support. Quality gates determine when a
capability is safe to ship.

The permanent product inventory is in [the feature ledger](../product/feature-ledger.md).
Competitor coverage is tracked in [the parity register](../product/competitor-parity.md).
Features remain in those documents when deferred so scope cannot silently disappear.

## Product Decisions

- Murmur is local by default and fully usable without an account or network connection.
- Murmur hosts no inference, storage, synchronization, telemetry, or account backend.
- Optional cloud capabilities are bring-your-own-key only.
- The first cloud interface supports OpenAI and OpenAI-compatible endpoints.
- A profile may explicitly route audio transcription or text transformation to a provider.
- Murmur never silently sends data, changes providers, or invents a fallback order.
- macOS quality comes first. Later platform work must not weaken the macOS core.
- General knowledge workers are the first audience; privacy-sensitive professional
  requirements are product-wide constraints rather than a separate edition.
- Raw recording retention is off by default. Users may explicitly enable encrypted,
  automatically expiring retention, with seven days as the suggested duration.
- Live transcription is visible only inside the Flow Bar and is never authoritative.
- All model-supported languages may be exposed, but quality claims use Verified,
  Community-tested, and Experimental tiers.

## Architecture

Murmur has five independently testable layers.

### Capture

Capture owns microphone and system audio, device management, adaptive preprocessing,
ordered frame delivery, the live-preview stream, and the complete authoritative recording.
No preview or streaming artifact can replace or mutate the source timeline.

### Understanding

Understanding owns local and BYOK transcription, language selection, timestamps,
alignment, completeness signals, deterministic speech repair, optional transformations,
and protected-detail grounding.

Local Whisper and OpenAI-compatible providers implement a capability-based interface.
Providers declare support for batch audio, streaming, language hints, timestamps,
translation, prompts, and structured responses. Murmur enables only proven capabilities.

### Writing

Writing owns profiles, application and website rules, modes, dictionary terms, snippets,
spoken formatting, correction learning, contextual formatting, commands, and custom
instructions.

### Delivery

Delivery owns target capture and revalidation, text insertion, clipboard safety, recovery,
history, and export. A failed insertion must leave the transcript recoverable.

### Evidence

Evidence owns encrypted session history, consented recording retention, transcript
versions and diffs, evaluation corpora, performance measurements, diagnostics,
compatibility results, and release gates.

## Authoritative Session Model

Every dictation creates one session identity and one chronological audio timeline.
Preview fragments, final transcripts, repairs, transformations, and retranscriptions are
derived, versioned artifacts.

The session data flow is:

1. Capture the target application, profile, language policy, provider route, and context
   permissions.
2. Record ordered audio while producing a non-authoritative live preview.
3. On release, drain capture and seal the complete timeline.
4. Run one full-recording transcription through the explicitly selected route.
5. Align the result to time and compute completeness and confidence signals.
6. Apply deterministic repair, personalization, and any selected transformation.
7. Ground protected details against permitted sources.
8. Revalidate the target and insert the final text.
9. Commit result versions, provenance, diagnostics, and allowed audio retention atomically.

Sessions end as Completed, Recoverable, Needs Review, Cancelled, or Failed. History stores
raw and final text, model and provider, language, profile, timings, insertion outcome,
transformation provenance, and result versions. Retranscription creates a new version; it
never overwrites an earlier result.

Profiles may define an explicit ordered fallback, such as an OpenAI-compatible endpoint
followed by a local model. No undeclared fallback is permitted.

## Intelligence and Context

The writing pipeline is staged and inspectable:

1. Speech-to-text
2. Alignment and completeness checks
3. Deterministic speech repair
4. Dictionary, snippets, and spoken formatting
5. Optional application-aware or custom transformation
6. Protected-detail grounding
7. Presentation formatting

Profiles independently select transcription route, transformation route, language, model,
style, target applications or websites, context permissions, fallback sequence, and
auto-submit behavior.

Context is permission-scoped. Profiles may allow the application identifier, browser
domain, selected text, nearby text, or workspace vocabulary. Whole-screen capture is not
the default context mechanism. Before a cloud profile is enabled, Murmur shows exactly
which audio, text, and context categories the endpoint may receive.

Correction learning runs only when the post-insertion comparison is reliable.
High-confidence localized substitutions enter a review queue. Broad rewrites, deletions,
and ambiguous edits do not silently become global rules.

Language tiers are:

- **Verified:** dedicated corpus, native-speaker review, and passing release thresholds.
- **Community-tested:** reproducible contributed evidence with incomplete coverage.
- **Experimental:** supported by the selected model without a Murmur quality claim.

Built-in modes cover plain dictation, message, email, document, prompt, developer,
meeting note, and user-defined instructions. Transformations store provenance and must
pass grounding before insertion.

## Product Surfaces

### Flow Bar

The non-activating Flow Bar shows waveform, live preview, language, profile, provider,
elapsed time, hands-free state, cancellation, finalization, and recovery state. Live text
never becomes final merely because it is non-empty.

### History and Recovery

History supports search, retained-audio playback, raw and final text, result versions,
aligned diffs, retry with another model or provider, copy, export, report, and secure
deletion.

### Transcription Studio

Studio supports audio and video import, batch queues, transcript editing, synchronized
playback, timestamps, speakers, diarization, translation, and export.

### Meeting Capture

Meeting Capture supports microphone and system audio, input selection and mixing, live
notes, diarization, and authoritative full-recording reconciliation.

### Profiles and Automation

Profiles combine target rules, modes, dictionary, snippets, instructions, provider
routing, context permissions, and workflow actions. Automation expands through CLI,
Shortcuts, URL scheme, a disabled-by-default localhost API, watch folders, integrations,
permissioned webhooks, MCP, and eventually a plugin SDK.

Scratchpad remains a local writing destination and can receive dictation or workflow
results without trying to replace a full note-taking application.

## Export and Interoperability

Initial export parity covers plain text, Markdown, JSON, CSV, SRT, and VTT. PDF and DOCX
follow. Export packages may include source audio, result versions, timestamps, speakers,
and processing provenance only when explicitly selected.

Hosted competitor capabilities are replaced with user-controlled equivalents:

- Hosted accounts become local profiles.
- Proprietary cloud inference becomes BYOK providers.
- Vendor sync becomes encrypted backup, iCloud Drive, selected folders, or self-hosted
  endpoints.
- Hosted team administration becomes signed policy and profile bundles.
- Vendor telemetry becomes a local quality dashboard and explicit diagnostic export.

## Failure Handling

Murmur treats lost speech as its highest-severity product failure.

- Complete audio remains available until processing and delivery reach a terminal state.
- If insertion fails, final text remains in History and on the clipboard.
- If transcription fails while audio is available, Murmur offers retry, route change, or
  explicit retention before discarding it.
- When retention is disabled, temporary audio is removed after the recovery interaction.
- Interrupted retained sessions can resume without overwriting their source recording.
- No failure may cause an automatic privacy-expanding provider change.
- Repeated provider requests must avoid duplicate billing where the provider protocol
  allows idempotency.

## Privacy and Security

- API keys live only in Keychain.
- Remote endpoints require HTTPS; loopback endpoints may use HTTP.
- Provider requests expose their audio, text, and context scope.
- Keys, transcripts, audio, and context are excluded from logs.
- Responses have strict size, timeout, status, and content-type validation.
- Recording retention uses per-file encryption keys wrapped by the Keychain master key.
- Automatic expiration deletes encrypted audio and associated cryptographic metadata.
- Local API and MCP bind only to loopback, require generated credentials, and expose
  scoped permissions.
- Imports, community packs, and plugins are untrusted input and require validation,
  limits, preview, and explicit activation.
- Plugins arrive only after the core interfaces stabilize and must declare network,
  filesystem, audio, transcript, and context capabilities.
- Murmur operates no telemetry backend. Diagnostic or fixture contribution is explicit.

## Evidence and Release Gates

The local evaluation system measures capture integrity, phrase preservation, word and
character error rates, correction resolution, protected-detail grounding, quiet-speech
recognition, hallucination rejection, local and BYOK latency, insertion compatibility,
resource use, recovery, and language quality.

Initial release gates are:

- Zero known silent phrase omissions in the release corpus.
- Zero invented protected entities.
- At least 98% explicit self-correction resolution.
- No dropped audio frames during normal stop and finalization.
- No transcript loss after an insertion failure.
- At least 99.5% successful or recoverable outcomes in the supported-app matrix.
- No dictated content in logs, diagnostics by default, or unintended network requests.
- No statistically significant verified-language accuracy regression.
- Local p95 release latency reported by duration bucket on the baseline M1 Mac.

Exact WER and latency ceilings are established from representative real-audio evidence
and ratcheted stricter. They cannot be relaxed merely to ship.

Every confirmed defect becomes a permitted anonymized audio fixture, synthetic fixture,
transcript corpus case, insertion test, or provider contract fixture.

## Delivery Milestones

1. **Foundation and evidence:** corpus runner, alignment, completeness scoring,
   application matrix, performance dashboard, and release gates.
2. **Recovery and trust:** opt-in encrypted recording retention, interrupted-session
   recovery, playback, retranscription, comparison, aligned diffs, and issue bundles.
3. **Gold-standard writing:** Flow Bar preview, multilingual tiers, OpenAI-compatible
   BYOK, profiles, contextual modes, correction learning, and advanced personalization.
4. **Transcription Studio:** file and video import, batches, editor, synchronized playback,
   timestamps, translation, speakers, subtitles, and document exports.
5. **Meetings and automation:** system audio, diarization, meeting sessions, CLI,
   Shortcuts, local API, watch folders, integrations, webhooks, and MCP.
6. **Ecosystem expansion:** plugin SDK, community evaluation packs, shareable profiles,
   user-owned synchronization, then iOS and Windows.

Each milestone inherits every earlier gate. A later feature cannot bypass the authoritative
session, provenance, grounding, recovery, security, or evaluation infrastructure.
