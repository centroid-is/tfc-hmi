# Phase 2: STBDDO3705 (16-Ch Digital Output) - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning
**Mode:** Autonomous smart-discuss (Beckhoff EL2008 / Phase 1 DDI3725 parity accepted)

<domain>
## Phase Boundary

Ship a `STBDDO3705Config` HMI asset cloning STBDDI3725 minus filters, plus an end-to-end manual force-write path. Operators place the module on a page, configure `rawStateKey` + `forceValuesKey` + `descriptionsKey`, see 16 channel LEDs reflect commanded bitmask state in the same column-major 2×8 grid as DDI3725, and tap to open an 8-row × 2-column detail dialog where each row exposes channel state + force segmented-button + description (NO filter inputs — outputs don't have filters). The manual force-write path is genuinely operator-driven: tapping `low`/`high` on the SegmentedButton writes to `forceValuesKey` and the painter reflects in the next frame.

Reuses verbatim from Phase 1: `IO16LedBlockPainter`, `kSTBChannelBitOrder` (LSB-first; same constant), `bitmaskToLedStates` helper, `bodyColor` (Schneider cream), `_combinedStream` pattern, golden harness, `GestureDetector(HitTestBehavior.opaque)` wrapping, JSON back-compat patterns. New: body painter for DDO3705 (output-style label strip + LED legend differentiating from DDI), and a force-write widget test verifying StateMan write end-to-end.

</domain>

<decisions>
## Implementation Decisions

### Bit-Ordering & Force Encoding (Inherited from Phase 1)
- **Bit order:** LSB-first via `kSTBChannelBitOrder` from `lib/painter/advantys_stb/io16.dart` — DO NOT re-declare; import via `show`.
- **Force encoding:** int8[16] array `{0=auto, 1=forcedLow, 2=forcedHigh}` — same as DDI3725.
- **Force collapse:** Forced channels render forced state only (no corner pip). Same as DDI3725.
- **Bit-mapping unit test:** Add a regression test asserting DDO3705 uses the SAME `kSTBChannelBitOrder` constant (compile-time guard preventing drift between DI and DO).

### Detail Dialog UX (Phase 1 minus filters)
- **Layout:** 8 rows × 2 columns, identical row pairing as DDI3725: `(1,9), (2,10), ..., (8,16)`.
- **Per-row content:** Channel index label + state indicator + description `TextFormField` + Force `SegmentedButton {auto, low, high}`. **NO filter ms inputs** (outputs don't have filters — outputs are commanded, not sampled).
- **Force write path:** Tapping `low`/`high` on the SegmentedButton writes to `forceValuesKey` via StateMan. The painter reflects in the next frame. Verified end-to-end by a widget test that drives the dialog interaction and asserts the painter's IOState changes.

### Visual Differentiation from DDI3725
- **Body painter file:** `lib/painter/advantys_stb/ddo3705.dart` (NEW; sibling to `ddi3725.dart`).
- **Top label strip:** Same Schneider blue band with "DDO3705" white text instead of "DDI3725". Same RDY indicator placement.
- **LED block:** Reuses `IO16LedBlockPainter` from Phase 1 verbatim. Same geometry, same palette.
- **Label legend differentiator:** Output module shows "1...16" channel numbers in a SLIGHTLY DIFFERENT visual style — could be label color tint or output-arrow glyph next to each LED. Operator-recognizable as the output module without reading the printed "DDO3705" text. Specific approach: use a small ▸ glyph adjacent to channel numbers (subtle, operator-recognizable). Planner picks final implementation.
- **Bottom blue accent + terminal blocks:** Identical to DDI3725 (same physical base form factor — confirmed by user-provided photo at `.planning/research/photos/DDO3705_front_clean.png`).

### State Semantics (Phase 1 verbatim)
- **Stale palette:** Dim grey LEDs + dim grey RDY (same as DDI).
- **No stale/disconnected distinction.**
- **RDY indicator:** Green when any of the bound keys has emitted; dim grey before any emission.

### Claude's Discretion
- Specific visual differentiator for output vs input (LED legend tint, glyph, label-color delta) — planner picks. Constraint: must produce visually distinct goldens between DDI and DDO at the same channel state.
- Exact widget class name (`STBDDO3705` vs `AdvantysSTBDDO3705` — follow Phase 1 naming).
- Whether detail dialog rows show separate "commanded" and "actual" states (Beckhoff EL2008 collapses them; we follow that)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (imported via `show`)
- `IO16LedBlockPainter`, `kSTBChannelBitOrder`, `bitmaskToLedStates`, `bodyColor`, `IOState` — `lib/painter/advantys_stb/io16.dart` (Phase 1 deliverable, do NOT redeclare).
- `STBDDI3725Config` patterns — reference, not import. Clone the config + widget shape.
- `RowIOView` widget — `lib/page_creator/assets/beckhoff.dart` (Phase 1 uses this; Phase 2 reuses via cross-vendor import — same pattern Phase 1 established).
- `_combinedStream` pattern — see `_STBDDI3725State._combinedStreamCache` in `advantys_stb.dart` (Phase 1 deliverable).
- `_stbAccentBlue` constant — declare at top of `ddo3705.dart` as a local copy of the Schneider corporate blue from Phase 1, or import from `ddi3725.dart` if exported. Planner picks.

### Established Patterns (from Phase 1)
- Single file `lib/page_creator/assets/advantys_stb.dart` — Phase 2 ADDS `STBDDO3705Config` to the same file (no new top-level Dart file).
- Painter file per module: `lib/painter/advantys_stb/ddo3705.dart` NEW.
- Codegen: re-run `dart run build_runner build --delete-conflicting-outputs` after adding `STBDDO3705Config`.
- Tests: add to `test/page_creator/assets/advantys_stb_test.dart` (same single file; Phase 2 adds new test groups).
- Goldens at `test/page_creator/assets/goldens/advantys_stb/ddo3705_*_{light,dark}.png` (10 PNGs: 5 states × 2 themes).

### Integration Points
- `lib/page_creator/assets/registry.dart` — add `STBDDO3705Config` to BOTH `_fromJsonFactories` AND `defaultFactories` (alongside DDI3725).
- `lib/page_creator/assets/advantys_stb.dart` — APPEND `STBDDO3705Config` and `_STBDDO3705` widget (no rewrite of existing DDI code).
- `test/page_creator/assets/advantys_stb_test.dart` — APPEND test groups (5+ new groups: config data shape, body painter, widget mount, detail dialog, force-write end-to-end, golden matrix).

</code_context>

<specifics>
## Specific Ideas

- **Force-write end-to-end widget test** is the DDO3705 differentiator vs DDI3725. Test: pump widget with fake StateMan, open dialog, drive SegmentedButton to `high` on channel 5, verify StateMan.write was called with the expected force array (index 4 = 2), verify the painter LED 5 renders green in the next frame.
- **Cross-DI/DO bit-order canary:** Add a unit test asserting `STBDDO3705Config.bitOrderConstant == STBBitOrder.lsbFirst` (or equivalent — verify the painter's bit-order matches Phase 1's). Prevents accidental drift.
- **Reference photo:** `.planning/research/photos/DDO3705_front_clean.png` (high-res with G-Sat watermark — ignore watermark; canonical for label strip differences).
- **DDI3725 body painter pattern in `lib/painter/advantys_stb/ddi3725.dart`** — Phase 2 painter is structurally identical but ships an output-style legend.

</specifics>

<deferred>
## Deferred Ideas

- Separate "commanded" vs "actual" output state (Beckhoff EL2008 doesn't — defer).
- Output-direction arrow on each LED (could be a v2.1 differentiator if user wants).
- Force timeout / auto-revert (PLC-side concern, OOS).

</deferred>
