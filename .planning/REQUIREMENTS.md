# Requirements: Elevator & Sensor Assets

**Defined:** 2026-05-06
**Core Value:** Operators can place an elevator on a page, assign sensors and conveyors to it via the config dialog, and watch those children physically ride the platform up and down as the PLC's position value changes — with sensor detection states reflected accurately in real time.

## v1 Requirements

### Sensor

- [ ] **SENS-01**: User can place a Sensor asset from the page-creator palette
- [ ] **SENS-02**: User can select sensor kind in the config dialog: red light (paired), optic field, inductive field
- [ ] **SENS-03**: Sensor renders kind-specific glyphs via dedicated `CustomPainter` per kind (no `switch` inside `paint()`)
- [ ] **SENS-04**: Red light sensor renders as a single instance with emitter + receiver + connecting beam line
- [ ] **SENS-05**: Sensor visual flips active/inactive immediately on bool state-key change (no client-side smoothing or animation)
- [ ] **SENS-06**: Beam line for red-light kind changes appearance with state — solid when clear (bool true), dashed/accent when blocked (bool false)
- [ ] **SENS-07**: Optic field and inductive field kinds render the field shape (cone / bubble) filled when active, outlined when inactive
- [ ] **SENS-08**: Active and inactive colours are configurable per instance; default active = `Colors.green` (matching `led.dart`), default inactive = neutral grey
- [ ] **SENS-09**: User can configure rising-edge-delay state key in the dialog (display-only — value shown in tooltip, does not affect visual)
- [ ] **SENS-10**: User can configure falling-edge-delay state key in the dialog (display-only — value shown in tooltip, does not affect visual)
- [ ] **SENS-11**: Tooltip on hover/longpress shows rising and falling edge-delay values resolved from their state keys
- [ ] **SENS-12**: User can toggle "active polarity" per sensor (invert detection bool — supports dark-on through-beam vs light-on diffuse without PLC remap)
- [ ] **SENS-13**: User can configure a per-sensor label/tag rendered next to the glyph (e.g. "PE-101A")
- [ ] **SENS-14**: Stale or disconnected stream renders the sensor in neutral grey (matches `conveyor_gate.dart` convention `baseColor = Colors.grey`)
- [ ] **SENS-15**: Sensor honours rotation via existing `Coordinates.angle` field (no new rotation primitive)
- [ ] **SENS-16**: Sensor registers with `AssetRegistry` such that older saved pages without sensor instances continue to load
- [ ] **SENS-17**: Sensor JSON round-trips through `_$SensorConfigFromJson` / `_$SensorConfigToJson` with defensible defaults on every field

### Elevator

- [ ] **ELEV-01**: User can place an Elevator asset from the page-creator palette
- [ ] **ELEV-02**: Elevator renders vertical rails + a platform deck (no shaft cage, no cabin glyph)
- [ ] **ELEV-03**: Elevator's travel range equals its bounding box: 0% = platform at bottom, 100% = platform at top
- [ ] **ELEV-04**: Platform position is driven by a single 0–100% state key from the PLC (continuous float)
- [ ] **ELEV-05**: Position pipeline hoists the StateMan stream to `initState` (no inline stream construction in `build()`)
- [ ] **ELEV-06**: Platform position transitions smoothly via `TweenAnimationBuilder<double>` (or equivalent `AnimationController` + `ValueNotifier<double>`); rebuilds scoped to `ValueListenableBuilder` only
- [ ] **ELEV-07**: User can add child assets to the elevator via a dropdown in the config dialog (filtered to Sensor and Conveyor kinds)
- [ ] **ELEV-08**: User can remove and edit child assets via the same dialog
- [ ] **ELEV-09**: Each child entry stores its lateral platform offset (0..1) and a stable identity (UUID) for `ValueKey` use
- [ ] **ELEV-10**: Children physically translate with the platform — their `Positioned.top` follows the platform Y in real time
- [ ] **ELEV-11**: Each child renders via its own polymorphic `BaseAsset.build(context)`; the elevator never switches on child runtime type
- [ ] **ELEV-12**: Children retain widget identity across position changes (`ValueKey<String>` keyed on the child entry's UUID)
- [ ] **ELEV-13**: Elevator's `allKeys` override flat-maps children's `allKeys` plus its own `positionKey` so alarms/collectors discover nested keys
- [ ] **ELEV-14**: Stale or disconnected position stream renders the elevator in subdued grey (consistent with sensor convention)
- [ ] **ELEV-15**: Out-of-range position (> 100% or < 0%) clamps and surfaces a coloured outline (amber per ISA-101)
- [ ] **ELEV-16**: Elevator registers with `AssetRegistry` such that older saved pages without elevator instances continue to load
- [ ] **ELEV-17**: Elevator JSON round-trips through `_$ElevatorConfigFromJson` / `_$ElevatorConfigToJson` with defensible defaults on every field; child list defaults to empty
- [ ] **ELEV-18**: `_childrenFromJson` legacy shim handles future schema evolution (mirror of `conveyor.dart:_gatesFromJson`)

### Quality

- [ ] **QUAL-01**: Per-kind sensor painter has its own `CustomPainter` subclass; `shouldRepaint` returns `true` when `runtimeType` differs (prevents kind-switch leakage)
- [ ] **QUAL-02**: Golden tests cover each `SensorKind` × {active, inactive} combination
- [ ] **QUAL-03**: Golden tests cover elevator at progress {0.0, 0.5, 1.0} with one Sensor and one Conveyor child attached
- [ ] **QUAL-04**: Unit test for the `platformOffsetTop(progress, bboxHeight, platformHeight)` helper at progress {0.0, 0.5, 1.0}
- [ ] **QUAL-05**: JSON round-trip tests for both assets, including legacy / missing-field tolerance
- [ ] **QUAL-06**: Multi-elevator smoke test verifies independent state subscriptions (no shared-mutable-state regression)
- [ ] **QUAL-07**: `LeakTesting.enable()` mount/unmount test verifies AnimationControllers and stream subscriptions are disposed cleanly

## v2 Requirements

### Sensor (deferred)

- **SENS-V2-01**: Position-in-mm readout configurable per sensor (signal-strength tint, per-kind)
- **SENS-V2-02**: "Last seen" freshness pip showing recency of last edge transition
- **SENS-V2-03**: Configurable analog signal-strength state key fading the active colour by intensity

### Elevator (deferred)

- **ELEV-V2-01**: Top/bottom position labels (configurable strings — e.g. "Loading", "Discharge")
- **ELEV-V2-02**: Position readout in millimetres via configurable `travelRangeMm`
- **ELEV-V2-03**: Direction arrow / motion pip (computed from position derivative over a small window; arrow only shown when moving)
- **ELEV-V2-04**: Soft-limit / interlock indicator zones (coloured bands on rails driven by setpoint state keys)
- **ELEV-V2-05**: Discrete floor/level labels for indexed lifts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Horizontal or 2D elevator motion | Operators only need vertical lifts in this milestone; revisit if a use case appears |
| Drag-drop child assignment in the editor | Dropdown is sufficient and avoids hit-testing complexity inherited from the gate work |
| Auto-attach children by overlap | Implicit attachment is invisible and fragile; explicit assignment required |
| Client-side debounce / delay smoothing for sensors | HMI shows raw PLC truth; PLC owns debouncing |
| Three separate sensor asset types in registry | Single asset with kind selector keeps the registry uncluttered |
| Discrete floor / level positioning | Continuous 0–100% covers servo and indexed mechanisms equally well |
| Edge-delay configuration as numeric fields in HMI dialog | Delay values come from PLC state keys, not HMI-local config |
| Animated platform easing tweens that exaggerate motion | ISA-101: no gratuitous animation; motion is reserved for actual abnormal states |
| Decorative motion (pulsing beam, spinning drum) | ISA-101 anti-pattern — fatigues operators and masks abnormal-condition motion |
| Red as default active colour for sensors | ISA-101 reserves red for fault/alarm — using red for normal detection drowns real alarms |
| 3D / isometric lift rendering | Diverges from tfc-hmi2 flat-painter convention |
| Drag platform to write position back to PLC | Inverts read-only contract — manual jog belongs on a dedicated control widget |
| Per-asset hand-coded SVG icons | Diverges from CustomPainter convention; harder goldens, no per-state colour control |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SENS-01 | TBD | Pending |
| SENS-02 | TBD | Pending |
| SENS-03 | TBD | Pending |
| SENS-04 | TBD | Pending |
| SENS-05 | TBD | Pending |
| SENS-06 | TBD | Pending |
| SENS-07 | TBD | Pending |
| SENS-08 | TBD | Pending |
| SENS-09 | TBD | Pending |
| SENS-10 | TBD | Pending |
| SENS-11 | TBD | Pending |
| SENS-12 | TBD | Pending |
| SENS-13 | TBD | Pending |
| SENS-14 | TBD | Pending |
| SENS-15 | TBD | Pending |
| SENS-16 | TBD | Pending |
| SENS-17 | TBD | Pending |
| ELEV-01 | TBD | Pending |
| ELEV-02 | TBD | Pending |
| ELEV-03 | TBD | Pending |
| ELEV-04 | TBD | Pending |
| ELEV-05 | TBD | Pending |
| ELEV-06 | TBD | Pending |
| ELEV-07 | TBD | Pending |
| ELEV-08 | TBD | Pending |
| ELEV-09 | TBD | Pending |
| ELEV-10 | TBD | Pending |
| ELEV-11 | TBD | Pending |
| ELEV-12 | TBD | Pending |
| ELEV-13 | TBD | Pending |
| ELEV-14 | TBD | Pending |
| ELEV-15 | TBD | Pending |
| ELEV-16 | TBD | Pending |
| ELEV-17 | TBD | Pending |
| ELEV-18 | TBD | Pending |
| QUAL-01 | TBD | Pending |
| QUAL-02 | TBD | Pending |
| QUAL-03 | TBD | Pending |
| QUAL-04 | TBD | Pending |
| QUAL-05 | TBD | Pending |
| QUAL-06 | TBD | Pending |
| QUAL-07 | TBD | Pending |

**Coverage:**
- v1 requirements: 42 total
- Mapped to phases: 0 (will be filled by roadmapper)
- Unmapped: 42 ⚠️ (expected — roadmap creates the mapping)

---
*Requirements defined: 2026-05-06*
*Last updated: 2026-05-06 after initial definition*
