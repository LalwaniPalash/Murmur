# F3 Transformation Routing and Automatic Email Mode Design

**Date:** 2026-08-04  
**Status:** Approved by Palash on 2026-08-04  
**Priority order:** completeness and correctness, latency, privacy, feature breadth

## Purpose

Deliver the first useful vertical slice of F3 writing intelligence without hosting Murmur
services or weakening the complete-recording transcription guarantee. Murmur recommends a
bring-your-own-key (BYOK) text transformation route for initial writing quality, while local
models and deterministic-only behavior remain first-class user choices.

This slice makes professional formatting automatic in Mail and Gmail after one-time consent,
adds genuine semantic selected-text commands through the same transformation boundary, and
fails safely to the complete local transcript whenever transformation is unavailable or unsafe.

## Approved Product Decisions

1. Murmur hosts no inference service and receives no user key, audio, transcript, or context.
2. Authoritative transcription remains local by default and always uses the sealed complete
   recording. Transformation cannot make preview text authoritative.
3. The writing routes are:
   - **BYOK — Recommended:** OpenAI first, followed by configurable OpenAI-compatible endpoints.
   - **Local model:** an optional separately installed model that runs on the Mac.
   - **Deterministic only:** the existing fastest offline pipeline without generative rewriting.
4. Mail and Gmail use professional Email mode automatically after one-time consent. Users can
   disable transformation globally or per application.
5. Email mode may improve wording and paragraph structure, but must not invent greetings,
   sign-offs, commitments, facts, or recipients.
6. Remote text permission is independent from audio and every other context category.
7. A transformation failure inserts the complete deterministic result with a visible fallback
   indication. Partial provider output is never inserted.

## Scope

This vertical slice implements the text-transformation parts of BYOK-001–007, MOD-004,
PROF-001/002/004–006, CTX-001, MODE-003/008, CORR-007, and PERS-003. It also replaces the
current filler-removal Command-mode heuristic with a semantic route when one is enabled.

The following remain subsequent F3 slices and stay in the feature ledger: non-authoritative
live preview, cloud audio transcription, complete site/profile routing, selected and nearby
text permissions outside explicit Command mode, correction learning, multilingual evidence
tiers, microphone/route hardening, and compatibility/update work.

## Architecture

### Captured Policy

At session start Murmur captures an immutable writing policy containing:

- application identity and classified writing context;
- mode and instruction version;
- selected transformation route and model;
- permitted outbound categories;
- timeout and explicit fallback behavior.

Changing Settings cannot reroute an active session.

### Shared Transformation Contract

BYOK and local engines implement one asynchronous text-transformation protocol. A request
contains a source text, declared operation, writing instruction, application category, limits,
and a request identifier. A response contains only candidate text plus provider/model and
usage metadata that the route can truthfully supply.

Capabilities describe text transformation, structured response support, cancellation, usage
metadata, and supported limits. Unsupported operations are not offered by the UI.

The first adapters are:

- OpenAI using a user key stored only in Keychain;
- a configurable OpenAI-compatible endpoint;
- an optional local MLX-backed text model;
- the existing deterministic engine as the non-generative route and final fallback.

Remote endpoints must use HTTPS, except HTTP on a validated loopback address. Requests have
bounded size, timeout, cancellation, response decoding, and output-size checks. Provider
fallback occurs only when the user explicitly configured its order.

### Writing Data Flow

1. Capture and seal the complete recording.
2. Run authoritative local transcription.
3. Apply deterministic speech repair, dictionary, snippets, and spoken formatting.
4. Resolve the captured writing policy.
5. If enabled, transform through its declared BYOK or local route.
6. Validate completeness, response bounds, and protected details.
7. Insert the validated candidate or the complete deterministic source on failure.
8. Append immutable source/result provenance and the transformation outcome.

No route can insert streaming or partial output.

## Context and Consent Boundary

Initial remote text consent permits only:

- the completed repaired transcript;
- the selected writing-mode instruction;
- a broad application category such as Email.

It does not permit audio, passwords, clipboard contents, History, nearby text, selected text,
browser URLs, workspace content, or diagnostics. Explicit Command mode may send the selected
text because the user deliberately invoked an operation on that selection; its setup and scope
preview must state this separately.

Credentials remain in Keychain and are excluded from preferences, logs, History, backups,
diagnostics, and issue bundles. Local model downloads are explicit; after installation, local
transformation needs no network permission.

## Automatic Email Mode

Mail and Gmail application classification selects the built-in Professional Email instruction
when transformation is enabled. The output should be direct, natural, and professionally
formatted, with paragraph breaks at topic or intent changes. It must not add a salutation or
sign-off unless the speaker dictated one.

The Engine surface presents BYOK as recommended and Local model and Deterministic only as equal
selectable routes. It shows what each route sends, expected storage/memory, and measured quality
and latency when evidence exists. The Flow Bar displays `Polishing locally` or
`Polishing with OpenAI`; processing is never hidden.

## Correctness and Failure Handling

Validation protects email addresses, URLs, numbers, dates, identifiers, dictated names, and
other high-risk spans. The candidate must not remove, alter, duplicate, or invent protected
details. It must also be non-empty, within declared expansion/contraction bounds, decodable,
and free of provider framing or instruction leakage.

Validation or route failure returns the complete deterministic text. Authentication errors,
rate limits, malformed or oversized responses, timeouts, cancellation, unavailable local
models, and offline state all follow that rule. Murmur reports the fallback without exposing
content or credentials.

History keeps immutable source and transformed result versions, route/model, instruction
version, timing, validation outcome, and insertion outcome. It supports later retry and
comparison without overwriting either version.

## Latency

Transformation begins only after the authoritative complete transcript exists. Selected local
models are warmed in the background. Every route uses a measured bounded timeout and supports
cancellation; no provider may stall insertion indefinitely. Plain dictation and deterministic
mode pay no generative-model cost. Release gates report transformation latency separately from
capture, transcription, validation, and insertion.

## Verification

- Golden email corpus covering paragraphs, dictated greetings/sign-offs, names, dates, numbers,
  addresses, links, negation, commitments, and long-form completeness.
- Command corpus covering semantic concision and other selected-text rewrites.
- Shared adapter contract fixtures for success, malformed/partial/oversized responses,
  authentication failure, rate limit, timeout, cancellation, and unsupported capability.
- Security tests proving credentials and submitted content do not enter logs, preferences,
  diagnostics, backups, exports, or issue bundles.
- Policy tests proving settings changes cannot reroute an active session and undeclared
  fallbacks are unreachable.
- Latency reports by route/model with no regression in deterministic-only sessions.
- Explicitly tracked manual checks for Mail, Gmail, local offline operation, provider failure,
  and semantic Command mode. No manual row is represented as passed until physically tested.

## Exit Criteria for This Slice

The slice exits when a user can choose BYOK, local-model, or deterministic transformation;
Mail/Gmail automatically apply safe Email mode after consent; semantic Command mode uses the
selected route; unsafe or unavailable transformations fall back to the complete local text;
provenance is inspectable; and all automated gates pass. The remaining F3 capabilities stay
visible as pending work.
