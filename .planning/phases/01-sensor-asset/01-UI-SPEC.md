---
phase: 1
slug: sensor-asset
status: draft
shadcn_initialized: false
preset: none
created: 2026-05-05
---

# Phase 1 — UI Design Contract: Sensor Asset

> Visual and interaction contract for the multi-kind sensor asset (red light beam, optic field, inductive field). The "UI surface" is a Flutter `CustomPainter` glyph + a Material config dialog + an on-canvas tooltip — no React, no shadcn, no component library. All locked decisions from `01-CONTEXT.md` are pre-populated and binding.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (Flutter `CustomPainter` + Material 3) |
| Preset | not applicable |
| Component library | Material 3 (`SegmentedButton`, `Tooltip`, `TextFormField`, `KeyField`, `SizeField`, `CoordinatesField`) |
| Icon library | `Icons.*` (Material) — only inside config dialog and tooltip; never inside the painter |
| Font | Theme default (inherits `Theme.of(context).textTheme`); painter labels use `TextPainter` with theme `bodySmall` size |
| Colour-picker widget | `flutter_colorpicker` `ColorPicker` (matches `conveyor_gate.dart:627` and `text.dart:661`) — open via `_showColorPicker` helper |
| Cross-references | `lib/page_creator/assets/conveyor_gate.dart` (variant dispatch + editor pattern), `lib/page_creator/assets/led.dart` (active colour convention + null-aware painter colour) |

---

## Spacing Scale

Painter geometry uses **proportional units** (fractions of `Size.shortestSide`), not absolute pixels — this is the established tfc-hmi2 convention so glyphs read at any asset size from 32 px to 256 px. Material widgets in the config dialog use the standard 4-multiple ladder.

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Tooltip line gap; segmented-button inner padding |
| sm | 8px | `SizedBox(height: 8)` between paired form fields (e.g. rising key + falling key) |
| md | 16px | `SizedBox(height: 16)` between distinct config sections (Kind → State key → Polarity → Delays → Colours → Label) |
| lg | 24px | Outer padding of the config dialog `Container` (matches `led.dart:64` `EdgeInsets.all(16)` is the existing baseline; standardise upward to 24 for the new dialog to leave room for the Kind segmented button) |
| xl | 32px | Reserved — not used in this phase |

### Painter proportional ladder (Claude's discretion, locked here)

| Painter token | Fraction of `size.shortestSide` | Usage |
|---------------|----------------------------------|-------|
| `kHousingFraction` | 0.25 | Diameter of optic / inductive housing puck; width of red-light emitter & receiver pucks |
| `kBeamStrokeWidth` | 0.06 | Stroke width of the beam line (red light kind) |
| `kFieldStrokeWidth` | 0.04 | Outline stroke for inactive field shape (optic / inductive) |
| `kBorderStrokeWidth` | 0.05 | Housing border stroke (matches `led.dart:300` `2px` at small sizes; proportional here) |
| `kDashOnPx` | 6.0 (absolute) | Dashed beam-line "on" segment length when broken |
| `kDashOffPx` | 4.0 (absolute) | Dashed beam-line "off" segment length when broken |
| `kFieldFillAlpha` | 0.40 | Active-state field-shape fill opacity (specifics from `01-CONTEXT.md`) |
| `kLabelFontFraction` | 0.30 | Label text size as fraction of `size.shortestSide` (matches `led.dart:333` `size.height * 0.6` for the `!` glyph; sensor label is smaller — used for tag like "PE-101A") |

**Dashed pattern note:** dash lengths are absolute (not proportional) so the pattern reads consistently across asset sizes. Stroke width itself scales proportionally — the visual rhythm is "thick line with frequent gaps", not "tiny line with tiny gaps" at 32 px.

Exceptions: none. All Material widget spacing follows the standard 4-multiple ladder above.

---

## Typography

The sensor asset itself only renders text in two places: the painter's optional label/tag (drawn via `TextPainter`) and the tooltip (Material `Tooltip` widget). The config dialog uses standard Material text styles inherited from `Theme.of(context).textTheme`.

| Role | Size | Weight | Line Height | Where used |
|------|------|--------|-------------|------------|
| Painter label (tag) | `size.shortestSide * 0.30` (proportional, ≈ 9-39 px depending on asset) | `FontWeight.w600` (semibold) | 1.0 (single line, no wrap) | Sensor tag drawn next to glyph (e.g. "PE-101A") via `TextPainter` |
| Tooltip body | `Theme.of(context).textTheme.bodySmall.fontSize` (12 px under default M3 theme) | `FontWeight.w400` (regular) | 1.4 | "Rising: 50ms\nFalling: 30ms" — two lines |
| Dialog section label | `Theme.of(context).textTheme.bodySmall.fontSize` (12 px) | `FontWeight.w400` (regular) | 1.5 | "Gate Variant"-style mini-headers above each segmented button (mirrors `conveyor_gate.dart:690`) |
| Dialog field label | `Theme.of(context).textTheme.bodyMedium.fontSize` (14 px) | `FontWeight.w400` | 1.5 | `TextFormField.decoration.labelText` and `KeyField` label |

Locked: exactly **2 weights** (regular 400 + semibold 600), exactly **3 effective sizes** (painter label proportional, tooltip 12 px, dialog 14 px). No new font families; everything inherits the Material 3 theme of the host app.

---

## Color

The sensor's colour contract is governed by **ISA-101** (HP-HMI): grayscale base, accent reserved for *operator-meaningful* state changes only. There is no "brand palette" — the colours are state-driven and derive from per-instance `Color` config fields with sensible defaults.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) — neutral grey | `Colors.grey.shade600` (housing strokes, beam-clear neutral line, inactive painter fill when stale) | Housing borders, baseline beam line when state=true (clear), all painter geometry that is not state-coloured |
| Secondary (30%) — disconnected/stale | `Colors.grey` (i.e. `Colors.grey.shade500` — exact value used by `conveyor_gate.dart:325, 350` for the `baseColor = Colors.grey` convention) | Whole sensor rendered in this colour when state stream is stale, errored, has no value, or `detectionKey` is empty |
| Accent (10%) — active detection | `Colors.green` (per-instance `activeColor`, default `Colors.green` matching `led.dart:49`'s `onColor = Colors.green`) | (a) Field-shape fill at α=0.40 when active, (b) field-shape outline when inactive, (c) dashed broken-beam line in red-light kind |
| Inactive colour (per-instance config) | `Colors.grey.shade400` (Claude's discretion default per `01-CONTEXT.md` "Specific Ideas") | (a) Field-shape outline when inactive, (b) red-light puck fill when state=true (cleared), (c) painter label colour |
| Destructive | not used in this phase | Sensor has no destructive actions — config dialog has no Delete button (assets are removed via the page editor's outer chrome, not this dialog) |

### Accent reserved for

The active accent colour (`activeColor`, default `Colors.green`) is reserved for **state-driven detection signalling only**:

1. Optic field cone — **filled at α=0.40** with `activeColor` when `isActive == true`
2. Inductive field bubble — **filled at α=0.40** with `activeColor` when `isActive == true`
3. Red-light beam line — **dashed line in `activeColor`** when broken (`isActive == true` per the locked dark-on / beam-broken convention in `01-CONTEXT.md`)
4. Optic/inductive field outline — **outlined in `activeColor`** when `isActive == false` (the field is *visible* but not *filled*; this is the inactive-but-defined state)

The accent colour is **never** used for: housing strokes, label text, dialog chrome, hover effects, or focus rings. Housings remain grey under all states; only the field/beam communicates detection.

### Colour state matrix (locked — drives the 8-golden test contract)

| Kind | State (after polarity) | Housing | Beam / Field |
|------|-----------------------|---------|--------------|
| `redLight` | clear (bool true) | grey pucks | solid neutral grey beam line |
| `redLight` | broken (bool false) | grey pucks | **dashed `activeColor` beam line** (6-on / 4-off) |
| `redLight` polarity-inverted | clear (bool false → "clear") | grey pucks | solid neutral grey beam line |
| `redLight` polarity-inverted | broken (bool true → "broken") | grey pucks | **dashed `activeColor` beam line** |
| `opticField` | inactive | grey housing | **outlined `inactiveColor`** cone |
| `opticField` | active | grey housing | **filled `activeColor` α=0.40** cone (outline still visible underneath) |
| `inductiveField` | inactive | grey housing | **outlined `inactiveColor`** bubble |
| `inductiveField` | active | grey housing | **filled `activeColor` α=0.40** bubble |
| (any) | stale / disconnected | overall `Colors.grey` | overall `Colors.grey` (no state colour at all) |

---

## Copywriting Contract

The sensor exposes copy in three surfaces: the config dialog labels, the painter's optional tag, and the on-hover tooltip. All copy is locked here — implementers must not paraphrase.

| Element | Copy |
|---------|------|
| Config dialog title (host-provided) | `"Configure Sensor"` (set by the page editor's outer dialog chrome — the asset's `configure(BuildContext)` returns the body only, mirroring `conveyor_gate.dart:159`) |
| Kind selector header | `"Sensor Kind"` |
| Kind segment labels | `"Red Light"` / `"Optic Field"` / `"Inductive Field"` (Title Case, two words each) |
| Detection state-key label | `"Detection State Key"` (matches operator vocabulary per FEATURES.md — never "OPC UA Key 1") |
| Active polarity toggle title | `"Invert Active Polarity"` |
| Active polarity toggle subtitle (when off) | `"Active when state is true"` |
| Active polarity toggle subtitle (when on) | `"Active when state is false"` |
| Rising-edge-delay key label | `"Rising Edge Delay Key"` |
| Falling-edge-delay key label | `"Falling Edge Delay Key"` |
| Active colour row | `"Active Color"` |
| Inactive colour row | `"Inactive Color"` |
| Tag/label field label | `"Tag (e.g. PE-101A)"` |
| Tag field hint | `"Optional"` |
| Primary CTA | not applicable — config dialogs in tfc-hmi2 mutate config in-place via `setState` and persist on dialog close; there is no "Save" button (matches `conveyor_gate.dart` and `led.dart` — neither has a primary CTA) |
| Empty state (no `detectionKey` configured) | The painter renders the glyph in `Colors.grey` (visual-only signal); **no text is drawn over the canvas**. The tooltip in this state shows `"Detection key not set"` |
| Stale stream state | The painter renders the glyph in `Colors.grey` (visual-only); the tooltip in this state shows `"Disconnected"` (matches `conveyor_gate.dart:429` `'Disconnected'` label) |
| Error state (snapshot.hasError) | Same visual as stale (grey glyph); the tooltip shows `"Stream error"` |
| Tooltip — both delay keys configured | `"Rising: <ms>ms\nFalling: <ms>ms"` (literal two-line `\n`-joined string; locked in `01-CONTEXT.md` decisions) |
| Tooltip — rising configured, falling not | `"Rising: <ms>ms\nFalling: —"` (em-dash for unconfigured) |
| Tooltip — neither configured | `"Rising: —\nFalling: —"` |
| Tooltip — keys configured but no value yet | `"Rising: …\nFalling: …"` (ellipsis while `snapshot.hasData == false`) |
| Destructive confirmation | not applicable — sensor config dialog has no destructive actions |

### Tooltip lifecycle copy contract

The tooltip is **only mounted while open**. When dismissed, all rising/falling-key subscriptions are cancelled (locked in `01-CONTEXT.md`). Implementation: use Material `Tooltip` with a custom `richMessage` builder that opens its own `StreamBuilder` per delay key; the `Tooltip`'s open-state controls subscription lifetime via Flutter's standard widget mount/unmount.

---

## Interaction Contract

This section is non-standard for the template but mandatory for this phase — gestures and tooltip lifecycle are first-class design concerns per the user directive in `01-CONTEXT.md`.

### Tap-to-configure gesture

- **Widget:** `GestureDetector(onTap: ...)` wrapping the `CustomPaint` returned by `Sensor.build(context)`. **Never** painter-level hit detection. **Never** `Listener` (no need for raw pointer events).
- **Behaviour at rest:** tap opens the config dialog via the page editor's existing dialog plumbing (same pathway `conveyor_gate.dart` uses for its force dialog; sensor uses the standard `entry.configure(context)` route).
- **Behaviour mid-translation (Phase 3 forward-compat):** the gesture **must already be tap-friendly through arbitrary `Transform.translate` / `Positioned` ancestors**. Concretely: do not wrap the sensor in `IgnorePointer`, do not use `Transform()` raw constructor (use `Transform.translate(...)` named constructor — its `transformHitTests` defaults to `true`).
- **Editor mode vs runtime mode:** in editor mode the page editor's outer `GestureDetector` intercepts taps for selection/move; the sensor's own tap is bypassed. In runtime mode the sensor's tap fires. (Standard tfc-hmi2 behaviour; the sensor inherits this from its `BaseAsset` placement, no extra wiring needed.)
- **Acceptance test (Phase 1):** widget test `sensor_test.dart` — pump a `Sensor` with a non-empty config inside a `MaterialApp`, simulate a tap, assert a dialog appears (find by `find.byType(AlertDialog)` or however `BaseAsset.configure` renders).

### Tooltip trigger

- **Widget:** Material `Tooltip(message: ..., child: GestureDetector(...))` — `Tooltip` wraps the `GestureDetector`, not the other way around, so long-press on touch and hover on desktop both trigger the tooltip without consuming the tap.
- **Trigger modes:** mouse hover (desktop), long-press (touch). Default Material thresholds.
- **Subscription lifecycle (locked):** the tooltip's content widget owns two independent `StreamBuilder`s for rising and falling delay keys. These streams are constructed **inside the tooltip content widget's `build`**, but only when the tooltip is open (Flutter mounts the tooltip overlay on demand and unmounts on dismiss — this satisfies the locked contract without explicit subscription bookkeeping).

### Polarity inversion semantics (locked)

The `invertActivePolarity` bool is applied **after** the raw bool is read from the stream and **before** the painter receives `isActive`:

```
isActive = invertActivePolarity ? !rawBool : rawBool
```

The tooltip and label are **not** affected by polarity inversion — they show the same key resolution regardless of polarity setting. Polarity is purely a visual-mapping concern.

---

## Painter Decomposition

This section is non-standard for the template but binding — it locks the contract that prevents Pitfall 3 (painter state leakage between kinds).

### One painter class per kind

Three classes in `lib/page_creator/assets/sensor_painter.dart`:

1. `RedLightBeamPainter extends CustomPainter`
2. `OpticFieldPainter extends CustomPainter`
3. `InductiveFieldPainter extends CustomPainter`

Dispatch via a `_createPainter(SensorKind, bool isActive, Color activeColor, Color inactiveColor)` switch in `_SensorState` (mirrors `conveyor_gate.dart:240-266`). **No `switch (kind)` inside any `paint()` method.**

### `shouldRepaint` contract (per QUAL-01)

Every painter overrides `shouldRepaint(oldDelegate)` and returns `true` when **any** of the following is true:

- `oldDelegate.runtimeType != runtimeType` (kind changed — covers Pitfall 3)
- `oldDelegate.isActive != isActive`
- `oldDelegate.activeColor != activeColor`
- `oldDelegate.inactiveColor != inactiveColor`
- `oldDelegate.label != label` (when label rendering is enabled)

### Painter constructor signature (uniform across all three)

```dart
RedLightBeamPainter({
  required this.isActive,
  required this.activeColor,
  required this.inactiveColor,
  this.label,         // optional — drawn below glyph if non-null/non-empty
  this.isStale = false, // when true, override active/inactive with Colors.grey
});
```

### Glyph layout (locked, painter's local coordinate frame is `Size`)

- **Red light:** emitter centre at `(0.15·w, 0.50·h)`, receiver centre at `(0.85·w, 0.50·h)`; both pucks `kHousingFraction · shortestSide` in diameter. Beam line spans the centres at stroke `kBeamStrokeWidth · shortestSide`. **Default orientation horizontal**; vertical orientation comes from `Coordinates.angle` (the painter never inspects rotation — the parent applies it).
- **Optic field:** housing rectangle on left at `(0.05·w, 0.30·h)` to `(0.30·w, 0.70·h)`; cone fans rightward — apex at the housing's right-centre, base at `(0.95·w, 0.20·h)` to `(0.95·w, 0.80·h)`.
- **Inductive field:** housing puck centred at `(0.30·w, 0.50·h)` with diameter `kHousingFraction · shortestSide`; near-field bubble is an ellipse centred at `(0.65·w, 0.50·h)` with horizontal radius `0.25·w` and vertical radius `0.30·h` (slightly taller than wide — matches near-field IEC pictograms).

### Stale-stream override

When `isStale == true`, the painter ignores `activeColor` / `inactiveColor` and renders the entire glyph (housing, beam/field, label) in `Colors.grey`. There is no "stale outline" or "fault badge" in this phase — that's a Phase 4 concern (ELEV-15 + QUAL-06).

---

## Config Dialog Layout (locked field order)

Mirrors `_ConveyorGateConfigEditor` structure (`conveyor_gate.dart:655-918`):

```
┌─ Live Preview (150×150 CustomPaint) ────────────────────────┐
│  [renders current kind with isActive=true for visibility]   │
│  [no Play button — sensor has no animation to preview]      │
└─────────────────────────────────────────────────────────────┘
─── Divider ──────────────────────────────────────────────────
"Sensor Kind"  ← Theme.of(context).textTheme.bodySmall
[ Red Light | Optic Field | Inductive Field ]  ← SegmentedButton<SensorKind>
SizedBox(height: 16)

KeyField(label: "Detection State Key")
SizedBox(height: 16)

SwitchListTile(
  title: "Invert Active Polarity",
  subtitle: dynamic per state,
  value: config.invertActivePolarity,
)
SizedBox(height: 16)

KeyField(label: "Rising Edge Delay Key")
SizedBox(height: 8)        ← paired field — tighter gap
KeyField(label: "Falling Edge Delay Key")
SizedBox(height: 16)

GestureDetector(onTap: _showColorPicker(activeColor))
  Row [ swatch · 8px gap · "Active Color" ]
SizedBox(height: 8)  // sm — paired colour rows, matching key-pair convention
GestureDetector(onTap: _showColorPicker(inactiveColor))
  Row [ swatch · 8px gap · "Inactive Color" ]
SizedBox(height: 16)

TextFormField(label: "Tag (e.g. PE-101A)", hint: "Optional")
SizedBox(height: 16)

SizeField(initialValue: config.size, ...)
SizedBox(height: 16)

CoordinatesField(initialValue: config.coordinates, ...)
```

Locked decisions reflected:

- Kind defaults to `SensorKind.redLight` (set in `SensorConfig()` constructor).
- `SwitchListTile` chosen for polarity (more discoverable than a checkbox; matches `conveyor_gate.dart:733`).
- Rising/falling delay keys grouped with 8 px gap (paired) vs 16 px between distinct sections (per Pitfall UX-Pitfall: "Group rising/falling edge fields visually").
- Colour swatches reuse the 24 × 24 circle pattern from `conveyor_gate.dart:643-653`.
- `SizeField` and `CoordinatesField` come last — standard tfc-hmi2 dialog convention.

---

## Test Coverage Contract (locked — TDD-first)

Per `01-CONTEXT.md` and QUAL-08, every behaviour below is implemented test-first.

### Golden tests (8 total — locked matrix)

Location: `test/page_creator/assets/goldens/sensor/`

| # | File | Kind | State | Polarity |
|---|------|------|-------|----------|
| 1 | `red_light_clear.png` | `redLight` | bool=true → clear | normal |
| 2 | `red_light_broken.png` | `redLight` | bool=false → broken | normal |
| 3 | `red_light_clear_inverted.png` | `redLight` | bool=false → clear | inverted |
| 4 | `red_light_broken_inverted.png` | `redLight` | bool=true → broken | inverted |
| 5 | `optic_field_inactive.png` | `opticField` | inactive | normal |
| 6 | `optic_field_active.png` | `opticField` | active | normal |
| 7 | `inductive_field_inactive.png` | `inductiveField` | inactive | normal |
| 8 | `inductive_field_active.png` | `inductiveField` | active | normal |

Polarity goldens for `opticField` and `inductiveField` are **not** included — polarity is a pure pre-painter bool inversion; covering it on `redLight` exercises the same code path. Stale-state golden is covered by a dedicated 9th test asserting all-grey rendering, but it lives outside the 8-golden matrix so it can be skipped if the canvas timing is platform-flaky.

### Widget tests

Location: `test/page_creator/assets/sensor_test.dart`

1. **Tap opens config dialog** — pump `Sensor` with `detectionKey: 'foo'`, simulate tap, assert dialog mounts.
2. **Tap survives `Transform.translate` ancestor** — wrap sensor in `Transform.translate(offset: Offset(0, 100), child: Sensor(...))`, simulate tap at the translated position, assert dialog mounts. (Forward-compat for Phase 3.)
3. **`shouldRepaint` returns true on kind change** — construct `RedLightBeamPainter`, call `shouldRepaint(OpticFieldPainter(...))`, assert `true`.
4. **Stale stream renders grey** — pump with `detectionKey: ''`, assert painter receives `isStale: true` (or equivalent — `Colors.grey` rendered).
5. **Polarity inversion flips visual** — pump with `invertActivePolarity: true`, push `bool=true`, assert painter receives `isActive: false`.

### Unit tests

Location: same `sensor_test.dart` file or `sensor_config_test.dart`

1. **JSON round-trip** for every field (kind, detectionKey, polarity, both delay keys, both colours, label).
2. **Legacy JSON load** — feed a JSON missing `invertActivePolarity` and `tag` fields, assert defaults are applied (per QUAL-05).
3. **AssetRegistry round-trip** — register `SensorConfig`, serialise, parse via `AssetRegistry.parse`, assert non-null and correct type.

### Rotation test (single, not multiplied)

One widget test renders a `Sensor` with `coordinates.angle = 90.0`, captures a golden, and visually confirms the beam runs vertically. **Not** part of the 8-golden matrix — kept separate to avoid 32 goldens.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| (none — no third-party registry) | not applicable | not required |
| Internal `AssetRegistry` (`lib/page_creator/assets/registry.dart`) | `SensorConfig` registered in **both** `_fromJsonFactories` and `defaultFactories` (per Pitfall 5) | code review — verified by Phase 1 acceptance test "saved page round-trip" |

No external component registries (shadcn or otherwise) are used. The "registry" relevant to this phase is the project's internal `AssetRegistry` map, which the planner must update in the same task that introduces `SensorConfig`.

---

## Cross-Phase Forward-Compat Notes

The following design choices are made in Phase 1 to avoid rework in Phase 3 (sensor as elevator child):

1. **`GestureDetector`-based tap** (not painter hit-test): survives being a child of a translating parent.
2. **`Transform.translate` named constructor only** (never raw `Transform()`): preserves `transformHitTests: true` default.
3. **No top-level / static `ValueNotifier`** in sensor code: per-widget `State`-owned only, so multi-instance pages don't share state (Pitfall 10 + QUAL-06).
4. **Painter takes primitives only** (`isActive`, `Color`, `Color`, `String? label`, `bool isStale`): no `WidgetRef`, no streams. Goldens construct painters directly with constants.
5. **Stream hoisted to `initState`** (Pitfall 2): the live `detectionKey` subscription is constructed once per `Sensor` widget, never inline in `build()` — even though Phase 1 only places sensors at rest.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
