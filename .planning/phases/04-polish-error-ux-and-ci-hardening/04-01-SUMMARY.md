---
phase: 04-polish-error-ux-and-ci-hardening
plan: 01
subsystem: ui
tags: [flutter, dart, custompainter, valuenotifier, streamsubscription, isa-101, error-ux, leak-tracker, regression-test, tdd, golden-test, page-creator, elevator]

# Dependency graph
requires:
  - phase: 02-elevator-foundation
    provides: "ElevatorPainter (Plan 02-03) — accepts isStale + activeColor + ValueListenable<double> progress; _ElevatorState (Plan 02-04) — owns _progress / _animProgress / _hoistedKey / _streamSub with dispose contract; @visibleForTesting debugProgress + debugPositionStream seams"
  - phase: 03-elevator-child-embedding
    provides: "Stack composition with Positioned children (Plan 03-01); ElevatorChildEntry polymorphic dispatch via entry.child.build(context); Plan 03-03 editor add/edit/remove UI surface (children leak alongside Elevator in QUAL-07 mount/unmount)"
  - phase: 01-sensor-asset
    provides: "SensorConfig + Sensor widget (used as Elevator child in QUAL-07 leak test); sensor.dart dispose precedent (StreamSubscription.cancel + ValueNotifier.dispose)"
provides:
  - "ELEV-15 — out-of-range outline: ElevatorPainter renders a 2px amber outline (Color(0xFFFFA500)) hugging the bbox when isOutOfRange=true. Widget pipeline detects raw values < 0 / > 100 / NaN in _onStreamData and flips _isOutOfRange. Stale and out-of-range are mutually exclusive in the painter."
  - "QUAL-06 — multi-elevator independence: regression-locked by a widget test that pumps two Elevator widgets with distinct positionKeys, drives them to 0.25 / 0.75 independently, and asserts both progress values land on the correct painter AND that stream identities differ."
  - "QUAL-07 — leak / dispose contract: mount/unmount widget test (Elevator + Sensor child) plus two source-level grep guards. The grep guards lock the literal `_streamSub?.cancel()` / `_progress.dispose()` / `_animProgress.dispose()` strings in elevator.dart and require a dispose() method with cancel/dispose calls in sensor.dart. Provides defence-in-depth even when the Flutter leak tracker is not actively enabled."
  - "QUAL-08 — TDD discipline: this plan is the closing TDD plan of the milestone. RED commit (8c8badc) precedes GREEN commit (262ec9c)."
  - "ELEV-15 painter golden — test/page_creator/assets/goldens/elevator/position_50_out_of_range.png (deterministic, captures the locked Color(0xFFFFA500) at progress=0.5)."
  - "Test seam: @visibleForTesting void debugInjectRaw(DynamicValue) — mirrors debugProgress / debugPositionStream pattern, drives synthetic stream emissions through _onStreamData without a full StateMan stub."
  - "Phase 4 closeout — milestone is functionally complete: 4 phases, 175 tests green 5/5 deterministic runs, all 4 plan-required requirements (ELEV-15, QUAL-06, QUAL-07, QUAL-08) closed."
affects:
  - "Future Elevator runtime work — _isOutOfRange flag is the seam any new fault-rendering features (e.g. drift-from-target alarm) hook into"
  - "Other PLC-driven assets — debugInjectRaw seam pattern (drive a single DynamicValue through the listener) generalises to sensor.dart and any future widget that subscribes via StateMan; saves writing a full mock StateMan"
  - "Future leak-tracker upgrade — when LeakTesting.enable() is wired into flutter_test_config.dart, the existing mount/unmount test gains automatic leak detection without source changes"

# Tech tracking
tech-stack:
  added: []  # No new packages — leak_tracker_flutter_testing was already transitively available via the Flutter SDK
  patterns:
    - "Out-of-range fault rendering: detect at the stream-listener boundary (raw < 0 / > 100 / NaN), set a single bool field, propagate to the painter as a constant-time outline draw (no per-progress allocations — T-04-01 mitigated)"
    - "Mutual-exclusivity contract for ISA-101 visual states: stale (grey) and out-of-range (amber) are computed by the widget and never raised simultaneously (`_isOutOfRange && !_isStaleEffective`). Centralises the rule so the painter doesn't need to encode precedence."
    - "Test seam pattern for stream-driven widgets: @visibleForTesting method that calls the production stream listener directly with a synthetic DynamicValue. Avoids a full StateMan mock for fault-injection tests."
    - "Multi-instance independence regression-locking: pump two instances under a Column with distinct keys, write each one's debugProgress, descend into Elevator subtrees with `find.descendant(of: find.byType(Elevator))`, and verify each painter's progress.value lands on the right instance. Plus identity-diff check on debugPositionStream."
    - "Defence-in-depth leak guards: runtime mount/unmount widget test for actually exercising the disposal path, AND source-level grep guards that lock the literal dispose() / cancel() / dispose() lines so the contract can't silently regress even if the leak tracker is offline."

key-files:
  created:
    - "test/page_creator/assets/goldens/elevator/position_50_out_of_range.png — 991-byte PNG capturing rails+deck at progress=0.5 with the amber outline overlay"
  modified:
    - "lib/page_creator/assets/elevator_painter.dart — added kOutOfRangeColor (0xFFFFA500) + kOutOfRangeStrokeWidth (2.0) constants, added required isOutOfRange field (default false), paint() draws the outline rect last when isOutOfRange=true, shouldRepaint includes isOutOfRange comparison"
    - "lib/page_creator/assets/elevator.dart — added _isOutOfRange field; _onStreamData detects out-of-range raw values (< 0, > 100, NaN) and sets _isOutOfRange via setState; _onStreamError clears _isOutOfRange (mutual-exclusion); _hoistStream clears _isOutOfRange on positionKey change; _buildStack passes (_isOutOfRange && !_isStaleEffective) to the painter; new @visibleForTesting void debugInjectRaw(DynamicValue) seam"
    - "test/page_creator/assets/elevator_widget_test.dart — added DynamicValue import; appended 3 new test groups: 'Out-of-range (ELEV-15)' (4 tests), 'Multi-elevator independence (QUAL-06)' (1 test), 'Leak test (QUAL-07)' (3 tests — 1 widget + 2 source-level grep guards)"
    - "test/page_creator/assets/elevator_painter_test.dart — added 1 shouldRepaint test for isOutOfRange + 1 golden test 'Out-of-range golden (ELEV-15) position_50_out_of_range.png'"

key-decisions:
  - "debugInjectRaw test seam (not a full StateMan mock) — operates at the same boundary as the existing debugProgress / debugPositionStream seams. Drops the test's wiring complexity from a Riverpod-overridden ProviderScope + StateMan stub to a single line: state.debugInjectRaw(DynamicValue(value: 150.0)). Matches the locked test-seam pattern from Plans 02-04 / 03-01."
  - "NaN treated as out-of-range (sets _isOutOfRange=true) rather than as stale — operator sees a fault rather than a silent grey-stale render. Mirrors the platformProgress NaN-as-0.0 defence in elevator_layout.dart but elevates the visual signal."
  - "Mutual-exclusivity computed at the widget layer: _buildStack passes (_isOutOfRange && !_isStaleEffective). Keeps the painter API simple (it just draws what it's told) and centralises the precedence rule (stale wins over out-of-range — operator sees grey when the stream is broken, not amber+grey)."
  - "Source-level grep guards alongside the runtime mount/unmount test: the runtime test catches actual leaks if/when LeakTesting.enable() is wired in, while the grep guards catch the regression of someone deleting `_streamSub?.cancel()` from the source. Both are cheap; both are valuable."
  - "Bundled QUAL-07 leak tests into the Task 1 RED commit (rather than a separate Task 3 RED) — they share the same test file and would all RED-fail together due to the shared compile error from the missing isOutOfRange parameter. Splitting them would create artificial commit boundaries with no semantic value (Rule 3 deviation, documented below)."

patterns-established:
  - "Pattern A — ISA-101 abnormal-state outline: detect at the stream boundary, propagate via a single bool to the painter, draw last as a constant-time stroke rect. Reusable for future amber/red fault overlays on any CustomPainter widget that subscribes to PLC values."
  - "Pattern B — debugInjectRaw test seam for stream-driven widgets: lets fault-injection tests run without a full mock StateMan. Recommended for any future HMI asset that wires StateMan.subscribe in initState."
  - "Pattern C — Mutual-exclusivity gate at the widget layer: when two visual states both want to render, compute precedence in the build method as a boolean expression (`_isOutOfRange && !_isStaleEffective`) rather than encoding it in the painter."

requirements-completed: [ELEV-15, QUAL-06, QUAL-07, QUAL-08]

# Metrics
duration: 6m 19s
completed: 2026-05-06
---

# Phase 4 Plan 01: Polish, Error UX & CI Hardening Summary

**Out-of-range amber outline (ELEV-15) on the elevator painter, multi-instance regression test (QUAL-06), and a defence-in-depth dispose contract (QUAL-07) — closing the milestone with three production-quality guards in a single TDD plan.**

## Performance

- **Duration:** 6m 19s
- **Started:** 2026-05-06T12:36:45Z
- **Completed:** 2026-05-06T12:43:04Z
- **Tasks:** 4 (all completed)
- **Files modified:** 4 (2 production, 2 tests)
- **Files created:** 1 golden PNG

## Accomplishments

- **ELEV-15** — When the position stream emits a value outside [0, 100] (or NaN), `_ElevatorState._onStreamData` now flags `_isOutOfRange=true` while still clamping `_progress` to [0, 1]. The `ElevatorPainter` overlays a 2px amber outline (`Color(0xFFFFA500)`) on the bbox. Stale (grey) and out-of-range (amber) are mutually exclusive — the operator never sees both at once.
- **QUAL-06** — Two Elevator widgets sharing a parent operate with fully independent `_progress` notifiers, `_hoistedKey` state, and `StreamSubscription`s. Locked by a widget test that drives them to distinct progress values and verifies each painter reflects its own instance's value. Stream identities also asserted distinct.
- **QUAL-07** — Mount/unmount widget test for Elevator + Sensor child confirms no exceptions during disposal. Two source-level grep guards lock the literal `_streamSub?.cancel()`, `_progress.dispose()`, `_animProgress.dispose()` lines in `elevator.dart`, and the presence of cancel/dispose in `sensor.dart`'s dispose method. Defence-in-depth — the runtime test catches actual leaks if/when LeakTesting is wired in; the grep guards catch source regressions immediately.
- **QUAL-08** — TDD discipline maintained: RED commit (`8c8badc`) precedes GREEN commit (`262ec9c`). All 6 new tests fail at compile time before implementation; all pass after implementation.
- **Phase 4 closeout** — 175 tests green across 7 test files (sensor + elevator surface), 5/5 deterministic runs, `flutter analyze` clean across the modified files.

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests for ELEV-15 + QUAL-06 + QUAL-07** — `8c8badc` (`test`)
   - 4 widget tests for out-of-range (150, -50, 50, mutual-exclusivity)
   - 1 widget test for multi-elevator independence
   - 1 widget test for mount/unmount + 2 source-level grep guards
   - 1 painter `shouldRepaint` test for `isOutOfRange`
   - 1 painter golden test for `position_50_out_of_range.png`
   - All compile-fail RED before implementation: `ElevatorPainter` lacks `isOutOfRange` parameter, `_ElevatorState` lacks `debugInjectRaw` seam.

2. **Task 2 (GREEN): isOutOfRange field + amber outline + multi-elevator verification** — `262ec9c` (`feat`)
   - `ElevatorPainter` gains `isOutOfRange` field, paints outline last, `shouldRepaint` includes the new field.
   - `_ElevatorState` gains `_isOutOfRange` flag, sets it in `_onStreamData`, clears it in `_onStreamError` and `_hoistStream` (mutual-exclusion contract).
   - `_buildStack` passes `(_isOutOfRange && !_isStaleEffective)` so stale always wins precedence.
   - New `@visibleForTesting void debugInjectRaw(DynamicValue)` test seam.
   - Golden `position_50_out_of_range.png` regenerated.
   - All 175 tests pass; `flutter analyze` clean on modified files.

3. **Task 3 (Leak test)** — _bundled into Task 1 RED commit `8c8badc`_ — see Deviations below.

4. **Task 4 (SUMMARY)** — _this commit_ (`docs`)

_TDD cadence: 1 test commit (RED) → 1 feat commit (GREEN). No refactor commit needed — implementation was clean on first pass._

## Files Created/Modified

**Created:**
- `test/page_creator/assets/goldens/elevator/position_50_out_of_range.png` — 991-byte PNG. Visually validates the amber outline (`Color(0xFFFFA500)`) overlaying rails+deck at progress=0.5. Captured deterministically via `RepaintBoundary` on macOS.

**Modified:**
- `lib/page_creator/assets/elevator_painter.dart` — Added `kOutOfRangeColor` and `kOutOfRangeStrokeWidth` constants. Added `final bool isOutOfRange` field with default `false`. `paint()` draws the outline rect last when `isOutOfRange=true`. `shouldRepaint` compares `isOutOfRange`.
- `lib/page_creator/assets/elevator.dart` — Added `bool _isOutOfRange = false` field. `_onStreamData` flags it (raw < 0 / > 100 / NaN). `_onStreamError` and `_hoistStream` clear it (mutual-exclusion). `_buildStack` passes `(_isOutOfRange && !_isStaleEffective)` to the painter. Added `@visibleForTesting void debugInjectRaw(DynamicValue)` seam.
- `test/page_creator/assets/elevator_widget_test.dart` — Added `DynamicValue` import. Three new test groups appended (Out-of-range, Multi-elevator independence, Leak test) — 8 new tests total.
- `test/page_creator/assets/elevator_painter_test.dart` — Added `shouldRepaint` test for `isOutOfRange`. Added new test group with 1 golden test for `position_50_out_of_range.png`.

## Decisions Made

- **`debugInjectRaw` test seam over a full StateMan mock** — Operates at the same boundary as existing `debugProgress` / `debugPositionStream` seams. Test wiring stays trivial: `state.debugInjectRaw(DynamicValue(value: 150.0))`. Matches the locked test-seam pattern from Plans 02-04 / 03-01.
- **NaN treated as out-of-range** — Operator sees a visible fault (amber outline) rather than a silent grey-stale render. Defensive complement to `platformProgress`'s NaN-as-0.0 clamp.
- **Mutual-exclusivity computed at the widget layer**, not the painter — Painter API stays simple. Precedence rule (stale wins over out-of-range) lives in one place. Closes the CONTEXT §decisions mutual-exclusivity contract.
- **Source-level grep guards alongside runtime mount/unmount test** — Defence-in-depth: runtime test catches actual leaks; grep guards catch source-regression of dispose calls. Both cheap, both valuable.
- **Constants `kOutOfRangeColor` and `kOutOfRangeStrokeWidth` extracted to top of file** — Locks the ISA-101 amber + 2px stroke at the source level. Future tweaks change the constant; the colour value never appears as a magic number elsewhere.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Bundled QUAL-07 leak tests into Task 1 RED commit instead of a separate Task 3 RED commit**

- **Found during:** Task 1 (RED — writing failing tests)
- **Issue:** The plan specifies a separate Task 3 commit for the leak test. But the leak tests, the ELEV-15 tests, and the QUAL-06 test all live in the same test file (`elevator_widget_test.dart`). Because the file would not compile without `isOutOfRange`, every test in the file failed at compile time — including the leak tests. Committing leak tests separately as a "RED" commit would be misleading: they don't fail because they're testing missing functionality, they fail because of an unrelated compile error in a sibling test group.
- **Fix:** Bundled all RED tests (ELEV-15, QUAL-06, QUAL-07) into the single Task 1 commit (`8c8badc`). The Task 2 GREEN commit (`262ec9c`) makes them all pass simultaneously. This preserves the TDD invariant (RED → GREEN), keeps the commit log honest about what failed, and avoids artificial commit boundaries.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart` (single RED commit covers all three groups)
- **Verification:** Both commits show on `git log --oneline`. RED commit's tests fail at compile; GREEN commit's implementation makes all 175 tests pass 5/5 deterministic runs.
- **Committed in:** `8c8badc` (RED — all groups), `262ec9c` (GREEN — all groups pass)

**2. [Rule 2 - Missing Critical] Added `_isOutOfRange` clearing in `_hoistStream` on positionKey change**

- **Found during:** Task 2 (GREEN — implementation review)
- **Issue:** The plan only specified setting `_isOutOfRange` in `_onStreamData` and not changing it elsewhere. But on a `positionKey` change (re-hoist), the prior key's last out-of-range value would persist as a stale visual artifact — operator would see amber on a fresh, untriggered new key.
- **Fix:** `_hoistStream` now resets `_isOutOfRange = false` alongside `_isStreamStale = true` whenever it re-hoists. Same setState batching pattern as the rest of the method.
- **Files modified:** `lib/page_creator/assets/elevator.dart` (`_hoistStream` body)
- **Verification:** `Out-of-range (ELEV-15) stale state and out-of-range state are mutually exclusive` test verifies the empty-key path; the broader 175-test suite confirms no regression on the existing positionKey-change tests.
- **Committed in:** `262ec9c` (GREEN — Task 2)

**3. [Rule 2 - Missing Critical] Treated NaN as out-of-range (not stale)**

- **Found during:** Task 2 (GREEN — implementation review)
- **Issue:** The plan specifies "raw < 0 or > 100 ⇒ out-of-range". NaN is technically neither, but treating it as a normal value silently propagates corruption to the tween (`platformProgress` already defends with `isNaN ⇒ 0.0`). The operator should see a fault, not a silent grey-stale render.
- **Fix:** `_onStreamData` flags `_isOutOfRange=true` for `raw.isNaN || raw < 0 || raw > 100`. Mirrors the defensive disposition of `platformProgress` but elevates the visual signal.
- **Files modified:** `lib/page_creator/assets/elevator.dart` (`_onStreamData`)
- **Verification:** Behaviour is consistent with the locked CONTEXT §decisions out-of-range contract; existing "stream value 50 → isOutOfRange=false" test verifies the legal-range path is unaffected.
- **Committed in:** `262ec9c` (GREEN — Task 2)

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 missing critical)
**Impact on plan:** All three deviations strengthen the implementation against silent-failure modes the plan didn't enumerate. No scope creep — all stay within the ELEV-15 / QUAL-07 surface.

## Issues Encountered

- **None.** Tests compiled, the painter golden generated cleanly on the first `--update-goldens` pass, and 5/5 deterministic test runs all pass.

## TDD Gate Compliance

This plan is type=tdd. Gate sequence verified in `git log --oneline`:
- RED gate: `8c8badc test(04-01): add failing tests...` — present.
- GREEN gate: `262ec9c feat(04-01): add out-of-range outline...` — present.
- REFACTOR gate: not used — implementation was clean on first pass; no refactor needed.

## User Setup Required

None — no external service configuration required.

## Phase 4 Closeout

This is the final plan in the milestone. With all four phases complete:

- **Phase 1** — Sensor asset (3 painter variants, dialog, registry).
- **Phase 2** — Elevator foundation (config, painter, widget, registry, dialog).
- **Phase 3** — Children riding the platform (Stack composition, polymorphic dispatch, editor add/edit/remove UI).
- **Phase 4** — Out-of-range fault rendering (this plan).

**Milestone status:** functionally complete. 175 tests green, 5/5 deterministic, `flutter analyze` clean across all modified files.

**Manual smoke checklist** in `test/page_creator/assets/elevator_widget_test.dart` (lines 1-86) covers operator-action flows that automated tests cannot verify (palette presence, real-PLC sweep, save+reload, cross-page back-compat). Phase 4 adds no new manual smoke items — the new visual is locked by the painter golden.

## Next Phase Readiness

- **No follow-up phase required** — the milestone is closed by this plan.
- **Future enhancements** (not blocking):
  - Wire `LeakTesting.enable()` into `flutter_test_config.dart` to upgrade the QUAL-07 mount/unmount test from "no exceptions" to active leak detection. The grep guards stay valuable as a complement.
  - Add an audible alarm tier for sustained out-of-range conditions (would hook into `_isOutOfRange` and the existing alarm system in `tfc_dart`). Out of scope for this milestone.
  - Extend the out-of-range pattern to other PLC-driven assets (`Sensor`, `Conveyor`) — same `kOutOfRangeColor` constant, same fault-overlay pattern.

## Self-Check: PASSED

Verified before commit:

**Files exist:**
- `lib/page_creator/assets/elevator_painter.dart` (modified) — FOUND
- `lib/page_creator/assets/elevator.dart` (modified) — FOUND
- `test/page_creator/assets/elevator_widget_test.dart` (modified) — FOUND
- `test/page_creator/assets/elevator_painter_test.dart` (modified) — FOUND
- `test/page_creator/assets/goldens/elevator/position_50_out_of_range.png` (created) — FOUND, 991 bytes

**Commits exist:**
- `8c8badc` (RED) — FOUND in `git log --oneline`
- `262ec9c` (GREEN) — FOUND in `git log --oneline`

**Tests pass:**
- `flutter test test/page_creator/assets/{sensor,elevator}*.dart` — 175/175 passed across 5/5 deterministic runs.

---
*Phase: 04-polish-error-ux-and-ci-hardening*
*Completed: 2026-05-06*
