# Phase 2: Elevator Foundation - Context

**Gathered:** 2026-05-06
**Status:** Ready for planning
**Mode:** TDD — tests first, implementation to satisfy them

<domain>
## Phase Boundary

Operators can place an elevator on a page, point its position state key at a PLC 0–100% value, and watch the platform glide vertically inside the bbox. The data pipeline is hoisted to `initState`; rebuilds are scoped to `TweenAnimationBuilder` (no full-tree setState). Stale-stream rendering matches the sensor convention (grey rails). JSON / registry round-trip is locked, including the future-proof `ElevatorChildEntry` wrapper schema (UUID + offsetX + child) — even though the children list is empty in this phase.

This phase delivers the empty (no children) elevator standalone. Phase 3 fills the children list and renders them as Positioned overlays.

</domain>

<decisions>
## Implementation Decisions

### Visual & Position Pipeline
- Rails: two thin vertical lines flanking the platform width, neutral grey, proportional stroke width (matches sensor inactive convention).
- Platform deck: filled rectangle slightly inset from rails, height = 8% of bbox height (proportional, like ConveyorGate constants).
- Animation: `TweenAnimationBuilder<double>` driven by stream values; rebuilds scoped to the wrapped subtree only (no separate ValueNotifier).
- Position interpretation: raw stream value clamped to [0, 100] → divided by 100 → progress 0..1. 0% = platform at bottom, 100% = top.
- `platformOffsetTop(progress, bboxHeight, platformHeight)` is a pure top-level function, unit-tested at progress {0, 0.5, 1} BEFORE any visuals (QUAL-04).

### Schema & Registration
- `ElevatorChildEntry` schema is locked from day one in this phase, even though children list stays empty:
  - `id: String` (UUID-style identifier, used for ValueKey in Phase 3)
  - `offsetX: double` (0..1, lateral position on the platform)
  - `child: BaseAsset` (polymorphic via existing AssetRegistry — `_childFromJson` / `_childToJson` round-trip)
- `ElevatorConfig.children: List<ElevatorChildEntry>` defaults to `[]` via `@JsonKey(defaultValue: <fn>)`.
- UUID source: `DateTime.now().microsecondsSinceEpoch.toString()` (no new package dependency — micros are sufficient for per-asset child uniqueness; switch to `package:uuid` later only if a real collision risk surfaces).
- Registry: register `ElevatorConfig` in both `AssetRegistry._fromJsonFactories` AND `defaultFactories` in `lib/page_creator/assets/registry.dart` (Pitfall 5 — mirror the Sensor registration pattern from Plan 01-05).

### Stale, Out-of-Range, & Tests
- Stale stream → subdued grey rails + grey platform when (a) positionKey empty, OR (b) stream emits null / error / no value yet. Mirrors `sensor.dart` convention which mirrors `conveyor_gate.dart:350`.
- Out-of-range visual (>100% or <0%): NOT in this phase — clamp silently to [0, 100]. Punted to Phase 4 (ELEV-15 mapped there in ROADMAP).
- Goldens: 4 in this phase — `stale.png`, `position_0.png`, `position_50.png`, `position_100.png`. Establishes platform-position baseline; child-overlay goldens are added in Phase 3.

### TDD Workflow (user directive)
- Test → confirm fail → implement → confirm pass → refactor (optional).
- Commit cadence: `test: …` then `feat: …` per behaviour.
- `platformOffsetTop` unit tests land BEFORE any painter or widget code.

### GestureDetector Compat (forward-compat for Phase 3)
- The elevator widget itself uses `GestureDetector` for tap-to-configure (mirror Sensor pattern), so when an elevator is later nested inside another animated parent, the gesture survives translation.
- Children (Phase 3) will be wrapped in `Positioned` whose `top` follows the platform Y — this means hit-test geometry naturally follows visual position (Flutter's hit-test walks the layout tree, not paint offsets).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BaseAsset` — `Coordinates.angle` rotation, `text` field, `allKeys` walker, `coordinates`, `size`.
- `KeyField` — state-key picker (reuse for positionKey).
- `_ColorConverter` — JSON Color round-trip (used for any optional rail/platform colour overrides).
- `AssetRegistry.parse(json)` — polymorphic deserialisation for the `child` field of `ElevatorChildEntry`.
- Sensor's `_buildSensor` + `GestureDetector` + `LayoutRotatedBox` chain — direct precedent.

### Established Patterns
- Streams hoisted to `initState`; never reconstructed in `build()` (Pitfall 2).
- Stale stream → `Colors.grey` baseline (sensor / conveyor_gate convention).
- JSON via `json_serializable`: `@JsonKey(defaultValue:)` on optional fields, `@JsonKey(unknownEnumValue:)` on enums, custom `fromJson`/`toJson` helpers for polymorphic fields.
- `TweenAnimationBuilder<double>` for continuous-target animation (vs `AnimationController` for binary state).

### Integration Points
- `AssetRegistry._fromJsonFactories` and `defaultFactories` in `registry.dart` — same pattern as Plan 01-05's Sensor registration (must be in BOTH).
- `pubspec.yaml` — no new dependencies needed.
- Test fixture root: `test/page_creator/assets/elevator_config_test.dart`, `elevator_widget_test.dart`, `elevator_painter_test.dart`, plus a single-test file `platform_offset_test.dart` for the helper.

</code_context>

<specifics>
## Specific Ideas

- Tween duration: 250ms `Curves.linear` initial default (research recommendation). Configurable per instance via optional `tweenDurationMs` field in ElevatorConfig (defaults to 250, can be tuned post-merge).
- Default rail width: `kRailStrokeWidth = bboxShortestSide * 0.04` (matches sensor field stroke fraction).
- Default platform height: `kPlatformHeightFraction = 0.08` (8% of bbox height).
- Default rail inset: rails sit at 10% and 90% of bbox width (centered, leaving room for child overhang in Phase 3).

</specifics>

<deferred>
## Deferred Ideas

- Out-of-range coloured outline → ELEV-15 mapped to Phase 4.
- Direction arrow / motion pip → ELEV-V2-03.
- Top/bottom position labels → ELEV-V2-01.
- Position readout in mm → ELEV-V2-02.
- Discrete floor labels → ELEV-V2-05.
- Soft-limit zones → ELEV-V2-04.

</deferred>
