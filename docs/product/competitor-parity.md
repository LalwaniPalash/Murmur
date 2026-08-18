# Murmur Competitor Parity Register

**Purpose:** Preserve every meaningful capability observed in the 2026-08-02 comparison
of VoiceInk, Handy, TypeWhisper, OpenWhispr, Wispr Flow, Superwhisper, Aqua Voice,
Willow, and MacWhisper.

This register tracks capabilities, not marketing claims. “Parity” means Murmur provides
the underlying user outcome. “Advantage” records how Murmur should exceed a checkbox-level
implementation. Stable feature IDs link to [the feature ledger](feature-ledger.md).

## Core Voice Writing

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| System-wide push-to-talk | All direct competitors | Yes | F0 | Complete-buffer authority and focus-safe delivery |
| Hands-free dictation | Willow, VoiceInk, TypeWhisper | Yes | F0 | Same recovery and completeness gates as push-to-talk |
| Live transcription preview | Handy, TypeWhisper, OpenWhispr, Aqua | No | FLOW-003, F3 | Preview is visibly provisional and never silently final |
| Real-time target insertion | Aqua and some mobile products | No | Excluded for initial Mac design | Avoid duplicate/moving text; final insertion remains authoritative |
| Quiet/whisper mode | Willow, Superwhisper | Yes | CAP-003–005 | Adaptive capture and separately measured whisper quality |
| Pause and resume media | VoiceInk, Handy, TypeWhisper | Partial | F3 | Restore behavior tied to session terminal state |
| Multiple microphones | Most desktop competitors | Partial | CAP-006, F3 | Route-change recovery and per-device evidence |
| Application-wide insertion | All direct competitors | Yes | INS-001–010 | Layout-aware, modifier-safe, target-verified, recoverable |

## Completeness, Recovery, and History

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Full history | VoiceInk, Handy, TypeWhisper, OpenWhispr, Willow | Yes | HIST-001–008 | Encrypted content and processing provenance |
| Saved recording playback | VoiceInk, Handy, TypeWhisper, Willow | Yes, opt-in | REC-002/HIST-005, F2 | Per-recording encryption, authenticated playback, and automatic expiration |
| Retry failed transcription | Willow, TypeWhisper, OpenWhispr | Yes, local | REC-004–007, F2 | Retry authenticated source audio without automatic reinsertion |
| Retranscribe old recording | VoiceInk, Willow, Superwhisper | Yes, local | REC-007, F2 | Parented immutable results instead of overwrite |
| Compare models/providers | Limited or manual elsewhere | Local models | REC-008–009, F2 | Arbitrary aligned A/B diff with latency and route provenance |
| Recover interrupted sessions | Willow, TypeWhisper | Yes | REC-004, F2 | Encrypted phase journal and partial authenticated-chunk recovery |
| Recording retention controls | VoiceInk, Handy, TypeWhisper | Advanced | REC-001–003, F2 | Off by default, explicit expiry, per-record keys, and crypto-shredding |
| Redacted issue export | Rare in direct competitors | Yes | REC-010, F2 | Preview-first metadata with transcript and audio independently off by default |
| Searchable history | Most competitors | Yes | HIST-002/006 | Keyed blind-index search over encrypted records |
| Cross-device history | Wispr Flow/cloud products | No | SYNC-001–003, F6 | User-owned encrypted synchronization |

## Transcription Engines and Providers

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Local Whisper | VoiceInk, Handy, TypeWhisper, Superwhisper, MacWhisper | Yes | TRN-001–002 | Resident runtime and one authoritative full pass |
| Multiple local engine families | Handy, TypeWhisper, MacWhisper | No | MOD-004/PLUG-001, F6 | Capability contracts and measured recommendations |
| Cloud transcription | All major commercial products; several OSS apps | No | TRN-008–010, F3 | BYOK, explicit audio scope, no Murmur-hosted relay |
| OpenAI-compatible endpoints | TypeWhisper | Writing only; manual pending | BYOK-002, F3 | Captured endpoint, fixed-content connection check, and contract fixtures |
| Local/cloud fallback | VoiceInk, TypeWhisper, OpenWhispr | No | PROF-006, F3 | Only the user-declared ordered policy can run |
| Model verification | Handy and Murmur | Yes | MOD-002–003 | Full digest and atomic activation |
| Model recommendations | Superwhisper, TypeWhisper | Basic | MOD-005, F3 | Hardware- and corpus-measured guidance |

## Language and Translation

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Broad model-supported languages | Wispr, Willow, Superwhisper, MacWhisper, TypeWhisper | Architecture only | LANG-001, F3 | Honest evidence tiers rather than one blanket claim |
| Automatic language detection | Most multilingual competitors | No | TRN-006, F3 | Published per-language confusion matrix |
| Language shortlist hints | TypeWhisper | No | TRN-007, F3 | Provider-aware behavior |
| Transcribe-and-translate | TypeWhisper, Superwhisper, MacWhisper | No | TRN-011, F4 | Source and translation stay linked and versioned |
| Community language packs | TypeWhisper term packs | No | LANG-006, F6 | Reproducible corpus, license, and quality metadata |

## Cleanup, Personalization, and Context

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Filler/repetition cleanup | Nearly all | Yes | CORR-001–004 | Deterministic and regression-corpus tested |
| Natural spoken corrections | Wispr, Willow, Aqua, Superwhisper | Yes | CORR-004 | Complete utterance repair across pauses |
| AI cleanup | VoiceInk, Handy, TypeWhisper, OpenWhispr, commercial apps | Implemented; manual pending | CORR-007/CORR-011, F3 | BYOK or local route with protected-detail validation, complete-source fallback, and provenance |
| Personal dictionary | Nearly all | Yes | PERS-001 | Encrypted storage, prompt validation, portable bundle |
| Snippets/shortcuts | Wispr, Willow, VoiceInk, OpenWhispr | Yes | PERS-002 | Deterministic expansion and collision handling |
| Automatic correction learning | Wispr, Willow, TypeWhisper, OpenWhispr | No | CORR-008–010, F3 | Reliable localized edits enter a review queue |
| Writing-style learning | Wispr, Willow, Aqua | No | PERS-003/PROF, F3 | Explicit rules and review instead of opaque global adaptation |
| Application context | VoiceInk, Wispr, Superwhisper, Aqua, Willow | Mail Email mode | CTX-001, F3 | Captured identity, exact off switch, and immutable routing policy |
| Browser/site context | TypeWhisper, Wispr | Gmail only; manual pending | CTX-002, F3 | Local exact-host classification with no URL retention or transmission |
| Selected/nearby text | Superwhisper, Aqua, Willow | Command selection only | CTX-003–004, F3 | Separate local/cloud context disclosure |
| Whole-screen context | Aqua and some commercial products | No | Not default | Prefer bounded accessible context over screen capture |

## Modes, Profiles, and Commands

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Built-in writing modes | VoiceInk, Superwhisper, Wispr, Aqua | Plain, Command, Email; manual pending | MODE-001–008, F3 | Generative results are grounded and fall back without partial insertion |
| Custom modes/instructions | VoiceInk, Superwhisper, TypeWhisper, Aqua | No | MODE-008, F3 | Previewable, portable, and evidence-gated |
| App-specific profiles | VoiceInk, TypeWhisper, Superwhisper | Mail/Gmail switches | PROF-001–007, F3 | Deterministic precedence and captured session policy; general profiles remain |
| Website-specific profiles | TypeWhisper | No | PROF-003, F3 | Cross-browser domain rules with explicit permission |
| Voice commands | Wispr, Aqua, Superwhisper | Command Mode | FLOW-008/MODE, F3 | Commands cannot mutate selection before safe completion |
| Auto-submit | TypeWhisper, Aqua | No | PROF-007, F3 | App-scoped and insertion-verified |

## File, Media, and Meeting Workflows

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Audio/video file transcription | TypeWhisper, Superwhisper, MacWhisper, OpenWhispr | No | FILE-001–002, F4 | Same authoritative session and provenance model |
| Batch transcription | TypeWhisper, MacWhisper | No | FILE-003, F4 | Recoverable queue with resource budgets |
| Transcript editor | MacWhisper, OpenWhispr | No | FILE-004, F4 | Immutable source and versioned edits |
| Synchronized playback | MacWhisper | No | FILE-005, F4 | Alignment quality is measured |
| Timestamps/subtitles | MacWhisper, TypeWhisper | No | FILE-006/EXP-004, F4 | Versioned timing through edits and translation |
| Speaker labels | MacWhisper, OpenWhispr | No | FILE-007, F4 | Manual edits remain traceable |
| Diarization | OpenWhispr, MacWhisper | No | FILE-008/MEET-006, F5 | Quality reported by speaker/acoustic condition |
| Meeting/system audio capture | OpenWhispr, MacWhisper, TypeWhisper, Superwhisper | No | MEET-001–007, F5 | Full-recording reconciliation and evidence-linked summaries |
| Live meeting notes | OpenWhispr, Superwhisper | No | MEET-004, F5 | Live output remains provisional |

## Export, Automation, and Ecosystem

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| TXT/Markdown/JSON/CSV export | Most transcription suites | Library only | EXP-001–003, F4 | Versioned schema and optional provenance |
| SRT/VTT export | MacWhisper, TypeWhisper | No | EXP-004, F4 | Validated timing and escaping |
| PDF/DOCX export | MacWhisper | No | EXP-005–006, F4 | Rendered/structural verification |
| CLI | Handy, TypeWhisper, MacWhisper | No | AUTO-001, F5 | Stable local JSON and exit-code contract |
| Local API | TypeWhisper, OpenWhispr | No | AUTO-004, F5 | Loopback-only, disabled, authenticated, scoped |
| Watch folders | TypeWhisper, MacWhisper | No | AUTO-005, F5 | Partial-write and duplicate safety |
| Raycast/Obsidian | Handy, MacWhisper | No | AUTO-006–007, F5 | Documented local interfaces and bounded vault scope |
| Webhooks | TypeWhisper, MacWhisper | No | AUTO-008, F5 | Explicit endpoint and payload preview |
| MCP | OpenWhispr | No | AUTO-009, F5 | Local, authenticated, and permission-scoped |
| Plugin SDK | TypeWhisper | No | PLUG-001–004, F6 | Declared capabilities and grounding boundary |
| Shareable profiles/dictionaries | Wispr/team products, TypeWhisper | Library bundles | SYNC-004/PERS-004, F6 | Signed, preview-first, accountless bundles |

## Platform, Distribution, and Collaboration

| Capability | Competitor examples | Murmur now | Target | Murmur advantage |
|---|---|---|---|---|
| Native macOS | VoiceInk, TypeWhisper, MacWhisper, commercial apps | Yes | PLAT-001 | Deep Mac integration without cross-platform compromise |
| Windows | Handy, OpenWhispr, Wispr, Superwhisper, Aqua, Willow | No | PLAT-005, F6 | Expand after macOS is the reference implementation |
| iOS | Wispr, Superwhisper, Aqua, Willow, MacWhisper | No | PLAT-004, F6 | Shared contracts without weakening desktop correctness |
| Account sync | Commercial products | No | User-owned sync only | No Murmur-hosted identity or transcript custody |
| Team dictionaries/policies | Wispr, Willow, Aqua | Local bundle only | SYNC-004, F6 | Signed accountless policies and dictionaries |
| Hosted collaboration spaces | OpenWhispr | No | Excluded | Prefer local/network or self-hosted collaboration later |
| Paid tiers/subscriptions | Commercial products | No | Excluded | Fully free MIT project |

## Required Review Cadence

- Re-audit the listed competitors before every major milestone.
- Add newly observed capabilities as rows; never silently delete old rows.
- Link each parity target to its stable feature IDs and implementation plan.
- Record intentional exclusions with product and safety reasoning.
- Mark parity only after the corresponding quality gate passes.
