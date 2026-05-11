# Phase 1: STBDDI3725 (16-Ch Digital Input) - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning
**Mode:** Autonomous smart-discuss (Beckhoff EL1008 parity accepted in batch)

<domain>
## Phase Boundary

Ship a `STBDDI3725Config` HMI asset that mirrors `BeckhoffEL1008Config` at 16-channel scale. Operators place the module on a page, configure five state keys (raw bitmask / force values / on-filter ms / off-filter ms / descriptions), see 16 channel LEDs reflect live state in a column-major 2×8 grid (channels 1–8 left, 9–16 right), and tap to open an 8-row × 2-column detail dialog with per-channel state + force segmented-button + filter inputs + description field. Bit-ordering and force-encoding semantics are locked via a unit test (Beckhoff convention by default; backend confirmation required before goldens lock). Force collapses raw state in the LED display (no corner pip in v2.0). Full JSON round-trip + back-compat + leak test.

This phase establishes every convention the remaining four phases reuse: `IO16LedBlockPainter` (sibling to `IO8LedBlockPainter`), bit-order constant at painter file top, combined-stream hoisted to `initState`, golden harness with macOS-gated light+dark theme pairs, cream-body discipline, `GestureDetector(HitTestBehavior.opaque)` wrapping, `@JsonKey(defaultValue:)` for back-compat.

</domain>

<decisions>
## Implementation Decisions

### Bit-Ordering & Force Encoding
- **Bit order:** LSB-first (bit 0 = channel 1, bit 15 = channel 16). Matches Beckhoff EL1008 convention. Unit-tested at top of `lib/painter/advantys_stb/io16.dart`. Backend team to confirm before goldens lock; if Schneider Advantys STB uses MSB-first the constant flips and one unit test updates.
- **Force values encoding:** `int8[16]` array (one byte per channel) with `0 = auto`, `1 = forcedLow`, `2 = forcedHigh`. Identical to `BeckhoffEL1008Config.forceValuesKey` semantics.
- **Bit-order constant location:** `kSTBChannelBitOrder` (or similar — planner's call on exact name) lives at the TOP of `lib/painter/advantys_stb/io16.dart`. DDO3705 (Phase 2) imports it via `show` to prevent convention drift between DI and DO modules.
- **Force-collapse rule:** Forced channels render their forced state only. The underlying raw wire state is NOT surfaced (no corner pip, no dual-LED). Matches `BeckhoffEL1008`'s `_ledStates()` collapse. Locked by REQUIREMENTS DDI-05.

### Detail Dialog UX
- **Layout:** 8 rows × 2 columns of `RowIOView`. Each row pairs channels at index `i` (left) and `i+8` (right) — i.e., rows render `(1, 9)`, `(2, 10)`, …, `(8, 16)`. Mirrors `BeckhoffEL1008`'s 4-row × 2-column dialog scaled to 16 channels.
- **Overflow handling:** `SingleChildScrollView` wrapping the rows `Column`. Dialog has a fixed `maxHeight` constraint; scroll engages when content overflows. EL1008 pattern.
- **Filter ms inputs:** `TextFormField` per filter field with `keyboardType: TextInputType.number`, numeric input formatter, and `suffix: 'ms'`. Mirrors `RowIOView` filter widgets verbatim.
- **Force SegmentedButton position:** Trailing in each row (after state indicator + filter inputs). Matches EL1008 layout.

### Visual State Semantics
- **Stale palette (no stream emission yet):** Dim grey LEDs + dim grey RDY indicator. Matches `IO8Painter`'s pre-emission render via `IOState.unknown` (or equivalent).
- **Stale vs disconnected:** No distinction. Both render as grey. Consistent with EL1008's single fallback path. Reduces state-machine complexity in painter + widget; operators can rely on the alarm subsystem (via `allKeys`) for connection-health UX.
- **RDY indicator:** Synthetic "module alive" signal — green when any of the five bound keys has emitted at least one valid value; dim grey before any emission. NO separate `readyKey` PLC binding (firmware-driven on real hardware, like the NIP2311 status LEDs).
- **Body cream color:** `import 'package:tfc/painter/beckhoff/io8.dart' show bodyColor` — Schneider Advantys STB cream and Beckhoff cream are visually indistinguishable (~`Color(0xFFF0EDE5)`). Reusing the constant prevents palette drift and keeps the visual identity coherent across vendor families.

### Claude's Discretion
- Exact bit-order constant name (e.g. `kSTBChannelBitOrder`, `kAdvantysSTBChannelMapping`)
- Exact widget class name (`STBDDI3725` vs `AdvantysSTBDDI3725` — match the class prefix used in the config; planner picks)
- Detail dialog max height constraint (likely 600px to match EL1008 dialog ergonomics)
- RDY indicator visual style (small LED dot vs labeled lamp — match the photo's RDY rendering as best as the painter can show it)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (imported via `show` or extended)
- `BaseLedBlockPainter` — abstract painter base in `lib/painter/beckhoff/io8.dart`. `IO16LedBlockPainter` extends this.
- `IOState` enum — `lib/painter/beckhoff/io8.dart`. Channel states: `low`, `high`, `forcedLow`, `forcedHigh`, `error`, `unknown` (or similar — planner reads exact enum).
- `bodyColor` constant — `lib/painter/beckhoff/io8.dart`. The Schneider cream `Color(0xFFF0EDE5)`. Imported verbatim.
- `RowIOView` widget — `lib/page_creator/assets/beckhoff.dart`. Reused 8 times in the detail dialog.
- `TriangleBoxPainter` — `lib/page_creator/assets/beckhoff.dart`. Force-channel red-border pulse animation in the dialog. Reused.
- `_combinedStream` pattern — `BeckhoffEL1008` widget. Combines all 5 keys into a single `Stream<IO8ChannelStates>`-equivalent record. Duplicate as `_combinedStream16` returning a 16-channel record.
- `KeyField`, `SizeField`, `CoordinatesField` — `lib/page_creator/assets/common.dart`. Used in the configure dialog.

### Established Patterns
- **Painter file convention:** One painter file per module type at `lib/painter/{vendor}/{module}.dart`. `lib/painter/advantys_stb/io16.dart` is NEW (sibling to `io8.dart`).
- **Config class convention:** `@JsonSerializable(explicitToJson: true)`, `factory fromJson`, `Map<String, dynamic> toJson()`, `build(BuildContext)` returning the widget, `configure(BuildContext)` returning the editor body.
- **Codegen convention:** `part 'advantys_stb.g.dart';` at top of `lib/page_creator/assets/advantys_stb.dart`. Run `dart run build_runner build --delete-conflicting-outputs` after schema changes.
- **Stream hoisting (Pitfall M-03):** `_combinedStream` cached in `initState` via `late final`; cancelled in `dispose`. NEVER reconstructed in `build()`.
- **Hit-test (Pitfall QUAL-05):** `GestureDetector(behavior: HitTestBehavior.opaque)` wraps the painter so taps register on transparent gaps in the body.
- **Golden harness (REQUIREMENTS QUAL-01):** Mirror `test/page_creator/assets/elevator_painter_test.dart`: `RepaintBoundary` + unique `Key` + deterministic `SizedBox` + `tester.pump(Duration.zero)` (NEVER `pumpAndSettle()`) + `AlwaysStoppedAnimation(0)` + macOS-gated + light/dark theme pair.

### Integration Points
- **`lib/page_creator/assets/advantys_stb.dart`** — NEW file (single-file convention per ARCHITECTURE research). Contains `STBDDI3725Config` in Phase 1, `STBDDO3705Config` in Phase 2, `STBNIP2311Config` in Phase 3, `STBPDT3100Config` in Phase 4, `AdvantysSTBStackConfig` in Phase 5. ~1,400 LoC total estimated.
- **`lib/painter/advantys_stb/io16.dart`** — NEW. Houses `IO16LedBlockPainter`, the bit-order constant, `IOState16Channel` (or equivalent record), `IO16Widget`.
- **`lib/painter/advantys_stb/ddi3725.dart`** — NEW. The DDI body painter (top label strip + LED block via `IO16LedBlockPainter` + terminal blocks per photo, NOT inaccurate DXF).
- **`lib/page_creator/assets/registry.dart`** — MODIFIED. Add `import 'advantys_stb.dart';` + `STBDDI3725Config.fromJson` and `STBDDI3725Config.preview` factories to BOTH `_fromJsonFactories` and `defaultFactories` maps.
- **`test/page_creator/assets/advantys_stb_test.dart`** — NEW. Bit-mapping unit test (LOCKS the convention), JSON round-trip + legacy-JSON test, widget mount/unmount leak test.
- **`test/page_creator/assets/goldens/advantys_stb/`** — NEW directory. Goldens: `ddi3725_all_off_{light,dark}.png`, `ddi3725_all_on_{light,dark}.png`, `ddi3725_alternating_0xAAAA_{light,dark}.png`, `ddi3725_forced_mix_{light,dark}.png`, `ddi3725_disconnected_{light,dark}.png` — 10 PNGs.

</code_context>

<specifics>
## Specific Ideas

- **Bit-mapping unit test (DDI-04 lock):** Three assertions minimum — `0x0001 → only channel 1 lit`, `0x8000 → only channel 16 lit`, `0xAAAA → channels 2,4,6,8,10,12,14,16 lit`. The constant `kSTBChannelBitOrder` (LSB-first) gates these. If Schneider's actual convention is MSB-first, flip the constant + flip the assertions; the painter math doesn't change.
- **Reference materials staged at:**
  - `.planning/research/dxf/IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf` — DXF outline (terminal-block geometry INACCURATE; use photo)
  - `.planning/research/photos/DDI3725_front_clean.png` — canonical for terminal-block geometry (2×18-pin) + LED label arrangement
  - `.planning/research/photos/momentum_stack_in_panel.png` — column-major 2×8 LED layout confirmation
- **Force-key write path (DDI vs DDO):** DDI3725 typically only READS `forceValuesKey` (the operator sets the PLC's force state via SCADA, not from this HMI). Force write paths land in Phase 2 (DDO3705) where outputs are genuinely operator-driven.

</specifics>

<deferred>
## Deferred Ideas

- Corner pip surfacing raw state under force (commissioning win — DDI-FUT-01 in REQUIREMENTS)
- Group-of-8 fuse status indicator (OOS-04)
- Per-channel current readback (OOS-03)
- 4-state-per-channel data model with raw + force as orthogonal fields (deferred to v2.1)
- Generalised `IONLedBlockPainter` parameterised by channel count (PAINTER-FUT-01)

</deferred>
