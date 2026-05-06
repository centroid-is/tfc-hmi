---
phase: 02-elevator-foundation
plan: 03
subsystem: ui
tags: [flutter, custom-painter, golden-tests, tdd, value-listenable, repaint-boundary]

# Dependency graph
requires:
  - phase: 02-elevator-foundation
    provides: platformOffsetTop helper (Plan 02-01) consumed by paint() to avoid recomputing the Y-axis off-by-one math
  - phase: 02-elevator-foundation
    provides: ElevatorConfig data model (Plan 02-02) — not directly imported by the painter, but locks the constructor primitives this painter accepts
provides:
  - ElevatorPainter (single CustomPainter; no kind enum since elevator has only one variant in this phase)
  - 4-golden matrix locked at 200x300 logical pixels (stale, position_0, position_50, position_100)
  - shouldRepaint contract enforced by 4 unit tests including the Pitfall 3 cross-runtimeType guard
  - kRailStrokeFraction / kPlatformHeightFraction / kLeftRailFraction / kRightRailFraction module-level constants for downstream re-use (widget, palette card)
affects: [02-04 elevator-widget, 02-05 elevator-registry, 03-children-overlay]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ValueListenable<double> + super(repaint:) for scoped painter repaints (Pitfall 2 / ARCHITECTURE Pattern 3)"
    - "RepaintBoundary + Key for golden tests at logical pixel sizes (mirrors conveyor_gate_golden_test.dart project convention)"
    - "shouldRepaint with cross-runtimeType guard then per-field equality (mirrors sensor_painter pattern)"

key-files:
  created:
    - lib/page_creator/assets/elevator_painter.dart
    - test/page_creator/assets/elevator_painter_test.dart
    - test/page_creator/assets/goldens/elevator/stale.png
    - test/page_creator/assets/goldens/elevator/position_0.png
    - test/page_creator/assets/goldens/elevator/position_50.png
    - test/page_creator/assets/goldens/elevator/position_100.png
  modified: []

key-decisions:
  - "Painter consumes platformOffsetTop from Plan 02-01 — does NOT recompute the (1 - progress) * (bboxHeight - platformHeight) formula"
  - "Painter takes ValueListenable<double> via constructor + super(repaint: progress) for scoped repaints — zero subscriptions, zero Riverpod (Pitfall 2)"
  - "Goldens use RepaintBoundary + find.byKey to render at logical 200x300 (matches project convention; required for the plan's '200 x 300' acceptance criterion)"
  - "shouldRepaint compares: runtimeType, identical(progress), isStale, activeColor — all four must match for false (deterministic)"
  - "Stale rendering overrides BOTH rail and platform colour to Colors.grey shade500 (#9E9E9E) regardless of activeColor — closes ELEV-14"

patterns-established:
  - "Pure painter pattern: primitives in (notifier + bool + Color), pixels out, ZERO state — locks Pitfall 2"
  - "Cross-runtimeType shouldRepaint guard: if (old.runtimeType != runtimeType) return true — locks Pitfall 3 against painter state leakage"
  - "Golden test scaffold: MaterialApp > Scaffold > Center > RepaintBoundary(key) > SizedBox > CustomPaint, then find.byKey + matchesGoldenFile"
  - "Per-test ValueNotifier construction (no shared module state) — locks Pitfall 6 determinism"

requirements-completed: [ELEV-02, ELEV-03, ELEV-14, QUAL-08]

# Metrics
duration: ~10min
completed: 2026-05-06
---

# Phase 02 Plan 03: ElevatorPainter + 4-golden matrix Summary

**Pure ElevatorPainter (rails + platform deck) with ValueListenable<double>-driven scoped repaints and a TDD-locked 4-golden matrix (stale, 0%, 50%, 100%) at 200x300 logical pixels.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-06T10:50:00Z
- **Completed:** 2026-05-06T10:55:00Z
- **Tasks:** 5
- **Files modified:** 6 (1 painter, 1 test, 4 golden PNGs)

## Accomplishments
- ElevatorPainter implemented with the locked visual contract (rails at 10/90% width, 8% platform deck height, stale → grey override)
- 4-golden matrix at 200x300 logical pixels — visually validated and deterministic across 5+5 consecutive runs
- shouldRepaint contract enforced by 4 unit tests including the Pitfall 3 cross-runtimeType guard
- Painter consumes platformOffsetTop from Plan 02-01 — never recomputes the off-by-one Y-axis formula
- ValueListenable<double> + super(repaint:) wiring for scoped repaints (Pitfall 2 / ARCHITECTURE Pattern 3)

## Task Commits

Each task was committed atomically following TDD RED→GREEN cadence:

1. **Seed: prerequisite files from upstream waves** - `7e0ef1b` (chore)
2. **Task 1 [RED]: failing tests for shouldRepaint contract** - `a61e995` (test)
3. **Task 2 [GREEN]: implement ElevatorPainter with shouldRepaint** - `bce82cd` (feat)
4. **Task 3 [RED]: failing golden tests for stale + 0/50/100** - `0144178` (test)
5. **Task 4 [GREEN]: generate elevator goldens (stale, position_0/50/100)** - `c6d1635` (feat)
6. **Task 5 lint cleanup: drop unused flutter/foundation import** - `5500db7` (style)

TDD commit cadence: 2 test commits + 2 feat commits + 1 style cleanup = 5/5 tracked, all matching `(test|feat|style)\(02-03\)` prefix.

## Files Created/Modified
- `lib/page_creator/assets/elevator_painter.dart` - ElevatorPainter (CustomPainter consuming ValueListenable<double> progress + isStale + activeColor; shouldRepaint with runtimeType + per-field equality)
- `test/page_creator/assets/elevator_painter_test.dart` - 4 shouldRepaint contract tests + 4 golden tests (stale, position_0, position_50, position_100)
- `test/page_creator/assets/goldens/elevator/stale.png` - 200x300 grey rails + grey deck centered (isStale=true override)
- `test/page_creator/assets/goldens/elevator/position_0.png` - 200x300 blue rails + blue deck at bottom edge (progress=0.0)
- `test/page_creator/assets/goldens/elevator/position_50.png` - 200x300 blue rails + blue deck centered (progress=0.5)
- `test/page_creator/assets/goldens/elevator/position_100.png` - 200x300 blue rails + blue deck at top edge (progress=1.0)

Seed commit (prerequisites pulled in to make worktree buildable):
- `lib/page_creator/assets/elevator.dart` - ElevatorConfig (Plan 02-02 output, fetched from main)
- `lib/page_creator/assets/elevator.g.dart` - generated JSON (Plan 02-02 output)
- `lib/page_creator/assets/elevator_layout.dart` - platformOffsetTop / platformProgress (Plan 02-01 output)
- `lib/page_creator/assets/sensor_painter.dart` - reference pattern (Phase 1 output, fetched from `a5b6584`)
- `test/page_creator/assets/sensor_painter_test.dart`, `elevator_layout_test.dart`, `elevator_config_test.dart` - reference tests / suite continuity

## Decisions Made
- **RepaintBoundary + find.byKey for goldens (deviation from plan code).** Plan code used `find.byType(CustomPaint).first` which captures the entire view at devicePixelRatio (2400x1800 PNGs). Switched to `find.byKey(elevatorKey)` wrapping a `RepaintBoundary` so PNGs render at 200x300 logical pixels — matches the existing project convention in `test/page_creator/assets/conveyor_gate_golden_test.dart` AND satisfies the plan's `file ... | grep -c "200 x 300"` acceptance criterion.
- **Stale colour: Colors.grey shade500 (#9E9E9E).** Mirrors sensor convention which mirrors conveyor_gate.dart:325. Hard-coded in painter to avoid Theme dependency in tests.
- **Default activeColor: Material blue 700 (#1976D2).** Test fixture default; widget (Plan 02-04) will override per Theme.colorScheme.primary at runtime.
- **Single CustomPainter (no kind enum).** Elevator has only one variant in Phase 2; future variants would warrant the sensor's one-class-per-kind decomposition pattern, but YAGNI for now.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RepaintBoundary + find.byKey for golden capture**
- **Found during:** Task 4 (golden generation)
- **Issue:** Plan code used `find.byType(CustomPaint).first` for `expectLater`. This captured the painter at the active devicePixelRatio (12x in this environment), producing 2400x1800 PNGs. The plan's acceptance criterion explicitly requires `file ... | grep -c "200 x 300"` to return 4.
- **Fix:** Wrapped `SizedBox(200, 300) > CustomPaint` in a `RepaintBoundary` keyed `Key('elevator_painter_golden')`, switched all 4 `expectLater` calls to `find.byKey(elevatorKey)`. This is the same pattern used by `test/page_creator/assets/conveyor_gate_golden_test.dart` (project convention).
- **Files modified:** `test/page_creator/assets/elevator_painter_test.dart` (4 lines: const key, 4× find.byKey, RepaintBoundary wrap)
- **Verification:** `file test/page_creator/assets/goldens/elevator/*.png | grep -c "200 x 300"` returns 4. All 8 tests pass on 5 consecutive runs.
- **Committed in:** `c6d1635` (Task 4 commit)

**2. [Rule 1 - Bug] Drop unused flutter/foundation.dart import**
- **Found during:** Task 5 (analyzer sweep)
- **Issue:** `flutter analyze` reported `unnecessary_import` info — `ValueNotifier` and `ValueListenable` are already exported by `package:flutter/material.dart`.
- **Fix:** Removed the redundant `import 'package:flutter/foundation.dart';` line from the test file.
- **Files modified:** `test/page_creator/assets/elevator_painter_test.dart`
- **Verification:** `flutter analyze` reports `No issues found!`. All 8 tests still pass on 5 consecutive runs.
- **Committed in:** `5500db7` (style commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 — bug-class fixes for acceptance-criterion satisfaction and analyzer-clean state)
**Impact on plan:** Both fixes preserve the locked visual contract and the TDD cadence. No scope creep — both stayed inside the plan's listed file set.

## Issues Encountered

- **Worktree seeded off stale main.** The worktree was created before plans 02-01 and 02-02 merged. Followed the `parallel_execution` block's escape hatch: pulled `elevator.dart`, `elevator.g.dart`, `elevator_layout.dart` from `main` and `sensor_painter.dart` + reference test files from the upstream merge commit `a5b6584`. Committed as `chore: seed worktree with prerequisites (02-01, 02-02 outputs)` (`7e0ef1b`). All TDD work then proceeded against a buildable worktree.

## Threat Mitigations

| Threat ID | Mitigation status | Where |
|-----------|-------------------|-------|
| T-02-07 (Tampering — OOR progress) | mitigated | `paint()` calls `progress.value.clamp(0.0, 1.0)` before passing to `platformOffsetTop` (line ~67 of elevator_painter.dart) |
| T-02-08 (DoS — over-eager shouldRepaint) | mitigated | `shouldRepaint` returns false when (runtimeType, identical(progress), isStale, activeColor) all match — guarded by Task 1 test `same inputs → shouldRepaint=false` |
| T-02-09 (Information Disclosure) | accepted | n/a — pure pixels from primitives, no PII surface |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Painter is locked under unit tests + golden matrix; Plan 02-04 (Elevator widget) can construct it with a stream-driven progress notifier and a Theme-derived activeColor with confidence
- 4-golden matrix protects against silent visual regressions (Pitfall 6 determinism guard)
- Zero file overlap with Plan 02-04 (this plan touches `elevator_painter.dart` + tests; Plan 02-04 touches `elevator.dart`) — both can run in parallel

## Self-Check: PASSED

Verifications performed before writing this section:

| Item | Status |
|------|--------|
| `lib/page_creator/assets/elevator_painter.dart` exists | FOUND |
| `test/page_creator/assets/elevator_painter_test.dart` exists | FOUND |
| `test/page_creator/assets/goldens/elevator/stale.png` exists @ 200x300 | FOUND |
| `test/page_creator/assets/goldens/elevator/position_0.png` exists @ 200x300 | FOUND |
| `test/page_creator/assets/goldens/elevator/position_50.png` exists @ 200x300 | FOUND |
| `test/page_creator/assets/goldens/elevator/position_100.png` exists @ 200x300 | FOUND |
| Commit `a61e995` (test 02-03 shouldRepaint) in `git log --all` | FOUND |
| Commit `bce82cd` (feat 02-03 shouldRepaint) in `git log --all` | FOUND |
| Commit `0144178` (test 02-03 goldens) in `git log --all` | FOUND |
| Commit `c6d1635` (feat 02-03 goldens) in `git log --all` | FOUND |
| Commit `5500db7` (style 02-03 cleanup) in `git log --all` | FOUND |
| `flutter test` — 8/8 pass, 5 consecutive runs deterministic | PASS |
| `flutter analyze` — 0 errors, 0 warnings, 0 info | PASS |
| TDD commit cadence (test → feat → test → feat) | PASS |

---
*Phase: 02-elevator-foundation*
*Plan: 03*
*Completed: 2026-05-06*
