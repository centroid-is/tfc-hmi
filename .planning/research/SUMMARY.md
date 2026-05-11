# Project Research Summary

**Project:** tfc-hmi2 v2.0 — Modicon Momentum I/O Asset Family
**Domain:** Brownfield Flutter HMI — additive asset family (Schneider distributed-I/O painters + Modbus TCP state binding)
**Researched:** 2026-05-11
**Confidence:** HIGH (architecture + stack), MEDIUM (Schneider firmware-internal semantics)

## Executive Summary

The v2.0 milestone adds five new page-creator assets — MomentumStack composite + NIP2311 (Ethernet head) + PDT3100 (power dist) + DDI3725 (16-ch DI) + DDO3705 (16-ch DO) — mirroring the existing Beckhoff family (CX5010 + EK1100 + EL1008/EL2008) one-for-one. The work is **purely additive**: zero pubspec changes, zero StateMan changes, zero changes to `beckhoff.dart` or `common.dart`, one modified file (`registry.dart`: +1 import, +10 entries). Every existing primitive (`CustomPainter` + `FittedBox`, `BaseLedBlockPainter` + `IOState`, `AssetListConverter`, `_combinedStream`, `RowIOView`, golden-test harness, JSON codegen) covers the milestone in full. Risk concentrates in two places: (a) **16-channel scale-up** of the LED painter and force-overlay logic, and (b) **Schneider-specific semantics** — Modbus bit ordering, force-encoding convention, and the fact that NIP2311 status LEDs are firmware-driven (not Modbus-addressable).

Recommended approach is **module-first, stack-last** in five plans: DDI3725 → DDO3705 → NIP2311 → PDT3100 → MomentumStack. This front-loads the highest-risk technical work (16-LED painter, force overlay, detail dialog) into Plan 01 while delivering the most operator-visible feature first; the stack is mechanical compose-work that's safest when its parts are proven. Painters live in `lib/painter/modicon/` (one file per module + a new `IO16LedBlockPainter` extending `BaseLedBlockPainter` as a sibling — NOT a parameterised generalisation; the Beckhoff codebase already chose the split-painter precedent). Configs live in a single `lib/page_creator/assets/modicon.dart` file (~1,400 LoC estimated, well under Beckhoff's 2,198).

**Top risks to mitigate before goldens lock:** (1) confirm Modbus bit ordering with the backend team — Beckhoff's LSB-first assumption is NOT portable to Momentum; (2) decide whether forced-channel LEDs should also surface the underlying raw state (current Beckhoff code collapses them, losing commissioning visibility); (3) make NIP2311 status LEDs decorative-by-default with at most one synthetic "comm OK" key, not five separately-keyed lamps that operators can misconfigure. **Verification strategy is locked: golden tests verify painters against the DXF + photo references staged at `.planning/research/dxf/`** — DXFs inform proportions (with one caveat: the shared I/O base DXF shows 2×6 terminal blocks but the physical module has 2×18; trust the photo for terminal-block geometry), photos confirm the column-major 2×8 LED layout and the operator-recognizable Schneider cream + green livery.

## Open Decision: Module Family Naming

**Surface before plan kickoff.** The STACK lane confirmed Schneider's catalog uses the **STB / Advantys STB** prefix on every part (STBNIP2311, STBPDT3100, STBDDI3725, STBDDO3705 — verified against the Schneider product portal). The user's vocabulary is **"Modicon Momentum"**, and `PROJECT.md` + the ARCHITECTURE lane both use `modicon.dart` / `Modicon...Config` (no STB prefix). Schneider's actual Modicon Momentum is a DIFFERENT family (170xxxxxxxx part numbers, different physical form factor).

| Option | Pros | Cons |
|--------|------|------|
| **Keep "Modicon Momentum" / `modicon.dart` / `Modicon...Config`** (user's vocabulary) | Matches how Centroid operators / panel builders refer to these modules. No churn on PROJECT.md or the milestone narrative. Asset-picker entry is friendly. | Technically inaccurate — these are Advantys STB modules. Future maintainer searching Schneider docs for "Modicon Momentum NIP2311" will find nothing. |
| **Rename to "Advantys STB" / `advantys_stb.dart` / `STB...Config`** (catalog-correct) | Matches Schneider's part numbers and datasheet vocabulary exactly. Maintainable. | Operators may not recognize "Advantys STB" by name. Requires renaming all milestone artifacts. |
| **Compromise: keep file/class as `modicon` but add a comment header documenting the naming** | Low-cost compromise. | Still inaccurate in the asset-picker UI. |

**Recommendation:** Honor the user's vocabulary (keep "Modicon Momentum" everywhere) and add a comment header on `modicon.dart` documenting the discrepancy so future maintainers can find Schneider docs under "Advantys STB" / "Modicon STB" if needed. This is a user-facing call — flag at plan-phase kickoff for explicit confirmation; do not assume.

## Key Findings

### Recommended Stack

**Stack changes required: NONE.** Every existing dependency covers v2.0 in full. No pubspec additions, no version bumps, no new test infrastructure. The STACK lane explicitly rejected `dxf` / `dxf_viewer` / `flutter_svg` / new Modbus abstractions — the Beckhoff precedent (hand-extract DXF polylines into `static const List<List<Offset>>` literals at painter file top) is the source of truth.

**Core technologies (all already present):**
- **Flutter `CustomPainter` + `FittedBox`** — every Beckhoff module already uses this; 16-channel is a sibling-painter, not a new capability
- **Riverpod (`stateManProvider`)** — identical pattern to `BeckhoffEL1008Config.build()`; subscribe to bool/uint16 keys per module
- **`tfc_dart` StateMan** — already exposes all four Modbus register types (coil / discreteInput / holdingRegister / inputRegister); STB process-image fits 1:1
- **`json_serializable` + `build_runner`** — same `@JsonSerializable()` pattern as `BeckhoffEK1100Config`
- **`flutter_test` golden harness** — existing macOS-gated `matchesGoldenFile(...)` pattern at `test/painter/atv320_golden_test.dart` and `test/page_creator/assets/elevator_painter_test.dart` is the template

**Reuses from Beckhoff (verbatim or imported via `show`):**
- `BaseLedBlockPainter`, `IOState` enum, `bodyColor` constant — imported from `lib/painter/beckhoff/io8.dart`
- `EthernetPortPainter` — imported from `lib/painter/beckhoff/ek1100.dart` for NIP2311's dual RJ45
- `_SubdeviceNormalized` (height-normalizing Row wrapper) — duplicated (~20 LoC) in modicon.dart per the no-cross-cutting-refactor discipline
- `_combinedStream` + `_ledStates` pattern — duplicated as `_ledStates16` with loop bound 16

### Expected Features

**Must have (table stakes — every item maps to an existing Beckhoff parity surface):**
1. All five module types registered + previewable in the page creator
2. **16-LED visualisation in a 2×8 column-major grid** (channels 1–8 left column top-to-bottom, channels 9–16 right column top-to-bottom — matches the physical module per the user-confirmed photo)
3. Bitmask-driven LED state from `rawStateKey` (uint16; bit i = channel i+1 — bit ordering convention TBD with backend before goldens lock)
4. Per-channel force-override array via `forceValuesKey` (auto / forcedLow / forcedHigh)
5. Per-channel ON/OFF filter ms (DI only)
6. Per-channel descriptions (string array via `descriptionsKey`)
7. Tap-to-open detail dialog with `RowIOView` repeated 8 times (vs 4 for EL1008)
8. Manual force-write (auto/low/high SegmentedButton — existing EL1008/EL2008 path, reused verbatim)
9. Schneider cream body + Schneider green branding on every module
10. NIP2311 dual RJ45 painter + decorative status LEDs (RUN/PWR/ERR/ST/TEST)
11. PDT3100 single-LED `inputOkKey` widget
12. MomentumStack with `allKeys` recursive flattening (CX5010 pattern verbatim)
13. MomentumStack reorderable subdevice list with filtered "Add" dropdown (only the 4 Modicon module types)
14. Full JSON round-trip via codegen for all 5 new types
15. AssetRegistry registration (`fromJson` + `preview` factory in BOTH maps)
16. Backwards-compatible deserialisation
17. Golden tests per painter (light + dark theme pair; ~14 PNGs minimum)
18. Disconnected-state visual (inherited from `IO8Painter`)
19. Forced-channel red-border pulse animation in dialog (inherited from `TriangleBoxPainter`)
20. Leak tests per module (PROJECT.md mandate)

**Should have (differentiators, low cost):** NIP2311 MAC ID / IP address tap-dialog readout; per-port Ethernet link/activity dot on RJ45 jacks; per-channel label live colouring for forced channels.

**Defer (v2.1+):** per-channel current/wire-break readback; group-of-8 fuse status; multi-stack composition; stack-level disconnected rollup; canonical-layout enforcement; 4-channel / parameterised `IONLedBlockPainter` generalisation.

**Explicit anti-features:** pixel-perfect Schneider trademark replication; 1-column 16-LED layout exactly matching photo; three-LED-per-channel diagnostic rendering; NIP2311 status LEDs wired to five separately-configurable PLC keys.

### Architecture Approach

Single-file config (`lib/page_creator/assets/modicon.dart`, ~1,400 LoC) + per-module painter files under `lib/painter/modicon/`. `IO16LedBlockPainter` lands as a SIBLING to `IO8LedBlockPainter` under `BaseLedBlockPainter` — NOT a parameterised generalisation. MomentumStack uses the CX5010 `subdevices: List<Asset>` + `@AssetListConverter()` + `allKeys` flat-map override verbatim — NO `ModuleSlotEntry` wrapper.

**Major components:**
1. **`lib/page_creator/assets/modicon.dart`** (NEW, single file) — 5 configs + dialogs + stream helpers
2. **`lib/painter/modicon/io16.dart`** (NEW) — `IO16LedBlockPainter extends BaseLedBlockPainter` + `IO16Widget` + `IO16Painter`
3. **`lib/painter/modicon/{ddi3725,ddo3705,nip2311,pdt3100}.dart`** (NEW) — per-module body painters
4. **`lib/page_creator/assets/registry.dart`** (MODIFIED) — +1 import + 5 entries in `_fromJsonFactories` + 5 in `defaultFactories`

**Pattern locks:** painters never touch StateMan; module body Schneider cream FIXED; text outside body uses `Theme.of(context).colorScheme.onSurface`; `GestureDetector` with `HitTestBehavior.opaque` wrapping each module; `_combinedStream` cached in `initState`.

### Critical Pitfalls (top 5 from PITFALLS lane's 16)

1. **M-02 — Modbus bit ordering ambiguity.** Beckhoff's LSB-first assumption is NOT portable to Schneider Momentum. **Confirm with backend team before locking goldens.** Add a bit-mapping unit test before painter implementation.
2. **M-04 — Force-override semantics collapse raw state.** EL1008 collapses raw+force into a single `IOState` — operator can't see whether underlying wire is energised on a forced channel. **User decision required before goldens lock.** Recommended: 4-state-per-channel data model + corner pip on forced LEDs.
3. **M-05 — NIP2311 status LEDs are NOT Modbus-addressable.** Firmware-driven, not PLC-application-driven. **Prevention:** decorative-by-default; optionally accept ONE synthetic "comm OK" boolean key, not five.
4. **M-09 — Column-major 2×8 LED layout per the photo.** Channels 1–8 LEFT column, 9–16 RIGHT column. Row-major would confuse commissioning.
5. **M-06 — JSON / codegen drift.** Every new field needs `@JsonKey(defaultValue: ...)` or nullable. CI gate on uncommitted `*.g.dart`. One JSON round-trip + one "legacy JSON" test per new config.

## Verification Strategy (LOCKED)

**Golden tests verify painters against DXF + photo references.** DXFs inform proportions (NIP2311 ~58×82 mm; PDT3100 ~115×162 mm; shared DI/DO base 107×152 mm). Photos at `.planning/research/photos/` are canonical for terminal-block geometry (DXF shows 2×6, physical has 2×18 — trust the photo). User-confirmed photo locks column-major 2×8 LED layout and stack order.

**Golden harness mirrors elevator/sensor v1.0:** `RepaintBoundary` + unique `Key` + deterministic `SizedBox` + `tester.pump(Duration.zero)` (NEVER `pumpAndSettle()`) + `AlwaysStoppedAnimation(0)` + macOS-gated + light/dark theme pair. Goldens under `test/page_creator/assets/goldens/modicon/`.

## Implications for Roadmap

**5 plans, module-first, stack-last:**

### Plan 01: DDI3725 (16-Channel Digital Input)
**Rationale:** Highest-risk technical work — 16-LED painter scale-up + force-overlay + detail dialog. Most operator-visible feature. Surfaces every painter and stream-handling decision before cheaper modules ride on top.
**Delivers:** `ModiconDDI3725Config` + dialog + ConsumerWidget + `lib/painter/modicon/io16.dart` + `lib/painter/modicon/ddi3725.dart` + registry entry + goldens + JSON round-trip + leak test.
**Avoids:** M-02 (bit-ordering locked here with unit test), M-03 (single combined-stream), M-04 (4-state-per-channel model), M-09 (column-major 2×8), M-16, M-08, M-11.
**Research flag:** YES — bit-ordering convention requires backend confirmation; force-encoding semantics need user/backend confirmation.

### Plan 02: DDO3705 (16-Channel Digital Output)
**Rationale:** Clones DDI3725 minus filter fields. Exercises DI/DO symmetry; reuses `IO16Widget`.
**Delivers:** Config + dialog + ConsumerWidget + `lib/painter/modicon/ddo3705.dart` + registry + goldens + tests.
**Avoids:** M-02 (MUST reuse DI's bit-ordering constant), M-03, M-08, M-11.
**Research flag:** NO — pattern proven by Plan 01.

### Plan 03: NIP2311 (Ethernet Modbus/TCP Head)
**Rationale:** Introduces `EthernetPortPainter` reuse + decorative status LEDs. Visual identity anchor.
**Delivers:** Config + dialog (one optional synthetic comm-OK + optional MAC/IP strings — NOT five status keys) + `lib/painter/modicon/nip2311.dart` + registry + goldens + tests.
**Avoids:** M-05 (decorative-by-default), M-07, M-10, M-08.
**Research flag:** PROBABLY — exact RUN/PWR/ERR/ST/TEST wording verification against Schneider 33001466 / EIO0000000051.

### Plan 04: PDT3100 (Power Distribution)
**Rationale:** Smallest module. Cheapest deliverable.
**Delivers:** Config + dialog (single optional `inputOkKey`) + `lib/painter/modicon/pdt3100.dart` (~150 LoC) + registry + goldens + tests.
**Avoids:** M-07, M-10, M-08.
**Research flag:** NO — surface fully locked.

### Plan 05: MomentumStack (Composite Parent)
**Rationale:** Mechanical compose-work; safest when all four parts are proven.
**Delivers:** `ModiconMomentumStackConfig` + ReorderableListView dialog with filtered `_availableModiconSubdevices` dropdown + `allKeys` flat-map override (CX5010 verbatim) + post-fromJson sanitiser + registry + goldens + integration test.
**Avoids:** M-01 (allKeys integration test), M-06 (JSON round-trip + legacy-JSON test), M-12 (permissive-render-restrictive-add), M-15 (collector-load downstream note).
**Research flag:** NO — CX5010 verbatim.

### Research Flags Summary
- **Needs research:** Plan 01 (bit ordering, force encoding), Plan 03 (status LED labels — probably)
- **Standard patterns:** Plan 02, Plan 04, Plan 05

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Zero pubspec changes verified by direct read; Beckhoff precedent covers every primitive. |
| Features | HIGH (HMI surface) / MEDIUM (Schneider LED semantics) | EL1008/EL2008 parity locked by direct read; exact NIP labels need datasheet verification. |
| Architecture | HIGH | All recommendations grounded in direct read of registry.dart, common.dart, beckhoff.dart, io8.dart, ek1100.dart, page.dart at HEAD. |
| Pitfalls | HIGH (codebase items) / MEDIUM (Schneider items M-02, M-05, M-16) | Beckhoff/v1.0 items bulletproof; Schneider firmware items need validation. |

**Overall confidence:** HIGH for structural milestone; MEDIUM for Schneider-specific semantic decisions (resolvable in Plan 01/03 research passes).

### Gaps to Address

| Gap | Resolution path |
|-----|-----------------|
| Modbus bit-ordering for STBDDI3725/STBDDO3705 | Plan 01 research-phase: confirm with backend before goldens lock. |
| Force-encoding semantics on Schneider Momentum (single-byte vs parallel bitmasks) | Plan 01 research-phase: confirm with backend. |
| NIP2311 exact status LED label set on shipping hardware revision | Plan 03 research-phase: verify against datasheet or device-side label strip. |
| Naming decision: "Modicon Momentum" vs "Advantys STB" | Plan-phase kickoff: explicit user confirmation. Recommended: keep user vocabulary + code-comment header. |
| Force-override raw-state visibility (M-04) | Plan 01 research-phase: UX call. Recommended: corner pip + 6 force×raw goldens per module. |
| Collector load downstream (~100 keys/stack) | Plan 05: surface in plan's downstream-impacts; not v2.0 deliverable. |

## Sources

**Primary (HIGH confidence — direct codebase read at HEAD, branch `elevator`):**
- `lib/page_creator/assets/beckhoff.dart` (2,198 lines, full read)
- `lib/page_creator/assets/registry.dart` (full read)
- `lib/page_creator/assets/common.dart` (full read)
- `lib/painter/beckhoff/io8.dart` (full read)
- `lib/painter/beckhoff/ek1100.dart` (full read)
- `lib/page_creator/page.dart:1-47`
- `test/page_creator/assets/elevator_painter_test.dart` (full read)
- `.planning/PROJECT.md` (full read)
- `.planning/research/dxf/README.md` + photo references
- User-supplied physical-stack photo + DDI3725/DDO3705 clean front photos
- `packages/tfc_dart/lib/core/state_man.dart` lines 195–325

**Secondary (MEDIUM confidence — Schneider product portal + community mirrors):**
- Schneider STBNIP2311 / STBDDI3725 / STBDDO3705 / STBPDT3100 product pages
- Advantys STB Applications Guide EIO0000000051
- Modicon 33001466 datasheet

**Tertiary (LOW confidence — needs validation):**
- Exact Modbus bit-ordering on STBDDI3725/STBDDO3705 — confirm Plan 01
- Force-encoding semantics on Schneider Momentum — confirm Plan 01
- STBPDT3100 indicator surface beyond INPUT OK — moot per user lock

---
*Research completed: 2026-05-11*
*Ready for roadmap: yes*
