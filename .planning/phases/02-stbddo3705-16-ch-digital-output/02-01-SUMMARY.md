---
phase: 02
plan: 01
subsystem: page_creator/advantys_stb
tags: [stb, digital-output, ddo3705, force-write, painter, registry, goldens]
type: combined-plan-execute
requires:
  - Phase 1 (STBDDI3725 — io16.dart, ddi3725.dart, kSTBChannelBitOrder, bitmaskToLedStates, IO16LedBlockPainter, bodyColor, stbAccentBlue, RowIOView, FilterEdit, _combinedStream, _forceArrayFromDynamicValue)
provides:
  - STBDDO3705Config (page_creator asset, JSON round-trippable)
  - STBDDO3705BodyPainter + STBDDO3705Widget (lib/painter/advantys_stb/ddo3705.dart)
  - Force-write end-to-end path via SegmentedButton → StateMan.write(forceValuesKey, int8[16])
  - 10 macOS goldens at test/page_creator/assets/goldens/advantys_stb/ddo3705_*
affects:
  - lib/page_creator/assets/advantys_stb.dart (appended; DDI untouched)
  - lib/page_creator/assets/advantys_stb.g.dart (regen)
  - lib/page_creator/assets/registry.dart (both factory maps)
  - test/page_creator/assets/advantys_stb_test.dart (16 new test groups, 26 new test cases)
tech-stack:
  added: []
  patterns:
    - Clone-and-trim DDI3725 (5 keys → 3 keys, no filter rows)
    - Inherit kSTBChannelBitOrder via import (no redeclaration; cross-DI/DO parity canary)
    - Cream-body bodyColor + Schneider stbAccentBlue reused via show imports
    - Force-write via in-place DynamicValue mutation + StateMan.write (matches EL2008)
    - Detail-dialog StreamBuilder owns subscription; dispose hygiene in _STBDDO3705State
    - Goldens: macOS-gated via Platform.isMacOS, RepaintBoundary + AlwaysStoppedAnimation(0)
key-files:
  created:
    - lib/painter/advantys_stb/ddo3705.dart
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_all_off_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_all_off_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_all_on_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_all_on_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_alternating_0xAAAA_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_alternating_0xAAAA_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_forced_mix_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_forced_mix_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_disconnected_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddo3705_disconnected_dark.png
  modified:
    - lib/page_creator/assets/advantys_stb.dart
    - lib/page_creator/assets/advantys_stb.g.dart
    - lib/page_creator/assets/registry.dart
    - test/page_creator/assets/advantys_stb_test.dart
decisions:
  - Output legend differentiator: small "▸" (U+25B8) glyph rendered in white immediately left of "DDO3705" in the top blue strip. Operator-recognizable as the output module without reading the printed text. Same TextPainter style as the module name; size = strip.height * 0.55.
  - Detail dialog hardcodes leftFilterEdit / rightFilterEdit to `null` (DDO-06) — outputs have no filter inputs.
  - Force-write path: SegmentedButton onChange mutates the force DynamicValue in-place, then writes the whole int8[16] back via stateMan.write(forceValuesKey, ...). Pattern verbatim from BeckhoffEL2008._statusDialog (beckhoff.dart:880-888).
  - DDO consumes kSTBChannelBitOrder from io16.dart via import (does NOT re-declare). Bit-order parity canary test guards against drift between DI and DO conventions.
  - Painter file lib/painter/advantys_stb/ddo3705.dart is a structural clone of ddi3725.dart — same layout fractions (top 0.07, LEDs 0.22, accent 0.025, terminals remainder), same disconnected exclamation overlay, same terminal-block geometry. Only label text + "▸" glyph differ. This keeps operator muscle memory across DI/DO modules and matches the photo-confirmed shared physical form factor.
metrics:
  duration_minutes: 9
  completed_date: 2026-05-11
  commits: 3
  tests_added: 26
  tests_passing: 91 / 91
  goldens_added: 10
  files_created: 11
  files_modified: 4
---

# Phase 2 Plan 01: STBDDO3705 (16-Ch Digital Output) — Combined Summary

## One-liner

`STBDDO3705Config` HMI asset: 16-channel digital-output module cloned from STBDDI3725 minus filter rows, plus genuine end-to-end manual force-write path (SegmentedButton → StateMan.write of int8[16]).

## Scope

Combined plan + execute pass for Phase 2. Ships every DDO requirement (DDO-01 through DDO-09) in three atomic TDD commits on `worktree-agent-aabefd25`:

| Commit | Hash | Purpose |
|--------|------|---------|
| RED    | `ad018a1` | 16 test groups appended to `advantys_stb_test.dart`; all reference symbols that don't exist yet → compile-time failure |
| GREEN  | `80d7d62` | `STBDDO3705Config`, `_STBDDO3705` widget, `STBDDO3705BodyPainter`, `STBDDO3705Widget`, registry entries, codegen regen |
| Goldens | `4c41e51` | 10 macOS PNGs generated via `--update-goldens`, deterministic on re-run, byte-distinct from DDI |

## Requirements Coverage

| Req | Description | Evidence |
|-----|-------------|----------|
| DDO-01 | `STBDDO3705Config` extends `BaseAsset` + registered in both factory maps | `lib/page_creator/assets/advantys_stb.dart`, `lib/page_creator/assets/registry.dart`; `STBDDO3705Config registry resolution` test group (3 cases) |
| DDO-02 | Painter reuses `IO16LedBlockPainter`; module body at `lib/painter/advantys_stb/ddo3705.dart` with output-style legend | `_drawOutputArrowGlyph` renders "▸" left of "DDO3705" in the top blue strip; `STBDDO3705BodyPainter shouldRepaint contract` group (6 cases) |
| DDO-03 | Bitmask state from `rawStateKey`; bit-ordering matches the constant locked in DDI-04 | DDO imports `kSTBChannelBitOrder` from `io16.dart` via `show`; `STBDDO3705 bit-order parity (cross DI/DO canary)` group |
| DDO-04 | Per-channel force-override via `forceValuesKey` | `_showDDO3705DetailDialog` `leftOnChanged` / `rightOnChanged` write int8[16] via StateMan; `STBDDO3705 detail dialog — force write integration (DDO-09)` group (3 cases) |
| DDO-05 | Per-channel descriptions via `descriptionsKey` | `RowIOView.leftDescription` / `.rightDescription` wired from `map['descriptions']`; `row 0 / row 7` description-pairing tests |
| DDO-06 | Tap-to-open detail dialog; NO filter rows (outputs have no filters) | `leftFilterEdit / rightFilterEdit` hardcoded to `null` in dialog; `renders ZERO FilterEdit widgets` test |
| DDO-07 | JSON round-trip + back-compat + leak coverage | `STBDDO3705Config full JSON round-trip + back-compat` group (3 cases); dispose hygiene mirrors `_STBDDI3725State` (covered by parent leak guards) |
| DDO-08 | Visual differentiates output from input; goldens confirm distinction | 10 PNGs at `test/page_creator/assets/goldens/advantys_stb/ddo3705_*`; bytewise differ from DDI counterparts at every (state, theme) |
| DDO-09 | Manual force-write path verified end-to-end | `tapping a Low SegmentedButton writes [0]==1`, `tapping a High writes [0]==2`, and `force-write round-trips: write [5]=2 → ch6 forced high` tests assert StateMan.write was called with the correct int8[16] payload |

## Deviations from Plan

### Rule 1 (Bug) — Test setup correction during GREEN

**Found during:** GREEN test pass on the `force-write round-trips: write [5]=2` test.

**Issue:** The test originally tapped `highFinders.at(5)` to force channel 6 high, but in widget-tree traversal order each RowIOView emits its `left` RowControl before its `right` RowControl. The sequence is therefore `ch1, ch9, ch2, ch10, ch3, ch11, ch4, ch12, ch5, ch13, ch6, ...` — so channel 6 is at index 10, not 5.

**Fix:** Updated the test to tap `highFinders.at(10)` and documented the indexing convention inline. This is a test-correctness fix (no production code changed); the underlying force-write path was already correct.

**Files modified:** `test/page_creator/assets/advantys_stb_test.dart`

**Commit:** `80d7d62` (rolled into GREEN since the test was new — RED's failure mode was "compile error", so this index-bug surfaced only after the implementation made the test compile).

## Authentication Gates

None — no auth required for this work.

## Architecture & Pattern Fidelity

The DDO3705 implementation follows every Phase 1 convention:

- **File layout**: New painter at `lib/painter/advantys_stb/ddo3705.dart`; config appended to the single-file `advantys_stb.dart` (no new top-level Dart file). Tests appended to `advantys_stb_test.dart` (single file, no new test file).
- **Imports**: `kSTBChannelBitOrder`, `IO16LedBlockPainter`, `bitmaskToLedStates`, `bodyColor` from `io16.dart`; `stbAccentBlue` from `ddi3725.dart`. No redeclaration.
- **`_combinedStream`**: hoisted to `initState` per PITFALL M-03 / QUAL-03. Dispose nulls cache + `_stateMan` to release closure-captured refs.
- **Gesture detection**: `GestureDetector(behavior: HitTestBehavior.opaque)` wrapping the painter (QUAL-05).
- **Dialog ownership**: dialog StreamBuilder owns its own subscription; closes when dialog pops (Plan 1's `mount/unmount` + `dialog open/close 10×` leak tests cover the parent-side discipline that DDO inherits).
- **Codegen**: `@JsonSerializable()` + `factory STBDDO3705Config.fromJson` + `Map<String, dynamic> toJson()`; `@JsonKey(defaultValue: '1')` on `nameOrId` for QUAL-04 back-compat.

## Test Results

- **91 / 91** tests pass in `test/page_creator/assets/advantys_stb_test.dart` (Phase 1 + Phase 2 combined: 65 inherited + 26 new).
- **Goldens** verified bytewise distinct from DDI counterparts at every (state, theme) pair — DDO PNGs are consistently ~108 bytes larger than DDI counterparts (the "▸ " glyph + text-layout shift). Manual visual inspection of `ddo3705_all_on_light.png`, `ddo3705_disconnected_light.png`, `ddo3705_forced_mix_light.png` confirms expected rendering.
- **`flutter analyze`** clean on every file touched by this plan (`ddo3705.dart`, `advantys_stb.dart`, `registry.dart`, `advantys_stb_test.dart`).

## Known Stubs

None. All data flows from real state keys; placeholder rendering exists only for the pre-emission "stale shell" state (matches DDI3725 and is intentional — covered by the `dialog body renders no rows` test).

## Threat Flags

None. No new network endpoints, no auth surfaces, no file access, no schema changes at trust boundaries.

## Self-Check: PASSED

- Files created:
  - `lib/painter/advantys_stb/ddo3705.dart` — FOUND
  - 10 PNGs at `test/page_creator/assets/goldens/advantys_stb/ddo3705_*` — FOUND
- Commits:
  - `ad018a1` (RED) — FOUND
  - `80d7d62` (GREEN) — FOUND
  - `4c41e51` (Goldens) — FOUND
- All 91 tests pass (verified via `flutter test test/page_creator/assets/advantys_stb_test.dart`).
- `flutter analyze` clean on all DDO3705 files.
- TDD gate sequence (RED → GREEN → Goldens) intact in `git log --oneline`.

## TDD Gate Compliance

- RED gate: `ad018a1` — `test(02-01): RED — STBDDO3705 data, painter, dialog, force-write, bit-order parity`. Tests fail at compile time (symbols undefined). Verified RED before GREEN.
- GREEN gate: `80d7d62` — `feat(02-01): STBDDO3705 16-Ch Digital Output (DDO-01..09, sans goldens)`. 81 / 81 non-golden tests pass; 10 goldens fail (expected, PNG-less).
- Goldens gate: `4c41e51` — `test(02-01): STBDDO3705 goldens — 5 states × 2 themes (DDO-08)`. All 91 tests pass deterministically.
