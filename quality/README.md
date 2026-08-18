# Murmur F1 Quality Evidence

This directory contains durable, content-free inputs for the local F1 quality gate.
Generated reports belong under `.build/quality` and are intentionally not uploaded by
Murmur.

## One-command gate

```bash
script/quality_gate.sh [output-directory] [benchmark-baseline.json]
```

The command is non-destructive. It emits `quality-gate.json`, corpus quality and
benchmark JSON when resident inference is available, one log per check, and an optional
benchmark comparison. Exit statuses are:

- `0`: every check passed;
- `1`: at least one check failed;
- `3`: no check failed, but required evidence was unavailable or insufficient.

The corpus report cannot pass when any required beginning, middle, ending phrase, or
protected token is missing. An unavailable model/runtime produces explicit skipped
fixtures and therefore an incomplete gate.

Performance comparisons require at least five matching samples per hardware, model,
stage, and duration bucket. The default regression tolerance is 15% at p95; single runs
are evidence samples, never regression proof.

## Current status

- Engineering checks: complete and passing.
- Manual application/control compatibility sweep: **pending and deferred by the owner**;
  all seed rows remain `untested`. F2 work may proceed, but this exception never changes
  the F1 machine report or represents the compatibility gate as passed.
- First statistically valid benchmark baseline: **next**.
- F1 gate: `incomplete` until both evidence items are finished.

## Insertion compatibility

[`insertion-matrix.json`](insertion-matrix.json) declares every supported control family.
Seed rows are deliberately `untested`; do not convert them to supported based on unit
tests or assumptions.

For a manual run, create a JSON file containing only app/control metadata and the result:

```json
{
  "applicationName": "Example Editor",
  "applicationVersion": "1.2.3",
  "bundleIdentifier": "com.example.editor",
  "controlType": "chromiumContentEditable",
  "notes": "Paste verified and the previous clipboard value was restored.",
  "outcome": "supported",
  "recovery": "notNeeded",
  "strategy": "clipboardPaste",
  "verification": "observed"
}
```

Then record it atomically (a matching `pending` seed is replaced):

```bash
swift run murmur-quality insertion record quality/insertion-matrix.json /path/to/record.json
```

Never include dictated text, selected text, clipboard contents, API keys, filenames that
contain private writing, or screenshots in a matrix record. Reproducible failures should
become local fixtures and automated tests where possible.

## Feature ownership

The complete product scope remains in [`docs/product/feature-ledger.md`](../docs/product/feature-ledger.md).
F1 implements or advances EVAL-001–003, EVAL-006–007, EVAL-010, TRN-004–005,
INS-009–010, and SEC-008. Quiet/whisper evaluation (EVAL-005) remains planned until the
corpus contains consented or reproducibly transformed audio that truly exercises those
conditions; a normal-volume synthetic voice must not be labeled as whisper evidence.
