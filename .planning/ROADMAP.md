# Roadmap: Advantys STB I/O Assets (v2.0)

## Overview

Five new HMI assets — four Schneider Advantys STB module faceplates (STBDDI3725 16-ch DI, STBDDO3705 16-ch DO, STBNIP2311 Ethernet head, STBPDT3100 power) plus an AdvantysSTBStack composite parent — delivered in five phases, **module-first / stack-last**. Phase 01 ships DDI3725 first: it is the highest-risk technical work (16-LED painter scale-up, bitmask decoding, force-overlay collapse, tap-to-open detail dialog) and the most operator-visible module; locking it first establishes every convention (golden harness, combined-stream hoisting, cream-body discipline, GestureDetector wrapping, @JsonKey defaults) that the remaining four phases reuse. Phase 02 clones DDO3705 (DI minus filters, plus manual force-write path). Phase 03 adds NIP2311 with decorative status LEDs and dual RJ45 reuse. Phase 04 ships PDT3100 (smallest, single bool key). Phase 05 composes everything into AdvantysSTBStack with `allKeys` recursive flattening (CX5010 verbatim) plus full integration test. Two upstream research items are flagged before Phase 01 lands and one before Phase 03 lands. Every phase has goldens against DXF + photo references; every leaf module phase delivers a JSON round-trip + leak test.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4, 5): Planned milestone work for v2.0
- Decimal phases (e.g. 2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

> v1.0 phases (Elevator & Sensor Assets) are archived to `.planning/milestones/v1.0/`. Phase numbering RESETS to 1 for v2.0.

- [x] **Phase 1: STBDDI3725 (16-Ch Digital Input)** - Highest-risk module first: 16-LED painter + force overlay + 16-row detail dialog; locks bit-ordering + golden harness + cream-body discipline for the milestone ✅ 51 tests + 10 goldens; LSB-first bit-order locked
- [x] **Phase 2: STBDDO3705 (16-Ch Digital Output)** - Clones DDI3725 minus filters; reuses `IO16LedBlockPainter` and proves DI/DO symmetry with manual force-write end-to-end ✅ 91 tests total + 10 goldens; force-write end-to-end verified
- [x] **Phase 3: STBNIP2311 (Ethernet Head Adapter)** - Module body + dual RJ45 (reuse `EthernetPortPainter`) + decorative-only status LEDs (no per-LED PLC keys) ✅ 108 tests total + 2 goldens
- [x] **Phase 4: STBPDT3100 (Power Distribution)** - Smallest module: body + single `inputOkKey` LED + JSON round-trip ✅ 135 tests total + 4 goldens
- [ ] **Phase 5: STBNIP2311 as Composite Head (RETROFITTED 2026-05-12)** - Make `STBNIP2311Config` itself the composite parent (mirrors CX5010/EK1100 precedent — head IS the composite, no standalone "stack" wrapper). `allKeys` flat-map + filtered Add dropdown (3 I/O modules; NIP excluded) + permissive-render-restrictive-add sanitiser + full-stack integration test.

## Phase Details

### Phase 1: STBDDI3725 (16-Ch Digital Input)
**Goal**: Operators can place an STBDDI3725 16-channel digital-input module on a page, point its `rawStateKey` at the PLC uint16 bitmask plus per-channel `forceValuesKey` / `onFiltersKey` / `offFiltersKey` / `descriptionsKey`, watch all 16 channel LEDs reflect live state in a column-major 2×8 grid (channels 1–8 left column, 9–16 right column), and tap the body to open an 8-row × 2-column detail dialog where each row exposes the channel's state, a force segmented-button (auto/low/high), filter ms inputs, and the description text — with bit-ordering locked by a unit test before goldens, force collapsing raw state in the LED (matching EL1008), the combined StateMan stream hoisted to `initState` for zero resubscribe storm, and full JSON round-trip + back-compat + leak test.
**Depends on**: Nothing (first phase; foundational)
**Requirements**: DDI-01, DDI-02, DDI-03, DDI-04, DDI-05, DDI-06, DDI-07, DDI-08, DDI-09, DDI-10, QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05
**Success Criteria** (what must be TRUE):
  1. Operator can place an `STBDDI3725Config` asset from the palette, configure five state keys (raw / force / on-filter / off-filter / descriptions) via `KeyField`, see all 16 channel LEDs reflect the live bitmask in a column-major 2×8 grid (matches physical module per `DDI3725_front_clean.png`), and observe force-mode channels render their forced state (raw collapsed — matching EL1008; no corner pip in v2.0).
  2. A bit-mapping unit test asserts `0x0001 → channel 1 only lit`, `0x8000 → channel 16 only lit`, `0xAAAA → alternating channels lit` — the chosen bit-order constant lives at the top of `lib/painter/advantys_stb/io16.dart` and is referenced by both DDI3725 and DDO3705 to prevent convention drift.
  3. Tapping the module body opens a detail dialog with 8 rows × 2-column `RowIOView` (one row per channel-pair) showing channel state + force segmented-button + ON/OFF filter ms inputs + description text field; closing/reopening the dialog 10× leaks no listeners (verified via leak test on `stateMan.subscriberCount`).
  4. Golden tests pass for `all_off`, `all_on`, `alternating_0xAAAA`, `forced_mix`, `disconnected` × {light, dark} themes against the DXF body proportions and photo terminal-block geometry (2×18-pin per `DDI3725_front_clean.png`, NOT the inaccurate DXF). The combined StateMan stream is hoisted to `initState` (cached in `late final`) and disposed in `dispose` — `flutter analyze` reports zero issues across new files.
  5. JSON round-trips every field via codegen with `@JsonKey(defaultValue: ...)` or nullable, and a legacy-JSON test (hand-written snippet omitting all v2.0 fields) loads cleanly into the default config — backward compatibility verified on a v1.0-era saved-page round-trip.
**Plans**: 4 plans
- [ ] 01-01-PLAN.md — IO16LedBlockPainter + kSTBChannelBitOrder + bit-mapping unit test (TDD foundation)
- [ ] 01-02-PLAN.md — STBDDI3725Config + body painter + live ConsumerWidget + 10-PNG golden matrix
- [ ] 01-03-PLAN.md — Tap-to-open detail dialog (8 rows × 2 RowIOView with force/filter/description)
- [ ] 01-04-PLAN.md — AssetRegistry registration + JSON round-trip + back-compat + mount/dialog leak tests
**UI hint**: yes
**Research flag**: YES — Plan 01 must confirm (a) Modbus bit-ordering convention with the backend team (Beckhoff's LSB-first is NOT portable to STB), and (b) Schneider force-encoding semantics (Beckhoff's `1=forcedLow / 2=forcedHigh` single-byte may differ from STB's parallel bitmask convention) before goldens lock.

### Phase 2: STBDDO3705 (16-Ch Digital Output)
**Goal**: Operators can place an STBDDO3705 16-channel digital-output module on a page, watch all 16 commanded channels reflect live bitmask state in the same column-major 2×8 LED grid as DDI3725, open a tap-to-open detail dialog with 8 rows × 2-column `RowIOView` (minus the filter inputs — outputs don't have filters), and manually force a channel high/low via the SegmentedButton (which writes to `forceValuesKey` and is reflected on the painter end-to-end) — with `IO16LedBlockPainter` reused verbatim from Phase 01 and the bit-ordering constant pinned to the same module-level value.
**Depends on**: Phase 1 (reuses `IO16LedBlockPainter`, bit-order constant, combined-stream pattern, golden harness, cream-body discipline)
**Requirements**: DDO-01, DDO-02, DDO-03, DDO-04, DDO-05, DDO-06, DDO-07, DDO-08, DDO-09
**Success Criteria** (what must be TRUE):
  1. Operator can place an `STBDDO3705Config` asset from the palette, configure `rawStateKey` + `forceValuesKey` + `descriptionsKey` via `KeyField`, and see all 16 channel LEDs reflect the commanded bitmask state — the module body painter at `lib/painter/advantys_stb/ddo3705.dart` reuses `IO16LedBlockPainter` from Phase 01 but ships its own output-style LED legend strip.
  2. A golden visually distinguishes DDO3705 from DDI3725 (label colour / legend strip) — same body geometry, different label semantics; operator-recognizable as the output module without reading the nameOrId.
  3. Tapping the module body opens a detail dialog mirroring DDI3725's structure but omitting filter rows; the operator drags-to-force a channel via the SegmentedButton, the `forceValuesKey` write hits StateMan, and the painter reflects the forced state in the same frame — verified by an end-to-end widget test that drives the dialog interaction and asserts the painter's IOState.
  4. JSON round-trips every field, legacy-JSON test passes, leak test on dialog open/close cycles confirms zero subscription leaks, and `flutter analyze` reports zero issues.
  5. Goldens cover `all_off`, `all_on`, `alternating_0x5555`, `forced_mix`, `disconnected` × {light, dark} themes; bit-ordering convention matches DDI3725 (asserted by a shared constant — drift would fail the bit-mapping test in Phase 01).
**Plans**: TBD
**UI hint**: yes

### Phase 3: STBNIP2311 (Ethernet Head Adapter)
**Goal**: Operators can place an STBNIP2311 Ethernet head adapter on a page, see the head body + dual RJ45 ports (reusing `EthernetPortPainter` from `lib/painter/beckhoff/ek1100.dart`) + a row of five decorative status LEDs (RUN / PWR / ERR / ST / TEST) rendered in fixed "normal" state — with NO per-LED PLC keys (firmware-driven on real hardware; locked decision), JSON round-trip clean, and the asset visually anchoring the Schneider cream + green Advantys STB livery.
**Depends on**: Phase 2 (inherits cream-body + GestureDetector + golden conventions from Phase 01/02)
**Requirements**: NIP-01, NIP-02, NIP-03, NIP-04
**Success Criteria** (what must be TRUE):
  1. Operator can place an `STBNIP2311Config` asset from the palette and see a module body at the NIP2311 DXF aspect ratio plus dual RJ45 ports (reusing `EthernetPortPainter` verbatim from `lib/painter/beckhoff/ek1100.dart` — no Beckhoff branding embedded in the painter) plus a row of five decorative status LEDs labelled RUN / PWR / ERR / ST / TEST.
  2. The status LEDs render decoratively only — there are NO `runKey`, `pwrKey`, `errKey`, `stKey`, `testKey` fields on the config (locked decision per PROJECT.md). The configure dialog exposes only `nameOrId` and the standard `Coordinates` / `Size` fields. Operators inspect the physical device for true status.
  3. Goldens cover the NIP2311 module body in `decorative_normal` state × {light, dark} themes against the NIP2311 DXF bounding-box proportions.
  4. JSON round-trip is clean; a legacy-JSON test (saved page without an NIP2311 instance) loads without error; `flutter analyze` reports zero issues.
**Plans**: TBD
**UI hint**: yes
**Research flag**: PROBABLY — Plan 03 should verify the exact RUN / PWR / ERR / ST / TEST label wording against Schneider datasheet 33001466 / EIO0000000051 before goldens lock (the wording is the only firmware-internal surface visible to operators; getting it wrong loses operator recognition).

### Phase 4: STBPDT3100 (Power Distribution)
**Goal**: Operators can place an STBPDT3100 24V DC power-distribution module on a page, configure an optional `inputOkKey` bool state key, and watch the single "INPUT OK" LED render green when the key is true / dim when null or false — the smallest module of the milestone, single state key, no detail dialog, but full JSON round-trip and back-compat.
**Depends on**: Phase 3 (inherits all conventions from Phases 01–03)
**Requirements**: PDT-01, PDT-02, PDT-03
**Success Criteria** (what must be TRUE):
  1. Operator can place an `STBPDT3100Config` asset from the palette, configure an optional `inputOkKey` via `KeyField`, and see the module body painter at `lib/painter/advantys_stb/pdt3100.dart` render at the PDT3100 DXF aspect ratio (~115×162 mm) with a single LED bound to the bool key (green = OK, dim = null/unknown/disconnected).
  2. Goldens cover `input_ok` and `fault` (or dim) states × {light, dark} themes.
  3. JSON round-trips cleanly with `inputOkKey` nullable, legacy-JSON test passes, `flutter analyze` reports zero issues.
**Plans**: TBD
**UI hint**: yes

### Phase 5: STBNIP2311 as Composite Head (RETROFITTED 2026-05-12)
**Goal**: Operators can place an STBNIP2311 (Ethernet head) onto a page, open its configure dialog, add subdevices from a filtered "Add" dropdown limited to the three STB I/O module types (PDT3100 / DDI3725 / DDO3705 — NIP itself excluded; a head cannot nest another head), reorder them in a `ReorderableListView`, watch the NIP head + all children render in a horizontal `Row` (height-normalized via `_STBSubdeviceNormalized`) — with `allKeys` flat-mapping every child's `*Key` fields (and recursive subdevices' keys) so alarms and collectors discover the full key set without separate registration, a post-`fromJson` sanitiser dropping any non-STB child types (permissive render, restrictive add — mirroring CX5010), and a full integration test confirming a NIP head containing one of every I/O module type loads cleanly, all child keys are discoverable, every painter renders, and taps register on each I/O module's body (DDI/DDO open detail dialogs; NIP head + PDT decorative). See `.planning/phases/05-advantysstbstack-composite-parent/05-RETROFIT.md`.
**Depends on**: Phase 4 (requires all four STB module types to exist in the registry)
**Requirements**: STACK-01, STACK-02, STACK-03, STACK-04, STACK-05, QUAL-06, QUAL-07
**Success Criteria** (what must be TRUE):
  1'. (Retrofitted) NIP composite is in the palette via the existing `STBNIP2311Config` registration in BOTH `_fromJsonFactories` and `defaultFactories` of `AssetRegistry` (no new palette entry required — the NIP was already there from Phase 3). The configure dialog uses a filtered "Add" dropdown bounded to `_availableSTBSubdevices` (PDT3100 / DDI3725 / DDO3705 only — NIP excluded so a head cannot nest a head) to add subdevices to a polymorphic `List<Asset> subdevices` annotated with `@AssetListConverter()` (mirrors CX5010 verbatim).
  2. The configure dialog supports reorder (via `ReorderableListView`) and delete (via trailing IconButton), and the `build()` renders all subdevices inside a `FittedBox(fit: BoxFit.contain, child: Row(...))` with each subdevice wrapped in `_SubdeviceNormalized` for height normalization.
  3. `STBNIP2311Config.allKeys` is overridden to flat-map each subdevice's `allKeys` (plus recursive subdevices' keys) into a de-duplicated `Set<String>` — verified by an integration test that asserts every leaf module's `*Key` fields appear in `head.allKeys`.
  4. A post-`fromJson` sanitiser drops any subdevice whose `runtimeType.toString()` is not in `{STBNIP2311Config, STBPDT3100Config, STBDDI3725Config, STBDDO3705Config}` (permissive render fallback for older saved pages, restrictive add via dropdown — silent filter + log, not throw, matching `AssetRegistry.parse`'s existing convention).
  5. An integration test mounts a single NIP head containing one PDT + one DDI + one DDO subdevices, asserts the page loads cleanly, `head.allKeys` returns the union of all child keys, every painter renders without exception, taps register on each I/O module's body (DDI/DDO open detail dialogs; NIP head and PDT decorative), `flutter analyze` reports zero issues across all new files, and the goldens `nip_with_modules_{light,dark}.png` capture the canonical NIP+PDT+DDI+DDO layout in both themes.
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. STBDDI3725 (16-Ch DI) | 4/4 | ✅ Complete | 2026-05-11 |
| 2. STBDDO3705 (16-Ch DO) | 1/1 | ✅ Complete | 2026-05-11 |
| 3. STBNIP2311 (Ethernet Head) | 1/1 | ✅ Complete | 2026-05-11 |
| 4. STBPDT3100 (Power) | 1/1 | ✅ Complete | 2026-05-11 |
| 5. AdvantysSTBStack (Composite) | 0/TBD | Not started | - |
