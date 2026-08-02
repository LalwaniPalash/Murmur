# Murmur Feature Ledger

**Purpose:** Permanent inventory of approved, current, and deferred product capabilities.

**Last updated:** 2026-08-02

## Status and Phase Definitions

- **Current:** Implemented in the active `MurmurNext` application.
- **Planned:** Approved but not yet implemented.
- **Partial:** Some approved behavior exists, but the ledger item is not complete.
- **Deferred:** Retained in scope for a later milestone.
- **Excluded:** Deliberately not planned; the reason must remain recorded.

Phases: **F0** current foundation, **F1** evidence, **F2** recovery, **F3** writing,
**F4** Studio, **F5** meetings/automation, and **F6** ecosystem/platforms.

Every implementation plan, pull request, test, and release note should reference the
relevant stable IDs. A feature is complete only when behavior, tests, privacy handling,
documentation, accessibility, and acceptance metrics are satisfied.

## Capture and Audio

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| CAP-001 | Ordered microphone frame capture | F0 | Current | No reordered or dropped frames in stop/drain tests |
| CAP-002 | Complete authoritative recording timeline | F0 | Current | Beginning, middle, and end survive the gold corpus |
| CAP-003 | Adaptive noise-floor calibration | F0 | Current | Quiet speech detected without unacceptable silence activation |
| CAP-004 | Whisper-likelihood detection | F0 | Current | Whisper corpus measured separately from normal speech |
| CAP-005 | High-pass, bounded gain, limiting, and 16 kHz normalization | F0 | Current | Audio normalization fixtures and clipping limits pass |
| CAP-006 | Microphone selection and hot switching | F3 | Planned | Device-change corpus and recovery behavior pass |
| CAP-007 | Bluetooth route-change recovery | F3 | Planned | No silent truncation during supported route changes |
| CAP-008 | Non-authoritative live preview audio stream | F3 | Planned | Preview cannot become final without full-recording decode |
| CAP-009 | System-audio capture | F5 | Planned | Permission, mixing, drift, and interruption tests pass |
| CAP-010 | Microphone/system-audio mixer | F5 | Planned | No clipping, drift, or source loss in meeting corpus |
| CAP-011 | Long-session recording stability | F5 | Planned | Sustained memory, disk, and thermal gates pass |

## Transcription and Models

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| TRN-001 | Resident in-process whisper.cpp runtime | F0 | Current | Real inference and repeated-context integration tests pass |
| TRN-002 | One authoritative full-recording final pass | F0 | Current | No plausible partial stream can bypass the full pass |
| TRN-003 | Dictionary/snippet vocabulary prompting | F0 | Current | Prompt limits and recognition fixtures pass |
| TRN-004 | Confidence and completeness signals | F1 | Planned | Signals correlate with labeled omissions and uncertainty |
| TRN-005 | Word/segment timestamp alignment | F1 | Planned | Alignment error stays within corpus threshold |
| TRN-006 | Local language detection | F3 | Planned | Per-language confusion matrix is published |
| TRN-007 | Explicit language selection and shortlist hints | F3 | Planned | Provider/model contract tests pass |
| TRN-008 | OpenAI audio transcription | F3 | Planned | Explicit scope, cancellation, timeout, and response tests pass |
| TRN-009 | OpenAI-compatible audio transcription | F3 | Planned | Capability probe and compatibility fixtures pass |
| TRN-010 | Explicit provider fallback order | F3 | Planned | No undeclared route is reachable |
| TRN-011 | Translation transcription task | F4 | Planned | Source preservation and target-language evaluation pass |
| TRN-012 | Local/BYOK model comparison | F2 | Planned | Same source audio can produce versioned comparable results |
| MOD-001 | Model download and management | F0 | Current | Install, activate, select, and remove tests pass |
| MOD-002 | Full SHA-256 verification before activation | F0 | Current | Corrupt assets never become active |
| MOD-003 | Atomic model activation and rollback | F0 | Current | Interrupted install preserves last working model |
| MOD-004 | Capability metadata per model/provider | F3 | Planned | UI never offers unsupported operations |
| MOD-005 | Model quality and hardware recommendations | F3 | Planned | Recommendations derive from measured device data |

## Preview, Flow Bar, and Dictation Control

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| FLOW-001 | Non-activating Flow Bar | F0 | Current | Target focus remains unchanged |
| FLOW-002 | Listening, finalizing, inserting, success, and failure states | F0 | Current | State-machine and UI tests pass |
| FLOW-003 | Live transcription preview inside Flow Bar | F3 | Planned | Clearly provisional and never inserted directly |
| FLOW-004 | Language, profile, model, and provider indicators | F3 | Planned | Display always matches captured session policy |
| FLOW-005 | Elapsed time and audio-device indicators | F3 | Planned | Long-session and device-change states remain accurate |
| FLOW-006 | Push-to-talk dictation | F0 | Current | Shortcut lifecycle and cancellation tests pass |
| FLOW-007 | Hands-free dictation | F0 | Current | Start/stop/cancel state is recoverable |
| FLOW-008 | Command Mode | F0 | Current | Selection remains unchanged on transform failure |
| FLOW-009 | Configurable shortcuts | F3 | Planned | Conflict detection and accessibility pass |

## Recovery and History

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| REC-001 | Recording retention disabled by default | F0 | Current | No raw audio persists without explicit setting |
| REC-002 | Explicit encrypted rolling retention | F2 | Planned | Consent, encryption, expiration, and purge tests pass |
| REC-003 | Suggested seven-day retention policy | F2 | Planned | User can shorten, extend, disable, or purge immediately |
| REC-004 | Interrupted-session recovery | F2 | Planned | Restart/interruption never overwrites source audio |
| REC-005 | Failed-transcription recovery | F2 | Planned | Available audio can be retried before disposal |
| REC-006 | Failed-insertion recovery | F0 | Current | Final text remains reachable and retryable |
| REC-007 | Retranscribe with another model/provider | F2 | Planned | Creates a new immutable result version |
| REC-008 | Aligned transcript diff | F2 | Planned | Insertions, deletions, substitutions, and moved spans are clear |
| REC-009 | Model/provider A/B comparison | F2 | Planned | Accuracy, latency, cost metadata, and text are comparable |
| REC-010 | One-click redacted issue bundle | F2 | Planned | Preview shows every included private field |
| HIST-001 | Encrypted local transcript history | F0 | Current | Payload encryption and tamper tests pass |
| HIST-002 | Keyed blind-index search | F0 | Current | Searchable plaintext is absent from storage |
| HIST-003 | Raw and final transcript versions | F2 | Planned | Provenance is immutable and queryable |
| HIST-004 | Provider/model/language/profile provenance | F2 | Planned | Every result identifies its processing route |
| HIST-005 | Retained-audio playback | F2 | Planned | Playback never decrypts to a persistent plaintext file |
| HIST-006 | Search, copy, retry, export, report, and delete actions | F2 | Partial | All actions operate on immutable result versions |
| HIST-007 | Secure cascading audio deletion | F2 | Partial | Deleting/expiring a session removes wrapped keys and files |
| HIST-008 | Usage and local quality dashboard | F1 | Planned | Metrics remain local and content-free by default |

## Repair, Grounding, and Personalization

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| CORR-001 | Deterministic filler removal | F0 | Current | Versioned repair corpus passes |
| CORR-002 | Immediate repetition removal | F0 | Current | False-positive regression corpus passes |
| CORR-003 | Restart and abandoned-clause repair | F0 | Current | Versioned repair corpus passes |
| CORR-004 | Explicit cross-pause self-correction repair | F0 | Current | Complete transcript is processed exactly once |
| CORR-005 | Spoken punctuation and numbered lists | F0 | Current | Formatting fixtures pass |
| CORR-006 | Protected-detail grounding | F0 | Current | Zero invented protected entities in release corpus |
| CORR-007 | Optional BYOK text transformation | F3 | Planned | Grounding and provenance gates pass |
| CORR-008 | Post-insertion correction detection | F3 | Planned | Learning runs only on reliably observed localized edits |
| CORR-009 | Correction review queue | F3 | Planned | No learned rule becomes global without review |
| CORR-010 | Per-profile correction rules | F3 | Planned | Scope and precedence are deterministic |
| PERS-001 | Dictionary management | F0 | Current | Validation, duplicates, import, and export tests pass |
| PERS-002 | Voice snippets | F0 | Current | Trigger collision and expansion tests pass |
| PERS-003 | Custom writing instructions | F3 | Planned | Instructions are scoped, previewable, and grounded |
| PERS-004 | Shareable dictionary/snippet/profile bundles | F6 | Partial | Signed/previewed import cannot silently overwrite data |

## Languages

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| LANG-001 | Expose all languages supported by the active model/provider | F3 | Planned | Unsupported combinations are hidden or disabled |
| LANG-002 | Verified quality tier | F3 | Planned | Dedicated corpus and native-speaker review pass |
| LANG-003 | Community-tested quality tier | F3 | Planned | Reproducible contributed corpus and results exist |
| LANG-004 | Experimental quality tier | F3 | Planned | UI makes absence of a Murmur quality claim explicit |
| LANG-005 | Per-language correction and formatting rules | F3 | Planned | Rules never silently apply across languages |
| LANG-006 | Community language evaluation packs | F6 | Planned | Packs are versioned, validated, licensed, and reproducible |

## BYOK Providers and Context

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| BYOK-001 | OpenAI provider adapter | F3 | Planned | Audio and text capability contract tests pass |
| BYOK-002 | OpenAI-compatible endpoint adapter | F3 | Planned | Capability probe and response fixtures pass |
| BYOK-003 | API keys stored in Keychain | F3 | Planned | Keys never enter preferences, logs, or exports |
| BYOK-004 | Separate audio and text transmission consent | F3 | Planned | Profile UI and request builder enforce scopes |
| BYOK-005 | Request scope preview | F3 | Planned | User can inspect audio/text/context categories before activation |
| BYOK-006 | HTTPS remote and HTTP-loopback endpoint policy | F3 | Planned | Invalid or unsafe endpoint configurations are rejected |
| BYOK-007 | Timeouts, size limits, cancellation, and response validation | F3 | Planned | Malformed/adversarial provider fixtures fail safely |
| BYOK-008 | Cost and latency metadata where available | F3 | Planned | Estimates are labeled and never expose content |
| CTX-001 | Application identity context | F3 | Planned | Permission is visible and profile-scoped |
| CTX-002 | Browser-domain rules | F3 | Planned | Domain matching handles subdomains and private browsing safely |
| CTX-003 | Selected-text context | F3 | Planned | Selection is unchanged on failure |
| CTX-004 | Nearby-text context | F3 | Planned | Bounded extraction and explicit provider disclosure pass |
| CTX-005 | Workspace vocabulary context | F3 | Planned | Only approved terms leave the workspace boundary |
| CTX-006 | Context permission inspector | F3 | Planned | Effective local and remote context is explainable per session |

## Profiles, Modes, and Writing Workflows

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| PROF-001 | Local profiles | F3 | Planned | Profiles require no account and are independently exportable |
| PROF-002 | Application rules | F3 | Planned | Deterministic matching and precedence tests pass |
| PROF-003 | Website rules | F3 | Planned | URL permission and matching tests pass |
| PROF-004 | Provider/model/language routing | F3 | Planned | Captured session policy cannot mutate mid-session |
| PROF-005 | Context permission routing | F3 | Planned | Effective scopes are inspectable before use |
| PROF-006 | Explicit fallback routing | F3 | Planned | Only declared routes are reachable |
| PROF-007 | Formatting and auto-submit behavior | F3 | Planned | Auto-submit is app-scoped and insertion-verified |
| MODE-001 | Plain dictation mode | F0 | Current | No stylistic rewrite beyond enabled deterministic processing |
| MODE-002 | Message mode | F3 | Planned | App-aware formatting and grounding pass |
| MODE-003 | Email mode | F3 | Planned | Greeting/body/signoff behavior is context-safe |
| MODE-004 | Document mode | F3 | Planned | Paragraph/list formatting corpus passes |
| MODE-005 | AI prompt mode | F3 | Planned | Technical terms and explicit wording are preserved |
| MODE-006 | Developer mode | F3 | Planned | Code, identifiers, terminal, and tool vocabulary corpus passes |
| MODE-007 | Meeting-note mode | F5 | Planned | Speaker and action-item provenance remains traceable |
| MODE-008 | User-defined mode | F3 | Planned | Instructions, context, provider, and output are previewable |

## Insertion and Application Compatibility

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| INS-001 | Original target capture and revalidation | F0 | Current | Focus changes cannot paste into the wrong application |
| INS-002 | Transactional clipboard paste | F0 | Current | User clipboard is restored only when still owned by Murmur |
| INS-003 | Clipboard-manager privacy markers | F0 | Current | Dictated text is marked transient/concealed where supported |
| INS-004 | Active-layout keyboard shortcut resolution | F0 | Current | Layout round-trip tests pass |
| INS-005 | Physical-modifier quiescence | F0 | Current | Held modifiers cannot corrupt the paste shortcut |
| INS-006 | Accessibility fallback with verification | F0 | Current | False negatives cannot cause duplicate insertion |
| INS-007 | Secure-input detection and recovery | F0 | Current | Transcript remains recoverable when keystrokes are blocked |
| INS-008 | Terminal-safe insertion | F3 | Planned | Supported terminal matrix passes without shell side effects |
| INS-009 | Application/control compatibility matrix | F1 | Planned | At least 99.5% successful or recoverable outcomes |
| INS-010 | Per-application insertion strategies | F3 | Planned | Strategies are evidence-based and regression-tested |

## Transcription Studio and Export

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| FILE-001 | Audio file import | F4 | Planned | Supported format matrix and malformed-file tests pass |
| FILE-002 | Video file import and audio extraction | F4 | Planned | Duration, channel, and timestamp integrity pass |
| FILE-003 | Batch transcription queue | F4 | Planned | Cancellation, restart, ordering, and resource limits pass |
| FILE-004 | Transcript editor | F4 | Planned | Edits create versions and never mutate source audio |
| FILE-005 | Synchronized audio/video playback | F4 | Planned | Seek and word-highlight alignment stays within threshold |
| FILE-006 | Timestamped segments and words | F4 | Planned | Import, edit, and export preserve timing |
| FILE-007 | Manual speaker assignment | F4 | Planned | Speaker edits are versioned and exportable |
| FILE-008 | Automatic diarization | F5 | Planned | Labeled speaker corpus meets published threshold |
| FILE-009 | Transcript translation | F4 | Planned | Source and translated versions remain linked |
| EXP-001 | Plain-text export | F4 | Planned | Encoding and line-ending tests pass |
| EXP-002 | Markdown export | F4 | Planned | Headings, lists, and escaping tests pass |
| EXP-003 | JSON and CSV export | F4 | Planned | Schema is versioned and documented |
| EXP-004 | SRT and VTT subtitle export | F4 | Planned | Timing and escaping validators pass |
| EXP-005 | PDF export | F4 | Planned | Rendered output is visually verified |
| EXP-006 | DOCX export | F4 | Planned | Generated document is structurally and visually verified |
| EXP-007 | Provenance-rich portable session package | F4 | Planned | Audio inclusion is separately consented and encrypted if requested |

## Meetings

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| MEET-001 | Microphone meeting recording | F5 | Planned | Long-session and recovery gates pass |
| MEET-002 | System-audio meeting recording | F5 | Planned | Permission and supported-application matrix pass |
| MEET-003 | Mixed-source recording | F5 | Planned | Drift and level-balancing thresholds pass |
| MEET-004 | Live meeting transcript/notes | F5 | Planned | Clearly provisional until final reconciliation |
| MEET-005 | Full-recording final reconciliation | F5 | Planned | No live segment can become authoritative by itself |
| MEET-006 | Speaker diarization | F5 | Planned | Quality reported by speaker count and acoustic condition |
| MEET-007 | Action-item and summary mode | F5 | Planned | Claims remain linked to transcript evidence |

## Automation, Integrations, and Plugins

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| AUTO-001 | Command-line interface | F5 | Planned | Stable exit codes, stdin/stdout, and JSON schema |
| AUTO-002 | macOS Shortcuts actions | F5 | Planned | Permission and cancellation behavior pass |
| AUTO-003 | URL scheme | F5 | Planned | Input validation and confirmation for sensitive actions |
| AUTO-004 | Loopback HTTP API | F5 | Planned | Disabled by default, authenticated, scoped, and rate-limited |
| AUTO-005 | Watch folders | F5 | Planned | Duplicate, partial-write, and recursion handling pass |
| AUTO-006 | Raycast integration | F5 | Planned | Uses documented local interfaces only |
| AUTO-007 | Obsidian integration | F5 | Planned | User-selected vault scope and conflict behavior pass |
| AUTO-008 | Permissioned webhooks | F5 | Planned | Per-workflow endpoint and data preview are mandatory |
| AUTO-009 | Local MCP server | F5 | Planned | Disabled by default with generated credentials and scopes |
| PLUG-001 | Provider plugin interface | F6 | Planned | Versioned ABI/API and capability declaration exist |
| PLUG-002 | Post-processor plugin interface | F6 | Planned | Grounding cannot be bypassed by default |
| PLUG-003 | Exporter/action plugin interfaces | F6 | Planned | Filesystem and network capabilities are explicit |
| PLUG-004 | Plugin signing and approval | F6 | Planned | Untrusted bundles cannot activate silently |

## Storage, Synchronization, and Scratchpad

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| STORE-001 | AES-GCM encrypted sensitive records | F0 | Current | Round-trip and tamper tests pass |
| STORE-002 | Keychain-protected master key | F0 | Current | Key never enters backup or plaintext storage |
| STORE-003 | Password-encrypted backup and restore | F0 | Current | Preview, wrong-password, and corruption tests pass |
| STORE-004 | Preview-first library import/export | F0 | Current | Schema, limits, duplicate, and atomicity tests pass |
| SYNC-001 | User-selected encrypted folder synchronization | F6 | Planned | Conflict resolution and deletion semantics are documented |
| SYNC-002 | iCloud Drive synchronization option | F6 | Planned | No hosted Murmur service or hidden content scope |
| SYNC-003 | Self-hosted synchronization endpoint | F6 | Deferred | Protocol is documented and end-to-end encrypted |
| SYNC-004 | Signed team policy/profile bundles | F6 | Planned | Import preview and signer identity are visible |
| SCR-001 | Searchable local Scratchpad | F0 | Current | Search remains encrypted at rest |
| SCR-002 | Pinned multi-tab notes | F0 | Current | Autosave and window lifecycle tests pass |
| SCR-003 | Local note revision history | F0 | Current | Revision pruning and restore tests pass |
| SCR-004 | Dictation/workflow destination | F3 | Planned | Source session provenance remains linked |

## Security, Diagnostics, and Evaluation

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| SEC-001 | Local operation without account or network | F0 | Current | Network-denied end-to-end path passes |
| SEC-002 | No telemetry backend | F0 | Current | Build and network audit find no telemetry path |
| SEC-003 | Redacted diagnostics export | F0 | Current | Private content requires separate explicit opt-in |
| SEC-004 | Per-recording encryption and crypto-shredding | F2 | Planned | Wrapped key deletion makes expired audio unrecoverable |
| SEC-005 | Provider data-flow inspector | F3 | Planned | Effective endpoint and payload categories are visible |
| SEC-006 | Import and community-pack sandboxing | F6 | Planned | Malformed and oversized inputs fail before mutation |
| SEC-007 | Plugin capability permissions | F6 | Planned | Network/filesystem/context/audio scopes are enforceable |
| SEC-008 | Privacy regression tests | F1 | Planned | Content cannot enter logs or unintended requests |
| EVAL-001 | Versioned real/synthetic audio corpus runner | F1 | Planned | Reproducible on baseline hardware |
| EVAL-002 | Phrase-boundary completeness scoring | F1 | Planned | Beginning/middle/end omissions block release |
| EVAL-003 | WER and CER dashboard | F1 | Planned | Reported by model, language, audio condition, and device |
| EVAL-004 | Correction and grounding acceptance corpus | F0 | Current | At least 98% correction resolution and zero invented entities |
| EVAL-005 | Quiet/whisper evaluation corpus | F1 | Planned | Metrics separated from normal-volume speech |
| EVAL-006 | Latency dashboard by duration bucket | F1 | Planned | p50/p95 reported on baseline M1 and current reference Mac |
| EVAL-007 | Application insertion matrix | F1 | Planned | At least 99.5% successful or recoverable outcomes |
| EVAL-008 | Provider contract fixture suite | F3 | Planned | Success, partial, malformed, timeout, and cancellation cases pass |
| EVAL-009 | Long-session memory, energy, and thermal suite | F5 | Planned | Published thresholds block regressions |
| EVAL-010 | Local quality dashboard | F1 | Planned | No dictated content is required for aggregate metrics |

## Platforms and Distribution

| ID | Capability | Phase | Status | Completion gate |
|---|---|---:|---|---|
| PLAT-001 | Native Apple Silicon macOS application | F0 | Current | macOS 15+ build, test, package, sign, and notarize gates |
| PLAT-002 | Signed/notarized free distribution | F1 | Planned | Reproducible release checklist and update authenticity |
| PLAT-003 | Automatic updates without hosted user data | F3 | Planned | Signed feed and rollback behavior pass |
| PLAT-004 | iOS application | F6 | Deferred | macOS quality gates remain unaffected |
| PLAT-005 | Windows application | F6 | Deferred | Shared contracts do not force a lowest-common-denominator Mac UX |
| PLAT-006 | Accessibility and localization baseline | F1 | Partial | VoiceOver, keyboard, contrast, reduced motion, and localization tests |

## Explicit Exclusions

| ID | Capability | Status | Reason |
|---|---|---|---|
| EXC-001 | Murmur-hosted inference | Excluded | BYOK and local inference preserve user control and avoid a hosted service |
| EXC-002 | Murmur accounts and subscription gates | Excluded | Product remains free, MIT, and accountless |
| EXC-003 | Murmur-hosted transcript or audio sync | Excluded | User-owned synchronization replaces vendor custody |
| EXC-004 | Hidden automatic provider fallback | Excluded | Conflicts with explicit routing and informed data transmission |
| EXC-005 | Authoritative streaming-segment stitching | Excluded | Plausible segments can silently omit speech |
| EXC-006 | Default raw-audio retention | Excluded | Recording storage requires explicit user consent |
| EXC-007 | Undifferentiated “100+ languages” quality claim | Excluded | Quality claims must be tied to evidence tiers |
