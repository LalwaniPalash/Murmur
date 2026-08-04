# F3 Transformation Routing Implementation Plan

**Date:** 2026-08-04  
**Design:** [F3 transformation routing and automatic Email mode](2026-08-04-f3-transformation-routing-design.md)  
**Status:** Approved design; implementation ready  
**Priority:** completeness/correctness, latency, privacy, feature breadth

## Outcome

Ship a narrow F3 vertical slice in which users choose deterministic, OpenAI BYOK, an
OpenAI-compatible endpoint, or a separately installed local MLX writing model. Mail and
Gmail automatically apply safe professional Email mode after consent, and Command mode can
perform semantic selected-text transformations. Murmur hosts nothing and inserts the complete
deterministic result whenever an AI transformation is unavailable or fails validation.

## Constraints

1. Preserve the complete-recording authoritative transcription path.
2. Capture route, model, instruction, application classification, permissions, timeout, and
   fallback at session start. Settings cannot reroute active work.
3. Plain/deterministic sessions perform no network request and load no writing model.
4. Remote requests never include audio. Email mode sends no selected text, nearby text, URL,
   clipboard, History, or workspace content.
5. Explicit Command mode may send the selected text only after its separate scope consent.
6. API credentials live only in Keychain.
7. Remote endpoints require HTTPS except validated loopback HTTP.
8. No implicit provider fallback. Safety fallback is always the deterministic source text.
9. Preserve the redesigned panel UI and reuse its components.
10. Manual checks remain pending until physically performed.

## Verified External Contracts

- Use OpenAI's `/v1/responses` endpoint for the OpenAI adapter.
- Request strict structured output through `text.format` with a JSON schema.
- Send `store: false`, no tools, no background mode, and bounded output tokens.
- Treat `incomplete`, refusal, missing output, malformed output, non-2xx responses, timeout,
  and cancellation as typed failures.
- Disclose that `store: false` disables Responses application-state storage but does not
  promise zero provider retention; provider/account data controls still apply.
- Default to the current `gpt-5.6` alias with low-latency settings, while keeping the model
  editable and evaluating alternatives on Murmur's corpus before labeling one best.
- Use MLX Swift LM 3.x for the in-process local route. Start with the separately downloaded,
  Apache-2.0 `Qwen3-0.6B-4bit` model at a pinned revision and do not label its quality verified
  until the Murmur transformation corpus passes.

References:

- <https://developers.openai.com/api/docs/guides/text?api-mode=responses>
- <https://developers.openai.com/api/docs/guides/structured-outputs>
- <https://developers.openai.com/api/docs/guides/your-data>
- <https://developers.openai.com/api/docs/guides/latest-model>
- <https://github.com/ml-explore/mlx-swift-lm>
- <https://huggingface.co/Qwen/Qwen3-0.6B-MLX-4bit>

## Slice 1 — Domain, Captured Policy, and Backward-Compatible Settings

**Create:**

- `Sources/MurmurNext/Core/WritingTransformationModels.swift`
- `Sources/MurmurNext/Intelligence/WritingPolicyResolver.swift`
- `Tests/MurmurNextTests/WritingPolicyResolverTests.swift`
- `Tests/MurmurNextTests/WritingSettingsCompatibilityTests.swift`

**Modify:**

- `Sources/MurmurNext/Core/DomainModels.swift`

Add `WritingTransformationRoute`, provider/model configuration, granular remote-text consent,
per-application overrides, transformation operation/mode, capability metadata, request/result,
typed failure, and an immutable `CapturedWritingPolicy`.

Extend `MurmurSettingsRecord` with backward-compatible decoding defaults. Existing users decode
to deterministic-only with no remote consent and no network behavior. Do not encode credentials.

Policy precedence for this slice is an exact per-app override followed by classified Email mode
and then the global route. Command mode requires selected-text consent for remote routes. Add
tests first for defaults, old payloads, route capture, disabled apps, and permission denial.

## Slice 2 — Protected-Detail and Completeness Validation

**Create:**

- `Sources/MurmurNext/Intelligence/TransformationValidator.swift`
- `Tests/MurmurNextTests/TransformationValidatorTests.swift`
- `Tests/MurmurNextTests/Fixtures/Transformation/email-golden.json`
- `Tests/MurmurNextTests/Fixtures/Transformation/command-golden.json`

Extract and compare protected spans including email addresses, URLs, numeric strings, dates,
currency, percentages, paths, identifiers, and dictionary-approved names. Reject loss, mutation,
duplication, or invention. Also reject empty output, instruction/provider framing, excessive
expansion or contraction, and results over hard byte/character limits.

The validator is deliberately deterministic and provider-independent. A failure returns a reason
code plus the complete source; it never tries to repair unsafe model output. Golden fixtures must
cover long input, paragraphing, dictated greetings/sign-offs, negation, commitments, addresses,
and multiple protected details.

## Slice 3 — Keychain Credentials, Endpoint Policy, and OpenAI Adapter

**Create:**

- `Sources/MurmurNext/Security/ProviderCredentialStore.swift`
- `Sources/MurmurNext/Intelligence/TransformationHTTPClient.swift`
- `Sources/MurmurNext/Intelligence/OpenAITextTransformationEngine.swift`
- `Tests/MurmurNextTests/ProviderCredentialStoreTests.swift`
- `Tests/MurmurNextTests/TransformationEndpointPolicyTests.swift`
- `Tests/MurmurNextTests/OpenAITextTransformationEngineTests.swift`

Store provider keys as generic-password Keychain items under a Murmur-specific service and
provider account identifier. Support save, replace, existence check, and delete without exposing
the key through published state or error text.

Validate endpoint scheme, host, port, user info, fragments, normalization, and loopback rules.
Inject a small HTTP transport so tests never call a real provider. Use an ephemeral `URLSession`,
disable caches and cookies, set explicit content type and bearer authorization, enforce request
and response bounds, and cancel the underlying task.

Build an OpenAI Responses request with strict `{ "text": string }` output, `store: false`, the
captured model, bounded output, and the versioned system instruction. Parse only message output
text that matches the schema. Map authentication, rate limit, timeout, cancellation, refusal,
incomplete, malformed, oversized, and server errors to content-free typed failures.

Add a compatible adapter mode for endpoints that truthfully support either Responses or Chat
Completions structured output. Capability probing is explicit and content-free; it never sends a
transcript. Unsupported compatibility configurations stay disabled.

## Slice 4 — In-Process Local MLX Route

**Create:**

- `Sources/MurmurNext/Intelligence/LocalWritingModelCatalog.swift`
- `Sources/MurmurNext/Intelligence/LocalMLXTextTransformationEngine.swift`
- `Tests/MurmurNextTests/LocalWritingModelCatalogTests.swift`
- `Tests/MurmurNextTests/LocalMLXTextTransformationEngineTests.swift`

**Modify:**

- `Package.swift`
- `THIRD_PARTY_NOTICES.md`
- `Vendor/Runtimes/README.md`

Add pinned compatible MLX Swift LM, Hugging Face downloader, and tokenizer dependencies. Keep
model weights outside the app and repository. Define a manifest with exact repository, revision,
license, expected files, and size. Download only after explicit user action, stage atomically,
reject traversal/symlinks/unexpected files, and verify pinned integrity metadata before activation.

Load the selected model in an actor, serialize generation, warm it only when the local route is
selected, cap prompt/output tokens, disable speculative decoding, and honor cancellation. Parse
the same bounded output contract used by remote providers and pass it through the same validator.

Unit tests use a fake model runner. A real-model integration test is opt-in and reports model
revision, hardware, latency, output, and validation result without becoming a normal test-suite
download. Keep the model Experimental until corpus evidence supports promotion.

## Slice 5 — Minimal Gmail Detection and Application Policy

**Create:**

- `Sources/MurmurNext/Context/BrowserDomainContext.swift`
- `Tests/MurmurNextTests/BrowserDomainContextTests.swift`

**Modify:**

- `Sources/MurmurNext/Insertion/TextInsertionCoordinator.swift`

Mail is classified from its bundle identifier. Gmail in a normal browser cannot be identified
from the browser bundle alone, so add a minimal local-only active-domain reader for supported
browsers. It runs only after local domain-detection consent, extracts and normalizes the domain,
and returns only the classification `email` for `mail.google.com`; it does not persist or transmit
the URL/domain. Private/unavailable/unsupported browser state falls back to Browser, not Email.

This is intentionally not the later general website-profile system. Test exact host matching,
subdomain rejection/acceptance policy, spoofed suffixes, Unicode/IDN normalization, private state,
permission denial, and unsupported browsers.

## Slice 6 — Router, Orchestrator, Flow State, and Provenance

**Create:**

- `Sources/MurmurNext/Intelligence/WritingTransformationRouter.swift`
- `Tests/MurmurNextTests/WritingTransformationRouterTests.swift`

**Modify:**

- `Sources/MurmurNext/Core/DictationOrchestrator.swift`
- `Sources/MurmurNext/Core/DictationPerformance.swift`
- `Sources/MurmurNext/Core/SessionResultModels.swift`
- `Sources/MurmurNext/Features/FlowBar/FlowBarController.swift`
- relevant result/version recovery and storage tests

Resolve and store the captured policy in `begin`. After the complete deterministic pipeline,
transform non-command Email text only when the captured policy enables it. For Command mode,
run deterministic commands first and use the selected generative route only for unsupported
semantic operations. Validate every generative candidate before insertion.

Route errors are recoverable for normal dictation: insert the complete deterministic text and
publish a concise fallback state. Command failures must leave the selected text unchanged rather
than replace it with the spoken instruction or source selection.

Add transformation latency as a separate performance stage. Extend result schema additively with
optional transformation provenance: operation, route, provider/model, instruction version,
source hash/length, output hash/length, duration, validation outcome, and content-free failure
code. Backward decoding must remain green. Do not place credentials, prompts, or context in
provenance.

## Slice 7 — Engine UI, Consent, and Per-App Controls

**Modify:**

- `Sources/MurmurNext/Features/Models/EngineFeatureView.swift`
- `Sources/MurmurNext/Features/Settings/SettingsFeatureView.swift`
- `Sources/MurmurNext/App/AppEnvironment.swift`
- `Tests/MurmurNextTests/SettingsMutationTests.swift`

Add a Writing section to Engine with three primary choices: BYOK (Recommended), Local model, and
Deterministic only. BYOK setup supports OpenAI first, model choice, key save/replace/delete, a test
connection action, endpoint configuration for compatible providers, and a scope preview. Never
read the stored key back into a field.

Local setup shows download size, license, experimental quality, install/remove state, and measured
hardware guidance when available. Per-app controls default Mail and consented Gmail to automatic
Email mode and offer an off switch. Remote email-text and remote selected-text consents are
separate. Disclose provider/account retention and link to the configured provider policy.

Flow Bar status distinguishes `Polishing locally`, `Polishing with OpenAI`, and a short fallback
notice without widening the bar or exposing content.

## Slice 8 — Privacy, Packaging, Quality Gates, and Documentation

**Modify:**

- `Tests/MurmurNextTests/RepositoryPrivacyTests.swift`
- `Tests/MurmurNextTests/BuildPackagingTests.swift`
- `Sources/MurmurNext/Diagnostics/IssueBundleService.swift` and tests if schema changes require it
- `docs/product/feature-ledger.md`
- `docs/product/competitor-parity.md`
- `tasks/todo.md`
- `tasks/lessons.md` when new field evidence warrants a general rule
- `README.md`

Allowlist only the reviewed model-download and transformation HTTP call sites. Add canaries for
provider keys and submitted text across preferences, logs, database metadata, diagnostics,
backups, issue bundles, and built app resources. Verify archive/restore never contains Keychain
credentials and that network requests cannot be constructed without captured permission.

Run focused tests after each slice, then:

1. `swift test`
2. `swift build`
3. `script/quality_gate.sh`
4. `git diff --check`
5. stable signed app rebuild

Record automated counts and capability status honestly. The release remains incomplete until the
manual matrix below is performed.

## Manual Checks — Pending, Not Passed

- [ ] Mail: automatic professional paragraphs; protected details preserved.
- [ ] Gmail in each declared supported browser: local classification and formatting.
- [ ] BYOK scope preview, Keychain save/replace/delete, successful OpenAI transformation.
- [ ] Provider offline, timeout, malformed response, authentication failure, and rate limit all
      insert the complete deterministic Email text with a visible fallback.
- [ ] Local model install, offline transformation, cancellation, memory pressure, and removal.
- [ ] Command mode semantic concision replaces the selection; failure leaves it unchanged.
- [ ] Deterministic-only and disabled-app routes make no transformation network request and show
      no writing-model latency regression.
- [ ] The previously deferred physical Ctrl+Fn routing check in `tasks/todo.md`.

## Slice Exit

This slice is complete only when all automated gates pass, the stable signed build runs, and every
manual item is either passed or explicitly left pending by the owner. Completion updates only the
feature-ledger rows actually delivered; live preview and the remaining F3 work stay planned.
