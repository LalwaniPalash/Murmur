# Design

<!-- impeccable:design-schema 1 -->

Recorded from the built world, not from intention. Seed key `7acc830d`, assigned
direction index 6. See `PRODUCT.md` for product truth; this file owns visual decisions
only.

## World

**Engraved Panel.** Murmur presents as equipment rather than as an app. The surface is an
anodised faceplate: legends are engraved caps cut into the finish, values are read against
printed scales, and state is reported by lamps that are either on or off.

The category default this refuses: the rounded floating pill with animated waveform bars,
translucent sidebar, and rounded content cards that every local dictation tool ships. The
predictable opposite — terminal-green monospace "local-first hacker" — is refused too.

Two anodizings of one panel:

| | Light | Dark |
|---|---|---|
| Finish | natural silver anodize | black anodize |
| Engraving fill | graphite | bone |

This is why the app has two appearances. It is one object photographed under two
finishes, not a palette with inverted tokens. The app follows the system appearance;
there is no in-app override.

## Colour

Strategy: **Restrained** — achromatic panel plus one record red, with a verify green
reserved solely for grounded/inserted confirmation. Nothing else on the panel is coloured.

Defined in `Sources/MurmurNext/DesignSystem/MurmurTheme.swift`.

| Token | Light | Dark | Use |
|---|---|---|---|
| `Finish.panel` | `#D8D9D5` | `#151614` | the panel face content sits on |
| `Finish.chassis` | `#C6C8C2` | `#0F100E` | the legend column, cut heavier |
| `Finish.plate` | `#F0F1EE` | `#262723` | a plate raised off the panel |
| `Finish.recess` | `#D3D5D0` | `#121311` | a milled well: fields, tracks |
| `Finish.seat` | `#DCDED8` | `#2B2C27` | the selected legend's seat |
| `Engraving.ink` | `#1E201D` | `#E9EAE5` | primary legend fill |
| `Engraving.secondary` | `#4B4F48` | `#ACAFA5` | secondary legends |
| `Engraving.tertiary` | `#5F635B` | `#8D9187` | micro-legends, held ≥4.5:1 on `plate` |
| `Engraving.scribe` | black 16% | white 16% | hairline scribe rule |
| `Engraving.scribeStrong` | black 30% | white 28% | panel division |
| `Lamp.record` | `#B83227` | `#E24A34` | lit only while audio is being captured |
| `Lamp.verify` | `#2F6B41` | `#53A468` | lit only on grounded/inserted confirmation |
| `Lamp.caution` | `#8F5D12` | `#D69A3C` | faults and unverified transfers |

Colours are `NSColor(name:dynamicProvider:)` so appearance resolution is the system's, not
a manually threaded environment value.

### Lamp discipline

A lamp that is always lit carries no information and becomes the loudest thing on screen.
The first build lit a verify lamp on every history row; it was removed. A lamp earns its
place only where the state it reports actually varies — the active model in Engine, a
granted permission in commissioning, capture in the Flow Bar.

## Type

Three voices, each with one job.

| Voice | Face | Use |
|---|---|---|
| Legend | **Archivo Condensed** (bundled, OFL) | all engraved lettering — always caps, always positive tracking |
| Body | SF Pro | transcripts, descriptions, note bodies |
| Readout | SF Mono | measured values only: dB, durations, byte counts, times, rates |

Archivo Condensed ships in the app under the SIL Open Font License
(`Sources/MurmurNext/Resources/Fonts/`), registered at first use via
`CTFontManagerRegisterFontsForURL`. If the resource bundle is ever missing, the fallback
is `NSFont.systemFont(width: .condensed)` — condensed, never the default width.

SF Pro is deliberately *not* the display voice; it is the body voice, which is what keeps
the app feeling native without the identity collapsing into stock macOS.

Monospace is confined to measurement. It is never used as a costume for "technical".

Legend sizes and tracking (`Legend.Size`): title 19/1.8, section 11.5/1.35,
control 11/1.35, micro 9.5/1.1.

## Geometry

A panel is rectilinear. Edge breaks are machined, not app rounding.

- `Edge.plate` 3 · `Edge.control` 2.5 · `Edge.flowBar` 5
- Space scale: 1, 4, 8, 12, 18, 28, 44
- Content column max width 880; legend column 194

Depth is physical: plates carry an offset shadow (`y: 1`, radius 3) and sit *above* the
panel; recesses carry an inner shadow and sit *below* it. There is no zero-offset halo.

## Components

`Sources/MurmurNext/DesignSystem/PanelComponents.swift`.

| Component | Role |
|---|---|
| `Legend` | engraved lettering, four optical sizes |
| `ScribeRule` | hairline scribe; `ticks: true` adds the end ticks of a panel division |
| `Plate` | raised plate. Plates never nest |
| `Recess` | milled well for anything typed or read into |
| `Lamp` | on or off; an unlit lamp is a dark bezel, never absent |
| `LevelMeter` | fixed-scale segment ladder in dBFS |
| `Readout` | tabular value against a micro-legend |
| `SpecLine` | legend left, measured value right |
| `PanelButtonStyle` | primary / secondary / destructive |
| `PanelToggleStyle` | machined slide switch |
| `PanelSwitch` | legend + optional detail + switch |
| `PanelField` | recessed field |
| `PanelPage` / `PanelSection` | page and division scaffolds |
| `BlankPlate` | empty state engraved into the panel, not illustrated on it |
| `StatusLine` | one-line outcome against a lamp |
| `MurmurMark` | five bars; never animates |

### Refused in this world

- Stock SwiftUI controls inside the committed form. The system toggle's blue exists
  nowhere else in the palette, so `PanelToggleStyle` replaces it everywhere.
- Cards as page structure. Lists are rows scribed into one plate, not a plate each.
- The kicker/eyebrow above a heading (removed from the old `PageHeader` outright).
- The hero-metric row. Usage totals are a foot strip below the content they describe.
- Fake screws, bevels, brushed-metal gradients, photographic texture, glow. The world
  lives on material and lettering; adding those turns it into a 2008 skeuomorph.
- Decorative motion. The only animations are the meter's 90ms level ease and the
  switch's 120ms throw.

## Surfaces

### Hub

Legend column (chassis) + panel. Four destinations: `RECORD`, `VOCABULARY`, `ENGINE`,
`SCRATCHPAD`. Selection is a milled seat plus a 2pt ink bar, never a filled pill.

The key legend is engraved at the foot of the column, where a real device prints it. This
replaced a Help destination whose whole content was three sentences.

### Record

Day groups; each group is one ledger plate with rows separated by scribe rules. The source
application is named once per run of consecutive rows, not repeated on every line. Time is
right-aligned in a fixed 62pt tabular column. Row actions occupy their width permanently
and fade in on hover, so revealing them cannot reflow the transcript.

### Vocabulary

Terms, snippets, and style on one panel as three scribed divisions. These were three
sibling destinations running the same list-with-add-sheet page.

### Engine

Models as specification rows. Speed / quality / size sit in fixed-width right-aligned
columns (62 / 74 / 68) so they read down the page as a real spec table. `Install` is
secondary rank: seven filled slabs would make installing look like the page's purpose when
reading the specs is.

### Onboarding

A commissioning checklist. All four steps stay on the panel with a lamp against each; only
the current step opens. Progress is legible without a progress indicator, and it replaced
four full-screen icon-circle-eyebrow cards.

### Flow Bar

The device, not the panel — **always black-anodised in both appearances**, because it
floats over unknown application content and a real recorder's status plate does not change
finish with the room.

**Every state shares one size (246×42), faults included.** The four bouncing capsules are
replaced by a fixed-scale 22-segment ladder over a printed scale with marks at floor, −40,
−20, and the caution point. The record lamp is lit only while audio is genuinely being
captured.

The bar's legend is tracked caps, which is a legend voice: it carries a label, never a
sentence. Faults therefore render a two-or-three-word label plus at most one recovery
action in the readout voice — `ON CLIPBOARD  ⌘V to paste` — sourced from
`TextInsertionError.flowBarLabel` / `.flowBarRecovery`. The full explanation stays on
`DictationOrchestrator.lastError` for a Hub surface. Putting a recovery sentence in the
bar's own voice is the mistake this rule exists to prevent.

`FlowBarFace` is driven entirely by values, not by the controller, so any state can be
rendered without a live dictation. `FlowBarStateGallery` (env `MURMUR_UI_GALLERY=1`)
renders all twelve at once; use it rather than provoking real faults.

### Settings

Native macOS `TabView` chrome — this is the most convention-bound window in a Mac app and
fighting it would cost more than it buys. Panel language inside every tab. Six tabs,
reduced from thirteen sidebar sections.

## Boundaries

- The Flow Bar's fixed dark finish is deliberate and must not be made appearance-reactive.
- `PanelPage`'s 880pt content cap keeps transcript measure readable; do not remove it.
- Any new control gets a panel component. Reaching for a stock control is the failure mode
  this system exists to prevent.
