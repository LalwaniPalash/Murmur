# Isolated Multi-Model MLX Design

**Date:** 2026-08-06  
**Status:** Approved  
**Priority:** correctness and crash isolation, then latency, privacy, and model breadth

## Outcome

Restore local semantic writing without allowing MLX or a model to crash Murmur. Support a small,
curated range of fast-to-strong MLX models and let users either select a model or let Murmur choose
one for a session.

## Selection Modes

- **Automatic:** choose one installed model when the session begins using application category,
  operation, transcript length, latency target, memory pressure, model health, and benchmark data.
- **Preferred:** normally use the selected model, with one stronger installed fallback when output
  validation fails.
- **Fixed:** use exactly the selected model and never substitute another model.

The chosen model remains fixed for the session. Automatic selection never downloads a model and
never changes the local/cloud route. A validation retry may escalate once when the mode permits it.

## Curated Catalog

The initial catalog contains approximately three pinned choices: fastest, balanced/recommended,
and highest quality. Every manifest records repository, immutable revision, file sizes and hashes,
license, architecture, tokenizer/chat template, memory requirement, output limit, supported tasks,
and benchmark class. Custom Hugging Face repositories remain an Advanced follow-up and must pass
the same compatibility checks before use.

## Process Boundary

MLX runs only in a dedicated `MurmurMLXWorker` process. Resident Whisper remains in the main app.
Murmur and the worker exchange bounded, versioned JSON containing model ID, operation, source,
spoken instruction, protected terms, generation limits, output, duration, and content-free failure
codes. The worker resolves only verified files from Murmur's model directory.

One worker owns one session and keeps its selected model resident. Later sessions may reuse it when
the model is still healthy and memory permits. Model replacement happens between sessions, never in
the middle of an operation.

## Packaging

The worker and version-matched MLX `default.metallib` are required signed bundle resources.
Packaging fails if either is absent, mismatched, unloadable, or outside the expected bundle path.
Local writing remains disabled unless a worker startup probe succeeds without transcript content.

## Failure Behavior

- Worker crash, native abort, timeout, missing Metal resources, or malformed response cannot end the
  main app.
- Email uses the complete deterministic formatted transcript on failure.
- Command mode leaves selected text unchanged and reports a recoverable failure.
- Invalid output may retry once according to the selection mode.
- Repeated failure marks the model unhealthy for the launch.
- No verified healthy model means deterministic behavior remains available.

The main app independently validates every worker result before insertion. No partial or ungrounded
candidate becomes authoritative.

## User Experience and Records

The existing Writing model list shows speed, quality, memory, size, supported tasks, installation,
verification, and health. Users choose Automatic, Preferred, or Fixed. History records the selected
model, content-free selection reason, latency, retry, and fallback without recording prompts in logs.

## Qualification Gates

Each curated model must pass the same local corpus for completeness, protected-detail retention,
Email paragraph quality, command accuracy, hallucination/omission rate, cold and warm latency, peak
memory, cancellation, and repeated-run stability. Release tests run real Whisper followed by real
worker inference, plus worker crash, timeout, malformed output, missing metallib, model removal,
memory pressure, Apple Mail, Gmail, and command-selection safety.

## Current Safety State

Until this design ships, production in-process MLX is fail-closed. Installed model files remain
available, but Murmur falls back to deterministic output rather than risk an uncatchable native
abort.
