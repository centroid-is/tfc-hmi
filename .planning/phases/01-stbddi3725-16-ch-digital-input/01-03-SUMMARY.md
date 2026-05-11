---
phase: 01-stbddi3725-16-ch-digital-input
plan: 03
subsystem: ui
tags: [flutter, advantys-stb, ddi3725, detail-dialog, tdd, riverpod, statemann, beckhoff-parity]

# Dependency graph
requires:
  - phase: 01-02
    provides: STBDDI3725Config + _STBDDI3725 ConsumerStatefulWidget + onTap stub + _combinedStream helper + _forceArrayFromDynamicValue helper
  - external: lib/page_creator/assets/beckhoff.dart
    provides: RowIOView + FilterEdit + IOForceButton + TriangleBoxPainter (re-used widgets, no duplication)
provides:
  - _showDDI3725DetailDialog(context, config, stateMan, animation) - private top-level dialog factory
  - Wired onTap handler in _STBDDI3725State (replaces Plan 02 stub)
  - Detail dialog StreamBuilder subscribing to all five state keys (raw + force + on_filters + off_filters + descriptions)
  - Force-write path via stateMan.write(forceValuesKey, mutated_int8_16_array)
  - Filter-write paths via stateMan.write(onFiltersKey | offFiltersKey, mutated_uint16_array)
affects: [01-04, 02-stbddo3705]  # Plan 04 leak test will exercise this dialog; Phase 2 DDO3705 clones the dialog shape minus filter rows

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-vendor widget re-use: `import 'beckhoff.dart' show RowIOView, FilterEdit;` — no duplication of EL1008 dialog widgets (ARCHITECTURE §9.3)"
    - "Dialog stream scoped to StreamBuilder lifetime — pops the dialog tears down the listeners (Plan 04 leak test will lock this)"
    - "Channel pairing `(r+1, r+9)` per row via single 8-iteration loop — locks DDI-09 grid layout (8 rows × 2 cols)"
    - "Force-write contract mirrors EL1008: mutate the cached `force` DynamicValue array in-place via `map['force']![i].value = newValue`, then `stateMan.write(forceValuesKey, map['force']!)` — same shape as beckhoff.dart:1397-1405"
    - "Test viewport widened to 1400×900 via `tester.binding.setSurfaceSize` for row-structure tests — RowIOView (~900px wide) overflows the default 800×600 viewport"
    - "Fake StateMan implementations: `_FakeStateMan extends Fake implements StateMan` (no overrides — sufficient for null-key path); `_StreamingStubStateMan extends Fake implements StateMan` (subscribe + write overridden — used by structure + force tests)"

key-files:
  created:
    - .planning/phases/01-stbddi3725-16-ch-digital-input/01-03-SUMMARY.md
  modified:
    - lib/page_creator/assets/advantys_stb.dart  (+126 LoC: import RowIOView/FilterEdit, replaced onTap stub, added _showDDI3725DetailDialog ~125 LoC)
    - test/page_creator/assets/advantys_stb_test.dart  (+325 LoC: 8 new tests across 3 groups + 2 fake-StateMan classes)

key-decisions:
  - "Imported `RowIOView` + `FilterEdit` from `beckhoff.dart` rather than re-implementing them in `advantys_stb.dart`. ARCHITECTURE §9.3 advice was to keep `_combinedStream` duplicated (private helpers can drift) but `RowIOView`/`FilterEdit` are public widgets and re-using them preserves operator muscle memory (CLAUDE.md Pattern fidelity constraint). Cross-vendor widget re-use is the documented cross-cutting pattern."
  - "Force-write path lands in DDI3725 (this plan) even though CONTEXT.md §Force-key-write-path notes 'true operator-driven force writes land in Phase 2 DDO3705'. The decision: ship the write path here for parity with EL1008. The EL1008 dialog at beckhoff.dart:1397-1405 wires force writes unconditionally for DI modules, and operators expect symmetric behaviour. The write IS gated by `config.forceValuesKey != null` (handler short-circuits if null at runtime via the `!` operator) — when the key is unbound the SegmentedButton segment selections never fire writes."
  - "DynamicValue stubbing IS feasible: `DynamicValue(value: int)` for scalar ints, `DynamicValue.fromList([DynamicValue, ...])` for the int8[16] force array. The full integration test (assert `[0]==1` after Low tap) is in the suite — NOT the surface-count-only fallback the plan's <behavior> block allowed."
  - "Test viewport widened to 1400×900 via `setSurfaceSize` for row-structure + force-write groups. The default 800×600 test viewport overflows: a single RowIOView is ~900px wide (left/right RowControl 250px each + 3 boxes × 120px + spacing). Rather than refactor RowIOView to shrink, expand the viewport (matches real-app behaviour — the dialog is meant for desktop HMI screens that are >1280px wide)."

patterns-established:
  - "Detail-dialog convention for STB DI modules: AlertDialog(title=nameOrId, content=SingleChildScrollView(StreamBuilder)), 8×2 RowIOView grid, Close TextButton action. Phase 2 DDO3705 clones this shape minus the FilterEdit rows (outputs don't have on/off filter ms)."
  - "Cross-vendor widget import via `show` keyword: `import 'beckhoff.dart' show RowIOView, FilterEdit;`. Phase 2 DDO3705 will follow the same pattern, importing only what it needs."

requirements-completed: [DDI-05, DDI-06, DDI-07, DDI-09]

# Metrics
duration: 16min
completed: 2026-05-11
---

# Phase 1 Plan 03: STBDDI3725 Detail Dialog — Summary

**Ship the per-channel detail dialog for STBDDI3725: AlertDialog opens on body tap, contains 8 rows × 2 columns of `RowIOView` (channel pairs `(r+1, r+9)` per row), with force SegmentedButton + ON/OFF filter ms TextFormFields + description per channel. Force/filter writes round-trip through `stateMan.write(...)` to the underlying state keys. Replaces Plan 02's onTap stub.**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-05-11 (immediately after Plan 02 merge `9261736`)
- **Completed:** 2026-05-11
- **Tasks:** 2 (Task 1 RED+GREEN scaffold, Task 2 RED+GREEN row-structure+force-write — landed in a single TDD cycle per the plan's two-task-each-RED-GREEN structure)
- **Files changed:** 2 (`advantys_stb.dart` + `advantys_stb_test.dart`)

## Accomplishments

- **Replaced Plan 02 onTap stub** with `_showDDI3725DetailDialog`. The stub at `_STBDDI3725State._buildShell` (commit `f9f830c`) is gone — `grep -n 'Detail dialog — implemented in Plan 03'` returns nothing. New onTap path:
  ```dart
  onTap: () {
    if (_stateMan == null) return;
    _showDDI3725DetailDialog(context, widget.config, _stateMan!,
        const AlwaysStoppedAnimation<int>(0));
  }
  ```
- **Shipped `_showDDI3725DetailDialog` as a private top-level function** in `advantys_stb.dart` (~125 LoC). AlertDialog titled `config.nameOrId`, `SingleChildScrollView` body wrapping a `Column` of 8 `RowIOView` widgets, `TextButton('Close')` action. The StreamBuilder subscribes to all five state keys (raw + force + on_filters + off_filters + descriptions) via the existing `_combinedStream` helper from Plan 02.
- **Locked the channel-pairing math** via `for (int r = 0; r < 8; r++)`. Row `r` left = channel `r+1`, right = channel `r+9`. Tests verify ch1+ch9 on row 0 and ch8+ch16 on row 7 (last-row).
- **Wired the force-write path** end-to-end: tapping a "Low " or "High" SegmentedButton segment mutates `map['force']![r].value = newValue` and calls `stateMan.write(config.forceValuesKey!, map['force']!)`. The integration test taps the first Low segment and asserts the write log: `lastWrite.key == 'force'`, `lastWrite.value[0].asInt == 1`, `[i].asInt == 0 for i in 1..15`.
- **Wired the filter-write paths** identically for `onFiltersKey` / `offFiltersKey`. FilterEdit widgets are only mounted when both keys are present in the data map (mirrors EL1008's conditional pattern at `beckhoff.dart:1409-1442`).
- **Re-used `RowIOView` + `FilterEdit` from `beckhoff.dart`** via `import 'beckhoff.dart' show RowIOView, FilterEdit;` — no duplication. Preserves operator muscle memory across Beckhoff and Schneider Advantys STB modules (CLAUDE.md Pattern fidelity constraint).
- **8 new tests pass** across 3 test groups, all 33 prior tests still pass (41 total). `flutter analyze lib/page_creator/assets/advantys_stb.dart test/page_creator/assets/advantys_stb_test.dart` returns "No issues found".

## Task Commits

Both tasks were committed atomically on `worktree-agent-aa3957a4`:

1. **Task 1 RED — failing trigger + row-structure + force-write tests** — `cd397c5` (`test`)
2. **Task 1+2 GREEN — `_showDDI3725DetailDialog` + onTap rewire + test viewport widening** — `d390c24` (`feat`)

TDD discipline: RED commit had 7 failing tests against Plan 02's stub. GREEN commit landed the dialog + replaced the stub + widened the test viewport — all 8 detail-dialog tests pass, plus the 33 from Plan 01/02 still green.

The plan's nominal two-task split (Task 1 = trigger only, Task 2 = row-structure + force-write) was condensed into one GREEN commit because the implementation surface is identical — adding the dialog body that satisfies Task 1's trigger also satisfies Task 2's row-structure assertions. Splitting into separate GREEN commits would mean shipping a half-implemented dialog (no rows). The test-side split is preserved: 3 separate test groups commit-by-commit. RED gate validated all 7 failures up-front.

## Files Created / Modified

### Created
- `.planning/phases/01-stbddi3725-16-ch-digital-input/01-03-SUMMARY.md` — this file.

### Modified
- `lib/page_creator/assets/advantys_stb.dart` — `import 'beckhoff.dart' show RowIOView, FilterEdit;` added (line 40). Plan 02 stub onTap (`Text('Detail dialog — implemented in Plan 03.')`) replaced with the real call (`_showDDI3725DetailDialog(...)`). New `_showDDI3725DetailDialog` top-level function (~125 LoC) added at the bottom after `_forceArrayFromDynamicValue`. File grew from ~370 to 496 LoC (+126).
- `test/page_creator/assets/advantys_stb_test.dart` — Three new test groups added (`detail dialog — trigger`, `detail dialog — row structure`, `detail dialog — force write integration`) totalling 8 tests. Two new fake-StateMan classes appended: `_FakeStateMan extends Fake implements StateMan` (no overrides — null-key trigger path) and `_StreamingStubStateMan extends Fake implements StateMan` (subscribe + write overridden — data-flow tests). New imports: `dart:async`, `package:open62541/open62541.dart` (`DynamicValue`), `package:tfc/page_creator/assets/beckhoff.dart` (`RowIOView`, `FilterEdit`), `package:tfc/providers/state_man.dart` (`stateManProvider`), `package:tfc_dart/core/state_man.dart` (`StateMan`). File grew from ~511 to 836 LoC (+325).

## Decisions Made

- **Force-write path lives in DDI (not deferred to DDO).** CONTEXT.md §Force-key-write-path noted that "true operator-driven force writes land in Phase 2 DDO3705". I shipped the write path here anyway because (a) EL1008's DI dialog at `beckhoff.dart:1397-1405` already wires force writes unconditionally — operators expect symmetric behaviour across DI/DO modules — and (b) the write is gated at runtime by `config.forceValuesKey != null` (the `!` operator forces a runtime null check). DDI3725 force writes ARE rare in practice (PLCs drive force state via SCADA), but the UI surface exists for commissioning workflows.
- **DynamicValue stubbing is feasible — full integration coverage chosen, not the surface-count fallback.** The plan's `<behavior>` block allowed falling back to `find.byType(SegmentedButton) findsNWidgets(16)` if `DynamicValue` construction in tests proved awkward. Reading `open62541_dart/lib/src/dynamic_value.dart:48-109` showed `DynamicValue(value: int)` constructs a scalar and `DynamicValue.fromList([...])` constructs an array. Constructed canned values for all five keys (raw=0xAAAA scalar, force=int8[16] array, onFilters/offFilters=uint16[16] arrays, descriptions=string[16] array). The force-write integration test asserts `[0].asInt == 1` after the first Low-segment tap — full content coverage, no fallback.
- **Imported RowIOView + FilterEdit from beckhoff.dart rather than duplicating them.** The plan's `<interfaces>` block explicitly advised this path: "do NOT duplicate `RowIOView` / `FilterEdit` — they are public widgets in `beckhoff.dart` and re-using them is the correct cross-vendor pattern". This contrasts with the private `_combinedStream` helper which Plan 02 deliberately duplicated (per ARCHITECTURE §9.3 — private helpers can drift; public widgets cannot).
- **Test viewport widened to 1400×900.** The default flutter_test surface is 800×600. A single RowIOView is ~900px wide (250 + 16 + 360 + 16 + 250 + AlertDialog padding ≈ 900px). With 800×600 the dialog body overflows by ~220px and the tree throws "RenderFlex overflowed". The fix: `tester.binding.setSurfaceSize(Size(1400, 900))` inside `openWithStub`, with `addTearDown(() => tester.binding.setSurfaceSize(null))` to reset. The trigger-only group keeps the default viewport (no rows render in the null-key path, so no overflow).
- **Single GREEN commit covering Task 1 + Task 2.** The plan splits work into two TDD cycles. I unified the GREEN commits because shipping a half-dialog (Task 1 GREEN with empty body) would not actually be a working dialog — the assertions in Task 2 are about the dialog body, which Task 1 must already have to satisfy its own trigger assertion (`find.byType(AlertDialog) findsOneWidget`). The RED commit covers both task groups together; the GREEN commit ships the whole `_showDDI3725DetailDialog` body in one shot.

## Deviations from Plan

### Auto-fixed Issues

None.

### Procedural / Test-Harness Adjustments

**1. [Procedural — viewport widening] `setSurfaceSize(1400, 900)` for row-structure + force-write groups.**

- **Why:** The default 800×600 test viewport is too narrow to render a single `RowIOView` without RenderFlex overflow exceptions, which `flutter_test` treats as test failures.
- **What:** Added `await tester.binding.setSurfaceSize(const Size(1400, 900))` at the top of `openWithStub` in both the row-structure and force-write groups. `addTearDown(() => tester.binding.setSurfaceSize(null))` resets the viewport between tests so neighbouring groups stay isolated.
- **Why not in the plan:** The plan's `<behavior>` block didn't predict the viewport issue. This is a pure test-harness adjustment — no production code change.
- **Impact:** Tests reflect real-app behaviour (the dialog is meant for desktop HMI screens > 1280px wide). No production code change.

### Worktree branch base reset (procedural, not a code change)

The worktree (`worktree-agent-aa3957a4`) was initially branched from `4bbede3` (UMAS hardening merge on `main`), which predates Plan 01 and Plan 02's merges on `elevator`. The executor prompt's `<worktree_branch_check>` step ("Verify base: `git merge-base HEAD 926173646c4edc8c4a5f89f8601bec9e1fb558a6`. Reset if needed.") triggered `git reset --hard 926173646c4edc8c4a5f89f8601bec9e1fb558a6` before any Plan 03 work was committed. The reset brought Plan 01 + Plan 02's commits into the worktree branch as the new base. Both Plan 03 commits (`cd397c5` RED + `d390c24` GREEN) sit on top.

## Issues Encountered

None beyond the test viewport adjustment documented above.

## Threat Flags

No new security-relevant surface introduced. The detail dialog ONLY writes to keys that the user-configured `*Key` fields point at — the write path is gated by `config.forceValuesKey != null` / `config.onFiltersKey != null` / `config.offFiltersKey != null` (the `!` operator triggers a runtime null check inside the handler). No new network endpoints, auth paths, file access, or schema changes.

## Carry-Forward TODOs

- **Plan 04: leak test.** Open and close the dialog 10× — `stateMan` listener counts must return to baseline. The dialog stream is scoped to the StreamBuilder inside `_showDDI3725DetailDialog`; when the dialog pops via `Navigator.of(dialogContext).pop()`, the StreamBuilder is disposed and the underlying `_combinedStream` listener(s) cancel. This SHOULD work cleanly because (a) `_combinedStream` is a `CombineLatestStream` (no internal caching), (b) the inner subscriptions come from `StateMan.subscribe(key).asStream().asyncExpand((s) => s)` which is fully cancellable. Plan 04 will confirm.
- **Plan 04: registry registration + back-compat test + AssetRegistry round-trip test.** Register `STBDDI3725Config.fromJson` and `STBDDI3725Config.preview` in `lib/page_creator/assets/registry.dart` (`_fromJsonFactories` + `defaultFactories` maps).
- **Force-write path documentation update.** CONTEXT.md §Force-key-write-path stated force writes "land in Phase 2 DDO3705". This plan shipped them in Phase 1 for EL1008 parity. Update CONTEXT.md when revising for the next iteration (low priority — the plan correctly reflects the operator-recognizability target).
- **Phase 2 DDO3705 detail dialog clone.** The Plan 03 dialog shape is the template: AlertDialog(title=nameOrId, content=SingleChildScrollView(StreamBuilder)), 8×2 RowIOView grid, Close action. DDO3705 will: remove the FilterEdit rows (outputs don't have on/off filter ms), keep the RowIOView with force SegmentedButton + description, and add a "Direct write" mode where tapping the channel state directly toggles the output (no SegmentedButton). The cross-vendor widget re-use pattern (`import 'beckhoff.dart' show RowIOView;`) is established.

## TDD Gate Compliance

- **RED gate:** Commit `cd397c5` (`test(01-03): RED — DDI3725 detail dialog (trigger + row structure + force write)`) — 7 of 8 new tests failed against Plan 02's onTap stub. The 1 accidentally-passing test (`with all-null keys, dialog body renders no rows`) passed because Plan 02's stub dialog (`AlertDialog(content: Text('Detail dialog — implemented in Plan 03.'))`) also has no `RowIOView` widgets. RED gate intent — drive the implementation — held: 7 of 8 are red.
- **GREEN gate:** Commit `d390c24` (`feat(01-03): DDI3725 detail dialog — 8×2 RowIOView grid + force/filter writes`) — all 8 new tests pass, plus all 33 prior tests, plus `flutter analyze` clean.
- **REFACTOR gate:** Not exercised — the GREEN implementation is direct port-pattern from EL1008's `_statusDialog`, no clean-up pass required.

## Self-Check: PASSED

- `_showDDI3725DetailDialog` defined in `lib/page_creator/assets/advantys_stb.dart` — FOUND (line 382, called from line 217).
- `import 'beckhoff.dart' show RowIOView, FilterEdit;` in `lib/page_creator/assets/advantys_stb.dart` — FOUND (line 40).
- `for (int r = 0; r < 8; r++)` in `lib/page_creator/assets/advantys_stb.dart` — FOUND (line 418) — locks DDI-09 8-row grid.
- `r + 8` occurrences in `lib/page_creator/assets/advantys_stb.dart` — 8 (>= 4 required) — locks channel pairing in raw/force/descriptions/filter slots on left+right.
- Plan 02's onTap stub text (`Detail dialog — implemented in Plan 03`) — GONE.
- Commit `cd397c5` (RED) — FOUND in git log.
- Commit `d390c24` (GREEN) — FOUND in git log.
- `flutter test test/page_creator/assets/advantys_stb_test.dart` — 41/41 pass.
- `flutter analyze lib/page_creator/assets/advantys_stb.dart test/page_creator/assets/advantys_stb_test.dart` — zero issues.

---
*Phase: 01-stbddi3725-16-ch-digital-input*
*Completed: 2026-05-11*
