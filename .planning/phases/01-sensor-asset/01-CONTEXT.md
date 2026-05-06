# Phase 1: Sensor Asset - Context

**Gathered:** 2026-05-06
**Status:** Ready for planning
**Mode:** TDD — tests first, implementation to satisfy them

<domain>
## Phase Boundary

Operators can place a sensor on a page, pick its kind (red light paired beam, optic field, or inductive field), and watch its visual flip live with the PLC bool state key. Each kind is drawn by its own dedicated `CustomPainter`. The active/inactive transition is immediate (no client-side smoothing or animation). Active and inactive colours are configurable per instance with sensible defaults. Edge-delay state keys are configurable but the values are display-only — surfaced via tooltip, not applied to the visual. The asset round-trips through JSON and the `AssetRegistry` such that older saved pages without sensors still load.

This phase delivers the Sensor asset standalone — it does NOT involve the elevator or any child-embedding scenarios.

</domain>

<decisions>
## Implementation Decisions

### Painter & Glyph Design
- Red light paired layout: horizontal default — emitter left, receiver right, beam line spanning the asset width. Vertical orientation is reached via the existing `Coordinates.angle` rotation.
- Optic-field cone: housing on the left side, cone fans out to the right (same axis as the red-light beam for consistency).
- Inductive-field bubble: small puck-style housing with a solid filled ellipse positioned just outside it — matches industry near-field pictograms.
- Beam-line broken-state visual: dashed line in the active accent colour when blocked (bool false per locked beam-polarity decision); solid line in neutral when clear (bool true).

### Config Dialog & Defaults
- Sensor kind selector: `SegmentedButton<SensorKind>` (consistent with `ConveyorGateConfig`'s variant selector pattern).
- Field ordering: Kind → Detection state key → Active polarity → Rising-edge-delay key → Falling-edge-delay key → Active colour → Inactive colour → Label/tag.
- Default kind on first placement: `SensorKind.redLight` (most common photoelectric in conveyor lines).
- Tooltip on hover/longpress shows two lines: "Rising: <ms>ms\nFalling: <ms>ms"; an unconfigured delay key renders as "—".

### State, Stale, & Test Coverage
- Stale stream → render in neutral grey when (a) the detection state key is empty, OR (b) the stream emits null / error / no value yet. Mirrors `conveyor_gate.dart:350` `baseColor = Colors.grey` convention.
- Edge-delay tooltip subscriptions: subscribe to the rising/falling keys only while the tooltip is open; cancel on close (avoids persistent per-instance subscription overhead).
- Default active polarity: `false` (no inversion — bool true means detected).
- Golden test matrix: one golden per (kind × active/inactive) = 6 goldens, plus 2 extra for the polarity-inverted variant of `redLight` = 8 goldens total. Rotation is verified via a dedicated rotation test, not multiplied across the colour matrix.

### TDD Workflow (user directive 2026-05-06)
- All implementation tasks must be sequenced test-first: write the failing test, confirm it fails for the right reason, then write the minimum code to pass, then refactor.
- Commit cadence follows the rhythm `test: …` → `feat: …` (or equivalent) per behaviour.
- Goldens are the preferred test type for visual behaviour; widget tests for tap/gesture; unit tests for pure logic (e.g. polarity inversion, JSON round-trip).

### Gestures Survive Translation (user directive 2026-05-06)
- The Sensor's tap-to-open-config-dialog uses a real `GestureDetector` widget — never painter-only hit detection — so it survives being a child of a moving parent (the elevator in Phase 3).
- Even though Phase 1 ships the sensor standalone, the gesture wiring must already be tap-friendly through arbitrary `Transform.translate` / `Positioned` ancestors. A widget test in this phase covers the standalone tap; Phase 3 adds the mid-translation tap test.

### Claude's Discretion
- Exact colour values for the dashed-line stroke pattern, glyph proportions, and housing-vs-field size ratios are at Claude's discretion as long as they read clearly at typical asset sizes (32–128 px).
- Choice of `Tooltip` widget vs custom overlay for the delay-value popup is Claude's discretion provided the stream lifecycle decision above is honoured.
- Whether to share a small `_paintHousing` helper across optic and inductive painters is Claude's discretion.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BaseAsset` (`lib/page_creator/assets/common.dart`) — base class with `Coordinates.angle` rotation, `text` field, `allKeys` walker.
- `KeyField` config widget — standard state-key picker used by every asset; reuse verbatim for detection key + delay keys.
- `_ColorConverter` annotation pattern (see `led.dart` lines 30–35) — JSON-friendly Color round-trip; copy for sensor's `activeColor`/`inactiveColor`.
- `SegmentedButton<GateVariant>` pattern in `_ConveyorGateConfigEditor` (`conveyor_gate.dart:534+`) — direct analog for `SensorKind` selector.

### Established Patterns
- Per-variant painter dispatch via exhaustive switch in `_createPainter` (`conveyor_gate.dart:240-266`) — replicate for `SensorKind` with one `CustomPainter` subclass per kind (no `switch` inside `paint()`).
- Stale data rendering: when state key is empty or stream has no value, set `baseColor = Colors.grey` (`conveyor_gate.dart:323, 350`).
- StreamBuilder over `stateMan.subscribe(key)` from `stateManProvider` is the canonical wiring.
- JSON round-trip via `json_serializable` with `defaultValue:` and `unknownEnumValue:` annotations for forward compatibility.

### Integration Points
- `AssetRegistry._fromJsonFactories` and `defaultFactories` (`registry.dart`) — register `SensorConfig` with two entries (factory + palette default).
- Build_runner: add `sensor.dart` and `sensor_painter.dart` to the codegen include set; run `flutter pub run build_runner build` for `sensor.g.dart`.
- Test fixture root: `test/page_creator/assets/sensor_test.dart` (mirror existing `test/painter/goldens` structure).

</code_context>

<specifics>
## Specific Ideas

- Default active colour = `Colors.green` (matches `led.dart` convention); default inactive colour = a neutral grey from the existing palette (Claude picks a defensible one, e.g. `Colors.grey.shade400`).
- Dashed beam line: 6-on, 4-off pattern at typical sizes; scales with stroke width.
- Field-sensor active state fills the field shape with the active colour at reduced alpha (~0.4) so the housing stays visible underneath; inactive state outlines the field with the inactive colour.
- Sensor label/tag uses the existing `BaseAsset.text` if it already supports overlay rendering; if not, add a small painter call that draws the label below the glyph.

</specifics>

<deferred>
## Deferred Ideas

- Position-in-mm readout per sensor — captured as SENS-V2-01.
- "Last seen" freshness pip — captured as SENS-V2-02.
- Configurable analog signal-strength fade — captured as SENS-V2-03.

</deferred>
