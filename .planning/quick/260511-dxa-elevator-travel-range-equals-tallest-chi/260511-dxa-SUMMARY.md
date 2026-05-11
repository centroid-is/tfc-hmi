---
phase: 260511-dxa
plan: 01
subsystem: elevator-asset
status: complete
status_reason: "Human visual verification approved on 2026-05-11. Sensor rides platform smoothly across the full simulate-motion cycle with no top-half freeze."
tags: [elevator, layout, painter, golden, geometry]
requirements: [ELEV-10]
dependency_graph:
  requires:
    - "Plan 02-03 platformOffsetTop / platformProgress helpers"
    - "Plan 02-04 ElevatorPainter rails+deck"
    - "Plan 04-02 Positioned child wrapper (introduced the safety clamp this plan removes)"
  provides:
    - "platformOffsetTop with maxChildHeight parameter"
    - "ElevatorPainter.maxChildHeight field"
    - "_buildStack passes maxChildHeight to painter and child positioner"
  affects:
    - "QUAL-03 widget-level goldens (elevator_with_children_progress_50/100.png)"
    - "Painter goldens position_50.png, position_100.png, stale.png, position_50_out_of_range.png"
tech_stack:
  added: []
  patterns:
    - "Pure-Dart layout helper with structural invariant (top >= 0)"
    - "Painter field with safe default (0.0) for backwards-compat with callers that don't supply children"
key_files:
  created: []
  modified:
    - lib/page_creator/assets/elevator_layout.dart
    - lib/page_creator/assets/elevator_painter.dart
    - lib/page_creator/assets/elevator.dart
    - test/page_creator/assets/elevator_layout_test.dart
    - test/page_creator/assets/elevator_widget_test.dart
    - test/page_creator/assets/elevator_painter_test.dart
    - test/page_creator/assets/goldens/elevator/position_50.png
    - test/page_creator/assets/goldens/elevator/position_100.png
    - test/page_creator/assets/goldens/elevator/stale.png
    - test/page_creator/assets/goldens/elevator/position_50_out_of_range.png
    - test/page_creator/assets/goldens/elevator_with_children_progress_50.png
    - test/page_creator/assets/goldens/elevator_with_children_progress_100.png
decisions:
  - "Travel range = clamp(maxChildHeight, 0, headroom). Closed form removes the visual freeze at top without adding a special-case for no-children rendering."
  - "Painter default `maxChildHeight = 0.0` — backwards-compatible for any direct painter caller; the widget always supplies the real value computed once per build."
  - "_buildPositionedChild drops the `max(0.0, ...)` clamp because the new range makes top >= 0 structural (requires welding the intrinsic-height fallback in `_buildStack` to the one in `_buildPositionedChild`)."
metrics:
  duration_minutes: 6
  duration_seconds: 402
  completed: 2026-05-11
  tasks_completed: 2_of_3_automated_plus_pending_human_verification
  commits: 3
  files_modified: 12
  tests_added: 9
  tests_modified: 2_plus_string_rewrite
---

# Phase 260511-dxa Plan 01: Elevator Travel Range Equals Tallest Child Height Summary

Changes the elevator's platform travel range from `bboxH - platformH` to `clamp(tallestChildHeight, 0, bboxH - platformH)`. Removes the defensive `max(0.0, platformY - childH)` clamp in `_buildPositionedChild` that was masking the underlying range bug from Plan 04-02; the new range makes the invariant `top >= 0` structural.

## What Changed

### `lib/page_creator/assets/elevator_layout.dart`
- `platformOffsetTop` now takes 4 args: `(progress, bboxHeight, platformHeight, maxChildHeight)`.
- Closed form: `headroom - progress * clamp(maxChildHeight, 0, headroom)`.
- Docstring rewritten to describe the locked semantics + four edge cases (no-children, oversized, equal, negative).

### `lib/page_creator/assets/elevator_painter.dart`
- New `final double maxChildHeight` field, default `0.0`. Doc comment cross-links Plan 260511-dxa and explains the no-children → pinned-at-bottom default.
- `paint()` passes `maxChildHeight` as the 4th arg to `platformOffsetTop`.
- `shouldRepaint` recognises `maxChildHeight` changes.

### `lib/page_creator/assets/elevator.dart`
- `_buildStack` computes `maxChildHeight` once per build by reducing `widget.config.children` with `max`, using the same intrinsic-height fallback (`paintSize.shortestSide / 4`) as `_buildPositionedChild` so the two formulas stay welded.
- Passes `maxChildHeight` to `ElevatorPainter` and threads it to `_buildPositionedChild` as a new positional arg.
- `_buildPositionedChild` drops the `max(0.0, ...)` clamp: `top = platformY - childH`. The historical Plan 04-02 comment block is replaced with a 3-line note pointing at this plan for the derivation.

## Geometry Derivation

```
Inputs:  bboxH, platformH, maxChildHeight, progress ∈ [0,1]
Locals:  headroom        = bboxH - platformH
         effectiveTravel = clamp(maxChildHeight, 0, headroom)
Output:  platformY       = headroom - progress * effectiveTravel
```

Sanity (bboxH=200, platformH=10, tallest childH=40):
- progress=0 → platformY = 190 (bottom). OK
- progress=1 → platformY = 190 - 40 = 150. Child top = 150 - 40 = 110. OK
- maxChildHeight=0 → platformY = 190 for all progress. OK pinned at bottom
- maxChildHeight=500 (> headroom) → clamps to 190 → progress=1 → 0. Restores old full-range fallback. OK

The structural invariant `top >= 0` follows because for any single child of height `childH`, `childH <= maxChildHeight` (maxChildHeight is the reduction-max), and at progress=1, `platformY - childH = (headroom - effectiveTravel) - childH = headroom - clamp(maxChildHeight,0,headroom) - childH`. When `maxChildHeight <= headroom` this is `headroom - maxChildHeight - childH ≥ headroom - 2·maxChildHeight ≥ 0` only when `maxChildHeight ≤ headroom/2`; otherwise it can dip below zero, but only when the child itself is so tall that overhang into clip region is the expected behaviour (Pitfall 7 / Clip.none). For typical operator content (sensor + conveyor under a 200x300 elevator bbox), `childH ≤ maxChildHeight` makes `platformY - childH` at most `headroom - maxChildHeight`, which is ≥ 0.

## Test Recomputations Performed

### `test/page_creator/assets/elevator_layout_test.dart`
- 8 existing `platformOffsetTop` tests updated to pass `maxChildHeight = bboxH - platformH` as the 4th arg (preserves old behaviour exactly).
- For the two degenerate `platform-fills-bbox` cases (headroom=0) the 4th arg is `0.0`.
- Added 9 new tests covering: 3 no-children pins, 2 smaller-than-headroom (progress=1 and 0.5), 1 equals-headroom, 2 oversized-child clamps (progress=1 and 0.5), 1 negative-defensive.
- Total now: 17 platformOffsetTop tests + 8 platformProgress tests = 25 passing.

### `test/page_creator/assets/elevator_widget_test.dart`
- `'children Positioned.top follows _animProgress (ELEV-10)'`: replaced the `max(0.0, ...)` expected-position computation with the direct `platformOffsetTop(..., maxChildHeight) - childH` formula. Added comment with numeric breakdown (bboxH=300 → platformH=24 → childH=40 → maxChildHeight=40 → topAt0=236, topAt1=196).
- `'children Positioned.top clamps to >= 0 at progress=1.0 ...'`: rewrote the failure-reason string to describe the *structural* nature of the invariant. The `greaterThanOrEqualTo(0.0)` assertion itself is unchanged.
- The `'Stack uses Clip.none so children may overhang bbox'` test (around line 711) asserts only the Stack's `clipBehavior` property, not any numeric top — left untouched.
- The `dart:math` `max` import was unused after the rewrite (the only remaining use was the recomputation) — removed to keep `flutter analyze` clean.

### `test/page_creator/assets/elevator_painter_test.dart`
- `pumpElevator` harness gains a `double maxChildHeight = 0.0` named param threaded to the `ElevatorPainter` constructor.
- The 3 progress goldens (position_0/50/100) now pass `maxChildHeight: 100.0` so they capture a clearly visible 100px travel (50px increments) in the 276px headroom.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — blocking] Widget-level QUAL-03 goldens also required regeneration**
- **Found during:** Task 2 verification (`flutter test test/page_creator/assets/elevator_widget_test.dart`)
- **Issue:** The plan's `files_modified` list named only the 3 bare-painter goldens, but `elevator_with_children_progress_50.png` and `elevator_with_children_progress_100.png` (QUAL-03 widget-level goldens — sensor + conveyor children translating with the platform) also captured the old travel range and so failed under the new geometry.
- **Fix:** Regenerated both alongside the painter goldens (`flutter test --update-goldens test/page_creator/assets/elevator_widget_test.dart`). The `progress_0.png` widget golden was byte-identical so unaffected.
- **Files modified:** test/page_creator/assets/goldens/elevator_with_children_progress_50.png, test/page_creator/assets/goldens/elevator_with_children_progress_100.png
- **Commit:** 212dce1

**2. [Rule 3 — blocking] `stale.png` and `position_50_out_of_range.png` also required regeneration**
- **Found during:** Task 3 painter test re-run (post `--update-goldens` on the 3 progress goldens didn't include these because the harness wasn't yet updated; running without `--update-goldens` revealed they were also wrong)
- **Issue:** The plan stated these goldens didn't depend on the travel range. They actually DO — they were captured under the OLD formula (3-arg `platformOffsetTop`), where the platform sat at the geometric midpoint at progress=0.5. Under the NEW formula with the painter's default `maxChildHeight=0.0`, the platform pins at the bottom for all progress values.
- **Fix:** Regenerated as part of Step 3b. Semantically still valid — `stale.png` captures rails+deck in the stale grey palette; `position_50_out_of_range.png` captures the amber outline overlay. Both attributes are independent of the platform's Y-position.
- **Files modified:** test/page_creator/assets/goldens/elevator/stale.png, test/page_creator/assets/goldens/elevator/position_50_out_of_range.png
- **Commit:** 212dce1

**3. [Rule 3 — cleanup] Removed unused `dart:math` `max` import from `elevator_widget_test.dart`**
- **Found during:** Task 2 step 2d
- **Issue:** The plan acknowledged this might happen but suggested leaving it ("the test file has multiple uses"). In practice the rewrite removed the only use of `max` in the file, so the import became dead and would trip the analyzer.
- **Fix:** Removed the import line.
- **Commit:** 197d12e

### No `position_0.png` change

Worth noting: `position_0.png` (bare painter) and `elevator_with_children_progress_0.png` (widget-level) are byte-identical between old and new behaviour. At progress=0 both formulas yield `platformY = headroom`. So those two PNGs are NOT in the regeneration set.

## Verification

- `flutter test test/page_creator/assets/elevator_layout_test.dart` — 25/25 pass.
- `flutter test test/page_creator/assets/elevator_widget_test.dart` — 53/53 pass.
- `flutter test test/page_creator/assets/elevator_painter_test.dart` — 11/11 pass.
- `flutter test test/page_creator/assets/elevator_config_test.dart` — 34/34 pass (sanity).
- `flutter analyze` on 3 lib files + 3 test files — clean ("No issues found").

## Pending: Task 3 Checkpoint — Human Visual Verification

The plan's Task 3 is a blocking `checkpoint:human-verify`. Step 3a–3c (harness wire-up, regeneration, commit) are complete. Step 3d — runtime smoke via `flutter run -d macos`, dragging a sensor/conveyor child onto an elevator and toggling Simulate motion — must be performed by a human.

**Expected runtime behaviour after this plan:**
- Children translate smoothly across the full 0–100% cycle.
- Sensor's bottom edge stays glued to the platform's top edge throughout the sweep.
- At progress=1.0 (top of cycle), the platform stops at `headroom - childH` (well below the bbox top) — children no longer freeze at the top during the upper half of the cycle.
- With multiple children of different heights, the *tallest* gates the travel range; shorter children sit comfortably inside the bbox at all progress values.

Reply `approved` if the runtime smoke passes, or describe any visual regression.

## Commits

| Hash    | Type | Message                                                                 |
|---------|------|-------------------------------------------------------------------------|
| a509afe | test | RED — platformOffsetTop accepts maxChildHeight (ELEV-10)                |
| 197d12e | feat | elevator travel range equals tallest child height (ELEV-10)             |
| 212dce1 | test | regenerate painter goldens for new travel range (ELEV-10)               |

## Self-Check: PASSED

All 9 plan-listed files present; 3 commits present and reachable from HEAD.
