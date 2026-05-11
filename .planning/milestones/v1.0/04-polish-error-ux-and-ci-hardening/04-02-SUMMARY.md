---
phase: 04-polish-error-ux-and-ci-hardening
plan: 02
subsystem: page_creator/assets (elevator + sensor)
tags:
  - elevator
  - sensor
  - polish
  - golden-review
  - tdd
requires:
  - 04-01 (Phase 4 wave 1 — out-of-range outline + leak guard)
provides:
  - "Plan 04-02 closure: 3 visual-review fixes landed under strict TDD"
affects:
  - lib/page_creator/assets/elevator_painter.dart
  - lib/page_creator/assets/elevator.dart
  - lib/page_creator/assets/sensor_painter.dart
tech-stack:
  added: []
  patterns:
    - "@visibleForTesting Color get debugLabelColour as a sync-with-paint() hook for locking colour formulas in unit tests"
key-files:
  created:
    - .planning/phases/04-polish-error-ux-and-ci-hardening/04-02-PLAN.md
    - .planning/phases/04-polish-error-ux-and-ci-hardening/04-02-SUMMARY.md
  modified:
    - lib/page_creator/assets/elevator_painter.dart
    - lib/page_creator/assets/elevator.dart
    - lib/page_creator/assets/sensor_painter.dart
    - test/page_creator/assets/elevator_painter_test.dart
    - test/page_creator/assets/elevator_widget_test.dart
    - test/page_creator/assets/sensor_painter_test.dart
    - test/page_creator/assets/goldens/elevator/position_0.png
    - test/page_creator/assets/goldens/elevator/position_50.png
    - test/page_creator/assets/goldens/elevator/position_100.png
    - test/page_creator/assets/goldens/elevator/position_50_out_of_range.png
    - test/page_creator/assets/goldens/elevator_with_children_progress_100.png
    - test/page_creator/assets/goldens/sensor/red_light_with_label.png
decisions:
  - "Default active colour for ElevatorPainter is Colors.grey.shade600 (#757575), matching 02-CONTEXT § Visual & Position Pipeline lock. Earlier Material blue 700 (#1976D2) was drift, not design."
  - "Children clamp to top >= 0 inside the elevator bbox at progress=1.0 — the platform itself still reaches its true position, but children rest at the bbox top edge instead of overshooting. Visual safety clamp; not a behavioural change to platform geometry."
  - "Sensor label colour is locked to Colors.black87 when not stale (Colors.grey when stale). It NEVER inherits inactiveColor — the label is a high-contrast operator-facing tag, not a state-coloured glyph element."
  - "Each sensor painter exposes @visibleForTesting Color get debugLabelColour mirroring the inlined paint() expression. This lets unit tests lock the formula without scanning rendered pixels."
metrics:
  completed: 2026-05-05
  tasks: 7
  duration_minutes: ~25
  test_count_after: 242
  goldens_regenerated: 6
  commits: 7  # 1 plan-scaffold + 3 RED + 3 GREEN + (this SUMMARY commit)
---

# Phase 4 Plan 02: Golden-Review Fixes Summary

Three production-quality fixes caught by a user-driven visual review of all 14 golden PNGs after Plan 04-01 closed Phase 4. The existing golden suite is regression-only ("looks the same") rather than spec-driven ("looks right"); this plan closes that loop by adding spec-anchored unit assertions and regenerating the affected goldens against corrected output.

All three fixes followed strict TDD: a failing `test(04-02): …` commit landed before each `fix(04-02): …` implementation commit. 6 commits in 3 fix-pairs.

## Fixes

### Fix 1 — ELEV-02: Default active colour drift to Material blue

**Caught by:** Visual review of `position_0.png`, `position_50.png`, `position_100.png`, `position_50_out_of_range.png` — rails and platform deck were vivid Material blue 700 (`#1976D2`), but `02-CONTEXT.md §Visual & Position Pipeline` locks them as **neutral grey** ("matches sensor inactive convention which mirrors `conveyor_gate.dart`").

**Source of drift:** `lib/page_creator/assets/elevator_painter.dart` line 31 set `_kDefaultActive = Color(0xFF1976D2)`. CONTEXT was never satisfied at the test fixture default; widget callers passing `Theme.colorScheme.primary` masked the drift in production runs.

**Fix:** Change `_kDefaultActive` to `Color(0xFF757575)` (`Colors.grey.shade600`).

**Test:** `ElevatorPainter().activeColor == Color(0xFF757575)` — added under `CONTEXT compliance — default active colour (ELEV-02)` group in `test/page_creator/assets/elevator_painter_test.dart`.

**Goldens regenerated (4):**
- `goldens/elevator/position_0.png` (929 → 927 bytes)
- `goldens/elevator/position_50.png` (958 → 955 bytes)
- `goldens/elevator/position_100.png` (931 → 930 bytes)
- `goldens/elevator/position_50_out_of_range.png` (991 → 988 bytes)

`stale.png` is unchanged — it uses `_kStaleColor`, not `_kDefaultActive`.

**Commits:**
- RED: `2f4b0db test(04-02): assert ElevatorPainter default active colour is neutral grey (CONTEXT compliance)`
- GREEN: `6d3c598 fix(04-02): use neutral grey for ElevatorPainter default active colour (ELEV-02 CONTEXT compliance)`

### Fix 2 — Children disappear at progress=100% in elevator

**Caught by:** Visual review of `elevator_with_children_progress_100.png` — children rendered partially or fully outside the elevator's bbox at high progress.

**Root cause:** `_buildPositionedChild` in `lib/page_creator/assets/elevator.dart` computed `top = platformOffsetTop(progress, h, ph) - childH`. At `progress = 1.0`, `platformOffsetTop` returns `0` (platform sits flush with bbox top), so `top = -childH`, pushing the child `childH` pixels above the bbox.

**Fix:** Visual safety clamp `final top = max(0.0, platformY - childH);` in the `_buildPositionedChild` ValueListenableBuilder. Added `import 'dart:math' show pi, max;`. The platform itself still reaches its true position; children stop translating upward when there is no room above the platform and rest at the bbox top edge — the natural operator visual ("the lift's at the top floor, the load's at the top of the shaft").

**Test:** Added `children Positioned.top clamps to >= 0 at progress=1.0` inside the existing `Children riding the platform (Phase 3)` group. Also updated the existing ELEV-10 numerical lock to expect `max(0.0, platformOffsetTop(...) - childH)` rather than the raw (buggy) value — added `import 'dart:math' show max;` to the test file.

**Goldens regenerated (1):**
- `goldens/elevator_with_children_progress_100.png` (1000 → 2173 bytes — the byte growth reflects the now-visible child pixels)

The progress-0 and progress-50 goldens are unaffected (`platformY - childH >= 0` at lower progresses, so the clamp is inert).

**Commits:**
- RED: `742ea11 test(04-02): add failing test for child top-edge clamp at progress 1.0`
- GREEN: `0fcd9f9 fix(04-02): clamp child Positioned.top to >= 0 so children stay visible at progress=100%`

### Fix 3 — SENS-13: Sensor label invisible against panel

**Caught by:** Visual review of `goldens/sensor/red_light_with_label.png` — the operator tag ('PE-101A') was painted in the painter's `inactiveColor`, which defaults to a light grey, against a dark panel. Effectively invisible.

**Root cause:** All three sensor painters (`RedLightBeamPainter`, `OpticFieldPainter`, `InductiveFieldPainter`) had `final labelColour = isStale ? Colors.grey : inactiveColor;`. Treating the label colour as state-coloured was a category error: the label is a high-contrast tag, not part of the glyph state matrix.

**Fix:** Lock `labelColour = isStale ? Colors.grey : Colors.black87` at all three call sites. Added `@visibleForTesting Color get debugLabelColour` to each painter mirroring the inlined paint() expression — used by the new SENS-13 unit tests to lock the formula without rendering pixels.

**Test:** New `Sensor label visibility (SENS-13)` group in `sensor_painter_test.dart` with 4 assertions:
1. `RedLightBeamPainter` label is `Colors.black87` (and explicitly NOT a low-contrast `inactiveColor`).
2. `OpticFieldPainter` label is `Colors.black87` when not stale.
3. `InductiveFieldPainter` label is `Colors.black87` when not stale.
4. All three painters fall back to `Colors.grey` when stale.

**Goldens regenerated (1):**
- `goldens/sensor/red_light_with_label.png` (3259 → 3291 bytes — slight growth from darker label pixels)

The 9 other sensor goldens carry `label: null` and are unaffected.

**Commits:**
- RED: `d13cd97 test(04-02): assert sensor label is rendered in a contrasting colour, not inactiveColor (SENS-13)`
- GREEN: `bfaea8f fix(04-02): paint sensor labels in contrasting Colors.black87 (SENS-13 readability)`

## QUAL-08 — TDD Cadence

Six commits in three RED→GREEN pairs. `git log --oneline f318965..HEAD` is symmetric: every `fix(04-02)` commit is preceded by a matching `test(04-02)` commit on the same fix surface.

| # | Fix | RED | GREEN |
|---|-----|-----|-------|
| 1 | Elevator default colour (ELEV-02) | `2f4b0db` | `6d3c598` |
| 2 | Child top-edge clamp | `742ea11` | `0fcd9f9` |
| 3 | Sensor label visibility (SENS-13) | `d13cd97` | `bfaea8f` |

## Verification

- **Full asset suite:** `flutter test test/page_creator/assets/` → **242 / 242 passing**.
- **Static analysis:** `flutter analyze` over all 6 modified files → **No issues found**.
- **Golden audit:** `git diff f318965..HEAD --stat -- test/page_creator/assets/goldens/` shows exactly the 6 expected goldens regenerated:

  ```
  position_0.png                                       929 → 927
  position_50.png                                      958 → 955
  position_100.png                                     931 → 930
  position_50_out_of_range.png                         991 → 988
  elevator_with_children_progress_100.png             1000 → 2173
  red_light_with_label.png                            3259 → 3291
  ```

  No unintended goldens (stale.png, progress 0/50 with-children, the 9 unlabelled sensor PNGs) were touched.

## Phase 4 Closeout Note

This plan is a polish iteration on top of the milestone-closing 04-01. Phase 4 itself was already closed by 04-01-SUMMARY.md; this plan does not move the milestone status, it records a follow-up correction loop and demonstrates that visual review of golden artifacts is a reliable QA layer that the regression-only golden suite alone cannot provide.

## Self-Check: PASSED

- All 6 commits exist on `worktree-agent-accd71e0`:
  - `git log --oneline -1 2f4b0db` ✓
  - `git log --oneline -1 6d3c598` ✓
  - `git log --oneline -1 742ea11` ✓
  - `git log --oneline -1 0fcd9f9` ✓
  - `git log --oneline -1 d13cd97` ✓
  - `git log --oneline -1 bfaea8f` ✓
- All claimed source-code changes present (verified via `grep`/`flutter test` outputs above)
- All 6 goldens visible in `git diff` and physically updated on disk
