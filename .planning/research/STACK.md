# Stack Research — Modicon Momentum I/O Asset Family (v2.0)

**Domain:** Industrial HMI asset family — Schneider distributed I/O painters + Modbus TCP state binding
**Researched:** 2026-05-11
**Confidence:** HIGH for stack additions (verified zero), MEDIUM for Schneider part identification (DXF filenames + Schneider portal cross-check), LOW only on the precise process-image register offsets (datasheet PDFs require Modbus configuration tool — see Open Questions).

---

## TL;DR

**Stack changes required: NONE.** Every existing dependency (Flutter `CustomPainter`, Riverpod, `tfc_dart` StateMan with full Modbus TCP support — coils / discrete inputs / holding / input registers, `flutter_test` golden harness on macOS, `json_serializable` + `build_runner`) already covers the v2.0 milestone in full. The four new module assets are pure additions to `lib/page_creator/assets/` + `lib/painter/` following the Beckhoff precedent — no new pubspec dependencies, no new protocol code, no new test infrastructure.

**One identification correction required (HIGH confidence).** The user-supplied part numbers (NIP2311, PDT3100, DDI3725, DDO3705) and DXF filenames identify these modules as **Schneider Advantys STB (Modicon STB)**, not Modicon Momentum. They are a different (newer) Schneider distributed-I/O family that shares the "I/O island over Modbus TCP" pattern but uses different mechanical, register, and naming conventions. This should be reconciled with the milestone narrative before painters are committed. See "Part-number reality check" below.

---

## Recommended Stack (no additions over status quo)

### Core Technologies (already in repo — no version bumps)

| Technology | Version | Purpose | Why for this milestone |
|------------|---------|---------|------------------------|
| Flutter SDK | stable channel (Dart ^3.5.1) | UI, `CustomPainter`, golden tests | `CustomPaint` + `FittedBox` + `RRect`/`drawLine`/`TextPainter` is what every Beckhoff module already uses (`lib/painter/beckhoff/ek1100.dart`, `io8.dart`). No new visual capability required. |
| Riverpod (+ `riverpod_generator`) | `flutter_riverpod` ^2.6.1 | Read `stateManProvider`, subscribe to bool keys per channel | Identical pattern to `BeckhoffEL1008Config.build()` — no change. |
| `json_serializable` + `build_runner` | ^6.9.4 / ^2.4.15 | Generate `*.g.dart` for `STBNIP2311Config`, `STBDDI3725Config`, etc. | Same `@JsonSerializable()` pattern as `BeckhoffEK1100Config`. |
| `tfc_dart` StateMan | path dependency (in-repo) | Subscribe to PLC bool keys for channel state, RUN/PWR/ERR LEDs | Already supports all four Modbus tables (`coil`, `discreteInput`, `holdingRegister`, `inputRegister`) — see `packages/tfc_dart/lib/core/state_man.dart` lines 195–227. STB process image fits these primitives cleanly. |
| `modbus_client_tcp` (local fork) | 1.2.3 (path: `packages/modbus_client_tcp`) | Underlying TCP transport for any STB island the customer wires up | No changes — STBNIP2311 speaks vanilla Modbus TCP on port 502. |
| `flutter_test` golden harness | SDK | Snapshot painter output | `test/painter/atv320_golden_test.dart` and `test/page_creator/assets/conveyor_gate_golden_test.dart` show the existing pattern: `matchesGoldenFile('goldens/foo.png')` gated by `Platform.isMacOS`. Re-use as-is. |

### Supporting Libraries (already present, no version bumps)

| Library | Version | Purpose | When to Use for v2.0 |
|---------|---------|---------|----------------------|
| `rxdart` | ^0.28.0 | `BehaviorSubject` snapshots inside StateMan | Already used by every asset that reads live values; new module widgets just call `stateMan.subscribe(key)`. |
| `open62541` | git pin (Centroid fork) | Provides `DynamicValue` shape that StateMan streams | Bool channel state arrives as `DynamicValue` regardless of source protocol — no protocol-specific code in painters. |
| `flutter` `animation` | SDK | `AnimatedWidget` + `AnimationController` for force-state pulsing | Already used in `IO8Widget` for forced-channel red border; reuse for any 16-channel force visualisation. |

### Development Tools (already configured)

| Tool | Purpose | Notes |
|------|---------|-------|
| `build_runner build --delete-conflicting-outputs` | Regenerate `.g.dart` after adding new config classes | Run after creating `STBNIP2311Config`, `STBPDT3100Config`, `STBDDI3725Config`, `STBDDO3705Config`. |
| `flutter test --update-goldens` | Capture/refresh painter goldens | Already gated to macOS in `dart_test.yaml` via the `golden` tag; PDT/DDI/DDO body goldens go under `test/painter/modicon/goldens/`. |
| `dart_test.yaml` `concurrency: 1` for integration | Existing — no change | Asset painter tests are pure widget tests, run under default concurrency 4. |

---

## Stack additions explicitly rejected (with rationale)

### Reject: `dxf` package on pub.dev (v3.1.3, last updated ~2 years ago)

- **What it does:** Parses AutoCAD DXF files into a Dart object model (LINE, LWPOLYLINE, CIRCLE, ARC, MTEXT entities). MIT-licensed. Published by `humg.edu.vn`.
- **Why not for v2.0:** The locked painter-fidelity decision (`.planning/PROJECT.md` line 16) is "operator-recognizable, not pixel-accurate." The Beckhoff precedent (`lib/painter/beckhoff/ek1100.dart` `EthernetPortPainter`) shows how DXF research output is handled today: a one-time **manual extraction** of polyline coordinates from the DXF into a hardcoded `List<List<Offset>>` literal at file top, drawn with `canvas.drawLine`/`Path`. This pattern:
  - Has zero runtime cost (no asset loading, no parsing)
  - Keeps DXFs out of the shipped binary
  - Survives DXF library abandonment (the `dxf` package's last release was 2023)
  - Naturally encourages stripping noise (dimension lines, hatch patterns, manufacturer text) at extraction time
- **Decision:** **Do not add `dxf` to pubspec.** During plan-phase research, a planner can read the DXF text directly (`grep`/`awk` for `EXTMIN`/`EXTMAX` and `LINE`/`LWPOLYLINE` blocks — confirmed working on the v2.0 DXFs, see "DXF bounding boxes" below). The painter's hand-written `_polylines` literal stays the source of truth at runtime.
- **Confidence:** HIGH. EK1100 ethernet-port geometry was extracted this way and has shipped without issue.

### Reject: `dxf_viewer` package (v0.0.3, ~15 months old, unverified publisher, "not all entities implemented")

- **What it does:** Renders a `DxfViewer` widget — read-only DXF preview.
- **Why not:** Renders the entire DXF including manufacturer logos, dimension lines, callouts. Operators need a stylised industrial visual, not a faithful CAD rendering. Also early-stage, unverified upload — not production-grade for an HMI shipped to customers.
- **Decision:** **Do not add.** Same hand-extraction workflow as above.

### Reject: any vector-graphics import (`flutter_svg`, `vector_graphics`, etc.)

- **Why not:** Schneider doesn't publish SVGs, the DXFs would need conversion, and the result would lose the visual-state-from-state-key pattern (LED colour depends on `IOState` which depends on a live `Stream<DynamicValue>` — needs `CustomPainter`, not a static asset).
- **Decision:** **Do not add.** Reuse `lib/painter/beckhoff/io8.dart` as the template for the 16-channel LED strip.

### Reject: golden-test DXF-reference diffing tooling

- **Hypothesis from the question:** "A script that renders a painter at known states and is diff'd against a reference PNG generated from the DXF."
- **Why not:**
  1. The DXF is mechanical (line drawings of a faceplate) — diffing it against a stylised painter (cream body, coloured LEDs, beveled terminals) would produce 100% pixel mismatch by design. The DXF cannot serve as a visual oracle.
  2. The existing `matchesGoldenFile('goldens/atv320_sto.png')` pattern with a macOS-gated commit (`test/painter/atv320_golden_test.dart` line 8) is already the right oracle — it pins the painter's *own* output, not the CAD source. First-write of a golden is human-reviewed via `--update-goldens`; subsequent runs catch regressions.
  3. A second oracle would create two sources of truth that diverge over time.
- **Decision:** **Do not add new tooling.** The flow is:
  1. Write painter following Beckhoff conventions.
  2. `flutter test --update-goldens -t golden` once to capture baseline.
  3. Visual review by human (commit the golden PNG).
  4. CI runs `flutter test` on macOS to detect regression.

### Reject: any new Modbus / process-image abstraction in StateMan

- **Why not:** STBNIP2311 exposes the STB island as a standard Modbus TCP server on port 502 (verified via Schneider Advantys application guide search). All four register tables (coils for outputs, discrete inputs for inputs, holding registers for diagnostics, input registers for status) map 1:1 to `ModbusRegisterType` already present in `packages/tfc_dart/lib/core/state_man.dart` (`coil`, `discreteInput`, `holdingRegister`, `inputRegister`).
- **What this means for the milestone:** Painters expect bool/int stream-of-`DynamicValue` keys; the upstream `stateman.json` configuration owns the mapping from `register_type + address` → asset state-key string. Per the `Out of scope (v2.0)` line in `.planning/PROJECT.md` ("Backend Modbus key plumbing — assumes StateMan keys already exist for the physical Momentum stack"), this is correctly out of scope for the v2.0 painter milestone.
- **Decision:** **No StateMan changes.** Update no Dart code in `packages/tfc_dart/`. Module config classes accept opaque state-key strings just like every other Beckhoff config.

---

## Part-number reality check (must surface before plan phase)

The user-supplied identifiers in the milestone description say "Modicon Momentum," but cross-referencing the **STB** prefix on every part number against Schneider's product portal places them in a different distributed-I/O family.

### Identified family: Schneider Advantys STB (a.k.a. "Modicon STB")

| User-supplied name | Actual Schneider part | Family | Schneider product page | Status |
|--------------------|----------------------|--------|------------------------|--------|
| NIP2311 | **STBNIP2311** — "network interface module, Modicon STB, standard, Ethernet, modbus TCP/IP, 10–100 Mbits" | Advantys STB (Modicon STB) | [se.com/us/en/product/STBNIP2311](https://www.se.com/us/en/product/STBNIP2311/network-interface-module-modicon-stb-standard-ethernet-modbus-tcp-ip-10100mbits/) | Commercialised (current product) |
| PDT3100 | **STBPDT3100** — "standard power distribution module STB — 24 V DC" | Advantys STB | [se.com/us/en/product/STBPDT3100](https://www.se.com/us/en/product/STBPDT3100/standard-power-distribution-module-stb-24-v-dc/) | Commercialised |
| DDI3725 | **STBDDI3725** — "basic digital input module, Modicon STB, 24V DC, 16I" | Advantys STB | [se.com/us/en/product/STBDDI3725](https://www.se.com/us/en/product/STBDDI3725/basic-digital-input-module-modicon-stb-24v-dc-16i/) | Commercialised |
| DDO3705 | **STBDDO3705** — "basic digital output module STB — 24 V DC — 16 O" | Advantys STB | [se.com/us/en/product/STBDDO3705](https://www.se.com/us/en/product/STBDDO3705/basic-digital-output-module-stb-24-v-dc-16-o/) | Commercialised |

**Modicon Momentum** (the family named in `PROJECT.md`) is a *different* Schneider product line — its modules use the `170xxxxxxxx` part-number scheme (e.g., `170ENT11001`, `170ADI34000`, `170ADM35010`) and have a different physical form factor (snap-on bus + I/O base instead of an STB island bus). Momentum and STB share Modbus TCP as a transport but are not interchangeable.

**Implication for the milestone:**

- **No technical impact** on the stack decisions in this file — both families use the same Modbus TCP + bool-channel-on-LED pattern, and the DXFs the user provided correctly match STB part dimensions (see below).
- **Naming impact** is non-trivial: file/class/registry names should reflect what they actually represent. Suggested rename:
  - `lib/page_creator/assets/modicon.dart` → `lib/page_creator/assets/advantys_stb.dart` (or keep `modicon.dart` since Schneider sells STB under the umbrella "Modicon STB" label — pick what reads better in the asset-picker dropdown)
  - Class prefix: `STB...Config` (matches the part-number prefix and Schneider's catalog name) instead of `Momentum...Config`
  - Asset category string: `'Modicon STB'` or `'Advantys STB'` in the `category` getter
- **Recommendation:** Flag this for the user at plan-phase kickoff. If they insist on the "Momentum" terminology because that's what their internal/operator vocabulary calls these modules, document the discrepancy in a comment header on `advantys_stb.dart` so future maintainers don't search for nonexistent Momentum docs. Confidence on the family identification: **HIGH** — STB prefix + dimensions + LED panel labels (RUN/PWR/ERR/ST/TEST/LINK/ACT) all match Schneider's STBNIP2311 user guide.

---

## Verified module facts (for painter implementation)

### STBNIP2311 (Ethernet head)

- **DXF bounding box:** 58.2 × 82.3 mm (`NIP2311_mcadid0005722.dxf`, 57k lines — has more entities because it includes RJ45 detail). DXF README's "~?" placeholder can be filled in with these dimensions.
- **LED panel** (per Schneider Advantys STB applications guide, document `EIO0000000051`):
  - `RUN` — island state (NIM operating state)
  - `PWR` — power supply present
  - `ERR` — module error
  - `ST` (`STS`) — Ethernet LAN status
  - `TEST` — test mode
  - `MS` (Module Status) and `NS` (Network Status) — also documented on the NIM; visible label set depends on hardware revision. Worth showing as small status dots if space allows.
  - Per Ethernet port: `LINK` and `ACT`
- **Ports:** dual RJ45 (10/100 Mbit, integrated switch). Reuse `EthernetPortPainter` from `lib/painter/beckhoff/ek1100.dart` — port geometry is generic enough that two side-by-side instances work.
- **Modbus exposure:** TCP port 502, unit ID configurable (the resolved StateMan key string hides this from the painter). Diagnostic data appears in the holding-register range 45357–45391 per the STB applications guide; sample I/O process image is in 45392–45409 for the demo island layout. Exact island-specific addresses depend on Schneider's Advantys Configuration Software output and are owned upstream.

### STBPDT3100 (Power distribution)

- **DXF bounding box:** 114.6 × 162.1 mm — taller than the I/O base. Includes input terminals + fuse.
- **Visual essentials:** 24 V DC input pair, fused 5 A indicator, terminal block. Indicator surface beyond power-OK to be confirmed during plan phase (datasheet behind Schneider portal 403'd to direct fetch; Scribd mirror exists — see Open Questions).
- **State-key need:** one bool ("input voltage OK") is sufficient for v2.0 fidelity.

### STBDDI3725 (16-channel DI) / STBDDO3705 (16-channel DO)

- **Shared base DXF:** 107.4 × 151.9 mm (`IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf`). Confirms the user's "DI/DO share base form factor" claim.
- **Channels:** 16 (24 V DC, 11–30 V state-1 threshold, ~2 ms response).
- **LEDs:** one per channel + `RDY` (module ready). Channel LED maps to bit state from the process image (coils for DO, discrete inputs for DI).
- **Terminal block:** 18-terminal screw connector (STBXTS1180) on the I/O base — 9 terminals per side typical, with channel inputs paired with 0 V/24 V returns. Exact A/B distribution confirmable from the DXF during painter implementation.
- **Outputs (DDO3705):** 0.5 A per channel, solid-state, short-circuit / thermal / reverse-polarity protected.
- **Dimensions per Schneider product page:** 128.3 × 70 × 13.9 mm (module body + base together). DXF shows the full faceplate at 107 × 152 mm (front view, base + module stacked).

---

## DXF bounding boxes (extracted from `.planning/research/dxf/`)

Verified via `awk` over the DXF `$EXTMIN`/`$EXTMAX` headers — no parser needed:

```text
NIP2311_mcadid0005722.dxf                  EXTMIN (0, 0)    EXTMAX (58.18, 82.29)
PDT3100_mcadid0005043.dxf                  EXTMIN (0, 0)    EXTMAX (114.59, 162.07)
IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf  EXTMIN (0, 0)    EXTMAX (107.38, 151.87)
```

These should replace the "~?" placeholder in `.planning/research/dxf/README.md` line 9.

---

## Installation

```bash
# No new pubspec entries required.
# After authoring new config classes:
flutter pub run build_runner build --delete-conflicting-outputs

# After authoring new painters:
flutter test --update-goldens -t golden   # macOS only
```

---

## Alternatives Considered

| Recommended | Alternative | When alternative would be better |
|-------------|-------------|----------------------------------|
| Hand-extract DXF polylines into a `static const List<List<Offset>>` literal in each painter (Beckhoff precedent) | Use `dxf` package on pub.dev | If pixel-accurate CAD rendering became a hard requirement (explicitly rejected by the milestone's painter-fidelity decision). |
| Re-use `EthernetPortPainter` from `lib/painter/beckhoff/ek1100.dart` for STBNIP2311's dual RJ45 | Author a new RJ45 painter | If STB's RJ45 jack visibly differs in housing (verify against DXF during plan phase — initial inspection of the 57k-line NIP2311 DXF suggests there's much more detail than the Beckhoff one, but the operator-recognizable jack outline is similar enough). |
| Continue golden tests gated by `Platform.isMacOS` (current pattern in `test/painter/atv320_golden_test.dart`) | Cross-platform golden harness with font shipping | If Linux/Windows test runners needed parity — but the existing macOS-only golden gate has worked for ATV320 and ConveyorGate; no regression risk. |
| Per-channel `IOState` enum (already in `lib/painter/beckhoff/io8.dart`: `low / high / forcedLow / forcedHigh / error`) scaled from 8 to 16 LEDs | New enum specific to STB | The STB DDI/DDO have the same force-low/force-high semantics in Schneider's Advantys runtime — reuse the enum. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `dxf` (pub.dev) | Adds a runtime parsing dependency for a one-time research-phase extraction; package itself is ~2 years stale. | `awk`/`grep` over DXF text during plan-phase; hand-coded `Offset` literals in painter. |
| `dxf_viewer` (pub.dev) | v0.0.3, unverified publisher, incomplete entity coverage, can't drive LED state from PLC keys. | `CustomPainter` following the Beckhoff io8 pattern. |
| `flutter_svg` for module faceplates | No SVG source from Schneider; can't bind dynamic LED colour to a `Stream<DynamicValue>` from a static asset. | `CustomPainter`. |
| Any new Modbus abstraction in `tfc_dart/state_man.dart` | All four register tables are already enumerated in `ModbusRegisterType` (lines 195–227); STB process image fits. | The existing `coil`/`discreteInput`/`holdingRegister`/`inputRegister` enum — upstream `stateman.json` does the mapping. |
| Adding `centroid-hmi/lib/main.dart` registrations for new module configs | Anti-pattern flagged in `CLAUDE.md` (Architectural Constraints / Anti-Patterns). | Register inside `lib/page_creator/assets/registry.dart`'s `_fromJsonFactories` + `_previewFactories` maps next to the existing `BeckhoffEL1008Config` lines. |
| `pdfrx` or any PDF library for datasheet rendering | Already in `pubspec.yaml` for tech docs, but the painter doesn't display datasheets — they inform plan-phase research, not runtime. | N/A — don't import in module asset files. |

---

## Stack Patterns by Variant

**If the milestone scope later includes per-channel current/diagnostic readbacks (currently out of scope):**
- Add a `WORD` (16-bit) state-key per module in addition to the per-channel bool keys.
- Map to `holdingRegister` via existing StateMan `ModbusRegisterType.holdingRegister` — still no code changes in `tfc_dart`.
- Painter renders a small numeric overlay; reuse `TextPainter` pattern from `IO8Painter._drawLeftLabel`.

**If the milestone scope later includes multi-stack composition (currently out of scope per `PROJECT.md` line 21):**
- Mirror `BeckhoffCX5010Config.subdevices` — `List<Asset>` with `@AssetListConverter()` and a `_SubdeviceNormalized` height-matching wrapper.
- The `STBNIP2311Config` head asset becomes the parent that hosts a list of `STBPDT3100 / STBDDI3725 / STBDDO3705` children, exactly mirroring `BeckhoffEK1100Config`'s pattern at `lib/page_creator/assets/beckhoff.dart` lines 287–354.

**If pixel-perfect rendering is later required (it's not — explicitly rejected by `PROJECT.md` line 16):**
- Only then revisit `dxf` package. Until then, hand-extract.

---

## Version Compatibility

| Package | Constraint | Notes |
|---------|------------|-------|
| `flutter` | stable (Dart ^3.5.1) | No constraint added by v2.0. |
| `tfc_dart` (path) | unchanged | StateMan already at the required surface area. |
| `modbus_client_tcp` (path: `packages/modbus_client_tcp` v1.2.3) | unchanged | Carries `coil`/`discreteInput`/`holdingRegister`/`inputRegister` element types through to STB. |
| `json_serializable` 6.9.4 / `build_runner` 2.4.15 | unchanged | New `.g.dart` files generate against current pinned versions. |

---

## Open Questions for Plan Phase

1. **Family naming:** Should the asset-picker entry read "Modicon Momentum" (per `PROJECT.md`) or "Modicon STB / Advantys STB" (per the actual part numbers)? Painter implementation does not depend on this decision but `category` getter and file names do. Recommend user confirmation.
2. **Exact STBDDI3725 / STBDDO3705 terminal block layout (A side vs B side count):** confirmable by reading the `IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf` polylines during plan-phase architecture pass. Not needed for stack research.
3. **STBPDT3100 indicator surface:** datasheet PDF behind Schneider login portal returned 403. The Scribd mirror (`scribd.com/document/873281263/17-Schneider-STB-PDT-3100-Datasheet`) was found but not fetched in this pass — confirm during plan phase whether there are any LEDs beyond the implicit "fuse OK / 24 V present" state. If single bool suffices, no impact on stack.
4. **NIP2311 process-image base address per island:** decided upstream by Schneider Advantys Configuration Software, not the HMI. Out of scope for stack research — assets just consume the resolved StateMan key strings.

---

## Sources

- [Schneider STBNIP2311 product page](https://www.se.com/us/en/product/STBNIP2311/network-interface-module-modicon-stb-standard-ethernet-modbus-tcp-ip-10100mbits/) — HIGH confidence, official Schneider catalog
- [Schneider STBDDI3725 product page](https://www.se.com/us/en/product/STBDDI3725/basic-digital-input-module-modicon-stb-24v-dc-16i/) — HIGH confidence, official Schneider catalog
- [Schneider STBDDO3705 product page](https://www.se.com/us/en/product/STBDDO3705/basic-digital-output-module-stb-24-v-dc-16-o/) — HIGH confidence, official Schneider catalog
- [Schneider STBPDT3100 product page](https://www.se.com/us/en/product/STBPDT3100/standard-power-distribution-module-stb-24-v-dc/) — HIGH confidence, official Schneider catalog
- [Advantys STB Standard Ethernet Modbus TCP/IP Network Interface Module Applications Guide (EIO0000000051)](https://www.se.com/us/en/download/document/EIO0000000051/) — HIGH confidence on LED label set; portal PDF behind 403, content corroborated by mirror at [mroelectric.com/static/app/product/pdfs/31003688_K01_000_11.pdf](https://www.mroelectric.com/static/app/product/pdfs/31003688_K01_000_11.pdf)
- [STBDDI3725KC datasheet (Schneider portal)](https://iportal2.schneider-electric.com/Contents/docs/SQD-STBDDI3725KC_DATASHEET.PDF) — referenced; portal returned 403 to WebFetch but URL confirmed from Schneider site
- [pub.dev/packages/dxf](https://pub.dev/packages/dxf) — HIGH confidence on version (3.1.3) and staleness (~2 years); evaluated and rejected
- [pub.dev/packages/dxf_viewer](https://pub.dev/packages/dxf_viewer) — HIGH confidence on version (0.0.3) and incomplete entity coverage; evaluated and rejected
- In-repo verification:
  - `packages/tfc_dart/lib/core/state_man.dart` lines 195–325 (Modbus enums and config classes) — HIGH confidence, direct read
  - `lib/painter/beckhoff/io8.dart` (8-channel LED strip painter; 16-channel pattern is a vertical extension) — HIGH confidence, direct read
  - `lib/painter/beckhoff/ek1100.dart` `EthernetPortPainter` (DXF polylines hand-extracted into `static final List<List<Offset>>`) — HIGH confidence, direct read, this is the precedent for STB painters
  - `test/painter/atv320_golden_test.dart` (existing macOS-gated golden pattern) — HIGH confidence, direct read
  - `lib/page_creator/assets/beckhoff.dart` lines 287–500 (`BeckhoffEK1100Config` parent-with-subdevices pattern for future multi-stack composition) — HIGH confidence, direct read
  - `.planning/research/dxf/*.dxf` EXTMIN/EXTMAX bounding boxes — HIGH confidence, extracted in this research pass

---

*Stack research for: Modicon STB (Advantys STB) HMI asset family v2.0*
*Researched: 2026-05-11*
