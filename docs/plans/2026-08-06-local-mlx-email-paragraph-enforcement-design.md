# Local MLX Email Paragraph Enforcement

**Date:** 2026-08-06
**Status:** Approved

## Problem

The local MLX model can return valid, grounded wording while collapsing the deterministic email
paragraphs it received. Apple Mail faithfully inserts that single-paragraph result.

## Design

After a successful local MLX professional-email response is parsed, pass only its `text` value
through `DeterministicEmailFormatter`. This final pass may normalize whitespace and insert blank
lines, but it must preserve the same ordered words. Semantic commands and remote writing routes are
unchanged. Provider output still passes the existing grounding validator before insertion.

Recognize “Respected …” as a greeting and punctuation-only forms such as “Regards.” as sign-offs.
Explicit model-produced blank lines remain authoritative and are only normalized.

## Verification

- Regress the exact single-paragraph Apple Mail result reported on 2026-08-06.
- Assert word-for-word preservation across post-formatting.
- Assert local semantic commands are not paragraph-formatted.
- Run transformation, formatter, routing, and full test suites before packaging.
