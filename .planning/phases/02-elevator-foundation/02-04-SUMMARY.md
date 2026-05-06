---
phase: 02-elevator-foundation
plan: 04
subsystem: ui
tags: [flutter, riverpod, customwidget, customstreamhoisting, streamsubscription, tweenanimation, valuenotifier, gesturedetector, layoutrotatedbox, page-creator, elevator]

# Dependency graph
requires:
  - phase: 02-elevator-foundation
    provides: "ElevatorConfig + ElevatorChildEntry data model (Plan 02-02), platformOffsetTop + platformProgress helpers (Plan 02-01), ElevatorPainter with isStale + activeColor + ValueListenable<double> progress (Plan 02-03)"
  - phase: 01-sensor-asset
    provides: "Sensor widget structural template — initState stream hoisting, _hoistedKey re-hoist guard, GestureDetector + LayoutRotatedBox layering, _openConfigDialog dialog wrapping precedent, three stale paths (empty key / no-data / error)"
provides:
  - Elevator ConsumerStatefulWidget — runtime entry point that ElevatorConfig.build() returns
  - _ElevatorState owning stream lifecycle (initState hoist, didUpdateWidget re-hoist on positionKey change), ValueNotifier<double> _progress + _animProgress, dispose contract for both notifiers + StreamSubscription
  - Three stale paths via _isStaleEffective getter (empty key, no-data, stream error / non-double payload)
  - GestureDetector(behavior: HitTestBehavior.opaque) wrapping painter — Phase 3 ancestor-translation forward-compat
  - LayoutRotatedBox honouring config.coordinates.angle (degrees → radians)
  - TweenAnimationBuilder<double> + Curves.linear smoothing wrapper toward _progress.value over config.tweenDurationMs (ELEV-06)
  - Placeholder AlertDialog returned by configure() so Plan 02-04 tap test has unique finder; Plan 02-05 swaps to real editor
  - 2 @visibleForTesting seams (debugPositionStream, debugProgress) for regression tests
  - 11 widget tests across 5 groups (Tap to configure, Stale paths, Stream lifecycle Pitfall 2, Rotation, Animation pipeline ELEV-06)
affects:
  - 02-05 (config dialog editor + AssetRegistry registration — replaces placeholder AlertDialog and updates tap-to-configure assertion to a unique-to-editor finder)
  - 03-* (children-on-elevator — GestureDetector wrap survives ancestor translation; ElevatorChildEntry consumed)
  - 04-* (Phase 4 leak detection — dispose contract is the seam)

# Tech tracking
tech-stack:
  added: []  # No new packages — uses existing flutter_riverpod, open62541, flutter/foundation
  patterns:
    - "Stream hoisted to initState via ref.read(stateManProvider.future).asStream().asyncExpand((sm)=>sm.subscribe(key).asStream()).asyncExpand((s)=>s) — never inline ref.watch in build (Pitfall 2 lock)"
    - "Re-hoist guard via stored _hoistedKey field, not oldWidget.config (in-place editor mutation)"
    - "Three-path stale detection (empty key | no-data | error) folded into _isStaleEffective getter that the painter consumes as isStale"
    - "Tween(begin: target, end: target) over config.tweenDurationMs ms with Curves.linear — fresh interpolation per _progress change, no animation while values are equal"
    - "Double ValueNotifier pattern: outer _progress (stream-driven target) + inner _animProgress (per-frame tween-driven, painter listens) — keeps painter API agnostic to the animation layer"
    - "GestureDetector(behavior: HitTestBehavior.opaque) outside LayoutRotatedBox — survives Phase 3 ancestor translation; mirrors sensor.dart precedent"
    - "@visibleForTesting test seams (debugPositionStream, debugProgress) for stream-identity regression assertion without poking private state"

key-files:
  created:
    - "test/page_creator/assets/elevator_widget_test.dart — 11 tests, 5 groups, regression-locked"
  modified:
    - "lib/page_creator/assets/elevator.dart — Elevator ConsumerStatefulWidget + _ElevatorState added below ElevatorConfig; build() returns Elevator(config: this); configure() returns placeholder AlertDialog"

key-decisions:
  - "Placeholder AlertDialog body in configure() so the Plan 02-04 tap test has a unique finder; Plan 02-05 will swap to _ElevatorConfigEditor (Plan 01-05 SegmentedButton<SensorKind> precedent)"
  - "Double-notifier pattern (_progress target + _animProgress per-frame) preserves Plan 02-03 painter API (ValueListenable<double> progress) while letting TweenAnimationBuilder do smoothing"
  - "Stream hoisted via ref.read in initState (NEVER ref.watch in build) — locked under 100-rebuild stream-identity regression test"
  - "_hoistedKey field comparison rather than oldWidget.config.positionKey — required by editor's in-place mutation pattern (sensor.dart precedent)"
  - "Curves.linear (not Curves.easeOut etc.) — operators expect industrial position lifts to track linearly, no overshoot or ease"

patterns-established:
  - "Pattern A — Stream lifecycle in ConsumerStatefulWidget: initState hoists, didUpdateWidget re-hoists on key change, dispose cancels"
  - "Pattern B — Three-path stale detection folded into single getter consumed by painter (empty key OR no-data OR error)"
  - "Pattern C — Tween wrapper around painter: ValueListenableBuilder<double> → TweenAnimationBuilder<double> → CustomPaint, with per-frame notifier as the painter's repaint anchor"

requirements-completed: [ELEV-01, ELEV-04, ELEV-05, ELEV-06, ELEV-14, QUAL-08]

# Metrics
duration: ~25min
completed: 2026-05-06
---

# Phase 02 Plan 04: Elevator Widget Summary

**Elevator ConsumerStatefulWidget with initState-hoisted position stream, three-path stale-grey rendering, GestureDetector tap-to-configure, and TweenAnimationBuilder<double> smoothing — 11 widget tests locking Pitfalls 2 + 10 + ELEV-06.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-05-06T11:07:18Z
- **Tasks:** 7 of 7 complete (3 RED→GREEN cycles + final sweep)
- **Files modified:** 2 (1 created + 1 modified)

## Accomplishments

- **Elevator runtime entry point landed.** `ElevatorConfig.build()` now returns `Elevator(config: this)` — replaces the UnimplementedError stub from Plan 02-02. The widget owns subscription lifecycle, animation pipeline, dispose contract, tap-to-configure dialog wiring.
- **Pitfall 2 locked under regression test.** 100 rebuilds with the same `positionKey` MUST preserve `_positionStream` reference identity — enforced by `'100 rebuilds with same positionKey: stream identity preserved'` in `'Stream lifecycle (Pitfall 2)'` group.
- **Three stale paths covered.** Empty `positionKey` (path 1), stream pre-data (path 2), stream error / non-double payload (path 3) all flow through `_isStaleEffective` getter into the painter's `isStale` flag — rails + deck render grey (ELEV-14).
- **TweenAnimationBuilder<double> smoothing.** `Tween(begin: target, end: target)` idiom drives fresh interpolation per `_progress` change with `Curves.linear` over `config.tweenDurationMs` (default 250ms, configurable per-instance — ELEV-06).
- **GestureDetector(behavior: HitTestBehavior.opaque)** wraps the painter outside `LayoutRotatedBox` — survives Phase-3 ancestor translation (forward-compat for elevator-as-child).
- **dispose contract.** `_streamSub.cancel()`, `_progress.dispose()`, `_animProgress.dispose()` — Pitfall 10 closed; locked under unmount regression test.

## Task Commits

Each TDD cycle committed atomically (chronological order, after the prerequisite seed commit):

1. **Worktree seed** — `6ffc85d` (chore: seed worktree with 02-01..03 prerequisites + sensor reference)
2. **Task 1 RED** — `6661256` (test(02-04): add failing widget tests for stale paths and tap-to-configure)
3. **Test selector fix [Rule 1]** — `aaaf1ca` (fix(02-04): scope CustomPaint finder to Elevator subtree)
4. **Task 2 GREEN** — `b6103a8` (feat(02-04): implement Elevator widget with stream hoisting + stale paths + GestureDetector)
5. **Task 3 RED** — `0606726` (test(02-04): add failing tests for stream-hoisting (no-resubscribe-storm))
6. **Task 4 GREEN/lock** — `cb573ed` (feat(02-04): document _hoistStream Pitfall-2 lock (regression guard locked))
7. **Task 5 RED** — `b5af6ea` (test(02-04): add failing tests for animation pipeline (TweenAnimationBuilder ELEV-06))
8. **Task 6 GREEN** — `b52853a` (feat(02-04): wire TweenAnimationBuilder pipeline + dispose _animProgress)

**Plan metadata:** committed alongside this SUMMARY.md.

_TDD cadence: 3 cycles, 6 commits matching `(test|feat)(02-04)` + 1 fix commit (Rule-1 deviation, see Deviations section)._

## Files Created/Modified

- `lib/page_creator/assets/elevator.dart` — **modified.** Added `Elevator extends ConsumerStatefulWidget`, `_ElevatorState extends ConsumerState<Elevator>` (initState/didUpdateWidget/dispose, `_hoistStream`, `_onStreamData`/`_onStreamError`, `_isStaleEffective`, `_openConfigDialog`, build with GestureDetector + LayoutRotatedBox + LayoutBuilder + ValueListenableBuilder + TweenAnimationBuilder + CustomPaint chain). `ElevatorConfig.build()` now returns `Elevator(config: this)`. `ElevatorConfig.configure()` returns placeholder `AlertDialog('Configure Elevator')`. Added 2 `@visibleForTesting` test seams (`debugPositionStream`, `debugProgress`).
- `test/page_creator/assets/elevator_widget_test.dart` — **created.** 11 tests across 5 groups: Tap to configure (2), Stale paths (1), Stream lifecycle Pitfall 2 (4), Rotation (1), Animation pipeline ELEV-06 (3).

## Decisions Made

- **Placeholder AlertDialog in configure().** Following Plan 01-03 precedent: install something for the tap test to find, swap for the real editor in Plan 02-05. The tap test's `find.byType(AlertDialog)` assertion will be replaced by Plan 02-05 with a unique-to-editor finder (precedent: Plan 01-05 swapped to `SegmentedButton<SensorKind>`).
- **Double-notifier pattern (`_progress` + `_animProgress`).** Plan 02-03 painter API takes a `ValueListenable<double>`. To keep that API unchanged while introducing tween-smoothing, the outer `_progress` notifier is the stream-driven target and the inner `_animProgress` is the per-frame tween-driven value the painter actually listens to. Painter remains tween-agnostic.
- **`Curves.linear`.** Industrial position lifts track linearly; operators do not expect ease-in-out overshoot or visual settling on a vertical platform position display.
- **`_hoistedKey` field over `oldWidget.config.positionKey`.** The editor mutates the same `ElevatorConfig` instance in-place, so `oldWidget.config` and `widget.config` are the same reference and `oldWidget.config.positionKey` already reflects the new value. Comparing to a stored `_hoistedKey` is the only reliable re-hoist trigger (sensor.dart precedent).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test selector for CustomPaint matched MaterialApp chrome**

- **Found during:** Task 2 GREEN attempt (the implementation was correct, but the Task 1 test failed because of a finder bug)
- **Issue:** Task 1's stale-path test used `find.byType(CustomPaint).first` which matches the `CustomPaint` instances in MaterialApp's chrome (Scaffold/Overlay) — those have no painter set, so the test failed with `Expected: <Instance of 'ElevatorPainter'>, Actual: <null>`.
- **Fix:** Scoped the finder to the Elevator subtree using `find.descendant(of: find.byType(Elevator), matching: find.byType(CustomPaint))` — mirrors the existing pattern in `sensor_widget_test.dart` 'Tag pass-through' group.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart`
- **Verification:** All 3 Task-1 tests pass after the fix; the implementation in Task 2 was correct as-written.
- **Committed in:** `aaaf1ca` (separate `fix(02-04)` commit per Git Safety Protocol — never amend)

---

**Total deviations:** 1 auto-fixed (1 bug — Rule 1).
**Impact on plan:** Single test-selector bug in the plan-as-written test source. Did not affect correctness of any production code or scope of work. No scope creep.

## Issues Encountered

- **Worktree was created off stale `origin/main`** (4bbede3 — UMAS hardening) and missing `.planning/`, `CLAUDE.md`, `lib/page_creator/assets/elevator*.dart`, `lib/page_creator/assets/sensor*.dart`, `lib/page_creator/assets/conveyor_gate*.dart`, and the elevator/sensor test files. Fetched all prerequisites from local `main` (5040ecf) into a single `chore: seed worktree with 02-01..03 prerequisites` commit (`6ffc85d`) before starting Plan 02-04 work. Standard parallel-execution pattern (precedent: `7e0ef1b chore: seed worktree with prerequisites`).
- **Pre-existing `elevator_config_test.dart` polymorphic-child round-trip test failures (3 tests).** The worktree's `lib/page_creator/assets/registry.dart` is the stale origin/main version that does not register `SensorConfig` (Phase 1 added that registration on main). The 3 failing tests are pre-existing and OUT OF SCOPE for Plan 02-04 (which only verifies `elevator_widget_test.dart`). On main HEAD these tests pass because `SensorConfig: SensorConfig.fromJson` is in the registry's `_fromJsonFactories` map. **Logged as deferred: registry.dart in this worktree is missing the SensorConfig registration; this will be picked up automatically when the worktree merges back to main.**

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 02-05 ready to start.** This plan's placeholder `AlertDialog('Configure Elevator')` is the seam Plan 02-05 will replace with `_ElevatorConfigEditor` (mirroring `_SensorConfigEditor` from Phase 1). Plan 02-05's TODO will include updating `test/page_creator/assets/elevator_widget_test.dart` 'Tap to configure' / 'tap opens placeholder config dialog' to use a unique-to-editor finder (e.g., a settings widget the editor renders).
- **Plan 02-05 also picks up registry registration.** `AssetRegistry.registerFromJsonFactory<ElevatorConfig>` and the corresponding `defaultFactories` entry are NOT in this plan; that's Plan 02-05's concern.
- **Phase 3 (children-on-elevator) ready.** `GestureDetector(behavior: HitTestBehavior.opaque)` wraps the painter, surviving ancestor translation; `ElevatorChildEntry` data model already in place from Plan 02-02; only Stack overlay layout work remains.
- **Phase 4 (leak detection) ready.** `dispose` contract covers `_streamSub.cancel()`, `_progress.dispose()`, `_animProgress.dispose()` — locked under `'unmount disposes ValueNotifier and cancels subscription'` regression test.

## Verification Snapshot

```
$ flutter test test/page_creator/assets/elevator_widget_test.dart
00:00 +11: All tests passed!

$ flutter analyze lib/page_creator/assets/elevator.dart test/page_creator/assets/elevator_widget_test.dart
No issues found! (ran in 3.8s)

$ for i in 1..5; do flutter test test/page_creator/assets/elevator_widget_test.dart; done
5/5 deterministic — Animation pipeline (ELEV-06) default tweenDurationMs=250 → duration=250ms

$ git log --oneline | grep -cE "(test|feat|fix)\(02-04\)"
7
```

## Self-Check: PASSED

- File `lib/page_creator/assets/elevator.dart`: FOUND (450 LOC)
- File `test/page_creator/assets/elevator_widget_test.dart`: FOUND (170 LOC)
- Commit `6661256` (Task 1 RED): FOUND
- Commit `aaaf1ca` (Rule-1 fix): FOUND
- Commit `b6103a8` (Task 2 GREEN): FOUND
- Commit `0606726` (Task 3 RED): FOUND
- Commit `cb573ed` (Task 4 lock): FOUND
- Commit `b5af6ea` (Task 5 RED): FOUND
- Commit `b52853a` (Task 6 GREEN): FOUND
- All 11 widget tests pass on 5 consecutive runs: VERIFIED
- `flutter analyze` exit 0: VERIFIED
- TDD commit cadence ≥ 6: VERIFIED (7)

---
*Phase: 02-elevator-foundation*
*Plan: 04 — Elevator widget — TweenAnimationBuilder + stream hoisting + GestureDetector*
*Completed: 2026-05-06*
