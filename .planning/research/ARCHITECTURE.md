# Architecture Research — Modicon Momentum I/O Assets (v2.0)

**Domain:** Brownfield Flutter HMI asset family — additions to existing tfc-hmi2 page-creator
**Researched:** 2026-05-11
**Confidence:** HIGH (all findings verified by direct read of current sources: `beckhoff.dart`, `registry.dart`, `common.dart`, `io8.dart`, `ek1100.dart`, `page.dart`, `elevator_painter_test.dart`)

This is **integration research**, not a redesign. The CX5010 + EK1100 + EL100x family is the source of truth; Modicon Momentum mirrors it. The job below is to identify the smallest set of NEW files, the MODIFIED files, and the build order that lands DDI3725/DDO3705/NIP2311/PDT3100 + MomentumStack with the same operator semantics as the Beckhoff family.

---

## 1. Existing Architecture (Locked — Do Not Redesign)

### 1.1 Asset family layering

```
┌─────────────────────────────────────────────────────────────────────┐
│  AssetRegistry  (lib/page_creator/assets/registry.dart)             │
│    _fromJsonFactories : Map<Type, fromJson>     ← parse(JSON)       │
│    defaultFactories   : Map<Type, preview>      ← palette + MCP     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ Type.toString() == json["asset_name"]
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Asset / BaseAsset  (lib/page_creator/assets/common.dart)           │
│    - JSON-serialised config classes (json_serializable + .g.dart)   │
│    - build(context)     : Widget   (runtime visual)                 │
│    - configure(context) : Widget   (editor dialog)                  │
│    - allKeys            : List<String>  (introspect tag-keys)       │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────────┐
        ▼                                          ▼
┌─────────────────────┐                ┌──────────────────────────┐
│ Leaf assets         │                │ Composite (stack) asset  │
│  EL1008 / EL2008 /  │                │  CX5010                  │
│  EK1100 / EL3054…   │                │   @AssetListConverter()  │
│  CustomPainter      │                │   subdevices : List<Asset>│
│  + StateMan stream  │                │   build = Row + FittedBox │
└──────────────────────┘                │   allKeys = flatMap(subs)│
                                        └──────────────────────────┘
```

### 1.2 Polymorphic child serialisation — `AssetListConverter`

Defined once in `lib/page_creator/page.dart:35-47`:

```dart
class AssetListConverter implements JsonConverter<List<Asset>, List<dynamic>> {
  List<Asset> fromJson(List<dynamic> json) =>
      AssetRegistry.parse({'assets': json});      // type-routed by asset_name
  List<dynamic> toJson(List<Asset> assets) =>
      assets.map((a) => a.toJson()).toList();
}
```

`BeckhoffCX5010Config.subdevices` is annotated `@AssetListConverter()`. Build_runner emits this into `beckhoff.g.dart`:

```dart
subdevices: const AssetListConverter().fromJson(json['subdevices'] as List)
```

The list element carries the child's full polymorphic JSON (including its `asset_name`). **There is no `ChildEntry { id, child }` wrapper for CX5010** — children are stored as bare polymorphic asset JSON objects. The position-and-side wrapping from `ChildGateEntry` (conveyors) is *not* used by CX5010 because stack children render in linear `Row` order (the list index IS the position). MomentumStack follows the same model.

### 1.3 `allKeys` flat-map for stacks

`BeckhoffCX5010Config` (beckhoff.dart:41-50) overrides `allKeys`:

```dart
@override
List<String> get allKeys {
  final keys = <String>{};
  for (final sub in subdevices) {
    if (sub is BaseAsset) keys.addAll(sub.allKeys);
  }
  return keys.toList();
}
```

Leaf modules rely on `BaseAsset.allKeys` (common.dart:217-243) which introspects `toJson()` for fields matching `RegExp(r'^key$|^key\d+$|Key$|_key$')`. The Modicon I/O modules (`rawStateKey`, `forceValuesKey`, `descriptionsKey`, `onFiltersKey`, `offFiltersKey`) match the suffix `Key$` and will be picked up automatically — **no override needed on leaves**. MomentumStack does need the same flat-map override as CX5010.

**Edge cases verified (no conflict):**
- Adapter-level keys (NIP2311 RUN/PWR/ERR/ST/TEST) are plain `*Key` fields → picked up by default introspection.
- Per-channel I/O keys are bit-packed into a single `rawStateKey` (already a string field) plus a `descriptionsKey` (string array of 16 descriptions) — same shape as EL1008. No per-channel string array of keys needed.
- PDT3100 single `inputOkKey` bool — same shape.
- Set-based flatten (`<String>{}`) already de-dupes if two modules share a key.

### 1.4 Runtime data flow (leaf → IO8Widget)

EL1008 wiring (beckhoff.dart:1272-1300) is the canonical pattern:

```dart
CombineLatestStream([
  for (var entry in keys.entries)
    if (entry.value != null)
      stateMan.subscribe(entry.value!).asStream().asyncExpand((s) => s),
], (values) => mapByName)
  → _ledStates(data)   // 16x bit-test against rawStateKey + force overlay
  → IO16Widget(...)
```

Modicon I/O modules reuse the same `_combinedStream` + `_ledStates` shape — only the LED-count constant flips from 8 to 16.

### 1.5 Painter scale model

`lib/painter/beckhoff/ek1100.dart` establishes the convention: native design space in mm (`widthMm`, `heightMm`), uniform `gScale` fit-to-box, strokes pre-divided by scale. New Modicon painters follow the same mm-based design space (DXF bounding box is the source of truth — see `.planning/research/dxf/README.md`).

`IO8Widget` (io8.dart:9-60) uses aspect ratio `width = height / 6`. Internally `IO8Painter.paint()` lays out a `2 cols × 4 rows` LED grid via `IO8LedBlockPainter._drawLeds`. The 4-channel and 6-channel variants are already split-out (`IO6LedBlockPainter`) — **the codebase already proves the "split painter per channel count" pattern over "generalise to N channels"**. See §3 for the recommended Modicon decision.

---

## 2. File-Structure Recommendation

### Recommended layout (NEW files in **bold**, MODIFIED in *italic*)

```
lib/
├── page_creator/
│   └── assets/
│       ├── registry.dart                          ← *MODIFIED* (5 entries × 2 maps + 1 import)
│       ├── beckhoff.dart                          (untouched — reference impl)
│       └── modicon.dart                           ← **NEW** single file
│           ├── ModiconMomentumStackConfig         (parent — mirrors CX5010)
│           ├── ModiconNIP2311Config               (head adapter)
│           ├── ModiconPDT3100Config               (power dist)
│           ├── ModiconDDI3725Config               (16-ch DI)
│           └── ModiconDDO3705Config               (16-ch DO)
│
├── painter/
│   ├── beckhoff/                                  (untouched — imported as references)
│   └── modicon/                                   ← **NEW** folder
│       ├── io16.dart                              ← **NEW** (16-LED strip + widget)
│       ├── ddi3725.dart                           ← **NEW** (DI body wraps IO16Widget)
│       ├── ddo3705.dart                           ← **NEW** (DO body wraps IO16Widget)
│       ├── nip2311.dart                           ← **NEW** (head body + dual RJ45)
│       └── pdt3100.dart                           ← **NEW** (power-dist body)
│
test/
└── page_creator/
    └── assets/
        ├── modicon_config_test.dart               ← **NEW** (JSON round-trip)
        ├── modicon_stack_test.dart                ← **NEW** (child mgmt + allKeys)
        ├── modicon_painter_test.dart              ← **NEW** (golden harness)
        ├── modicon_widget_test.dart               ← **NEW** (StateMan integration + leaks)
        └── goldens/
            └── modicon/                           ← **NEW** folder (~13 PNGs)
```

### 2.1 Single-file vs split-file decision

**Recommendation: ONE file — `lib/page_creator/assets/modicon.dart`.**

**Rationale (anchored in Beckhoff precedent):**

| Argument | Evidence |
|---|---|
| Beckhoff is 2,198 lines and 9 configs in one file | `wc -l beckhoff.dart` = 2198; covers CX5010 + EK1100 + EL1008/2008/3054/9222/9186/9187 |
| Modicon is 5 configs (1 stack + 4 modules) | Strictly smaller surface than Beckhoff |
| `_availableSubdevices` map is per-stack-file scope | beckhoff.dart:21 — split files would force exporting these or duplicating |
| The `part 'X.g.dart'` directive is per file | One `part 'modicon.g.dart'` keeps codegen output single and predictable |
| Shared helpers (`_combinedStream`, `_ledStates`, `_SubdeviceNormalized`) co-locate with users | Splitting forces a `modicon_common.dart` that adds noise without removing duplication |
| PROJECT.md already endorses single file | Line 23: "new module assets land at `lib/page_creator/assets/modicon.dart` (or split file per the planner's call)" |

**Estimated size:** 5 configs × ~250 LoC each + stack wrapper (~150) + helpers (~50) ≈ **1,400 LoC** — comfortably under the Beckhoff precedent. The point at which to revisit splitting is when the file approaches `beckhoff.dart` size *and* a third Modicon-family stack is added. At that point split by `modicon_stack.dart` + `modicon_modules.dart`. Not now.

**Painters stay split per-module under `lib/painter/modicon/`** — this matches `lib/painter/beckhoff/` which has one file per module (`ek1100.dart`, `cx5010.dart`, `io8.dart`). Painters are larger (mm-to-px geometry, polylines from DXF) and benefit from per-file isolation for golden-test stability and review.

---

## 3. Painter Decisions

### 3.1 The 8 → 16 question

**Do NOT reuse `io8.dart` by side-by-siding two 8-LED widgets.** Reasons:

1. **DXF says one body, 16 LEDs, not two stacked bodies.** The Momentum I/O base is a single faceplate (107 × 152 mm per `.planning/research/dxf/README.md`); LEDs are arranged in a continuous grid on one face, not two adjacent 2×4 grids with a seam.
2. **Beckhoff already split painters per channel count.** `IO8LedBlockPainter` and `IO6LedBlockPainter` (io8.dart:424, 456) extend a shared `BaseLedBlockPainter`. The precedent is to *create a new painter that extends the same base*, not stack instances.
3. **Reusing IO8Widget twice doubles the body chrome** (top labels, terminal blocks, "BECKHOFF"/manufacturer text) which is wrong for one physical module.
4. **Golden stability.** Two side-by-sided IO8 widgets at non-integer scales produce sub-pixel seams that cause flaky goldens.

**Recommended approach:**

Add a sibling LED block painter to `lib/painter/modicon/io16.dart`:

```dart
class IO16LedBlockPainter extends BaseLedBlockPainter {   // reuses base
  IO16LedBlockPainter({required super.ledStates, required super.animation})
    : assert(ledStates.length == 16);
  @override
  void _drawLeds(Canvas canvas, Size size) { /* 4×4 or 2×8 grid */ }
}
```

The Beckhoff `BaseLedBlockPainter` (`io8.dart:347-421`) and the `IOState` enum live in `lib/painter/beckhoff/io8.dart`. **Import them from there** in the new Modicon painter:

```dart
import '../beckhoff/io8.dart' show BaseLedBlockPainter, IOState, bodyColor;
```

Reason: `IOState` and `_drawLed` are the cross-module contract — they were promoted to a base class precisely so additional LED block variants can plug in. Adding a Modicon-flavoured `IO16Widget` (with Schneider-cream body colour, terminal block geometry from the DXF) means **`io16.dart` constructs an `IO16Widget`+`IO16Painter` pair that internally uses an `IO16LedBlockPainter extends BaseLedBlockPainter`**.

**Whether to move `BaseLedBlockPainter` + `IOState` to a neutral location (e.g., `lib/painter/common/io_state.dart`):** Reuse from `lib/painter/beckhoff/io8.dart` directly. If/when this pattern grows to 4+ painters (Beckhoff EL1008 + EL1004 + Modicon IO16 + a future Wago), promote to common. Flag for v2.1. **Do not refactor Beckhoff in this milestone** (anti-pattern §9.3).

**The 4-channel / 2-channel generalisation is explicitly deferred** per the question prompt — do not introduce a parameterised `IONLedBlockPainter` in v2.0.

### 3.2 Painters for adapter and power-dist

- **`nip2311.dart`** — head module body + dual RJ45. Reuse `EthernetPortPainter` from `lib/painter/beckhoff/ek1100.dart:217-413` (it is a generic DXF-derived RJ45 polyline renderer with no Beckhoff branding embedded). Import: `import '../beckhoff/ek1100.dart' show EthernetPortPainter;`. Add the 5 status LEDs (RUN/PWR/ERR/ST/TEST) as small filled rectangles or circles per Schneider photo — these are NOT IOState LEDs, they are single-bool status indicators with their own colour scheme; **do not conflate with the `BaseLedBlockPainter` family**.
- **`pdt3100.dart`** — power-distribution body. Simple painter: faceplate + terminal blocks + a single "INPUT OK" indicator. ~150 LoC.

### 3.3 What stays out of painters

Painters never touch StateMan. The widget layer (`_BeckhoffEL1008` pattern, beckhoff.dart:1302) does the FutureBuilder + StreamBuilder + `_combinedStream(...)` and feeds a plain `List<IOState>` into the painter. Modicon mirrors this exactly — painters in `lib/painter/modicon/` are pure CustomPainters; subscription wiring lives in `lib/page_creator/assets/modicon.dart`.

---

## 4. MomentumStack — Child Management

### 4.1 Structural mirror of CX5010

```dart
@JsonSerializable()
class ModiconMomentumStackConfig extends BaseAsset {
  @override String get displayName => 'Modicon Momentum Stack';
  @override String get category => 'Modicon Devices';

  @AssetListConverter()
  List<Asset> subdevices = [];

  ModiconMomentumStackConfig();
  ModiconMomentumStackConfig.preview() : super();

  @override
  List<String> get allKeys {
    final keys = <String>{};
    for (final sub in subdevices) {
      if (sub is BaseAsset) keys.addAll(sub.allKeys);
    }
    return keys.toList();
  }

  @override Widget build(BuildContext context) { /* Row + FittedBox of subdevices */ }
  @override Widget configure(BuildContext context) { /* dialog with whitelist dropdown */ }

  factory ModiconMomentumStackConfig.fromJson(Map<String, dynamic> j) =>
      _$ModiconMomentumStackConfigFromJson(j);
  Map<String, dynamic> toJson() => _$ModiconMomentumStackConfigToJson(this);
}
```

### 4.2 Whitelist enforcement — recommended

CX5010 currently uses a top-level const map (`_availableSubdevices`, beckhoff.dart:21-28) which serves *as a palette* but **does not enforce types on `subdevices.add()`**. The list type is `List<Asset>` — any asset deserialised from JSON would slot in. The user wants Modicon filtered, so:

**Recommendation: keep the palette pattern AND add a runtime type check at deserialisation.**

```dart
const Map<String, Asset Function()> _availableModiconSubdevices = {
  'NIP2311': ModiconNIP2311Config.preview,
  'PDT3100': ModiconPDT3100Config.preview,
  'DDI3725': ModiconDDI3725Config.preview,
  'DDO3705': ModiconDDO3705Config.preview,
};

// Optional post-fromJson sanitiser:
static const _allowedTypes = {
  'ModiconNIP2311Config',
  'ModiconPDT3100Config',
  'ModiconDDI3725Config',
  'ModiconDDO3705Config',
};

factory ModiconMomentumStackConfig.fromJson(Map<String, dynamic> json) {
  final cfg = _$ModiconMomentumStackConfigFromJson(json);
  cfg.subdevices.retainWhere((a) => _allowedTypes.contains(a.runtimeType.toString()));
  return cfg;
}
```

The dialog's `DropdownButtonFormField` is naturally bounded by `_availableModiconSubdevices.keys`. The `retainWhere` guards against hand-edited JSON or future pages that paste a non-Modicon asset into the `subdevices` list. Strict mode (throw) would break backward compatibility — silent filter + log is the existing project convention (registry.dart:145-151 already wraps fromJson errors in try/catch).

### 4.3 Layout — same `_SubdeviceNormalized` Row pattern

Reuse the `_SubdeviceNormalized` wrapper logic from beckhoff.dart:114-134. Either:

(a) **Duplicate** it in `modicon.dart` (private class — Beckhoff's is `_SubdeviceNormalized`, file-private, can't be imported across files). Simplest, mirrors the no-cross-cutting precedent.

(b) **Promote** to `common.dart` (`SubdeviceNormalized`, public). Costs one common.dart edit. Better long-term.

**Recommendation: (a) duplicate.** v2.0 is additive; refactoring shared widget pattern is a separate cleanup milestone. The duplication is ≈20 lines. Acceptable.

### 4.4 Native size for MomentumStack

CX5010 uses `_cxNativeSize = Size(1055, 1000)` (beckhoff.dart:53). For Modicon there is no single equivalent — the head (NIP2311) defines the stack height. From `.planning/research/dxf/README.md`: I/O base is 107 × 152 mm. Recommendation: use the I/O base height as the stack reference (`_momentumNativeHeight = 1520`, with each module at `Size(natureWidth, 1520)`). The NIP2311 head and PDT3100 may be physically taller; verify against `NIP2311_mcadid0005722.dxf` `$EXTMIN/$EXTMAX` during plan phase. If heights differ, the head sets the reference and modules `FittedBox.fitHeight` to it (which is exactly what `_SubdeviceNormalized` already does for Beckhoff).

---

## 5. Registry Modification (the only edit outside `modicon.*` files)

`lib/page_creator/assets/registry.dart` — add 10 lines (5 entries × 2 maps), plus 1 import.

```dart
// Line ~31 (add import next to other asset imports)
import 'modicon.dart';

// In _fromJsonFactories (line ~37), add 5 entries:
ModiconMomentumStackConfig: ModiconMomentumStackConfig.fromJson,
ModiconNIP2311Config: ModiconNIP2311Config.fromJson,
ModiconPDT3100Config: ModiconPDT3100Config.fromJson,
ModiconDDI3725Config: ModiconDDI3725Config.fromJson,
ModiconDDO3705Config: ModiconDDO3705Config.fromJson,

// In defaultFactories (line ~78), add 5 entries:
ModiconMomentumStackConfig: ModiconMomentumStackConfig.preview,
ModiconNIP2311Config: ModiconNIP2311Config.preview,
ModiconPDT3100Config: ModiconPDT3100Config.preview,
ModiconDDI3725Config: ModiconDDI3725Config.preview,
ModiconDDO3705Config: ModiconDDO3705Config.preview,
```

**Confirmed by direct read of registry.dart:** every existing asset appears in BOTH maps (lines 36-76 and 78-117). The palette UI iterates `defaultFactories` and the JSON parser uses `_fromJsonFactories`; omitting from either map silently breaks one path. The convention is mechanical and exact — replicate it.

`AssetRegistry.parse()` uses `factory.key.toString() == assetName` (registry.dart:139), so the JSON `asset_name` MUST equal the Dart class name literally. The `BaseAsset` constructor (common.dart:107-111) auto-sets `variant = runtimeType.toString()` so this works without a manual `asset_name` field — the codegen's `toJson` emits `variant` mapped to `"asset_name"`. **No special handling needed; just match the registry key exactly.**

---

## 6. Data Flow — Momentum Edition

### 6.1 Editor flow

```
[Operator opens Page Editor]
     ↓
[Palette shows MomentumStack + 4 modules]      ← defaultFactories
     ↓ drop onto canvas
[ModiconMomentumStackConfig.preview()]
     ↓ open configure(context)
[Add Subdevice dropdown — filtered to 4 types] ← _availableModiconSubdevices
     ↓ select e.g. "NIP2311"
[subdevices.add(ModiconNIP2311Config.preview())]
     ↓ tap child in list
[showDialog(builder: (_) => child.configure(context))]
     ↓ edit KeyFields
[child fields mutate in place; same reference]
     ↓ close dialog → page save
[AssetPage.toJson() → AssetListConverter().toJson()
      → ModiconMomentumStackConfig.toJson()
      → @AssetListConverter() emits children as polymorphic JSON]
     ↓ SharedPreferences.setString(storageKey, …)
```

### 6.2 Runtime flow (StateMan-driven)

```
[Page loads from prefs]
     ↓ AssetRegistry.parse()  ← recursively type-routes via asset_name
[ModiconDDI3725Config built in widget tree]
     ↓ build(context) → ConsumerWidget
[FutureBuilder<StateMan>(future: ref.watch(stateManProvider.future))]
     ↓ StateMan resolved
[StreamBuilder + _combinedStream(LinkedHashMap{
     "raw":   rawStateKey,
     "force": forceValuesKey,
}, stateMan)]
     ↓ each subscribe() returns Stream<DynamicValue> (ref-counted, AutoDisposing)
[CombineLatestStream → Map<String, DynamicValue>]
     ↓
[_ledStates16(data) → List<IOState>(16)]      ← bit-test rawStateKey 0..15
     ↓
[IO16Widget(ledStates: leds, …)]
     ↓ CustomPaint
[IO16Painter / IO16LedBlockPainter → screen]
```

**Reuse `_combinedStream` from `beckhoff.dart`?** It is private (`_combinedStream`, beckhoff.dart:1272). Same recommendation as `_SubdeviceNormalized`: duplicate in `modicon.dart` for v2.0. Trivial cost (15 lines), keeps modules independent.

**Generalise `_ledStates` from 8 to N?** The 8-LED version is private. Write `_ledStates16` in `modicon.dart`:

```dart
List<IOState> _ledStates16(Map<String, DynamicValue> data) {
  final raw = data["raw"]?.asInt;
  final force = data["force"]?.asInt;
  return List.generate(16, (i) {
    if (force != null) {
      // Force value encoding TBD — Schneider Momentum may differ from Beckhoff's
      // 1=forcedLow, 2=forcedHigh single-byte encoding. Confirm during plan phase.
    }
    if (raw == null) return IOState.low;
    return (raw & (1 << i)) != 0 ? IOState.high : IOState.low;
  });
}
```

**Note for plan phase:** verify Schneider Momentum force-encoding semantics — Beckhoff's `1=forcedLow / 2=forcedHigh` (beckhoff.dart:1290-1299) is a Beckhoff convention. Momentum likely uses two parallel bitmasks (force-mask + force-value) but this is in the PLC-side abstraction layer (out of scope per PROJECT.md:19 — "Backend Modbus key plumbing — assumes StateMan keys already exist"). Plan phase confirms with the user what the PLC actually exposes.

### 6.3 StateMan key conventions

No new conventions. Reuse the Beckhoff vocabulary literally — the operator will configure these via `KeyField` (common.dart:246) at edit time, pointing at whatever the PLC exposes:

| Module | Field name | Type | Notes |
|---|---|---|---|
| ModiconDDI3725Config / DDO3705Config | `rawStateKey` | `String?` | uint16 bitmask (bit i = channel i) |
| same | `forceValuesKey` | `String?` | force encoding TBD (plan phase) |
| same | `descriptionsKey` | `String?` | OPC UA array of 16 strings |
| same | `onFiltersKey`, `offFiltersKey` | `String?` | per-channel filter ms (mirrors EL1008) |
| same | `nameOrId` | `String` | non-null, defaults to `"1"` per EL1008 |
| ModiconNIP2311Config | `runKey`, `pwrKey`, `errKey`, `stKey`, `testKey` | `String?` each | single-bool status |
| ModiconPDT3100Config | `inputOkKey` | `String?` | single-bool |
| ModiconMomentumStackConfig | (no own keys) | — | aggregates via `allKeys` |

All `*Key` suffix fields are automatically picked up by `BaseAsset.allKeys` introspection (common.dart:223). Confirmed — **no `allKeys` overrides needed on the four leaf module configs**.

---

## 7. Test Infrastructure

### 7.1 File locations (mirror elevator/sensor precedent)

| Layer | File | Pattern |
|---|---|---|
| JSON round-trip | `test/page_creator/assets/modicon_config_test.dart` | `elevator_config_test.dart` |
| Stack child mgmt + allKeys | `test/page_creator/assets/modicon_stack_test.dart` | `elevator_layout_test.dart` |
| Painter shouldRepaint + goldens | `test/page_creator/assets/modicon_painter_test.dart` | `elevator_painter_test.dart` |
| Runtime + StateMan integration | `test/page_creator/assets/modicon_widget_test.dart` | `elevator_widget_test.dart` / `sensor_widget_test.dart` |

The elevator harness establishes the golden pattern that Modicon **must** mirror (verified by direct read of `elevator_painter_test.dart:64-96`):

```dart
await tester.pumpWidget(
  MaterialApp(home: Scaffold(body: Center(
    child: RepaintBoundary(
      key: elevatorKey,
      child: SizedBox(width: 200, height: 300, child: CustomPaint(...)),
    ),
  ))),
);
await tester.pump(Duration.zero);   // no pumpAndSettle — Pitfall 6 lock
await expectLater(find.byKey(elevatorKey), matchesGoldenFile('goldens/elevator/…'));
```

Key locks transferred to Modicon:
- `RepaintBoundary` with `Key('momentum_painter_golden')` per test
- Deterministic `SizedBox` (suggest 200×300 or scaled to module native aspect)
- `await tester.pump(Duration.zero)` — never `pumpAndSettle()` (animations would shift)
- `AlwaysStoppedAnimation(0)` for the IO16 animation arg (force-LED pulse must be frozen)

### 7.2 Golden location

`test/page_creator/assets/goldens/modicon/` — new folder, mirrors `goldens/elevator/` and `goldens/sensor/` already present at HEAD. Failed-diff outputs land in `test/page_creator/assets/failures/` (auto-created by `flutter_test`; existing convention — both `elevator_with_children_progress_*` failures present today).

### 7.3 Golden matrix (recommended minimum)

| Module | Goldens (per painter) |
|---|---|
| DDI3725 | `all_off`, `all_on`, `alternating_0xAAAA`, `forced_mix`, `disconnected` |
| DDO3705 | `all_off`, `all_on`, `alternating_0x5555`, `forced_mix`, `disconnected` |
| NIP2311 | `run_ok`, `err_red`, `disconnected` |
| PDT3100 | `input_ok`, `fault` |
| MomentumStack | `stack_full` (NIP + PDT + DI + DO in canonical order) |

Total ≈ 14 goldens. Note: per CLAUDE.md (`dart_test.yaml`) "golden tests skipped unless `--update-goldens`". First-run generates them; CI verifies. Modicon goldens follow the existing `flutter test --update-goldens` workflow.

### 7.4 Leak tests

PROJECT.md:14 mandates leak tests. The recent elevator/sensor v1.0 work established `StreamSubscription` cancellation tests. The Beckhoff family **does not have leak tests today** — Modicon should land them since the user has flagged this as a v2.0 directive. Use the elevator/sensor pattern: spin up the widget, dispose, verify `stateMan.subscriberCount(key)` returns to baseline. (Confirm exact API during plan phase by reading the elevator leak test fixture.)

---

## 8. Recommended Build Order

The build-order question has three coherent answers; below is the rationale for each and the recommendation.

### Option A: Module-first → Stack-last (RECOMMENDED)

```
Plan 01: IO16 painter + DDI3725 (16-ch DI module)
Plan 02: DDO3705 (clones DDI3725 with O semantics — minor delta)
Plan 03: NIP2311 head (introduces RJ45 reuse + status LEDs)
Plan 04: PDT3100 (simplest — could swap with 03)
Plan 05: ModiconMomentumStackConfig (compose 01-04 + filtered subdevices)
```

**Rationale:**
- DDI3725 is the **most operator-visible** module (PROJECT.md:11 "16-ch DI strip" with force overrides and detail dialog — the richest feature surface). Landing it first proves the riskiest path: 16-LED painter scale-up, IOState reuse, force-overlay semantics, detail dialog. Every other module is simpler.
- The stack is just a `Row` of children — composing already-tested children is the *easiest* step. Building the stack with stub children produces ambiguous test results ("is the stack broken, or the children?").
- DDO3705 ≈ DDI3725 minus the input-filter keys, plus writable bit — a short delta after the DI module is locked, exercising the DI/DO symmetry that PROJECT.md identifies (one DXF base covers both).
- Stack-last means the registry edits accumulate by plan (each module registers itself when shipped) — but the stack's `_availableModiconSubdevices` whitelist depends on the module classes existing first.
- Mirrors how Beckhoff likely evolved structurally: EL leaf modules predate the CX5010 wrapper (the wrapper composes leaves — the dependency direction is one-way).

### Option B: Stack-first (NOT RECOMMENDED)

Lock the composition contract first, then drop modules in. Sounds clean but: the stack adds no UX value without modules to host, the whitelist is hardcoded so it cannot be tested without module classes (chicken-and-egg), and a Row-of-empty-list is the trivially simplest part. Defer.

### Option C: Head-first (NIP2311) (ALTERNATIVE)

If operator recognition is in doubt and the head module is the visual identity anchor, landing NIP2311 first lets the user sanity-check Schneider cream colour, body proportions, RJ45 placement, and the status LED tower before investing in 16-channel grid work. **Switch to Option C if the team wants design validation before scaling.** Otherwise Option A is safer because it surfaces the painter scale-up risk first.

### Final recommendation

**Option A.** It front-loads the highest-risk technical work (16-LED painter, force overlay, detail dialog) while delivering the most visible operator feature first. The stack is mechanical compose-work and is best built when the parts are proven.

---

## 9. Anti-Patterns to Avoid

### 9.1 Stacking two `IO8Widget` instances side-by-side

**What people do:** Save a day of painter work by laying out two IO8Widgets in a `Row`.
**Why it's wrong:** Sub-pixel seams break goldens; double-prints body chrome (top labels, terminal blocks, manufacturer text); wrong physical mapping (one body, not two); future force-encoding changes need two edits.
**Do this instead:** New `IO16LedBlockPainter extends BaseLedBlockPainter` in `lib/painter/modicon/io16.dart`, with a 4×4 or 2×8 grid laid out in one pass.

### 9.2 Registering in only one factory map

**What people do:** Add to `_fromJsonFactories` but forget `defaultFactories` (or vice versa).
**Why it's wrong:** JSON loads but palette doesn't show it; or palette shows it but saved pages crash to load.
**Do this instead:** Mechanical pair — every new asset gets ONE line in EACH map. Verify with `grep -c "ModiconNIP2311Config" registry.dart` — must return ≥2.

### 9.3 Moving shared helpers to a new common file in v2.0

**What people do:** "Refactor while we're here" — move `_SubdeviceNormalized`, `_combinedStream`, `_ledStates` to a shared file.
**Why it's wrong:** v2.0 is additive. Touching Beckhoff while shipping Modicon doubles the test surface, risks regressing the existing family, and violates the brownfield discipline. The duplication is ≈40 LoC.
**Do this instead:** Duplicate in `modicon.dart`. Flag for a separate refactor milestone.

### 9.4 Generalising painters now ("but EL1004 will need it")

**What people do:** Build a parameterised `IONLedBlockPainter(N)` to "future-proof" 4/8/16 variants.
**Why it's wrong:** The existing codebase rejected this pattern — `IO6LedBlockPainter` is a sibling, not a parameter, because the LED grid layout (big-small-big for the 6-channel, 2×4 for the 8-channel) is *not* a number-of-cells problem, it's a per-module geometry. The DXFs prove each module has a hand-tuned layout.
**Do this instead:** New sibling class per channel count. Generalise when there are 4+ siblings AND the layouts are actually uniform.

### 9.5 Adding per-channel state keys (16 separate `*Key` fields)

**What people do:** Mirror an OPC UA naming structure 1:1 with 16 fields on the config.
**Why it's wrong:** Existing pattern uses a single `rawStateKey` (bitmask uint16) + a `descriptionsKey` (OPC UA array of 16 strings). Per-channel string fields would (a) explode `toJson()` size, (b) break the existing `allKeys` introspection contract, (c) deviate from EL1008 operator muscle memory.
**Do this instead:** One `rawStateKey`, one `forceValuesKey`, one `descriptionsKey`. The PLC-side OPC UA structure maps a 16-element array to that one key — that abstraction is the StateMan layer's job (out of v2.0 scope).

### 9.6 Storing children with explicit `ChildEntry { id, child }` wrapper

**What people do:** Apply the conveyor `ChildGateEntry` pattern (id + position + side) to MomentumStack children.
**Why it's wrong:** Stack children render in list order (Row position = list index). There is no "side" or "fractional position" — modules slot in linearly. The `ChildGateEntry` wrapper was for conveyors where children can be anywhere on the belt. Adding it to MomentumStack creates an artificial id-tracking burden, breaks the symmetry with CX5010, and doesn't match physical hardware (modules clip onto a rail in a fixed order).
**Do this instead:** Bare `List<Asset>` with `@AssetListConverter()`, exactly as CX5010.

### 9.7 Conflating NIP2311 status LEDs with `IOState`

**What people do:** "An LED is an LED" — use `IOState.high` for the RUN indicator.
**Why it's wrong:** NIP2311 RUN/PWR/ERR/ST/TEST are single-bool status lamps with their own colour code (RUN=green, ERR=red, etc.) and no force/disconnected semantics. `IOState` encodes I/O-channel-specific concepts (forcedLow/forcedHigh, error). Forcing the abstraction creates bug surface (an "error" force-state on a status lamp makes no sense).
**Do this instead:** NIP2311 status lights use plain `bool` per indicator + per-indicator colour constants in `nip2311.dart`. Reserve `IOState` for the channel painters (IO16).

---

## 10. Integration Points Summary

### NEW files (12 + generated)

| File | Purpose |
|---|---|
| `lib/page_creator/assets/modicon.dart` | 5 configs + dialogs + stream helpers |
| `lib/page_creator/assets/modicon.g.dart` | Codegen output (build_runner generated) |
| `lib/painter/modicon/io16.dart` | 16-LED block painter + IO16Widget |
| `lib/painter/modicon/ddi3725.dart` | DI module body painter (wraps IO16) |
| `lib/painter/modicon/ddo3705.dart` | DO module body painter (wraps IO16) |
| `lib/painter/modicon/nip2311.dart` | Head adapter body + dual RJ45 + status LEDs |
| `lib/painter/modicon/pdt3100.dart` | Power-distribution body painter |
| `test/page_creator/assets/modicon_config_test.dart` | JSON round-trip + backward compat |
| `test/page_creator/assets/modicon_stack_test.dart` | Child mgmt, allKeys flatten, whitelist filter |
| `test/page_creator/assets/modicon_painter_test.dart` | shouldRepaint + goldens harness |
| `test/page_creator/assets/modicon_widget_test.dart` | StateMan integration + leaks |
| `test/page_creator/assets/goldens/modicon/` | ~14 PNG goldens (folder) |

### MODIFIED files (1)

| File | Change |
|---|---|
| `lib/page_creator/assets/registry.dart` | +1 import + 5 entries in `_fromJsonFactories` + 5 in `defaultFactories` |

### UNTOUCHED (verified by direct read)

- `lib/page_creator/assets/beckhoff.dart` — no changes (imported as cross-package references only)
- `lib/painter/beckhoff/*` — imported via `show` clauses: `BaseLedBlockPainter`, `IOState`, `EthernetPortPainter`, `bodyColor`
- `lib/page_creator/assets/common.dart` — no changes (BaseAsset.allKeys regex picks up `*Key` fields automatically)
- `lib/page_creator/page.dart` — no changes (`AssetListConverter` reused as-is)
- Riverpod providers — no changes (`stateManProvider` is the existing contract)

### Cross-file imports the new code uses

```dart
// In lib/page_creator/assets/modicon.dart:
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';
import 'common.dart';
import '../page.dart';                                  // for @AssetListConverter()
import '../../providers/state_man.dart';                // for stateManProvider
import '../../painter/modicon/io16.dart';
import '../../painter/modicon/ddi3725.dart';
import '../../painter/modicon/ddo3705.dart';
import '../../painter/modicon/nip2311.dart';
import '../../painter/modicon/pdt3100.dart';

part 'modicon.g.dart';

// In lib/painter/modicon/io16.dart:
import '../beckhoff/io8.dart' show BaseLedBlockPainter, IOState, bodyColor;

// In lib/painter/modicon/nip2311.dart:
import '../beckhoff/ek1100.dart' show EthernetPortPainter;
```

---

## Sources

All findings verified by direct read of repo files at HEAD on branch `elevator` (commit `d5a8d5d`, 2026-05-11):

- `lib/page_creator/assets/registry.dart` (full read — confirmed dual-map registration, parse-by-toString)
- `lib/page_creator/assets/beckhoff.dart` (CX5010 lines 1-285, EK1100 287-505, EL1008 507-660, helpers 1272-1300, EL1008 runtime 1302-1351)
- `lib/page_creator/assets/common.dart` (full read — confirmed `BaseAsset.allKeys` regex, `variant` auto-set, KeyField semantics)
- `lib/painter/beckhoff/io8.dart` (full read — confirmed BaseLedBlockPainter hierarchy and IO8/IO6 split-painter precedent)
- `lib/painter/beckhoff/ek1100.dart` (full read — confirmed EthernetPortPainter is generic and reusable, mm-based design space)
- `lib/page_creator/page.dart:1-47` (confirmed `AssetListConverter` defines polymorphic child JSON contract)
- `test/page_creator/assets/elevator_painter_test.dart` (full read — confirmed RepaintBoundary + pump(Duration.zero) golden harness)
- `test/page_creator/assets/goldens/elevator/` and `goldens/sensor/` (directory listings — confirmed folder layout precedent)
- `.planning/PROJECT.md` (full read — confirmed v2.0 scope and pattern-source-of-truth lock)
- `.planning/research/dxf/README.md` (full read — confirmed DXF references and bounding-box source-of-truth)

---
*Architecture research for: Modicon Momentum I/O assets (v2.0 milestone) — additive layering on existing Beckhoff family pattern*
*Researched: 2026-05-11*
