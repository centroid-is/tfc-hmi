# Feature Landscape — Modicon Momentum I/O Assets (v2.0)

**Domain:** HMI assets for the Schneider Modicon Momentum I/O stack (NIP2311 Ethernet head, PDT3100 power, DDI3725 16-ch DI, DDO3705 16-ch DO) running inside the tfc-hmi2 Flutter page creator.
**Researched:** 2026-05-11
**Confidence:** HIGH on the HMI surface (full parity with Beckhoff EL1008/EL2008 is locked by the user and the prior art is read line-by-line). MEDIUM on individual Schneider LED semantics (Schneider datasheet PDFs were not exhaustively scraped; LED labels are confirmed in the user-supplied photo and module datasheet listings, but exact "ST" vs "TEST" wording is best-effort).

---

## Scope Reminder (locked in PROJECT.md)

The user has already pinned the following decisions; they are restated here as anti-features so this list cannot drift back into the wishlist column:

- **Painter fidelity:** operator-recognizable, NOT pixel-perfect (DXFs inform proportions, not paths)
- **DI/DO share base form factor:** one painter base, two label/colour variants
- **Out of scope:** backend Modbus key plumbing, per-channel current/diagnostic readbacks beyond bit state, multi-rack composition on one page
- **Parity target:** EL1008's full surface (LEDs + force-override + filter ms + descriptions + detail dialog with tap-to-open) is the bar; nothing less, nothing more

Everything below stays inside that perimeter.

---

## Architecture-Bound Constraints That Shape Every Feature

These come from reading `lib/page_creator/assets/beckhoff.dart` and `lib/painter/beckhoff/io8.dart` and govern what "parity" actually means.

1. **`IO8Widget` is hard-locked to 8 LEDs** (`assert(ledStates.length == 8 || ledStates.length == 6)`). It paints a 2×4 grid with `pad`/`labelW` computed from a `cols = 2`, `rows = 4` constant. Going to 16 channels means **either** (a) a new `IO16Widget` (2×8 grid, new I/O label section with 8 rows of pairs) **or** (b) a stacked layout of two `IO8Widget` instances. The two options have very different golden-test stories and operator-recognizability outcomes — and the photo strongly favours option (a): the physical Momentum body shows one continuous LED column, not two stacked Beckhoff bodies. Treat (a) as table stakes.
2. **`_combinedStream` + `_ledStates` use bit-mask indexing on a single integer** (`(data["raw"]!.asInt & (1 << i)) != 0`). 16 channels means widening the loop bound from `8` to `16` and validating that the upstream `DynamicValue.asInt` carries at least a `UInt16` — confirmed compatible since `DynamicValue.asInt` is a `BigInt`-backed `int`. The bit-mask pattern is reusable as-is.
3. **`_ledStates` reads a single `force` value, not a per-channel array** (the existing code does `forceValue = data["force"]?.asInt; if (forceValue == 1) return forcedLow;` which is a bug-or-quirk where any non-zero force forces *all* LEDs the same way). The per-channel force logic actually lives in the *dialog* (`map["force"]?[i].asInt`). For Momentum 16-ch parity we must keep this exact split: bitmask for LED state, per-index array for force buttons. **Do not "fix" the existing behaviour in this milestone** — that's a separate decision.
4. **`BeckhoffEK1100Config.allKeys` does NOT recursively flatten its subdevices' keys** — only `BeckhoffCX5010Config` does (lines 42–50 of beckhoff.dart). The user said "MomentumStack mirrors CX5010 (flattens allKeys across children for alarms/collectors)" — that means MomentumStack must use the **CX5010** pattern, not the EK1100 pattern. Worth flagging in PITFALLS.
5. **Subdevice composition is positional / list-based**, ordered by `ReorderableListView`. Heterogeneous children are allowed at the data-model level today. No type-discrimination logic anywhere.

---

## Per-Module Feature Surface

### NIP2311 — Ethernet Modbus/TCP Head Adapter

Closest analog: **BeckhoffEK1100**. It's a head with no I/O channels of its own, just status indicators and ports.

| Feature | Tier | Complexity | Notes |
|---------|------|------------|-------|
| Body painter at correct aspect ratio (tall narrow head — wider than I/O modules in user's photo) | Table stakes | LOW | `NIPxxxx` CustomPainter mirroring `EK1100`'s structure. Native size from the NIP2311 DXF `$EXTMAX-$EXTMIN`. Schneider cream `bodyColor` (~`0xFFF7F5E6`) — same constant as Beckhoff, low-risk reuse. |
| Status LED block (5 LEDs: RUN / READY / COMM / FAULT / 100M — exact labels from datasheet 33001466) | Table stakes | LOW | Render as a small 5×1 vertical strip top-of-body. Each LED is a coloured circle/rect with on/off state from a separate bool state key. **State-key surface:** `runKey`, `readyKey`, `commKey`, `faultKey`, `linkSpeedKey` (or one bitmask key like the I/O modules — user can decide; default to 5 separate bool keys for clarity, matching how operators think). |
| Dual Ethernet RJ45 ports drawn near the bottom of the body | Table stakes | LOW | Reuse `EthernetPortPainter` from `ek1100.dart` *unchanged*. Place two ports stacked vertically (mirrors EK1100's `30mm` center-to-center offset) — proportions taken from NIP2311 DXF. |
| Per-port link/activity LED (small dot above or beside the jack) | Table stakes | LOW–MED | Two more bool state keys (`port1LinkKey`, `port2LinkKey`). Rendered as small green dots overlaid on the port painter output. **NOT** the link/activity blink pattern from a real switch — just a binary "linked" colour swap. (Animation cost-of-blink is not worth it.) |
| "Schneider" branding text (rotated 90°, vertical, white-on-Schneider-green) | Table stakes | LOW | Direct port of the BECKHOFF text-rotation logic in `EK1100`. Replace text + colour. The Schneider green is `~0x00A56B` (verify against DXF; cream body + green logo is the Momentum visual signature). |
| `nameOrId` label (vertical, smaller, black) above/below the branding | Table stakes | LOW | Same pattern as `EK1100`'s "EK1100" rendering. |
| Tap-to-open status dialog with MAC ID / IP address readouts | Differentiator | LOW–MED | NOT in the Beckhoff parity scope; raised by the question. Recommended: add a `macIdKey` and `ipAddressKey` (string state keys) and show them in a tap-opened dialog **only if the keys are configured**. Cheap to wire, real value for operators who diagnose comm faults. **If a v1 cut is needed, drop this.** |
| Hostname / Subnet mask / Gateway readout | Anti-feature for v2.0 | — | Drift toward "configuration UI" rather than "monitoring view". Operators have other tools for that. |
| Per-port speed/duplex indicator | Anti-feature for v2.0 | — | Bit-mask exists in Modbus diagnostic registers, but reading it on the HMI is rarely useful and noisy. |

**Recommended `NIP2311Config` field surface:**
```
String nameOrId;
String? runKey;
String? readyKey;
String? commKey;
String? faultKey;
String? port1LinkKey;
String? port2LinkKey;
String? macIdKey;     // optional, dialog-only
String? ipAddressKey; // optional, dialog-only
```

**Reuses from existing code:** `EthernetPortPainter` (verbatim), `EK1100`'s rotate-90-text idiom, `bodyColor` constant, `KeyField`/`CoordinatesField`/`SizeField` from `common.dart`.

**New code needed:** `NIPxxxx` CustomPainter, `NIPxxxxConfig`+`fromJson`+`toJson`, `_NIP2311ConfigContent` (config dialog), `_BeckhoffNIP2311`-equivalent ConsumerWidget for live state.

---

### PDT3100 — Power Distribution Module

No real Beckhoff analog. The user said "INPUT OK boolean" is enough — closest pattern is the EL9186/EL9187 "passive bus module" types in beckhoff.dart, which are pure-painter, no state keys.

| Feature | Tier | Complexity | Notes |
|---------|------|------------|-------|
| Body painter at correct aspect ratio (115×162 mm per DXF — fatter than DI/DO base) | Table stakes | LOW | New `PDT3100` CustomPainter. The DXF gives exact proportions. |
| Schneider cream body + Schneider green branding | Table stakes | LOW | Reuse the same constants as NIP2311. |
| "24 VDC" / "PWR IN" label rendered on the body | Table stakes | LOW | Static text in the painter — operator-recognizability cue. |
| Power terminal block visual (terminals for L+, L-, PE) | Table stakes | LOW–MED | Reuse the "wire hole + square slot" idiom from `IO8Painter` (lines 270–290) but only 3–6 terminals total, no LED row above. Coloured I/O labels (red for L+, blue for L-, yellow/green for PE) directly mirror the EK1100 IO8 painter's existing label-colour pattern. |
| "INPUT OK" LED — single green circle, lit when `inputOkKey` is `true` | Table stakes | LOW | One bool state key. Single LED is its only live state. |
| `nameOrId` rendered vertically (matches NIP2311 / Beckhoff label style) | Table stakes | LOW | Pattern reuse. |
| Tap-to-open dialog | Anti-feature for v2.0 | — | A single boolean doesn't need a dialog. Tap can be a no-op or just show a tiny "PDT3100 — INPUT OK: true" tooltip. The user explicitly chose "just INPUT OK" — keep the surface flat. |
| Voltage/current readback | Anti-feature for v2.0 | — | Out of scope per PROJECT.md ("Per-channel current / diagnostic readbacks beyond bit state"). |

**Recommended `PDT3100Config` field surface:**
```
String nameOrId;
String? inputOkKey; // bool
```

**Reuses from existing code:** `IO8Painter` terminal-block idiom (extracted), label-colour constants, body colours, `KeyField`/`SizeField`/`CoordinatesField`.

**New code needed:** `PDT3100` CustomPainter, config class + dialog + ConsumerWidget. Smallest module of the four.

---

### DDI3725 — 16-Channel Digital Input

Closest analog: **BeckhoffEL1008** (8-ch DI with full force/filter/description surface). Target is "EL1008 doubled". The Schneider 170ADI34000 datasheet confirms 16 inputs at 24 VDC, no per-channel current readback.

| Feature | Tier | Complexity | Notes |
|---------|------|------------|-------|
| Body painter at DDI3725 aspect ratio (107×152 mm — DXF `IO_BASE`) | Table stakes | LOW | Direct mapping. Native size from DXF `$EXTMAX-$EXTMIN`. |
| **16-LED strip — 2 columns × 8 rows OR 1 column × 16 rows** | Table stakes | **MEDIUM** (new painter) | The user's photo clearly shows a single vertical column of dense LED indicators on each module, **not** a 2×8 layout. But the existing `IO8LedBlockPainter` is 2×4. Two options: (A) extend `IO8LedBlockPainter` to `IO16LedBlockPainter` with `rows = 8`, keeping 2 columns; (B) create `IO16LedBlockPainter` with `cols = 1, rows = 16`. **Recommendation: (A) 2×8** — matches "operator-recognizable, not pixel-perfect", reuses ~95% of the LED-cell math, and the Momentum's physical 16 LEDs being in a single column is a Schneider-specific cosmetic that operators won't miss. **Note the cost:** if golden tests are strict, this is a divergence from the photo. Flag for the planner. |
| **16 I/O label cells** (with terminal-block visuals below each, mirroring the IO8 4×2 terminal layout doubled to 8×2) | Table stakes | **MEDIUM** | The bigger painter cost. `IO8Painter` lays out 4 sections × 2 columns of label+square+circle terminals (lines 246–291). For 16-ch, this becomes 8 sections × 2 cols — a straightforward generalisation but requires either a parameterised `IO_N_Painter` or a duplicated `IO16Painter`. **Recommendation: parameterise `IO8Painter` to accept `int channelCount` (default 8) and adjust `sectionH = ioAreaH / (channelCount / 2)`** — this also delivers the EL1008 refactor as a side benefit (zero behaviour change since 8 stays default). |
| Per-channel state from `rawStateKey` (bitmask) | Table stakes | LOW | Same `(data["raw"]!.asInt & (1 << i)) != 0` pattern as EL1008, with loop bound 16. |
| Per-channel processed state from `processedStateKey` (bitmask, optional) | Table stakes | LOW | Same pattern as EL1008. |
| Per-channel force-override (auto / low / high) from `forceValuesKey` (array of int 0/1/2) | Table stakes | LOW | Same pattern; 16 entries in the array. |
| Per-channel ON filter ms / OFF filter ms (arrays of int) | Table stakes | LOW | Same pattern; 16 entries. |
| Per-channel description strings from `descriptionsKey` (array of string) | Table stakes | LOW | Same pattern; 16 entries. |
| Tap-to-open detail dialog with **8 rows of `RowIOView` pairs** (16 channels as 8 left/right pairs) | Table stakes | LOW | Existing `_statusDialog` in `_BeckhoffEL1008` loops `for (int i = 0; i < 8; i = i + 2)` producing 4 row-pairs. For Momentum: `for (int i = 0; i < 16; i = i + 2)` producing 8 row-pairs. Zero structural change — just a loop-bound change. **`RowIOView`, `RowControl`, `IOForceButton`, `FilterEdit`, `TriangleBoxPainter` all reuse verbatim.** |
| Forced-channel red-border animation (existing pulsing red box) | Table stakes | LOW | Inherited free from `TriangleBoxPainter` reuse. |
| Disconnected indicator (red exclamation overlay) | Table stakes | LOW | Inherited free from `IO8Painter`'s `disconnected` flag — already painter-generic, no work. |
| `nameOrId` + "DDI3725" labels (vertical, like Beckhoff "EL1008") | Table stakes | LOW | Pattern reuse. |
| Manual force-low / force-high write via dialog | Table stakes | LOW | Already wired in EL1008 dialog (`stateMan.write(config.forceValuesKey!, map["force"]!)`) — same write target, same `DynamicValue` array shape. |
| Per-channel current readback / wire-break detection | Anti-feature for v2.0 | — | Out of scope per PROJECT.md. |
| Channel grouping into pairs / quads with shared label | Anti-feature for v2.0 | — | Beckhoff doesn't do it either. Avoids visual clutter. |
| Live re-ordering of channels (channel-to-physical-input mapping) | Anti-feature | — | Not the HMI's job. |

**Recommended `DDI3725Config` field surface — IDENTICAL to `BeckhoffEL1008Config`:**
```
String nameOrId;
String? descriptionsKey;
String? rawStateKey;
String? processedStateKey;
String? forceValuesKey;
String? onFiltersKey;
String? offFiltersKey;
```

**Reuses from existing code (almost everything):** `_combinedStream`, `_ledStates` (with `channelCount` parameter), `RowIOView`, `RowControl`, `IOForceButton`, `FilterEdit`, `TriangleBoxPainter`, `KeyField`+other field widgets. The only DI-specific new code is the body painter and the 16-LED block painter.

**New code needed:** `DDI3725` CustomPainter (or shared `MomentumIOBase` painter — see DDO3705), `DDI3725Config` + JSON, `_DDI3725ConfigContent`, `_MomentumDDI3725` ConsumerWidget. `_ledStates` and `_combinedStream` should be generalised to accept a `channelCount` parameter (default 8) so both EL1008 and DDI3725 share them.

---

### DDO3705 — 16-Channel Digital Output

Closest analog: **BeckhoffEL2008** (8-ch DO with descriptions + force + raw state, **no filters**). Target is "EL2008 doubled" with an open question about manual write.

| Feature | Tier | Complexity | Notes |
|---------|------|------------|-------|
| Body painter — **same DXF base as DDI3725** | Table stakes | LOW | One painter, two label variants. Per user lock: "DI/DO share base form factor — one DXF covers both." Implementation: a shared `MomentumIOBasePainter` parameterised by `ioLabels` (e.g. `O1..O16` vs `I1..I16`) and a colour list. |
| 16-LED strip with same layout as DDI3725 | Table stakes | LOW | Inherits from the painter generalisation. |
| Per-channel state from `rawStateKey` (bitmask, output commanded state) | Table stakes | LOW | Same as EL2008. **Note:** for outputs, "raw" is the *commanded* value (what the PLC told the output to be). There's no "processed" because the actual electrical state matches commanded unless there's a fault — which we're not surfacing in v2.0. |
| Per-channel force-override (auto / low / high) | Table stakes | LOW | Identical to EL2008's surface. Output forcing is the operator's main reason for opening the dialog. |
| Per-channel description strings | Table stakes | LOW | Same as EL2008. |
| Tap-to-open dialog with **8 rows of `RowIOView` pairs** | Table stakes | LOW | Same as DDI3725 dialog, minus the filter-ms fields (matching EL2008's `leftFilterEdit: null`). |
| No on-filter / off-filter fields | Table stakes | LOW | EL2008 doesn't have them either — outputs don't filter. |
| **Manual write of output state from dialog (operator clicks force-high to push an output high)** | Table stakes | LOW | **Already implemented in EL2008** — the force-high path writes to `forceValuesKey`, which the PLC then propagates to the output. From the HMI's perspective, "manual write" is the *same code path* as the force override. **No new feature.** The question hints at "write target value vs actual readback" — neither distinction is meaningful for DO without per-channel current readback, which is out of scope. |
| Direction-of-flow indicator (arrow showing output → field) | Differentiator (declined) | — | Beckhoff doesn't paint this; the I/O labels (`O1..O16` vs `I1..I16`) and the "DDO3705" body label already disambiguate. Adding arrows would clutter without recognisability gain. |
| Per-channel short-circuit / overload diagnostic | Anti-feature for v2.0 | — | Out of scope (no per-channel diagnostics). |
| Group-of-8 fuse status (the 170ADO34000 has 2× group fuses physically) | Anti-feature for v2.0 | — | Real but not modelled in v2.0; can be added in a future milestone if a fuseOK state key emerges. |

**Recommended `DDO3705Config` field surface — IDENTICAL to `BeckhoffEL2008Config`:**
```
String nameOrId;
String? descriptionsKey;
String? rawStateKey;
String? forceValuesKey;
```

**Reuses from existing code:** everything DDI3725 reuses, plus the `_BeckhoffEL2008._statusDialog` row-pair loop pattern (no filter edits).

**New code needed:** `DDO3705Config`, config dialog, ConsumerWidget. The painter is *shared* with DDI3725. This module is the cheapest of the I/O pair.

---

### MomentumStack — Composite Parent

Closest analog: **BeckhoffCX5010**. The user said it mirrors CX5010 — that means the `allKeys` flattening implementation (lines 42–50 of beckhoff.dart) is the contract.

| Feature | Tier | Complexity | Notes |
|---------|------|------------|-------|
| `List<Asset> subdevices` field (reorderable, drag-handle UI) | Table stakes | LOW | Direct pattern reuse from `_CXxxxxConfigContent` (`ReorderableListView.builder`). |
| `allKeys` getter that flattens all subdevices' keys recursively | Table stakes | LOW | Identical to CX5010's implementation. **This is the key feature** — alarms and the collector subscribe to flattened keys. |
| `build()` lays out children in a horizontal row, FittedBox-contained | Table stakes | LOW | Direct pattern reuse from `_CXxxxxConfigContent`. Native size set by NIP2311 (the tallest module) — height-normalize all others via `_SubdeviceNormalized`. |
| Config dialog: dropdown to add module of type {NIP2311, PDT3100, DDI3725, DDO3705} | Table stakes | LOW | Replace `_availableSubdevices` map contents — pure data swap. |
| Reorder support | Table stakes | LOW | Inherited from `ReorderableListView`. |
| Delete subdevice | Table stakes | LOW | Inherited from CX5010 list-tile trailing IconButton. |
| Heterogeneous children allowed in any order | Table stakes | LOW | **Recommended over enforcement.** Real Momentum installations almost always go NIP → PDT → DDI(s) → DDO(s), but: (a) CX5010 doesn't enforce, (b) enforcement adds UI complexity for negative value, (c) operators who get it wrong can reorder. **Convention, not enforcement.** Document the convention in the asset's tooltip / hint text in the config dialog (`"Typical order: NIP2311 (head) → PDT3100 (power) → DDI/DDO modules"`). |
| Canonical-layout validation warning | Differentiator (decline) | — | Adds plan-time complexity (which modules are "head" vs "I/O"?), can be added later as a non-blocking lint if real misconfigurations emerge. |
| Limit to one NIP2311 per stack | Differentiator (decline) | — | Physical reality: one head per stack. But this is a soft constraint — let the operator place two if they're modelling two stacks side-by-side. Don't enforce. |
| Top-level "stack name" field (e.g. "Stack-01") | Table stakes | LOW | Add a `nameOrId` field to `MomentumStackConfig` — used in tooltips and the page-creator tree. |

**Recommended `MomentumStackConfig` field surface:**
```
String nameOrId;
@AssetListConverter()
List<Asset> subdevices; // initially empty
```

**Reuses from existing code:** `_CXxxxxConfigContent` (rename + swap `_availableSubdevices`), `_SubdeviceNormalized` (verbatim), `AssetListConverter`, JSON codegen pattern.

**New code needed:** `MomentumStackConfig` class with the CX5010 `allKeys` override copied verbatim, a `MomentumStack` body painter (a thin background showing the DIN rail and Schneider branding — *or* skip the body and just compose children, as CX5010 paints itself as the first child of the row). **Recommended:** no separate "stack body" painter; the MomentumStack is purely a composition wrapper (unlike CX5010 which paints the CX body itself). The NIP2311 *is* the visible head — let it speak for the whole stack. This is one clear divergence from the CX5010 pattern, and it's correct: in Momentum, the head **is** part of the stack; in Beckhoff, the CX5010 PLC is separate from the EK1100 head.

---

## Table Stakes (Aggregated)

Features that, if missing, will make the asset feel broken or wrong to a Centroid operator coming from EL1008/EL2008:

1. All four module types registered + previewable in the page creator
2. 16-LED visualization (any reasonable layout — 2×8 is the recommendation)
3. Bitmask-driven LED state from `rawStateKey`
4. Per-channel force-override array via `forceValuesKey`
5. Per-channel ON/OFF filter ms (DI only, via `onFiltersKey` / `offFiltersKey`)
6. Per-channel descriptions (string array via `descriptionsKey`)
7. Tap-to-open detail dialog with the existing `RowIOView` pattern repeated 8 times (vs 4 for EL1008)
8. Manual force-write (auto/low/high SegmentedButton, already implemented in EL1008/EL2008 — reuse)
9. Schneider cream body + correct branding on every module
10. Dual RJ45 painter on NIP2311 (reuse `EthernetPortPainter`)
11. NIP2311 status LEDs (RUN/READY/COMM/FAULT at minimum) — separate bool keys
12. PDT3100 INPUT OK single-LED widget
13. MomentumStack with `allKeys` recursive flattening (CX5010 pattern)
14. MomentumStack reorderable subdevice list
15. Full JSON round-trip via codegen for all 5 new types
16. AssetRegistry registration (`fromJson` + `preview` factory)
17. Backwards-compatible deserialisation (existing pages keep loading — defensive defaults for new fields)
18. Golden tests for each painter (per the milestone's locked-in painter-fidelity gate)
19. Disconnected-state visual on I/O modules (inherited from `IO8Painter`, free)
20. Forced-channel red-border pulse animation in dialog (inherited from `TriangleBoxPainter`, free)

## Differentiators (Worth Considering, Don't Block v1)

| Feature | Value | Cost | Decision |
|---------|-------|------|----------|
| NIP2311 MAC ID / IP address tap-dialog readout | Real operator value during comm fault diagnosis | LOW (just two string state keys + a small dialog) | **Include if cheap.** Drop if the planner sees scope pressure. |
| Per-port Ethernet link/activity dot on RJ45 jacks | Mirrors what operators see on the physical device | LOW (two bool keys + a small overlay) | **Include.** Cheap and recognisable. |
| Channel-label live colouring (e.g. red for forced-active channels) | Quick "what's overridden" scan | LOW (the existing `ioLabelColors` array already supports per-cell colours) | **Include.** Already a free affordance of `IO8Painter`. |
| Stack-level "any module disconnected" rollup indicator on MomentumStack | Single-glance health | MEDIUM (needs an OR-rollup across child disconnected states) | **Defer.** Belongs to alarms layer, not asset layer. |

## Anti-Features (Explicitly NOT building)

| Feature | Why Avoid | Instead |
|---------|-----------|---------|
| Per-channel current/wire-break readback | Out of scope per PROJECT.md; Modicon doesn't natively expose it on these modules anyway | Use alarms layer on dedicated diagnostic state keys |
| Group-of-8 fuse status visual | Real but unused — no fuseOK key today | Add in a future milestone if the key surfaces |
| Pixel-perfect Schneider-trademark replication | User locked "operator-recognizable, not pixel-perfect" | Cream + green + correct LED count + recognisable port placement = enough |
| Stack canonical-order enforcement (NIP first, etc.) | Adds UI work for negative value; operators self-correct | Document the typical order in dialog hint text only |
| Voltage / current readback on PDT3100 | User locked "just INPUT OK" | A single bool key |
| 1-column 16-LED layout matching the Schneider photo exactly | Costs a new painter geometry path; minimal recognisability gain | 2×8 grid reusing parameterised `IO8Painter` is "Momentum-shaped enough" |
| Multi-stack composition (multiple MomentumStacks composed under one parent) | Out of scope per PROJECT.md | Single stack first; revisit if a real use case appears |
| Three-LED-per-channel "input/output/diagnostic" rendering | Modicon photo shows one LED per channel; no diagnostic LED on 170ADI34000/170ADO34000 | Single LED per channel |
| Per-channel write of a separate "target" vs "actual" value for DO | No actual-readback exists; commanded state = observed state in PLC view | One state key (commanded), one force array; matches EL2008 exactly |
| Animated link-blink on Ethernet ports | Visual noise, no diagnostic value beyond "linked" / "not linked" | Static binary colour swap on port-link dot |

---

## Feature Dependencies

```
MomentumStack
  ├── needs → AssetListConverter (existing)
  ├── needs → ReorderableListView pattern (CX5010 — existing)
  └── flattens → child.allKeys (CX5010 pattern — existing, just copy)

DDI3725 / DDO3705
  ├── needs → IO8Painter parameterised by channelCount (NEW — affects EL1008/EL2008 too)
  ├── needs → IO8LedBlockPainter parameterised by channelCount (NEW)
  ├── needs → _combinedStream + _ledStates generalised (NEW — same change applies to EL1008/EL2008)
  ├── reuses → RowIOView, RowControl, IOForceButton, FilterEdit, TriangleBoxPainter (verbatim)
  └── reuses → KeyField, SizeField, CoordinatesField, AssetListConverter

NIP2311
  ├── reuses → EthernetPortPainter (verbatim from ek1100.dart)
  ├── reuses → EK1100's rotate-90 text idiom (pattern, not class)
  └── needs → New status-LED-strip painter (5 LEDs vertical) — small custom painter

PDT3100
  ├── reuses → IO8Painter's terminal-block idiom (extracted)
  ├── reuses → bodyColor constant
  └── needs → Single-LED widget for INPUT OK (trivial)
```

**Critical dependency:** Generalising `IO8Painter` to accept a `channelCount` parameter touches `EL1008Config`, `EL2008Config`, `EL9222Config`, `EL9186Config`, `EL9187Config`, `EL3054Config` (every caller of `IO8Widget`). Default `channelCount = 8` keeps all existing call sites behaviour-identical, but the **change must land first** and be golden-tested before any 16-ch module gets built on top of it. This is the highest-risk refactor in the milestone and the natural first phase.

---

## MVP Recommendation (Phase Ordering)

1. **Phase A — Painter refactor.** Generalise `IO8Painter` / `IO8LedBlockPainter` / `IO8Widget` / `_ledStates` / `_combinedStream` to accept `channelCount` (default 8). Zero behaviour change for Beckhoff family. Land with golden tests on EL1008/EL2008 that pass with bit-for-bit identical output to today. **This unblocks everything else.**

2. **Phase B — Shared Momentum I/O painter.** Implement `MomentumIOBasePainter` (shared by DDI3725 and DDO3705) with 2×8 LED grid + 8×2 terminal block layout. Golden-test against DXF-derived bounds and the photo (recognisability check, not pixel match).

3. **Phase C — DDI3725 + DDO3705 asset configs + dialogs.** Direct copy-and-rename of `BeckhoffEL1008Config` and `BeckhoffEL2008Config` with channel count = 16. Detail dialogs use the existing `RowIOView` loop pattern.

4. **Phase D — PDT3100.** Smallest module, builds on the Phase-A constants + terminal-block idiom.

5. **Phase E — NIP2311.** Head module with status LEDs + dual RJ45. Reuses `EthernetPortPainter` verbatim. New status-LED-strip painter is small.

6. **Phase F — MomentumStack.** Direct port of `_CXxxxxConfigContent` with the new dropdown contents and the CX5010 `allKeys` override copied verbatim.

7. **Phase G — Registry + JSON round-trip + leak tests.** Bulk registration + the existing leak-test pattern from `state_man_test.dart`.

**Defer to a future milestone:** multi-stack composition; per-channel diagnostic readbacks; stack-level health rollup; canonical-layout linting.

---

## Sources

- `lib/page_creator/assets/beckhoff.dart` (2198 lines, read in full — primary pattern source) — HIGH
- `lib/painter/beckhoff/io8.dart` (read in full — LED block + terminal block geometry) — HIGH
- `lib/painter/beckhoff/ek1100.dart` (read in full — EthernetPortPainter, rotated-text pattern, fillColor + DXF-derived geometry) — HIGH
- `lib/page_creator/assets/registry.dart` (registration map confirmed) — HIGH
- User-supplied physical-stack photo (`/Users/jonb/.claude/image-cache/.../3.png`) — HIGH (visual confirmation of 5-module layout, Schneider cream + green livery, LED column placement on I/O bodies, dual RJ45 on NIP2311, terminal block geometry)
- `.planning/research/dxf/README.md` (DXF mapping + bounding boxes) — HIGH
- [Modicon Momentum 170ADO34000 — 16 solid-state outputs, 2 groups of 8](https://www.se.com/us/en/product/170ADO34000/discrete-output-module-modicon-momentum-16-o-solid-state/) — MEDIUM (confirms 16-channel, 2-group layout — informs the 2-column LED arrangement recommendation)
- [Modicon Momentum 170ADI34000 — 16 inputs at 24 VDC](https://www.se.com/us/en/product/170ADI34000/discrete-input-module-modicon-momentum-16-input-24-v-dc/) — MEDIUM (confirms 16-channel DI; DDI3725 is a regional SKU for this product family)
- [Schneider STBNIP2311 — dual-port Ethernet Modbus/TCP](https://www.ebay.com/itm/166431962934) — LOW (dual-port confirmation; LED-label specifics not exhaustively verified — flag for plan-phase verification against datasheet 33001466)
- [Modicon Momentum 33001466 datasheet (Schneider)](https://media.distributordatasolutions.com/schneider2/2020q3/documents/9be1de6575cd531289f97ebad31fb74dd6089f66.pdf) — referenced for LED-label semantics — LOW (not scraped in full during this research; planner should verify exact NIP2311 LED labels against pages 4-character status block before locking the `NIPxxxx` painter's status-LED label strings)
