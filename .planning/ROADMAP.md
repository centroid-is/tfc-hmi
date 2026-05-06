# Roadmap: Elevator & Sensor Assets

## Overview

Two new HMI assets — a vertical-lift elevator carrying child assets and a multi-kind sensor visualiser — delivered in four phases. Phase 1 ships the standalone Sensor asset (simpler; establishes per-kind painter and golden-test conventions). Phase 2 ships the elevator's config + static visuals + position pipeline (validates the data path independently of child-embedding risk). Phase 3 wires children onto the platform (highest complexity: identity, hit-testing, allKeys, editor). Phase 4 hardens the assets for production (error UX, leak tests, multi-elevator smoke). Each phase is a verifiable user-facing deliverable; no horizontal layering.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Sensor Asset** - Multi-kind sensor renders detection state from a bool state key, with config dialog, painters, and goldens
- [ ] **Phase 2: Elevator Foundation** - Elevator config + static visuals + position-driven platform pipeline (no children yet)
- [ ] **Phase 3: Elevator Child Embedding** - Children translate with the platform; editor dropdown adds/removes/edits children
- [ ] **Phase 4: Polish, Error UX & CI Hardening** - Out-of-range fault outline, leak tests, multi-elevator smoke

## Phase Details

### Phase 1: Sensor Asset
**Goal**: Operators can place a sensor on a page, pick its kind, and watch its visual flip live with the PLC bool state key — with each kind drawn by its own painter, immediate (un-smoothed) state response, configurable colours, edge-delay tooltips, and full JSON / registry round-trip.
**Depends on**: Nothing (first phase)
**Requirements**: SENS-01, SENS-02, SENS-03, SENS-04, SENS-05, SENS-06, SENS-07, SENS-08, SENS-09, SENS-10, SENS-11, SENS-12, SENS-13, SENS-14, SENS-15, SENS-16, SENS-17, QUAL-01, QUAL-02, QUAL-05
**Success Criteria** (what must be TRUE):
  1. Operator can place a Sensor asset from the palette, choose one of three kinds (red light, optic field, inductive field) in the config dialog, and see the kind-specific glyph render on the page.
  2. The sensor's active/inactive visual flips immediately when the bool state key changes (red-light beam swaps solid/dashed; field kinds swap filled/outlined), with no client-side smoothing or animation lag.
  3. Operator can configure rising-edge and falling-edge delay state keys, an active-polarity inversion toggle, a per-instance label/tag, and active/inactive colours; the tooltip on hover reveals the resolved edge-delay values.
  4. Sensor renders neutral grey when the state stream is stale or disconnected, honours `Coordinates.angle` rotation, and saved pages without sensor instances continue to load (back-compat).
  5. JSON serialization round-trips for every field with defensible defaults, and golden tests pass for each `SensorKind` × {active, inactive} combination with `shouldRepaint` returning true on `runtimeType` change.
**Plans**: 5 plans
- [ ] 01-01-PLAN.md — SensorConfig data model + JSON round-trip + polarity helper (TDD)
- [ ] 01-02-PLAN.md — Three CustomPainter classes + 8-golden matrix + stale golden (TDD)
- [ ] 01-03-PLAN.md — Sensor widget: GestureDetector tap, hoisted stream, stale-grey, rotation (TDD)
- [ ] 01-04-PLAN.md — Tooltip wrapper + per-tooltip-open subscription + label golden (TDD)
- [ ] 01-05-PLAN.md — Config dialog + AssetRegistry registration + back-compat test
**UI hint**: yes

### Phase 2: Elevator Foundation
**Goal**: Operators can place an elevator on a page, point its position state key at a PLC 0–100% value, and watch the platform glide vertically inside the bbox — with the data pipeline hoisted to `initState`, smooth `ValueNotifier`-scoped repaints, stale-stream handling, and JSON / registry round-trip locked in (including the future-proof `ElevatorChildEntry` wrapper schema).
**Depends on**: Phase 1
**Requirements**: ELEV-01, ELEV-02, ELEV-03, ELEV-04, ELEV-05, ELEV-06, ELEV-14, ELEV-16, ELEV-17, ELEV-18, QUAL-04
**Success Criteria** (what must be TRUE):
  1. Operator can place an Elevator asset from the palette and see vertical rails plus a platform deck (no shaft cage, no cabin glyph) sized to the asset's bounding box.
  2. The platform position is driven by a single PLC 0–100% state key — 0% places the platform at the bottom, 100% at the top, with smooth `TweenAnimationBuilder`-backed motion and no resubscribe storm (the StateMan stream is hoisted to `initState`, never rebuilt in `build()`).
  3. The platform's vertical position derives exclusively from a unit-tested `platformOffsetTop(progress, bboxHeight, platformHeight)` helper that returns the correct value at progress {0.0, 0.5, 1.0}, eliminating off-by-one bugs around platform thickness.
  4. Elevator renders subdued grey when the position stream is stale or disconnected, and saved pages without elevator instances continue to load (back-compat).
  5. JSON serialization round-trips for every field with defensible defaults — children list defaults to empty, `ElevatorChildEntry` wrapper shape (UUID, offsetX, child) is established from day one, and `_childrenFromJson` is in place to absorb future schema evolution.
**Plans**: TBD
**UI hint**: yes

### Phase 3: Elevator Child Embedding
**Goal**: Operators can attach sensor and conveyor child assets to the elevator via a dropdown in the config dialog, edit and remove them through the same dialog, and watch every child physically ride the platform up and down — with stable widget identity across position changes, polymorphic `BaseAsset.build`, and the elevator's `allKeys` override surfacing nested keys to alarms and collectors.
**Depends on**: Phase 2 (also requires Phase 1's Sensor for the integration golden test)
**Requirements**: ELEV-07, ELEV-08, ELEV-09, ELEV-10, ELEV-11, ELEV-12, ELEV-13, ELEV-19, QUAL-03, QUAL-08
**Success Criteria** (what must be TRUE):
  1. Operator can open the elevator config dialog, add a child via a dropdown filtered to Sensor and Conveyor kinds, set its lateral platform offset (0..1), and see it appear on the platform; existing children can be edited or removed via the same dialog.
  2. As the platform's Y position changes, every assigned child's `Positioned.top` follows in real time, the child renders via its own polymorphic `BaseAsset.build(context)` (the elevator never switches on child runtime type), and the child's `State.initState` fires exactly once per page load — never on position changes.
  3. Each child entry carries a stable UUID used as a `ValueKey<String>`, ensuring widget identity (and therefore stream subscriptions, animation controllers, and dialog state) survives every position change unchanged.
  4. The elevator's `allKeys` override flat-maps each child's `allKeys` plus its own `positionKey`, so alarms and collectors discover nested state keys without the operator having to register them separately.
  5. Golden tests cover the elevator at progress {0.0, 0.5, 1.0} with one Sensor and one Conveyor child attached, demonstrating end-to-end correctness of identity, layout, and translation.
**Plans**: 3 plans
- [ ] 03-01-PLAN.md — Stack composition + Positioned children with ValueKey + hit-test-through-translation widget tests + 3 integration goldens (TDD)
- [ ] 03-02-PLAN.md — ElevatorConfig.allKeys override flat-mapping children's keys (TDD)
- [ ] 03-03-PLAN.md — Editor add/edit/remove/offsetX child management UI (filtered to Sensor + Conveyor)
**UI hint**: yes

### Phase 4: Polish, Error UX & CI Hardening
**Goal**: The elevator surfaces fault states clearly per ISA-101, no animation controllers or stream subscriptions leak across mount/unmount cycles, and multiple elevators on the same page operate with fully independent state subscriptions — closing the milestone with the production-quality guards that turn the feature from "works" to "shippable."
**Depends on**: Phase 3
**Requirements**: ELEV-15, QUAL-06, QUAL-07
**Success Criteria** (what must be TRUE):
  1. When the PLC reports a position outside 0–100%, the elevator clamps the displayed platform to the legal range and surfaces an amber outline (per ISA-101) so operators can immediately distinguish a sensor fault from a normal extreme position.
  2. A multi-elevator smoke test verifies that placing several elevators on one page — including configurations with the same and different position keys — produces fully independent stream subscriptions with no shared-mutable-state regressions or cross-talk.
  3. A `LeakTesting.enable()` mount/unmount test confirms every `AnimationController`, `ValueNotifier`, and StateMan stream subscription owned by the new assets is disposed cleanly when the widget unmounts.
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Sensor Asset | 0/TBD | Not started | - |
| 2. Elevator Foundation | 0/TBD | Not started | - |
| 3. Elevator Child Embedding | 0/TBD | Not started | - |
| 4. Polish, Error UX & CI Hardening | 0/TBD | Not started | - |
