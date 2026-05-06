# Feature Research

**Domain:** Industrial HMI assets — vertical lift (elevator) and discrete sensors (photoelectric paired beam, optic field, inductive field) embedded in a Flutter SCADA/HMI page creator
**Researched:** 2026-05-05
**Confidence:** MEDIUM-HIGH (ISA-101 / High-Performance HMI guidance is well-documented; some specifics on lift visualisation are inferred from analogous stacker/reclaimer practice and existing tfc-hmi2 conveyor_gate prior art)

---

## Scope Reminder (from PROJECT.md)

The user has already pinned several decisions out of scope. This document deliberately re-affirms them as anti-features so that requirements can't drift back in:

- Horizontal/2D motion, drag-drop child assignment, auto-attach by overlap, client-side debounce smoothing, three separate sensor types, discrete floor positioning, edge-delay numeric configuration. See `.planning/PROJECT.md` "Out of Scope".

Active milestone scope is the elevator + sensor primitives only; the feature tables below stay inside that perimeter.

---

## Feature Landscape

### Table Stakes (Operator confusion or wrong actions if missing)

These features must be present in v1, otherwise the asset misrepresents plant state or creates operator hesitation.

#### Elevator

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Vertical rails / shaft outline | Operator must see the travel envelope. Without rails the moving platform looks unanchored and the 0%/100% extents are ambiguous. | LOW | Two thin vertical lines flanking the platform width, drawn in CanvasPainter. Match conveyor neutral grey palette (ISA-101 grayscale base). |
| Platform / carriage glyph | The thing that moves needs a clear horizontal bar — distinct from rails — so the eye locks onto position changes. | LOW | Filled rectangle, slightly inset from rails. Proportional thickness (e.g. 8–12% of asset height). Reuse proportional-radius idiom from `conveyor_gate_painter`. |
| Live position from PLC 0–100% | Core of the asset. Without it, lift is a static decoration. | LOW | StateMan stream of `DynamicValue` → `double.clamp(0,1)`. Linearly map to platform Y inside bounding box (0% = bottom, 100% = top per PROJECT.md decision). |
| Numeric position readout | "Where exactly is it?" — operators want a number, not just a position. ISA-101 calls out live numeric values alongside graphical indicators. | LOW | Display "%" or value with 0–1 decimals. Place adjacent to platform or in a tooltip. ISA-101 source: live digital values accompany graphical bars/gauges. |
| Travel range = bounding box | Predictable resize semantics — operators (and config authors) need WYSIWYG; "what I draw is what it sweeps". | LOW | Already a project decision; just enforce in painter. |
| Children translate with platform | Whole point of the asset. If children stay put the metaphor breaks. | MEDIUM | Reuse `ChildGateEntry`-style wrapper but with a 1D fractional offset on the platform; transform child paint by `(0, -position * travelRange)`. |
| Out-of-range / stuck-state visual | If PLC reports >100, <0, or NaN, the asset must look "wrong" not "fine at 0/100". Without this, faults hide. | LOW | Cap value, draw a coloured outline (amber for out-of-range, red for stale/null) per ISA-101: colour reserved for abnormal states. |
| Stale data indication | StateMan disconnect must surface — operator must not trust a frozen-looking platform. | LOW-MEDIUM | Match existing pattern (`Led`/`Number`): show subdued colour or hatch when stream errors / no value yet. Verify exact tfc-hmi2 convention before implementing. |
| Backwards-compatible JSON | Saving a page with the new asset must keep old pages loading; missing fields fall back to defensible defaults. | LOW | json_serializable with `defaultValue:` + `unknownEnumValue:`, mirror conveyor_gate practice. |

#### Sensor (single asset, kind enum)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Visually distinct kind glyphs | A light-beam, an optic field and an inductive field have different field shapes — one shape would mislead operators about *what is being detected and where*. | MEDIUM | Three painter branches keyed off `SensorKind`. Beam: two pucks plus connecting line. Optic field: emitter housing with a fanned/conical sensing field. Inductive field: housing with a circular/elliptical near-field bubble. Inspired by IEC-60617 schematic conventions adapted for at-a-glance HMI use. |
| Active vs inactive colour state | The single most important bit of information. Must read at a glance, even peripherally. | LOW | Inactive = neutral grey/dark; active = saturated accent (project palette). Per ISA-101 reserve red for alarms — do **not** use red for "detected"; prefer blue/cyan/green-accent for "object present", or follow whatever existing tfc-hmi2 LED uses (`led.dart`) for consistency. Verify before locking colour. |
| Immediate visual flip on bool change | "HMI mirrors PLC truth" decision. No transitions, no debounce. | LOW | StreamBuilder `setState` on bool change. No tween. Explicitly *not* animated. |
| Paired-beam: emitter + receiver + beam line in ONE asset | Decision: one placement gives the full beam. Operators don't reason about two halves of a beam separately. | LOW | Beam line spans the asset width (or height when rotated). Emitter glyph one end, receiver glyph the other end. Default horizontal; rotation handles vertical. |
| Beam-broken visual semantics | The beam line itself should change appearance when the bool flips. Just changing the puck colour is too subtle. | LOW | Continuous line when "clear", broken/dashed or coloured line when "broken/detected". Decide which polarity matches PLC convention (most through-beam sensors are dark-on, output high when blocked) — config option may be needed. |
| Field-sensor active state shows the field | For optic-field and inductive-field kinds, the *field* (cone, bubble) is the part that lights up — that's the natural mental model. | LOW | Field shape filled / outlined depending on active state. |
| Rotation / orientation handling | Sensors get mounted in arbitrary orientations on a real conveyor; the page must reflect that. | LOW | Use existing `BaseAsset` rotation if present, else add `rotationDegrees` field. Beam asset especially needs vertical orientation for top-mounted overhead beams. Painter applies `canvas.rotate(...)` around centre. |
| Tooltip with edge-delay values | Decision: edge-delay state keys are display-only. Tooltip is the natural place — visible on hover/longpress, doesn't clutter the screen. ISA-101 endorses on-demand detail vs always-on clutter. | LOW | Wrap painter with `Tooltip` showing `Rising: <value>ms\nFalling: <value>ms` + state-key labels. Stream subscriptions resolve via stateMan. |
| State-key labels in config dialog match operator vocabulary | Config field names are part of the contract. "Detection State Key", "Rising Edge Delay Key", "Falling Edge Delay Key" — not "OPC UA Key 1". Mirrors gate-visual-feedback memory note. | LOW | Pure UI string work in `configure()` builder. |

### Differentiators (Nice to have for later milestones)

Not required to ship v1, but credible enhancements to revisit.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Position readout in mm (configurable scale) | Operators on real lifts often think in millimetres of travel, not %. Setting `travelMm` lets the tooltip/numeric display show both. | LOW | Optional config field `travelRangeMm`; tooltip computes mm from %. Defer until anyone asks — % suffices for scope. |
| Top/bottom position labels | Some lifts have named extremes ("Loading", "Discharge"). Per-position label config makes the lift self-describing. | LOW | Two optional string fields. Render at top/bottom of rails. |
| Soft-limit / interlock indicator zones | Visualising a "do-not-go-here" range (e.g. lower 5% reserved as crash zone) helps operators predict alarms before they fire. | MEDIUM | Coloured band overlay on the rails. Driven by additional state keys (limit setpoints) — out of v1 scope but a natural v2. |
| Direction arrow / motion pip | Tiny up/down arrow that flashes only when delta-position over time is non-zero. Gives a sense of "moving up" vs "stationary at 80%" without animating the platform itself. | LOW-MEDIUM | Compute derivative from stream over a small window. Keeps ISA-101-compliant: arrow only shown when *abnormal/active*, otherwise hidden. |
| Sensor signal-strength tint | If the PLC publishes an analog "intensity" value alongside the bool, fade the active colour by intensity. Mostly relevant to optic/inductive. | MEDIUM | Optional analog state-key field on sensor config. Defer until use case appears. |
| Sensor "last seen" freshness pip | Tiny dot showing how recently the bool toggled — quick spot-check that the line is alive vs the sensor stuck on. | MEDIUM | Tracks last edge timestamp; turns dim if quiet for >N seconds. Defer; wait for operator complaint. |
| Configurable "active polarity" per sensor | True polarity inversion ("active when bool false") covers dark-on through-beam vs light-on diffuse without PLC remap. | LOW | Single bool field. Useful enough that this could slip into v1 if cost is trivial. Flag for product decision. |
| Per-sensor custom label / tag | Sensor tag (e.g. "PE-101A") rendered next to glyph. Helpful for identification at glance. | LOW | Reuse `BaseAsset.text` if it already supports overlays; else add. |

### Anti-Features (Commonly Requested, Often Problematic)

These would seem reasonable to a casual stakeholder but conflict with project decisions, ISA-101 guidance, or maintainability. Reject these explicitly.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Horizontal or 2D elevator motion** | "What if the lift moves sideways too?" | Out of scope per PROJECT.md. Mixing dimensions doubles painter complexity, child-position math, and config UI; no current customer needs it. | Vertical-only lift; revisit via PROJECT.md if a second use case arises. |
| **Drag-drop child assignment** | Feels modern/intuitive at first glance. | Out of scope per PROJECT.md. Hit-testing on an asset that already gets resized/rotated is fragile (gate-visual-feedback memory note shows the pain). Discoverability of a dialog is fine. | Dropdown of available sensors/conveyors in the elevator config dialog. |
| **Auto-attach children by overlap** | "Just put them visually on the platform and they ride along." | Out of scope per PROJECT.md. Implicit attachment is invisible — operators can't tell *why* something does or doesn't ride. Fragile under resize. | Explicit assignment via the dialog; deterministic JSON. |
| **Client-side debounce / smoothing for sensors** | "Light beams flicker on edges, smooth it out so it doesn't strobe." | Out of scope per PROJECT.md. The HMI's job is to show PLC truth; debouncing on the HMI hides bugs in PLC config. PLC owns debouncing. | Display raw bool; show edge-delay values from PLC state keys in tooltip so operators see where debouncing **is** happening. |
| **Three separate sensor asset types in registry** | "Cleaner: one asset per kind." | Out of scope per PROJECT.md. Triples registry entries, dialog code, painter files; users hunt across asset palettes. | Single sensor asset with `SensorKind` enum + branching painter. |
| **Discrete floor / level positioning** | "Lifts have floors, model floors." | Out of scope per PROJECT.md. Continuous % covers servos and indexed mechanisms. Discrete floors would require per-asset floor-table config. | Continuous 0–100; if a customer needs floor labels later, add optional N-stop label list as a v2 differentiator. |
| **Edge-delay configuration as numeric fields in HMI dialog** | "Let operators tune debounce from the screen." | Out of scope per PROJECT.md. Splits source-of-truth between HMI and PLC; recipe drift; operators forget which is authoritative. | Edge delays come from PLC state keys; HMI tooltip shows them read-only. |
| **Animated platform motion / easing tweens** | "Snappy animations look nice." | ISA-101: "no gratuitous animation … animation only used to highlight abnormal situations". Operators are cued by *value change*, not *motion*. Easing also lies about real lift dynamics. | Snap to the latest stream value, no tween. Let real value updates drive the perceived motion. |
| **Spinning / pulsing decorative motion (rotating drum on platform, pulsing beam, etc.)** | "Looks alive." | Same ISA-101 anti-pattern. Decorative motion fatigues operators and masks real abnormal-condition motion. | Static rendering; motion reserved for actual abnormal states (e.g. flashing border on stale data). |
| **Red as the "detected" colour for sensors** | Red is "noticeable", and many people want sensors red. | ISA-101 reserves red for fault/alarm. If "detected" is red, real alarms drown in normal operation. | Use a non-red accent (project palette saturated colour) for active. Red is for alarm states only. |
| **Live-stream the field strength as a wobbling/breathing visual** | "Show the operator how strong the signal is." | Continuous animation = ISA-101 anti-pattern; eats CPU on Flutter painter; distracts. | If signal-strength is needed (differentiator above), use a discrete tint *level*, not animated breathing. |
| **3D / isometric lift rendering** | "Looks more realistic." | ISA-101: "graphics should be intentionally simple, often grayscale, so real problems pop instead of drowning in gradients and 3-D art." | Flat 2D painter; consistent with rest of tfc-hmi2 asset library. |
| **Drag platform to write position back to PLC** | "Manual jog." | Inverts the read-only contract. Position is observed, not commanded; manual jog belongs on a dedicated control widget where consequences are visible (and write-confirmation can apply). | Read-only platform; jog buttons (if needed) live elsewhere — out of this milestone's scope. |
| **Per-asset hand-coded SVG icons for each sensor kind** | "SVG looks nicer than CustomPainter." | Diverges from tfc-hmi2 convention (everything is CustomPainter), prevents stateful colour/active animation, makes goldens harder. | CustomPainter branches keyed off `SensorKind`. |

---

## Feature Dependencies

```
Elevator: live position stream
    └──requires──> StateMan key resolution (existing)
    └──requires──> Travel-range = bounding box decision (existing)
    └──enables───> Children translate with platform
                       └──requires──> ChildGateEntry-style wrapper (1D)
                       └──requires──> Painter composition / child paint transform

Elevator: numeric position readout
    └──enhances──> Position stream (gives precise value alongside graphical)

Elevator: out-of-range / stale visual
    └──requires──> Position stream
    └──conflicts─> Easing tweens (would mask out-of-range jumps)

Sensor: kind enum + painter branches
    └──requires──> SensorKind enum + JSON serialisation
    └──enables───> Beam visual, optic-field visual, inductive-field visual

Sensor: tooltip with edge-delay values
    └──requires──> Two optional state-key config fields (rising, falling)
    └──requires──> StateMan subscription for those keys (display only)

Sensor: rotation / orientation
    └──requires──> rotation field on BaseAsset (verify if exists, else add)
    └──enhances──> Beam (vertical mount), field sensors (angled mount)

Differentiator: position labels (top/bottom)
    └──requires──> Two optional string fields on ElevatorConfig

Differentiator: direction arrow
    └──requires──> Position stream
    └──requires──> Local time-window derivative (cheap)

Anti-pattern: HMI debounce ──conflicts──> "PLC owns truth" decision
Anti-pattern: drag-drop assignment ──conflicts──> dropdown decision (PROJECT.md)
Anti-pattern: red = detected ──conflicts──> ISA-101 colour reservation
```

### Dependency Notes

- **Children-translate-with-platform requires the position stream**: makes ordering trivial — position pipeline must land before child translation can be wired.
- **Numeric readout enhances but doesn't require the visual**: can ship visual first, add readout in same phase. Both are table stakes.
- **Stale/out-of-range visual conflicts with easing**: tweens hide value-source faults. Project decision (snap to value) is also the ISA-101 alignment.
- **Tooltip requires the edge-delay state keys** but those are *optional* config fields; if unset, tooltip simply shows main detection state.
- **Rotation hinges on BaseAsset capability**: if rotation is already in the base, sensor inherits; if not, a milestone-internal extension is required first. Flag for codebase verification.

---

## MVP Definition

### Launch With (v1 — this milestone)

This is a brownfield milestone-scoped MVP. "Minimum viable" = enough to register both assets, drive them from real PLC keys, and survive page save/load.

**Elevator:**
- [ ] `ElevatorConfig extends BaseAsset` registered in `AssetRegistry`
- [ ] Painter draws rails + platform inside bounding box (0% bottom, 100% top)
- [ ] `positionKey` (single state key, 0–100% double) drives platform Y
- [ ] Children list (typed wrapper analogous to `ChildGateEntry`, 1D fractional offset on platform) translate with platform in real time
- [ ] Config dialog exposes child-assignment dropdown (sensors, conveyors)
- [ ] Numeric position readout (% with 0–1 decimals)
- [ ] Out-of-range and stale-data visual indicator
- [ ] Backwards-compatible JSON

**Sensor:**
- [ ] `SensorConfig extends BaseAsset` registered, with `SensorKind { redLightBeam, opticField, inductiveField }`
- [ ] Painter branches per `SensorKind` (beam: emitter+receiver+beam-line; optic: housing+cone field; inductive: housing+near-field bubble)
- [ ] `detectionKey` (bool) flips active/inactive colour state immediately
- [ ] Beam line itself changes appearance on bool change (not just pucks)
- [ ] Tooltip showing rising-edge and falling-edge delay values from configured state keys (display-only)
- [ ] Rotation handling for arbitrary mounting orientations
- [ ] Backwards-compatible JSON

**Cross-cutting:**
- [ ] Both assets follow `conveyor_gate` painter conventions (proportional radii, palette overflow handling, golden tests)
- [ ] Both reuse the `Led`/`Number` stale-stream convention (verify in code)

### Add After Validation (v1.x — same milestone if cheap)

- [ ] Configurable active polarity on sensor (one bool, very low cost; flag for product decision)
- [ ] Per-sensor tag/label overlay (if BaseAsset already supports text)
- [ ] Top/bottom position labels on elevator (two optional strings)

### Future Consideration (v2+ — explicitly deferred)

- [ ] Position readout in mm (configurable travel scale)
- [ ] Direction arrow / motion pip
- [ ] Soft-limit / interlock zones
- [ ] Sensor signal-strength tint (if analog signal-strength state key becomes available)
- [ ] Sensor freshness pip
- [ ] Discrete floor labels (if any customer requests indexed lifts)

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Rails + platform glyph | HIGH | LOW | P1 |
| Live position stream → platform Y | HIGH | LOW | P1 |
| Children translate with platform | HIGH | MEDIUM | P1 |
| Child-assignment dropdown in config | HIGH | MEDIUM | P1 |
| Numeric position readout | MEDIUM | LOW | P1 |
| Out-of-range / stale visual | HIGH | LOW | P1 |
| Sensor kind enum + 3 painter branches | HIGH | MEDIUM | P1 |
| Sensor active/inactive colour flip | HIGH | LOW | P1 |
| Beam-line visual changes on bool | MEDIUM | LOW | P1 |
| Sensor tooltip with edge-delay values | MEDIUM | LOW | P1 |
| Sensor rotation handling | HIGH | LOW | P1 |
| Backwards-compatible JSON | HIGH | LOW | P1 |
| Active-polarity bool on sensor | MEDIUM | LOW | P2 |
| Top/bottom position labels | LOW | LOW | P2 |
| Per-sensor tag overlay | MEDIUM | LOW | P2 |
| Direction arrow on elevator | LOW | LOW-MEDIUM | P3 |
| Position in mm | LOW | LOW | P3 |
| Soft-limit zones | MEDIUM | MEDIUM | P3 |
| Signal-strength tint | LOW | MEDIUM | P3 |
| Freshness pip | LOW | MEDIUM | P3 |
| Discrete floor labels | LOW | MEDIUM | P3 |

**Priority key:**
- **P1**: Required for v1 (this milestone). Operator confusion or wrong actions if missing.
- **P2**: Should fit in this milestone if cost is trivial; otherwise next.
- **P3**: Future milestones.

---

## Competitor / Convention Analysis

| Feature | Industry Convention (ISA-101 / High-Performance HMI) | Inductive Automation Ignition | Rockwell / FactoryTalk View | Our Approach |
|---------|------------------------------------------------------|-------------------------------|-----------------------------|--------------|
| Visual style | Grayscale base, colour reserved for abnormal | Symbol Factory library; gradient/3D options exist but discouraged in HP-HMI projects | Process HMI Style Guide white paper aligns with HP-HMI grayscale | Follow HP-HMI: grey rails/housing, colour only for active sensor, abnormal lift state |
| Lift / vertical motion glyph | No specific symbol — usually composed from rails + filled-rectangle platform | Custom drawing or Symbol Factory generic | Custom drawing | Custom Flutter painter, two thin rails + platform bar |
| Sensor symbols | IEC-60617 schematic conventions (rectangle housing + arrows for emit/receive); HMI uses simplified pictograms | Symbol Factory has photo-eye / proximity icons | Symbol library available | Custom painter inspired by IEC-60617 conventions, simplified for at-a-glance HMI |
| Position readout | Live numeric next to graphical bar/gauge — explicitly endorsed | Same | Same | Numeric % readout adjacent to or in tooltip on platform |
| Animation | Discouraged for routine motion; reserved for abnormal | Available but HP-HMI guidance recommends restraint | Same | None for normal motion; only for stale/out-of-range states |
| Sensor active colour | Red reserved for alarms; "detected" typically blue/cyan/yellow accent | Configurable | Configurable | Match existing tfc-hmi2 LED active colour for consistency (verify in code) |
| Tooltip on detail | Endorsed for on-demand detail without screen clutter | Native tooltip support | Native tooltip support | Flutter `Tooltip` widget showing edge-delay values |

---

## Quality Gate Checklist

- [x] Categories clear (table stakes vs differentiators vs anti-features) — three explicit sections
- [x] Anti-features explicitly cite the user's prior decisions when relevant — see "Why Problematic" column referencing PROJECT.md and gate-visual-feedback memory
- [x] Complexity noted for each feature — Complexity column in every table

---

## Open Questions for Requirements / Design Phase

1. **Existing rotation support on `BaseAsset`?** Sensor rotation is table-stakes; need to confirm whether to extend BaseAsset or use existing field. → Read `lib/page_creator/assets/common.dart` early in design.
2. **Active colour convention in tfc-hmi2** — what does `led.dart` use? Sensor active state should match for operator muscle memory. → Read `lib/page_creator/assets/led.dart`.
3. **Stale-stream convention** — is there a shared painter helper for "no value yet / error"? → Check `Number`, `LED`, `analog_box.dart`. Avoid inventing a new one.
4. **Active-polarity field (P2)** — accept now or defer? Trivial cost, real-world value (dark-on through-beam vs light-on diffuse). Flag for product owner.
5. **Beam-line broken-state colour polarity** — most through-beam sensors are dark-on (output high when blocked). Decide whether the asset's "active" colour means "object detected/blocked" or "beam clear". This affects all sensor kinds, not just beam — better to lock convention now.

---

## Sources

ISA-101 / High-Performance HMI guidance:
- [ISA-101 Series of Standards](https://www.isa.org/standards-and-publications/isa-standards/isa-101-standards)
- [Going Gray: A New HMI Standard (control.com)](https://control.com/technical-articles/going-gray/)
- [What Is High-Performance HMI? (RealPars)](https://www.realpars.com/blog/high-performance-hmi)
- [ISA-101 — The Standard for Modern, High-Performance HMI Interfaces (IoT Industries)](https://www.iotindustries.sk/en/blog/isa-101/)
- [Rockwell Automation Process HMI Style Guide (PDF)](https://literature.rockwellautomation.com/idc/groups/literature/documents/wp/proces-wp023_-en-p.pdf)
- [Unpacking ISA-101: Beyond the Misunderstood Grayscale (Malisko)](https://malisko.com/isa-101/)
- [HMI Design Best Practices: Balancing Color, Animation, and Usability (Industrial Monitor Direct)](https://industrialmonitordirect.com/blogs/knowledgebase/resolving-hmi-design-conflicts-color-animation-and-operator-engagement)

Sensor symbol conventions:
- [IEC-60617 Photoelectric Emitter/Receiver Symbols (Autodesk)](https://knowledge.autodesk.com/support/autocad-electrical/learn-explore/caas/CloudHelp/cloudhelp/2019/ENU/AutoCAD-Electrical/files/GUID-15ABE47A-723F-4004-BF2A-9CC285DE7882-htm.html)
- [From Application to Schematic: Proximity Sensor Symbols (OMCH)](https://www.omch.com/proximity-sensor-symbol/)
- [Photoelectric sensor (Wikipedia)](https://en.wikipedia.org/wiki/Photoelectric_sensor)
- [Overview of Photoelectric Sensors (Omron)](https://www.ia.omron.com/support/guide/43/introduction.html)
- [Photoelectric sensor types — through beam (ifm)](https://www.ifm.com/us/en/us/overview/photoelectric/sensor-type/through-beam)

Conveyor / lift HMI practice:
- [HMI for Conveyor Systems (LaFayette Engineering)](https://www.lafayette-engineering.com/hmi-for-conveyor-systems/)
- [HMI/SCADA Screen Design: Layout Standards (PLC Construction)](https://www.plcconstruction.com/hmi-scada-screen-design-layout-standards-that-boost-operator-response/)
- [HMI Operator Screen Best Practices: What to Display (Industrial Monitor Direct)](https://industrialmonitordirect.com/blogs/knowledgebase/hmi-operator-screen-best-practices-what-to-display)
- [A Guide to Knowing Your HMI Cell Status Screen (Motion Controls Robotics)](https://motioncontrolsrobotics.com/resources/tech-talk-articles/a-guide-to-knowing-your-hmi-cell-status-screen/)
- [Stacker-Reclaimer Position Monitoring (Automated Control)](https://automatedcontrol.com.au/portfolio-item/stacker-reclaimer-position-monitoring/)

Internal references:
- `.planning/PROJECT.md` — milestone scope and out-of-scope decisions
- `.planning/codebase/ARCHITECTURE.md` — Asset / BaseAsset / AssetRegistry / StateMan patterns
- `lib/page_creator/assets/conveyor_gate.dart` — `ChildGateEntry` prior art for child-assignment wrapper
- `~/.claude/projects/-Users-jonb-Projects-tfc-hmi2/memory/gate-visual-feedback.md` — painter conventions, terminology lessons (state-key labelling, hit-testing pain) from prior milestone

---

*Feature research for: Industrial HMI elevator + sensor assets (tfc-hmi2 page creator)*
*Researched: 2026-05-05*
