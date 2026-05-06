# Elevator & Sensor Assets

## What This Is

Two new HMI assets for the tfc-hmi2 page creator: an **elevator** that translates child assets vertically based on a PLC-driven 0–100% position, and a **sensor** asset with a configurable kind (paired red light beam, optic field, inductive field) that visualises detection state from a bool state key. Built for industrial operators using the existing centroid-hmi Flutter app to monitor and configure conveyor lines that include lifting platforms and sensor instrumentation.

## Core Value

Operators can place an elevator on a page, assign sensors and conveyors to it via the config dialog, and watch those children physically ride the platform up and down as the PLC's position value changes — with sensor detection states reflected accurately in real time.

## Requirements

### Validated

<!-- Inferred from existing codebase. -->

- ✓ Asset registry with JSON-serialised configs and painter-based widgets — existing
- ✓ StateMan multi-protocol PLC subscription (OPC UA / Modbus / M2400) — existing
- ✓ Asset config dialogs with state-key fields and per-asset typed config — existing
- ✓ Child-asset embedding pattern (ChildGateEntry on conveyors) — existing
- ✓ Build-runner codegen for `*.g.dart` config classes — existing

### Active

<!-- Current scope. Hypotheses until shipped. -->

- [ ] Elevator asset registered in the page creator with a vertical-shaft visual
- [ ] Elevator position driven by a single 0–100% state key from the PLC
- [ ] Elevator travel range = its bounding box (0% = bottom, 100% = top)
- [ ] Elevator config dialog exposes a child-assignment dropdown (sensors, conveyors)
- [ ] Assigned child assets visually translate with the elevator platform in real time
- [ ] Sensor asset registered in the page creator with selectable kind in config dialog
- [ ] Sensor kinds: red light (paired sender + receiver + beam), optic field, inductive field
- [ ] Sensor active state driven by a single bool state key (true = detected); visual flips immediately
- [ ] Sensor config dialog exposes separate state-key fields for rising-edge delay and falling-edge delay (display-only — values shown but do not affect visual)
- [ ] Backwards-compatible JSON deserialisation (existing pages keep loading)

### Out of Scope

- **Horizontal or 2D elevator motion** — operators only need vertical lifts in this milestone; revisit if a use case appears
- **Drag-drop child assignment in the editor** — dropdown is sufficient and avoids hit-testing complexity inherited from the gate work
- **Auto-attach by overlap** — implicit attachment is fragile and hard to debug; explicit assignment is preferred
- **Client-side debounce / delay smoothing for sensors** — HMI shows raw PLC truth; PLC owns debouncing
- **Three separate sensor asset types** — single asset with kind selector keeps the registry uncluttered and the dialog consistent
- **Discrete floor / level positioning** — continuous 0–100% covers servo and indexed mechanisms equally well
- **Edge-delay configuration as numeric fields** — values come from PLC state keys, not HMI-local config

## Context

**Codebase:** Brownfield Flutter monorepo with established asset, painter, and registry patterns. See `.planning/codebase/` for the full map. Most relevant prior art: `lib/page_creator/assets/conveyor_gate.dart` and `conveyor.dart` — the `ChildGateEntry` wrapper there (gate embedded on conveyor with position+side) is the closest analog for elevator's child-assignment pattern.

**Prior work:** Recent ConveyorGate milestone established the painter conventions (proportional radii, visual-state-from-bool patterns, palette overflow handling). Open issues from that work (slider/diverter painter polish) are independent of this milestone.

**PLC integration:** All live data flows through `StateMan.subscribe(key)` returning `Stream<DynamicValue>`. Assets read `stateManProvider`; existing assets show how to wire continuous (analog) and bool keys.

## Constraints

- **Tech stack**: Must use existing Flutter + Riverpod + Asset Registry + StateMan stack — no new frameworks
- **Pattern fidelity**: Follow `ConveyorGate` painter and child-wrapper conventions; deviating breaks operator muscle memory and forces future rework
- **Backwards compatibility**: Existing saved pages must continue to load; any new config fields need defensible defaults
- **Codegen**: New configs require `*.g.dart` files via build_runner — must round-trip through JSON cleanly
- **State-key driven**: All live values (position, bool, edge delays) come from `StateMan` keys; no hard-coded values in production paths

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Elevator translates vertically only | User confirmed classic elevator semantics; horizontal can be added later if needed | — Pending |
| Continuous 0–100% PLC position via single state key | Covers both servo and indexed mechanisms; simplest contract | — Pending |
| Travel range = elevator bounding box (0% bottom, 100% top) | Resizing the asset is the natural way to control range; matches operator expectations | — Pending |
| Children assigned via dialog dropdown (not drag-drop) | Avoids hit-testing complexity; explicit and discoverable | — Pending |
| Single sensor asset with `SensorKind` enum (4 kinds) | Keeps registry uncluttered; one dialog covers all variants | — Pending |
| Red light kind paired in one instance (sender + receiver + beam) | Operator places one asset, gets the full beam — fewer placements, clearer semantics | — Pending |
| Sensor visual flips immediately with bool input | HMI mirrors PLC truth; debouncing is the PLC's job | — Pending |
| Edge-delay state keys are display-only | Operators want visibility into PLC config but the HMI doesn't apply the delays itself | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-05 after initialization*
