# Research Summary

**Project:** Elevator & Sensor Assets (tfc-hmi2 milestone)
**Researched:** 2026-05-05
**Sources:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md
**Confidence:** HIGH

## Executive Summary

This milestone adds two new assets to the tfc-hmi2 page creator: a vertical-lift **elevator** that translates assigned child assets in sync with a PLC 0–100% position key, and a multi-kind **sensor** that visualises detection state from a bool state key (red light beam, optic field, inductive field). Both are brownfield extensions of established codebase patterns — no new frameworks, no new packages, no registry surgery. The recommended approach is direct copy-and-adapt from `conveyor.dart` (`ChildGateEntry` child-embedding) and `conveyor_gate.dart` (variant-dispatch painter, `AnimationController` + `ValueNotifier`, config editor) with two targeted deviations: `TweenAnimationBuilder<double>` for the elevator's continuous-target position, and per-kind `CustomPainter` subclasses for the sensor (never a `switch` inside `paint()`).

The key risks are architectural, not technology-related. Four pitfalls demand up-front design decisions before production code begins:
1. Child widget identity loss when elevator position changes — every child needs a stable `ValueKey` derived from a UUID on `ElevatorChildEntry`.
2. OPC UA stream resubscribe storms if streams are constructed inline in `build()` rather than hoisted to `initState`.
3. Painter state leakage when sensor kind changes.
4. Y-axis off-by-one in the bbox-to-platform mapping.

Five open design questions from FEATURES.md must be answered at requirements time:
- Does `BaseAsset` already carry a rotation field?
- What colour does `led.dart` use for its active state?
- Is there a shared stale-stream painter helper convention?
- Does active-polarity inversion ship in v1 or defer?
- What's the beam-line broken-state colour polarity (dark-on vs light-on)?

## Key Findings

### Stack — add nothing

Flutter 3.41.9, Riverpod 2.6, RxDart 0.28, `json_serializable`, `build_runner`, and the SDK animation/painting primitives cover every requirement.

- **Elevator:** `TweenAnimationBuilder<double>` for continuous-target re-targeting, no manual `animateTo` churn.
- **Sensor:** plain `StreamBuilder<bool>` with no animation.
- **Both:** `CustomPainter` + `ValueListenable` for paint-only updates that bypass build/layout.

### Features

**Elevator — table stakes:**
- Rails + platform glyph
- Live position from `positionKey` (0–100% → platform Y; 0% bottom, 100% top)
- Numeric % readout
- Children translate with platform
- Child-assignment dropdown in config dialog
- Out-of-range and stale-data visual
- Backwards-compatible JSON

**Sensor — table stakes:**
- Three `SensorKind` painters:
  - Red light: emitter + receiver + beam line
  - Optic field: housing + cone
  - Inductive field: housing + near-field bubble
- Bool `detectionKey` flips active/inactive immediately (no client-side delay)
- Beam line itself changes appearance with active state
- Tooltip showing rising/falling edge-delay values (display-only)
- Rotation handling
- Backwards-compatible JSON

**Deferred to v2+:** position in mm, direction arrow, soft-limit zones, signal-strength tint, freshness pip, discrete floor labels.

### Architecture

- `ElevatorConfig` extends `ConveyorConfig`'s child-list pattern.
- `SensorConfig` extends `ConveyorGateConfig`'s variant-dispatch pattern.
- **Position pipeline:** `StateMan.subscribe(positionKey)` → stream hoisted to `initState` → `ValueNotifier<double>` → `ValueListenableBuilder` → `Positioned.top = platformOffsetTop(progress, height, platformHeight)`.
- Children live inside the elevator's local `Stack`; their own subscriptions are fully independent.
- The `allKeys` override on `ElevatorConfig` must flat-map children's keys.

### Top 5 Pitfalls

1. **Child identity loss** — stable `ValueKey<String>` from UUID on `ElevatorChildEntry`; constant wrapping structure at all positions; `ValueListenableBuilder.child:` caches the child subtree.
2. **Stream resubscribe storm** — hoist all `stateManProvider.future.asStream().asyncExpand(...)` out of `build()`; store in `State` field; one monitored item per key per widget.
3. **Painter state leakage** — one `CustomPainter` class per `SensorKind`; `shouldRepaint` returns `true` when `runtimeType` differs; per-kind `AnimationController` disposed on kind change.
4. **Y-axis off-by-one** — single `platformOffsetTop(position, bboxHeight, platformHeight)` helper; unit-tested at 0/0.5/1.0 before any visuals.
5. **JSON migration** — `@JsonKey(defaultValue: [])` on all list fields; `@JsonKey(unknownEnumValue:)` on all enum fields; full `ElevatorChildEntry` wrapper shape from day one; legacy-JSON round-trip test in same PR as schema.

## Roadmap Implications

**Suggested phases: 4**

1. **Sensor — config, painters, and golden tests**
   Simpler (no children, no positional layout); establishes per-kind painter conventions, `shouldRepaint` contract, and golden determinism before elevator painters are written. Requires five codebase lookups before definition: `BaseAsset` rotation field, `led.dart` active colour, stale-stream helper convention, active-polarity decision, beam-line polarity convention.

2. **Elevator — config, static visuals, and position pipeline**
   Establishes the data pipeline (position key → `ValueNotifier` → `Positioned` platform) without child embedding complexity. Validates the animation path (Pitfalls 2, 4) independently. `ElevatorChildEntry` JSON schema defined with full wrapper shape (UUID, offsetX, child) even though children list is empty in this phase.

3. **Elevator — child embedding, editor, and integration**
   Depends on Phases 1 and 2. Highest-complexity phase: child identity (`ValueKey`), hit-testing through translated parents, child-list config editor, `_childrenFromJson` backwards-compat shim, `allKeys` override.

4. **Polish, error states, and CI hardening**
   Grey/fault rendering on stale stream; multi-elevator smoke test; golden CI matrix; `LeakTesting.enable()` mount/unmount tests; rotation test matrix (0°/90°/180°/270° × on/off elevator).

**Phase ordering rationale:** Sensor first separates painter conventions from layout math. Static elevator second separates animation pipeline risk from child-identity risk. Polish last avoids scope creep in core phases. JSON schema locked in Phase 2 (not Phase 3) to prevent the wrapper-promotion migration trap.

## Research Flags

**Needs codebase lookup before Phase 1 definition** (5-minute `Read` calls, not full research):
- Does `BaseAsset`/`Coordinates` already carry a rotation field?
- What colour does `led.dart` use for active state?
- Is there a shared stale-stream painter helper?

**Standard patterns (no further research needed):**
- Phase 2: `TweenAnimationBuilder` + `ValueNotifier` — verified against Flutter API docs; established in `conveyor_gate.dart`.
- Phase 3: Child embedding — established in `conveyor.dart` `_positionedChildGate` + `_gatesFromJson`.
- Phase 4: `LeakTesting.enable()` — standard Flutter test; golden CI matrix — additive to existing infra.

## Confidence Assessment

Overall: **HIGH**

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Direct codebase inspection + Flutter API doc verification |
| Features | MEDIUM-HIGH | ISA-101 solid; five open codebase questions need answers before Phase 1 definition |
| Architecture | HIGH | Every pattern has exact file/line citations |
| Pitfalls | HIGH | Grounded in existing `CONCERNS.md` + ConveyorGate post-mortem |

**Gaps:** active colour convention (`led.dart`), `BaseAsset` rotation field, stale-stream helper, active-polarity v1/v2 decision, beam-line polarity convention. All five are codebase reads, not external research.

---
*Synthesized from project research: 2026-05-05*
