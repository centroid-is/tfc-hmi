---
phase: 01-stbddi3725-16-ch-digital-input
plan: 04
subsystem: page_creator/assets
tags: [registry, json-roundtrip, back-compat, lifecycle, leak-test, phase-verification]
dependency_graph:
  requires:
    - 01-01 (kSTBChannelBitOrder + bitmaskToLedStates)
    - 01-02 (STBDDI3725Config + STBDDI3725Widget + goldens)
    - 01-03 (detail dialog + force/filter write paths)
  provides:
    - "STBDDI3725Config registered in AssetRegistry (palette + load wiring)"
    - "Lifecycle hygiene grep-locked on _STBDDI3725State.dispose()"
    - "QUAL-04 back-compat lock for legacy v1.0-era saved pages"
  affects:
    - lib/page_creator/assets/registry.dart
    - lib/page_creator/assets/advantys_stb.dart
    - test/page_creator/assets/advantys_stb_test.dart
tech_stack:
  added: []
  patterns:
    - "Dual-map registration (PITFALL §9.2): both _fromJsonFactories and defaultFactories receive the new asset"
    - "Defensive dispose(): null out cached cold-stream + StateMan reference to release closure-captured refs"
    - "Grep-guard tests lock dispose contract structurally (mirrors elevator/sensor v1.0 pattern)"
    - "Real-flow back-compat tests go through jsonEncode/jsonDecode to match PageManager save path"
key_files:
  created: []
  modified:
    - lib/page_creator/assets/registry.dart
    - lib/page_creator/assets/advantys_stb.dart
    - test/page_creator/assets/advantys_stb_test.dart
decisions:
  - "@JsonKey(defaultValue: '1') on nameOrId is sufficient — no factory belt-and-suspenders added"
  - "_STBDDI3725State.dispose() override added defensively (nulls _combinedStreamCache + _stateMan) even though StreamBuilder owns the live subscription — releases closure-captured StateMan reference for long-lived pages"
  - "Legacy 'minimal' JSON snippet retains coordinates+size keys (the v1.0 BaseAsset baseline) — the Phase 1 'v2.0 fields' are nameOrId + the five *Key fields, all of which DO rehydrate to defaults"
  - "STBDDI3725Config inserted between BeckhoffEL3054Config and SchneiderATV320Config in BOTH factory maps — matches alphabetical-by-vendor convention already established"
metrics:
  duration: "≈18 minutes wall time"
  completed: "2026-05-11"
  tasks_complete: 4
  commits: 3
---

# Phase 01 Plan 04: AssetRegistry + JSON back-compat + leak test + verification sweep Summary

Phase 1 of the v2.0 Advantys STB milestone is now closed and shippable. Plan 04 wired the work shipped by Plans 01–03 into the AssetRegistry (palette + saved-page loading), proved the JSON round-trip + legacy-JSON back-compat contracts (QUAL-04), grep-locked the lifecycle hygiene that Plans 02+03 implemented (DDI-10 / QUAL-03), and ran the four-audit verification sweep that gates Phase 2.

## One-liner

Land STBDDI3725Config in both AssetRegistry factory maps, prove the JSON contract end-to-end (full round-trip + v1.0 legacy snippet + saved-page-shape parse), and grep-lock `_STBDDI3725State.dispose()` so mount/unmount + 10× dialog cycles cannot leak.

## What shipped

### Task 1 — Registry registration (`feat(01-04): bce8900`)

- Added `import 'advantys_stb.dart';` to `lib/page_creator/assets/registry.dart` (placed next to `import 'beckhoff.dart';` per the alphabetical-by-vendor convention).
- Added `STBDDI3725Config: STBDDI3725Config.fromJson` to `_fromJsonFactories` after the `BeckhoffEL3054Config` entry.
- Added `STBDDI3725Config: STBDDI3725Config.preview` to `defaultFactories` (same position).
- New test group `STBDDI3725Config registry resolution` (3 tests) verifies:
  - `AssetRegistry.createDefaultAssetByName('STBDDI3725Config')` returns a typed instance (palette wiring).
  - `AssetRegistry.parse(saveJson)` round-trips a saved JSON entry through `jsonEncode/jsonDecode` and recovers a typed `STBDDI3725Config` with the original `nameOrId` + `rawStateKey` preserved.
  - `AssetRegistry.defaultFactories` contains the `STBDDI3725Config` type key (palette enumerability).
- PITFALL §9.2 lock: `grep -c "STBDDI3725Config" lib/page_creator/assets/registry.dart == 2`.

### Task 2 — JSON full round-trip + back-compat (`feat(01-04): 6ffdf4d`)

- New group `STBDDI3725Config full JSON round-trip` (1 test): a fully-populated config (all five `*Key` fields + every BaseAsset field including `coordinates`, `size`, `text`, `textPos`, `techDocId`, `plcAssetKey`) survives `jsonEncode + jsonDecode + fromJson` with every field equal to its pre-encode value.
- New group `STBDDI3725Config JSON back-compat` (3 tests):
  - Minimal legacy snippet (v1.0 baseline = `asset_name + coordinates + size`) rehydrates Phase 1 defaults (`nameOrId='1'`, all five `*Key` fields null, BaseAsset defaults).
  - v1.0-era saved-page-shape JSON (`pages → home → assets → snippet`) flows through `AssetRegistry.parse` and recovers a typed `STBDDI3725Config`.
  - Forward-compat: unknown future fields are silently ignored by the codegen `fromJson`.
- The existing data-shape group's "legacy JSON without nameOrId loads as '1'" test already verified `@JsonKey(defaultValue: '1')` works. **No factory belt-and-suspenders was added** — the annotation alone is sufficient.

### Task 3 — Mount/unmount + dialog cycle leak tests (`feat(01-04): a9e6521`)

- New group `STBDDI3725 mount/unmount lifecycle` (2 tests):
  - Runtime test: pump live widget with `_StreamingStubStateMan` overriding `stateManProvider`, replace with `SizedBox.shrink()`, pump 1 second, assert `tester.takeException() == null`.
  - Source-level grep guard (mirrors `elevator_widget_test.dart:1897-1932` precedent): assert `_STBDDI3725State` overrides `dispose()`, calls `super.dispose()`, and either `cancel()`s a held subscription or nulls out `_combinedStreamCache`.
- New group `STBDDI3725 dialog open/close 10× leak` (1 test): 10 cycles of tap-to-open + tap-Close, then unmount + pump 1s, assert no exception.
- Added `_STBDDI3725State.dispose()` override that nulls `_combinedStreamCache` and `_stateMan` defensively (StreamBuilder still owns the live `StreamSubscription` — this releases the closure-captured `StateMan` reference for long-lived pages).

### Task 4 — Phase 1 verification sweep (no source diff)

Four audits all green; values recorded below. No source changes; the sweep was diagnostic only.

## Final audit values (Task 4)

| Audit | Metric | Value | Threshold | Status |
|-------|--------|-------|-----------|--------|
| 1 | Tests passing in advantys_stb_test.dart | 51 | ≥ 25 (relaxed) / ≥ 42 (ideal) | PASS |
| 1 | Tests failing | 0 | 0 | PASS |
| 2 | `flutter analyze` issues across Phase 1 footprint | 0 | 0 | PASS |
| 3 | `grep -c STBDDI3725Config registry.dart` | 2 | ≥ 2 | PASS |
| 3 | `HitTestBehavior.opaque` in advantys_stb.dart | 1 | ≥ 1 | PASS |
| 3 | `Color(0xFFF7F5E6)` hardcoded in advantys_stb.dart | 0 | == 0 | PASS |
| 3 | `bodyColor` references in ddi3725.dart | 3 | ≥ 1 | PASS |
| 3 | Goldens PNG count under `goldens/advantys_stb/` | 10 | ≥ 10 | PASS |
| 5 | `_combinedStream(...)` invocations in main widget `build()` | 0 | == 0 (PITFALL M-03) | PASS |

## Requirements coverage matrix (DDI-01..10 + QUAL-01..05)

| ID | Plans referencing | Verification path | Status |
|----|-------------------|-------------------|--------|
| DDI-01 | 01-02, 01-04 | Registry resolution + KeyField surface tests | Complete |
| DDI-02 | 01-02 | Painter + golden matrix (10 PNGs) | Complete |
| DDI-03 | 01-01 | bitmaskToLedStates unit tests | Complete |
| DDI-04 | 01-01 | kSTBChannelBitOrder LSB-first canary | Complete |
| DDI-05 | 01-01, 01-03 | Force-collapse tests in bit-mapping + dialog row groups | Complete |
| DDI-06 | 01-03 | 16 FilterEdit widgets group | Complete |
| DDI-07 | 01-03 | FilterEdit widgets + force-write integration | Complete |
| DDI-08 | 01-02, 01-03 | Data-shape + editor surface (5 KeyFields + Name or ID) | Complete |
| DDI-09 | 01-03 | 8 RowIOView widgets group | Complete |
| DDI-10 | 01-04 | Mount/unmount + dialog 10× leak tests | Complete |
| QUAL-01 | 01-02, 01-04 | Golden matrix (macOS-gated) | Complete |
| QUAL-02 | 01-01, 01-02, 01-04 | bodyColor imported, never hardcoded in advantys_stb.dart | Complete |
| QUAL-03 | 01-02, 01-04 | Stream hoisted to initState + dispose grep guard | Complete |
| QUAL-04 | 01-02, 01-04 | Legacy-JSON + forward-compat tests | Complete |
| QUAL-05 | 01-02, 01-04 | GestureDetector(HitTestBehavior.opaque) wraps body | Complete |
| QUAL-06 | (Phase 5) | — | Inherited by Phase 5 with a clean Phase 1 footprint |
| QUAL-07 | (Phase 5) | — | Owned by milestone-wide phase |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Registry-resolution test passed a raw `toJson()` Map to `AssetRegistry.parse`**

- **Found during:** Task 1
- **Issue:** Initial test directly passed `cfg.toJson()` as a Map into `AssetRegistry.parse`. The codegen `toJson()` leaves nested `Coordinates` / `RelativeSize` as Dart objects (not Maps); `_$STBDDI3725ConfigFromJson` later does `json['coordinates'] as Map<String, dynamic>` which throws `type 'Coordinates' is not a subtype of type 'Map<String, dynamic>' in type cast`.
- **Fix:** Route the test JSON through `jsonEncode/jsonDecode` to mirror the production save flow (see existing in-file round-trip pattern at line 132).
- **Files modified:** test/page_creator/assets/advantys_stb_test.dart
- **Commit:** bce8900

**2. [Rule 2 — Critical functionality] `_STBDDI3725State.dispose()` was missing**

- **Found during:** Task 3
- **Issue:** The widget held `_combinedStreamCache` (a `CombineLatestStream` whose closure captures `StateMan`) but had no `dispose()` override. The runtime leak test (mount + unmount) passed without it because `StreamBuilder` owns + cancels the actual `StreamSubscription`. The grep guard (mirroring the elevator/sensor QUAL-07 precedent) failed: the source contract for "dispose is reachable to release closure refs" was absent.
- **Fix:** Added `dispose()` to `_STBDDI3725State` that nulls `_combinedStreamCache` and `_stateMan` then calls `super.dispose()`. Documented as defensive/belt-and-suspenders (StreamBuilder is still the primary subscription owner).
- **Files modified:** lib/page_creator/assets/advantys_stb.dart
- **Commit:** a9e6521

**3. [Rule 1 — Test correctness] Initial "minimal legacy snippet" test omitted `coordinates`+`size` and crashed in `_$STBDDI3725ConfigFromJson`**

- **Found during:** Task 2
- **Issue:** Initial test included only `{ asset_name: 'STBDDI3725Config' }`. The codegen `_$STBDDI3725ConfigFromJson` unconditionally casts `json['coordinates'] as Map<String, dynamic>` (no null-tolerance — same shape in every peer `*.g.dart` including `beckhoff.g.dart`). The cast threw `Null is not a subtype of Map<String, dynamic>`.
- **Fix:** Re-scoped "v1.0 legacy snippet" to the actual v1.0 BaseAsset baseline (asset_name + coordinates + size, both always present in every saved page since BaseAsset shipped). "v2.0 fields" in this context are the Phase 1 additions: `nameOrId` and the five `*Key` fields, all of which DO rehydrate to defaults under this contract. This matches what the plan's `<must_haves>` actually require (line 21: "nameOrId='1', all *Key fields null"). Added a third forward-compat test that explicitly verifies unknown future fields are silently ignored.
- **Files modified:** test/page_creator/assets/advantys_stb_test.dart
- **Commit:** 6ffdf4d

No checkpoint reached. No architectural changes (Rule 4) needed.

## Carry-forward TODOs for Phase 2 (STBDDO3705)

1. **Import bit-order convention, NOT re-derive it:** `import '../../painter/advantys_stb/io16.dart' show kSTBChannelBitOrder, IO16LedBlockPainter, bitmaskToLedStates, bodyColor;` — these are the Phase 1 locks.
2. **Reuse the dual-map registration pattern:** Add `STBDDO3705Config` to BOTH `_fromJsonFactories` and `defaultFactories` in `registry.dart` (PITFALL §9.2).
3. **Reuse the dispose pattern:** Mirror `_STBDDI3725State.dispose()` defensively in `_STBDDO3705State`.
4. **Reuse the JSON back-compat test shape:** Phase 2 should ship the same `full JSON round-trip` + `JSON back-compat` groups in `advantys_stb_test.dart` for `STBDDO3705Config`.
5. **Backend bit-order question status:** Plan 02 Task 4 flagged the question "is Schneider Advantys STB bit-order MSB-first or LSB-first?" The CONTEXT.md locked decision was LSB-first by default (matching Beckhoff EL1008 convention). Plan 01 captured this in the `kSTBChannelBitOrder` constant with a canary test (`bit-order constant default is LSB-first (locked canary)` at advantys_stb_test.dart:26-28). If backend confirms MSB-first, flip the constant and the canary test together — painter math is unchanged. **Status as of this plan: LSB-first remains the locked default; no backend confirmation has been received that would require flipping. Carrying forward as a recurring smoke-test invariant.**

## Phase 1 closure

All four plans in Phase 1 are now shipped:

- **01-01** kSTBChannelBitOrder + bitmaskToLedStates (bit-mapping foundation)
- **01-02** STBDDI3725Config + STBDDI3725Widget + 10 goldens (data shape + visuals)
- **01-03** Detail dialog (8×2 RowIOView grid, force + filter write paths)
- **01-04** AssetRegistry registration + JSON back-compat + leak test + verification sweep (this plan)

Phase 1 is shippable. Phase 2 (STBDDO3705) is unblocked.

## Files Modified

| File | Change |
|------|--------|
| lib/page_creator/assets/registry.dart | +3 lines (1 import + 2 factory map entries) |
| lib/page_creator/assets/advantys_stb.dart | +14 lines (dispose override on `_STBDDI3725State`) |
| test/page_creator/assets/advantys_stb_test.dart | +210 lines net (registry resolution group, full JSON round-trip, back-compat group, lifecycle + leak groups, dispose grep guard); imports updated for `Coordinates`/`RelativeSize`/`TextPos`/`AssetRegistry`/`File` |

## Commits

- `bce8900` feat(01-04): register STBDDI3725Config in AssetRegistry (both maps) (DDI-01)
- `6ffdf4d` feat(01-04): DDI3725 JSON round-trip + legacy-JSON back-compat (DDI-10, QUAL-04)
- `a9e6521` feat(01-04): DDI3725 mount/unmount + dialog cycle leak tests (DDI-10, QUAL-03)

## Self-Check: PASSED

- File present: `lib/page_creator/assets/registry.dart` — STBDDI3725Config appears 2× (verified)
- File present: `lib/page_creator/assets/advantys_stb.dart` — dispose() override present (verified)
- File present: `test/page_creator/assets/advantys_stb_test.dart` — new test groups present (verified)
- Commits present in `git log --oneline`: bce8900, 6ffdf4d, a9e6521 (verified)
- `flutter test test/page_creator/assets/advantys_stb_test.dart` — 51 passed / 0 failed (verified)
- `flutter analyze` Phase 1 footprint — 0 issues (verified)
