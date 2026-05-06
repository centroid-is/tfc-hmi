# Architecture Research

**Domain:** Industrial HMI custom assets (Flutter / tfc-hmi2 monorepo) — adding `Elevator` parent asset and multi-kind `Sensor` asset
**Researched:** 2026-05-05
**Confidence:** HIGH

## Standard Architecture

Both new assets are direct extensions of established patterns in the codebase. No new abstractions, no registry surgery, no provider changes.

- **Elevator** = `ConveyorConfig`'s `List<ChildGateEntry> gates` pattern, generalised to `List<ElevatorChildEntry>` where each entry holds a 2D offset + a polymorphic child `BaseAsset`. Vertical translation is a `ValueNotifier<double>` driven by a `StateMan` stream → `AnimationController`-backed tween, applied to all children inside a `Stack`.
- **Sensor** = `ConveyorGateConfig`'s `GateVariant` + dispatch-in-`_createPainter` pattern, copy-pasted with kinds renamed (`SensorKind.{redLight, opticField, inductiveField}`). One `SensorConfig`, one widget, one `_createPainter(...)` switch, three painter classes in `sensor_painter.dart`.

Both register exactly like every other asset (`AssetRegistry._fromJsonFactories` + `defaultFactories` in `lib/page_creator/assets/registry.dart`). Backwards compatibility is solved by the `_gatesFromJson` precedent at `lib/page_creator/assets/conveyor.dart:26-48`.

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Page Creator (lib/page_creator/)              │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐    │
│  │ AssetRegistry   │ ← │ ElevatorConfig  │   │ SensorConfig    │    │
│  │ (registry.dart) │   │ (elevator.dart) │   │ (sensor.dart)   │    │
│  └─────────────────┘   └────────┬────────┘   └────────┬────────┘    │
└─────────────────────────────────┼─────────────────────┼─────────────┘
                                  ▼                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       Widget Layer (StatefulWidget)                 │
│  ┌─────────────────────────────┐   ┌────────────────────────────┐   │
│  │ Elevator                    │   │ Sensor                     │   │
│  │  StreamBuilder(positionKey) │   │  StreamBuilder(stateKey)   │   │
│  │  AnimationController        │   │  GestureDetector → dialog  │   │
│  │  ValueNotifier<double>      │   │  _createPainter(kind)      │   │
│  │   ↓                         │   │   ↓                        │   │
│  │  Stack:                     │   │  CustomPaint               │   │
│  │   - ElevatorPainter (rails) │   └────────────────────────────┘   │
│  │   - Platform deck           │                                    │
│  │   - children Positioned     │       Painters (sensor_painter):   │
│  │       (translate w/ deck)   │       RedLightBeamPainter          │
│  └─────────────────────────────┘       OpticFieldPainter            │
│              │                         InductiveFieldPainter        │
│              │                                                      │
│              ▼ recursive build()                                    │
│  Child assets (any BaseAsset — typically Sensor or Conveyor)        │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       Data Layer (Riverpod + StateMan)              │
│   stateManProvider → StateMan.subscribe(key) → Stream<DynamicValue> │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `ElevatorConfig extends BaseAsset` | JSON-serialised config: `positionKey`, `List<ElevatorChildEntry> children`, `tweenDurationMs`, optional inversion flag | `lib/page_creator/assets/elevator.dart` |
| `ElevatorChildEntry` | Wrapper holding `double offsetX` (0–1, lateral on platform) + child asset | `lib/page_creator/assets/elevator.dart` |
| `Elevator extends ConsumerStatefulWidget` | Subscribes to position key, drives `AnimationController`-backed `ValueNotifier<double>`, lays out shaft + platform + children | `lib/page_creator/assets/elevator.dart` |
| `_ElevatorConfigEditor` | Dialog: `KeyField` for position, child list with add/remove/edit (dropdown of registered child types) | `lib/page_creator/assets/elevator.dart` |
| `ElevatorPainter` | Static visuals only: shaft rails, top/bottom limits. Does NOT paint children | `lib/page_creator/assets/elevator_painter.dart` |
| `SensorKind` enum | `redLight`, `opticField`, `inductiveField` — `@JsonEnum()` with `@JsonKey(unknownEnumValue: …)` | `lib/page_creator/assets/sensor.dart` |
| `SensorConfig extends BaseAsset` | `kind`, `stateKey`, `risingEdgeDelayKey`, `fallingEdgeDelayKey`, colour fields | `lib/page_creator/assets/sensor.dart` |
| `Sensor extends ConsumerStatefulWidget` | `StreamBuilder<DynamicValue>` on `stateKey`, dispatches via `_createPainter(kind, isActive)` | `lib/page_creator/assets/sensor.dart` |
| `_SensorConfigEditor` | `SegmentedButton<SensorKind>` + three `KeyField`s + display-only delay readout | `lib/page_creator/assets/sensor.dart` |
| `RedLightBeamPainter`, `OpticFieldPainter`, `InductiveFieldPainter` | One `CustomPainter` per kind | `lib/page_creator/assets/sensor_painter.dart` |

## Recommended Project Structure

New files only — additive to the existing asset directory:

```
lib/page_creator/assets/
├── elevator.dart            # ElevatorConfig, ElevatorChildEntry, Elevator widget, editor
├── elevator.g.dart          # codegen (json_serializable)
├── elevator_painter.dart    # ElevatorPainter — shaft + rails + platform deck
├── sensor.dart              # SensorConfig, SensorKind, Sensor widget, editor
├── sensor.g.dart            # codegen
└── sensor_painter.dart      # RedLightBeamPainter, OpticFieldPainter, InductiveFieldPainter

test/page_creator/assets/    # mirroring goldens directory in test/painter/goldens
├── sensor_test.dart         # widget + golden tests for each kind × on/off
└── elevator_test.dart       # progress 0.0/0.5/1.0, child-translation, JSON round-trip

lib/page_creator/assets/registry.dart   # +2 entries in _fromJsonFactories + defaultFactories
```

### Structure Rationale

- **One file per asset, one painter file per asset:** matches existing convention (`conveyor.dart` + `conveyor_painter.dart`, `conveyor_gate.dart` + `conveyor_gate_painter.dart`). Splitting painters keeps widget/state logic out of paint code, which makes goldens trivial to drive with constructor primitives.
- **Tests mirror lib structure** — `test/page_creator/assets/` matches `lib/page_creator/assets/`, same convention used elsewhere.

## Architectural Patterns

### Pattern 1: Polymorphic child via `BaseAsset` typing (no new interface)

**What:** `ElevatorChildEntry.child` is typed `BaseAsset`, not a new `ElevatorMountable` interface or sealed union. The registry already deserialises any registered asset type from `asset_name`.
**When to use:** Whenever a parent asset needs to embed arbitrary child assets at offsets.
**Trade-offs:** + Zero new abstractions, future child types Just Work. − Cannot statically restrict children at the type level (must be enforced via dropdown filter in the editor only).

**Example (sketch):**
```dart
@JsonSerializable(explicitToJson: true)
class ElevatorChildEntry {
  ElevatorChildEntry({this.offsetX = 0.5, required this.child});

  final double offsetX;

  @JsonKey(fromJson: _childFromJson, toJson: _childToJson)
  final BaseAsset child;

  factory ElevatorChildEntry.fromJson(Map<String, dynamic> json) =>
      _$ElevatorChildEntryFromJson(json);
  Map<String, dynamic> toJson() => _$ElevatorChildEntryToJson(this);
}

BaseAsset _childFromJson(Map<String, dynamic> json) =>
    AssetRegistry.parse(json) ?? const _UnknownAsset();
Map<String, dynamic> _childToJson(BaseAsset a) => a.toJson();
```

### Pattern 2: Switch-on-enum painter dispatch (single widget, multiple painters)

**What:** One `Sensor` widget; `_createPainter(SensorKind, bool isActive)` returns the appropriate painter via exhaustive `switch`. Direct copy of `_ConveyorGateState._createPainter` (`conveyor_gate.dart:240-266`).
**When to use:** When variants share lifecycle/state but differ only in visual rendering.
**Trade-offs:** + Compiler-enforced exhaustiveness on enum switches. + Per-kind constructor params at the call site, not a unified painter constructor. − Three painter classes to maintain — but this is correct, since the kinds *should* not share `paint()` code.

**Example (sketch):**
```dart
CustomPainter _createPainter(bool isActive) {
  final color = isActive ? widget.config.activeColor : widget.config.inactiveColor;
  switch (widget.config.kind) {
    case SensorKind.redLight:
      return RedLightBeamPainter(isActive: isActive, color: color);
    case SensorKind.opticField:
      return OpticFieldPainter(isActive: isActive, color: color);
    case SensorKind.inductiveField:
      return InductiveFieldPainter(isActive: isActive, color: color);
  }
}
```

### Pattern 3: `ValueNotifier<double>` + `ValueListenableBuilder` for animated layout

**What:** `AnimationController.addListener` writes the curve-transformed value to a `ValueNotifier<double>`. The platform layout reads via `ValueListenableBuilder<double>`.
**When to use:** Whenever an animation must drive layout without rebuilding the entire widget tree.
**Trade-offs:** + Per-frame rebuilds scoped to the listener subtree only. + Goldens drive the notifier directly, skipping `pumpAndSettle`. − One indirection (notifier) versus reading `controller.value` directly.

**Example (sketch):**
```dart
final _progress = ValueNotifier<double>(0.0);
late final AnimationController _controller = AnimationController(
  vsync: this,
  duration: Duration(milliseconds: widget.config.tweenDurationMs),
)..addListener(() {
  _progress.value = Curves.linear.transform(_controller.value);
});

void _onPositionChanged(double target /* 0..1 */) {
  _controller.animateTo(target);
}
```

### Pattern 4: Backwards-compatible JSON via `_xFromJson` shim

**What:** A static helper detects old vs new format and dispatches accordingly. Direct precedent: `_gatesFromJson` (`conveyor.dart:26-48`).
**When to use:** Whenever a list of children gets a wrapper layer added.
**Trade-offs:** + Saves migration scripts and avoids breaking existing pages. − Carries the legacy decode path forever; document the cutover point.

## Data Flow

### Position pipeline (Elevator)

```
PLC value (0-100)
  │
  ▼
StateMan.subscribe(positionKey)            packages/tfc_dart/lib/core/state_man.dart
  │   Stream<DynamicValue>
  ▼
StreamBuilder in Elevator.build            mirrors conveyor_gate.dart:336-391
  │   .asDouble  →  normalised 0..1
  ▼
_onPositionChanged(target):                mirrors _onStateChanged at conveyor_gate.dart:225
  AnimationController.animateTo(target,
    duration: config.tweenDurationMs)
  │
  ▼
controller.addListener:                    conveyor_gate.dart:208-210
  _progress.value = curve.transform(controller.value)
  │  (ValueNotifier<double>)
  ▼
LayoutBuilder + ValueListenableBuilder<double>
  │   builds Stack:
  │     - ElevatorPainter (shaft, rails — static)
  │     - Positioned platform at top: (1 - progress) * (height - platformHeight)
  │     - For each child:
  │         Positioned(
  │           left: child.offsetX * width - childSize/2,
  │           top:  platformY - childSize,    // sit ON the platform
  │           child: child.child.build(context),  // recursive!
  │         )
  ▼
Children paint themselves (their own StateMan subscriptions are independent;
the Elevator only owns layout offsets)
```

### Sensor active-state pipeline

```
PLC bool (true=detected)
  │
  ▼
StateMan.subscribe(stateKey) → Stream<DynamicValue>
  │
  ▼
StreamBuilder in Sensor.build  →  isActive: bool (immediate flip; no client-side delay)
  │
  ▼
_createPainter(isActive)  →  kind-specific CustomPainter
  │
  ▼
CustomPaint  →  glyph rendered with active/inactive colours
```

Edge-delay state keys are subscribed by the editor dialog only (display-only readout), not by the live painter.

### Key Data Flows

1. **Elevator position → child translation:** continuous PLC % drives a tween whose value reshapes the children's `Positioned` `top` offsets. Children's own state is independent.
2. **Sensor bool → painter:** raw bool flips the painter's active flag — no debounce, no animation.

## Build Order

The roadmap should sequence phases in this order (each phase ≈ one PR):

```
Phase 1: Sensor (simpler, no children)
  ├─ 1a  SensorConfig + SensorKind enum + Sensor widget skeleton + part 'sensor.g.dart'
  ├─ 1b  flutter pub run build_runner build  → sensor.g.dart
  ├─ 1c  Register in AssetRegistry (registry.dart fromJson + default factories + import)
  ├─ 1d  RedLightBeamPainter (most complex — paired sender/receiver/beam)
  ├─ 1e  OpticFieldPainter, InductiveFieldPainter
  ├─ 1f  Config editor (SegmentedButton + KeyField × 3 + colours)
  └─ 1g  Golden tests under test/page_creator/assets/

Phase 2: Elevator config + static visuals (no children yet)
  ├─ 2a  ElevatorConfig + ElevatorChildEntry skeleton + part 'elevator.g.dart'
  ├─ 2b  build_runner build
  ├─ 2c  Register in AssetRegistry
  ├─ 2d  ElevatorPainter (shaft, rails, platform)
  └─ 2e  Position pipeline: StreamBuilder → AnimationController → ValueNotifier<double>
         → ValueListenableBuilder repaints platform position only

Phase 3: Elevator child embedding
  ├─ 3a  Stack overlay layout in Elevator widget; Positioned per-child driven by
  │      ValueListenableBuilder<double>
  ├─ 3b  Editor: child list UI (Add → dropdown of AssetRegistry.defaultFactories filtered
  │      to {SensorConfig, ConveyorConfig}; Edit → existing entry.configure(context); Remove)
  ├─ 3c  _childrenFromJson with backward-compat (parallel to _gatesFromJson)
  └─ 3d  Golden tests with one Sensor + one Conveyor child at progress 0.0, 0.5, 1.0

Phase 4: Polish
  ├─ allKeys override on ElevatorConfig that flat_maps children's allKeys
  ├─ Empty-state handling (positionKey empty → platform sits at midpoint, grey rails)
  └─ Error UX (snapshot.hasError → exclamation in shaft, mirroring conveyor.dart:783-803)
```

Phase 1 must complete before Phase 3 ships, because Phase 3 demos the Elevator with a Sensor child. Phase 2 can ship independently — an empty elevator is still useful.

**Dependency rule:** never write the painter (`elevator_painter.dart`) before the config (`elevator.dart`). The painter only consumes plain primitives via constructor; if you write it first you will accidentally couple it to widget concerns and have to refactor.

## Anti-Patterns

### Anti-Pattern 1: Switching on child type in the elevator's layout code

**What people do:** Replicate `_positionedChildGate`'s `switch (entry.gate.gateVariant)` (`conveyor.dart:846-900`) inside the elevator to handle special placement for sensors vs conveyors.
**Why it's wrong:** Couples elevator to specific child types. Adding a future child class forces an elevator change.
**Do this instead:** Type the child as `BaseAsset`. Compute offsets from `ElevatorChildEntry.offsetX` only. Children own their own intrinsic size via `RelativeSize.toSize()`.

### Anti-Pattern 2: Subscribing to streams inside the painter

**What people do:** Pass `WidgetRef`/`StateMan` into the painter and subscribe in `paint()`.
**Why it's wrong:** Painters must be pure — same inputs ⇒ same pixels. Subscriptions inside `paint()` cause repaint storms and break golden tests.
**Do this instead:** Subscriptions live in the widget. Painters take primitives (`progress`, `colors`, `isActive`) via constructor. Goldens drive notifiers directly.

### Anti-Pattern 3: Animating with `setState`

**What people do:** Call `setState((){})` from `controller.addListener` to refresh the platform.
**Why it's wrong:** Rebuilds the entire elevator subtree (including child `StreamBuilder`s) every frame. At 60 fps with a `ConveyorConfig` child this causes perceptible jank.
**Do this instead:** `ValueNotifier<double>` + `ValueListenableBuilder` — scoped repaints only.

### Anti-Pattern 4: Three separate sensor asset types in `AssetRegistry`

**What people do:** Register `RedLightSensorConfig`, `OpticFieldSensorConfig`, `InductiveFieldSensorConfig` separately to "keep things explicit."
**Why it's wrong:** Clutters the asset palette, triplicates dialog code, and the user already chose single-asset-with-kind-enum.
**Do this instead:** Single `SensorConfig` + `SensorKind` enum, dispatch via `_createPainter`.

### Anti-Pattern 5: Letting the elevator drive child animations

**What people do:** Tween a child's open/closed state from the elevator because "it's already animating."
**Why it's wrong:** Frame-rate coupling, hard-to-reproduce glitches, inverts ownership.
**Do this instead:** Children own their own `AnimationController`. The elevator only translates `Positioned` offsets.

### Anti-Pattern 6: Forgetting `allKeys` override on the parent

**What people do:** Inherit the default `BaseAsset.allKeys` (`common.dart:218-243`), which only walks top-level JSON entries — misses nested `children: [...]` keys (Conveyor has this gap today).
**Why it's wrong:** Alarms / collectors that consume `allKeys` silently miss the elevator's children's keys.
**Do this instead:** Override `allKeys` on `ElevatorConfig` to flat-map `children.expand((e) => e.child.allKeys)` plus the elevator's own `positionKey`.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Elevator ↔ AssetRegistry | Standard `BaseAsset` registration in `registry.dart` | Add to both `_fromJsonFactories` and `defaultFactories` |
| Elevator ↔ children | `entry.child.build(context)` — polymorphic via existing registry | Children types restricted only by editor's dropdown filter |
| Sensor ↔ StateMan | `stateManProvider` (Riverpod) → `subscribe(stateKey)` → bool stream | Hoist stream to `initState`; never rebuild in `StreamBuilder.stream:` |
| Both assets ↔ JSON | `_$XFromJson` / `_$XToJson` via `json_serializable` | Mirror `_gatesFromJson` legacy shim for elevator children |

## Sources

- `lib/page_creator/assets/conveyor.dart` (parent-with-children precedent)
- `lib/page_creator/assets/conveyor_gate.dart` (variant dispatch + animation precedent)
- `lib/page_creator/assets/registry.dart` (registration mechanism)
- `lib/page_creator/assets/common.dart` (`BaseAsset.allKeys` semantics)
- `packages/tfc_dart/lib/core/state_man.dart` (subscription contract)
- `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md` (current map)
- Flutter API: `TweenAnimationBuilder`, `AnimationController`, `CustomPainter`, `ValueListenableBuilder`

---
*Architecture research for: tfc-hmi2 elevator + sensor assets milestone*
*Researched: 2026-05-05*
