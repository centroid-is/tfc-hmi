---
phase: 03-elevator-child-embedding
plan: 01
subsystem: ui
tags: [flutter, stack-composition, value-key, hit-test, gesture-detector, custompaint, golden-tests, tdd]

# Dependency graph
requires:
  - phase: 02-elevator-foundation
    provides: ElevatorChildEntry schema (id, offsetX, child) + _animProgress notifier + LayoutRotatedBox tap pipeline + 4 painter goldens + JSON round-trip + AssetRegistry registration + config dialog body
  - phase: 01-sensor-asset
    provides: Sensor widget with GestureDetector + LayoutRotatedBox tap pattern (used as a child here)

provides:
  - Multi-child Stack composition in Elevator widget (painter at index 0, Positioned per ElevatorChildEntry)
  - ValueKey<String>(entry.id) wrapper preserves child State identity across _animProgress changes (Pitfall 1 closed)
  - Polymorphic entry.child.build(context) dispatch — no runtime-type switching (ELEV-11 / Anti-Pattern 1 closed)
  - Children's GestureDetectors fire while platform is mid-translation (ELEV-19 / Pitfall 7 — user's locked directive closed)
  - Stack(clipBehavior: Clip.none) — children may overhang elevator bbox during translation
  - Per-child ValueListenableBuilder `child:` cache — only Positioned (and its `top`) rebuilds per frame
  - LayoutRotatedBox.hitTest now forwards to its child render box at angle=0 and angle != 0 (Rule 1 deviation, fixes a long-standing bug)
  - 7 widget tests + 3 integration goldens covering identity, layout, polymorphism, tap-during-translation
affects: [03-02 (allKeys flat-map; Plan reads this surface), 03-03 (editor list-management UI; depends on this Stack composition rendering correctly), Phase 4 (any future asset embedded as child of elevator)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stack composition: painter index 0, children index 1..N — single source of truth for layout via platformOffsetTop"
    - "Per-child ValueListenableBuilder with cached `child:` parameter — preserves State identity while Positioned.top tracks animation"
    - "ValueKey<String>(entry.id) on outer KeyedSubtree wrapper — Flutter element-reconciliation key for dynamic child lists"
    - "LayoutRotatedBox.hitTest forwards to child first, then adds self — descendant GestureDetectors remain reachable"

key-files:
  created:
    - test/page_creator/assets/goldens/elevator_with_children_progress_0.png
    - test/page_creator/assets/goldens/elevator_with_children_progress_50.png
    - test/page_creator/assets/goldens/elevator_with_children_progress_100.png
  modified:
    - lib/page_creator/assets/elevator.dart (Stack composition + Positioned children + per-child ValueListenableBuilder)
    - lib/page_creator/assets/common.dart (LayoutRotatedBox.hitTest forwards to child — Rule 1 fix)
    - test/page_creator/assets/elevator_widget_test.dart (7 widget tests + 3 goldens + 2 test-only BaseAsset subclasses)

key-decisions:
  - "LayoutRotatedBox.hitTest must forward to child render box (Rule 1 fix): without forwarding, any GestureDetector mounted INSIDE a LayoutRotatedBox is unreachable. This was always a bug but only surfaced now because Phase 1/2 always wrap LayoutRotatedBox in an OUTER GestureDetector."
  - "Per-child ValueListenableBuilder uses its `child:` parameter to cache the child subtree — locks Pitfall 1 (50 progress changes → 1 initState call) without needing a separate State-preservation mechanism."
  - "Stack uses Clip.none + per-child KeyedSubtree(key: ValueKey<String>(entry.id)) is sufficient identity preservation; no need for manual ElementRegistry."
  - "Children render via entry.child.build(context) — polymorphic dispatch only. Zero `is`/`runtimeType` switches (locked by source-grep regression test in the widget test file)."
  - "Goldens use positionKey='' so the painter renders in its grey/stale palette — eliminates Theme/primary-colour dependence in captured pixels (Pitfall 6 determinism)."

patterns-established:
  - "Pattern: parent-positioned child — Positioned(top:platformOffsetTop(...) - childH, left:offsetX*W - childW/2) per ElevatorChildEntry, wrapped in ValueListenableBuilder<double> on _animProgress so only the Positioned rebuilds per frame."
  - "Pattern: ValueKey<String>(entry.id) on the KeyedSubtree wrapper above the SizedBox+entry.child.build — the wrapper is the identity, the inner subtree is content."
  - "Pattern: hit-test-through-translation — Positioned in a Stack hits-tests at its rendered position because Flutter's hit-test walks the layout tree (not paint-time offsets). Locked by the tap-during-translation test."

requirements-completed: [ELEV-09, ELEV-10, ELEV-11, ELEV-12, ELEV-19, QUAL-03, QUAL-08]

# Metrics
duration: 12min
completed: 2026-05-06
---

# Phase 3 Plan 01: Stack composition + Positioned children + ValueKey + tap-through-translation Summary

**Multi-child Stack composition: painter at index 0, ValueKey-keyed Positioned children that ride the platform via per-child ValueListenableBuilder, with hit-test-through-translation locked by widget test and 3 goldens**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-06T11:53:19Z
- **Completed:** 2026-05-06T12:04:46Z
- **Tasks:** 3 (RED → GREEN → goldens)
- **Files modified:** 3 (elevator.dart, common.dart, elevator_widget_test.dart)
- **Files created:** 3 PNG goldens

## Accomplishments

- `_ElevatorState.build` now emits `Stack(clipBehavior: Clip.none, children: [painter, ...positionedChildren])` inside the existing animation pipeline. The painter and children share the same `_animProgress` notifier, so children translate in lock-step with the platform without rebuilding above the Stack.
- Each child wrapper carries `ValueKey<String>(entry.id)` on a `KeyedSubtree` above the `SizedBox` + `entry.child.build(context)` — this is what Flutter's element-reconciliation algorithm uses to keep the child's State alive across position changes (locked by the 50-progress-changes test → 1 `initState` call).
- Polymorphic dispatch via `entry.child.build(context)` — zero runtime-type switching. A source-level regression test in the widget-test file fails any future commit that adds `is SensorConfig`, `is ConveyorConfig`, `child.runtimeType ==`, or `switch (...runtimeType)` to elevator.dart.
- Children's `GestureDetector`s fire while the platform is mid-translation (the user's locked directive in `feedback_gesture_through_translation.md`). Lock test: tap a Sensor child at progress=0.5 (mid-tween) → Sensor's "Detection State Key" dialog opens, NOT the Elevator's "Position State Key" dialog.
- 3 deterministic PNG goldens at progress {0.0, 0.5, 1.0} with one Sensor (offsetX=0.3) + one Conveyor (offsetX=0.7) child, captured via `RepaintBoundary` and verified 5/5 consecutive runs without diff.

## Task Commits

Each task was committed atomically:

1. **Task 1 [RED]: failing tests for child layout, identity, polymorphism, tap-during-translation** — `fd3e9fb` (`test`)
2. **Task 2 [GREEN]: Stack composition + Positioned children + ValueKey + polymorphic build + LayoutRotatedBox hit-test fix** — `859f5a3` (`feat`)
3. **Task 3 [GREEN-extension]: 3 integration goldens at progress {0, 0.5, 1.0} with Sensor + Conveyor children** — `662f89b` (`test`)

_Note: Plan 03-01 is an explicit TDD plan; the `test → feat → test` cadence follows the locked QUAL-08 discipline._

## Files Created/Modified

- `lib/page_creator/assets/elevator.dart` — `_ElevatorState.build` now returns `_buildStack(paintSize, isStale, activeColor)` from the inner `TweenAnimationBuilder` builder. New private methods `_buildStack` and `_buildPositionedChild`. Imports `kPlatformHeightFraction` from elevator_painter.dart so the children's anchor and the painted platform's top edge stay welded.
- `lib/page_creator/assets/common.dart` — `_RenderLayoutRotatedBox.hitTest` now forwards to `child!.hitTest(...)` BEFORE adding itself, at both `_angle == 0.0` and `_angle != 0.0` branches. Without this, descendant GestureDetectors are unreachable.
- `test/page_creator/assets/elevator_widget_test.dart` — adds groups `'Children riding the platform (Phase 3)'` (7 tests) and `'Goldens — elevator with children at progress {0, 0.5, 1.0} (QUAL-03)'` (3 tests). Adds two test-only `BaseAsset` subclasses (`_CountingChildConfig` for the Pitfall-1 lock, `_FixedSizeChildConfig` for numerical layout assertions).
- `test/page_creator/assets/goldens/elevator_with_children_progress_{0,50,100}.png` — 3 captured PNG goldens.

## Decisions Made

- **LayoutRotatedBox.hitTest forwarding** (see Deviation 1 below). Without it, ELEV-19 cannot be satisfied because the elevator's outer `LayoutRotatedBox` swallows any tap directed at a descendant `GestureDetector`. The fix is local (one render-object method) and preserves all existing tap-to-configure behaviour for Sensor / Elevator / Conveyor (all 203 existing widget/painter/config/gate tests continue to pass).
- **Per-child `ValueListenableBuilder` with cached `child:`** instead of one outer `ValueListenableBuilder` on `_animProgress` rebuilding the whole children list. This way: (a) only the `Positioned` rebuilds per frame (cheap), and (b) the child subtree's State stays alive (locked by the 50-progress-changes Pitfall-1 test).
- **Goldens use `positionKey: ''`** (stale-grey palette). This eliminates Theme/primary-colour dependence so the captured pixels are identical across machines/runs.
- **Source-level grep guard** in the widget test file (`File('lib/page_creator/assets/elevator.dart').readAsStringSync()` + RegExp). This is a regression test, not a runtime test — it fails any future commit that introduces runtime-type switching even if the runtime tests would still pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LayoutRotatedBox.hitTest blocks taps to descendant GestureDetectors**
- **Found during:** Task 2 (GREEN — running the tap-during-translation test against the new Stack composition).
- **Issue:** `_RenderLayoutRotatedBox.hitTest` at angle=0 (and angle != 0) only added itself to the hit-test result and never forwarded to its child render box. This meant any `GestureDetector` mounted inside a `LayoutRotatedBox` was unreachable. The bug pre-dates Phase 3 — it never surfaced because Phase 1 (Sensor) and Phase 2 (Elevator) both wrap `LayoutRotatedBox` in an OUTER `GestureDetector`, so the outer GD intercepts taps before the broken hit-test runs. As soon as a child with its own `GestureDetector` is placed INSIDE the elevator's `LayoutRotatedBox`, the bug bites: the elevator's outer GD eats the tap, and the child's GD never fires. This is exactly ELEV-19's failure mode.
- **Fix:** at `_angle == 0.0`, call `child!.hitTest(result, position: position)` before `result.add(BoxHitTestEntry(this, position))`. At `_angle != 0.0`, transform `position` into the child's local frame (the existing `(x0, y0)` calculation) and forward via `child!.hitTest(result, position: Offset(x0, y0))`.
- **Files modified:** lib/page_creator/assets/common.dart (lines 1334–1370).
- **Verification:** All 203 pre-existing widget/painter/config/gate tests still pass. The 7 new Phase-3 widget tests pass. The 3 new integration goldens pass 5/5 consecutive runs. `flutter analyze` clean.
- **Committed in:** `859f5a3` (Task 2 GREEN commit).

**2. [Rule 1 - Bug] Default RelativeSize too small for tap-during-translation test**
- **Found during:** Task 2 (GREEN — first attempt at tap-during-translation test failed because `SensorConfig.preview()` inherits BaseAsset's 0.03×0.03 default, which is 6×9 pixels in a 200×300 bbox — too small for `tester.tap` to land on reliably).
- **Issue:** The test as originally drafted in Task 1 used `SensorConfig.preview()` for the child. The 6×9 pixel hit target is brittle.
- **Fix:** Test-side adjustment only — `sensor.size = const RelativeSize(width: 0.4, height: 0.2)`. The test still locks the contract (tap-through-translation reaches the Sensor's GestureDetector) but uses a generous hit target. No production code change.
- **Files modified:** test/page_creator/assets/elevator_widget_test.dart.
- **Verification:** Tap-during-translation test passes; Sensor's "Detection State Key" dialog opens, Elevator's "Position State Key" dialog does NOT.
- **Committed in:** `859f5a3` (Task 2 GREEN commit, alongside the LayoutRotatedBox fix).

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs).
**Impact on plan:** Both essential. Deviation 1 was the actual blocker — without it the user's locked ELEV-19 directive could not be satisfied. Deviation 2 is a minor test-fixture adjustment. No scope creep, no architectural change required.

## Issues Encountered

- The widely-used `LayoutRotatedBox` at angle=0 had a long-standing hit-test bug (deviation 1). Fix is localised and benefits ALL existing tappable widgets behind a `LayoutRotatedBox` — but the codebase had previously masked the bug by always wrapping `LayoutRotatedBox` in an OUTER `GestureDetector`. No regression observed in 203 pre-existing tests.

## TDD Gate Compliance

All three required gates landed in order:

- **RED:** `fd3e9fb` `test(03-01): add failing tests …` (6 widget tests fail, 1 source-grep gate trivially passes since no switching exists yet).
- **GREEN:** `859f5a3` `feat(03-01): wire Stack composition …` (all 6 widget tests pass; source-grep gate continues to hold).
- **GREEN-extension (goldens):** `662f89b` `test(03-01): add 3 integration goldens …` (3 PNG goldens captured deterministically; 5/5 consecutive runs pass).

No REFACTOR commit — none was needed (the GREEN code is the final shape; no clean-up rounds required).

## Verification Gate (Plan §verification)

| Gate | Result |
|------|--------|
| `flutter test test/page_creator/assets/elevator_widget_test.dart` | 23/23 pass (13 Phase-2 + 7 Phase-3 widget + 3 goldens) |
| `flutter analyze lib/page_creator/assets/elevator.dart test/page_creator/assets/elevator_widget_test.dart` | No issues found |
| 5 consecutive runs deterministic | 5/5 pass |
| `git log --oneline | grep -cE "(test|feat)\(03-01\)"` | 3 |
| Source-grep for runtime-type switching in elevator.dart | 0 matches |
| 3 PNG goldens present | 3 files |

## Self-Check

- Files created/modified: all present.
- Commits: `fd3e9fb`, `859f5a3`, `662f89b` — all in `git log`.
- Goldens: 3 PNGs at the locked paths.
- Source-grep gates: all pass.
- All tests: 23/23 pass on 5/5 consecutive runs.

## Next Phase Readiness

- **Plan 03-02 (allKeys flat-map):** Ready. The Stack composition is locked; Plan 03-02 only touches `ElevatorConfig.allKeys` (an override on the model), independent of widget-tree shape.
- **Plan 03-03 (editor list-management UI):** Ready. The editor will mutate `widget.config.children` via `setState`; `didUpdateWidget` already preserves stream identity, and the new Stack composition handles dynamic child lists correctly because `ValueKey<String>(entry.id)` is the identity (no positional reliance).
- **Manual smoke (Phase 3 closeout):** Will need to verify children physically ride the platform end-to-end with a real PLC value; can wait until 03-02 + 03-03 are also merged.

## Threat Flags

None — the plan's threat model dispositions held. T-03-01 (polymorphic dispatch tampering — accepted, validated through AssetRegistry); T-03-02 (DoS from frequent _animProgress changes — mitigated, locked by Pitfall-1 test); T-03-03 (information disclosure — accepted, same operator authority surface as standalone Sensor); T-03-04 (repudiation — N/A, no write actions). The LayoutRotatedBox hit-test fix (Rule 1 deviation) does not introduce new attack surface — it is a hit-test forwarding fix that simply restores expected Flutter render-object behaviour (delegate to child).

---
*Phase: 03-elevator-child-embedding*
*Completed: 2026-05-06*
