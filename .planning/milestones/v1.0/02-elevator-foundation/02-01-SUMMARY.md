---
phase: 02-elevator-foundation
plan: 01
subsystem: ui
tags: [elevator, layout, helper, tdd, dart, flutter]

# Dependency graph
requires:
  - phase: 01-sensor-asset
    provides: "AssetRegistry pattern + sensor stale-state convention (referenced in 02-CONTEXT.md, no direct code dependency)"
provides:
  - "platformOffsetTop(progress, bboxHeight, platformHeight) — pure-Dart Y-offset helper closing Pitfall 8 off-by-one math"
  - "platformProgress(rawValue) — NaN-safe, OOR-clamping 0..100 -> 0..1 progress derivation"
  - "lib/page_creator/assets/elevator_layout.dart — zero-Flutter-import contract for downstream painter/widget plans"
affects:
  - 02-02-elevator-config
  - 02-03-elevator-painter
  - 02-04-elevator-widget
  - 02-05-elevator-registry-and-goldens

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-Dart top-level helper functions (no class wrapper, no Flutter imports) for math primitives that must be unit-tested in isolation"
    - "TDD RED→GREEN commit cadence per behaviour: separate test commit precedes feat commit"
    - "NaN guard precedes Dart `.clamp` calls (since Dart `.clamp` propagates NaN through)"

key-files:
  created:
    - lib/page_creator/assets/elevator_layout.dart
    - test/page_creator/assets/elevator_layout_test.dart
  modified: []

key-decisions:
  - "Helper is top-level pure-Dart function (not method, not class); zero Flutter imports beyond the implicit dart:core"
  - "Locked formula `(1 - progress) * (bboxHeight - platformHeight)` from PITFALLS.md Pitfall 8 — no clamping inside platformOffsetTop; caller uses platformProgress for clamping"
  - "platformProgress short-circuits NaN to 0.0 BEFORE clamp (Dart's `.clamp` returns NaN for NaN input — would break downstream tween math)"
  - "Out-of-range silent clamp (no fault outline) — ELEV-15 amber-outline rendering deferred to Phase 4 per CONTEXT decision"

patterns-established:
  - "Pure-Dart helper isolation: math primitives that must be unit-tested live in their own file with zero Flutter imports, consumed by both painter and widget"
  - "TDD commit cadence enforced at plan level: 4 commits in `(test|feat)\\(02-01\\)` form, alternating test→feat per behaviour"

requirements-completed: [QUAL-04, QUAL-08]

# Metrics
duration: 3min
completed: 2026-05-06
---

# Phase 2 Plan 1: Elevator Layout Helpers Summary

**Pure-Dart `platformOffsetTop` and `platformProgress` helpers landed via 4-commit TDD cadence; Pitfall 8 off-by-one math now isolated in a single 16-test-covered file that downstream painter/widget plans will import.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-05-06T10:42:52Z
- **Completed:** 2026-05-06T10:45:57Z
- **Tasks:** 5
- **Files modified:** 2 (both newly created)

## Accomplishments

- `platformOffsetTop(progress, bboxHeight, platformHeight)` — locked formula `(1 - progress) * (bboxHeight - platformHeight)` covered by 8 unit tests at progress {0.0, 0.5, 1.0} and degenerate platform-fills-bbox cases
- `platformProgress(rawValue)` — NaN-safe clamp + divide-by-100, covered by 8 unit tests including NaN, +/-Infinity, and OOR clamp cases
- 16/16 unit tests green; `flutter analyze` reports zero issues on both files
- Zero Flutter imports in production file (`grep -cE "^import 'package:flutter" lib/page_creator/assets/elevator_layout.dart` returns 0) — pure-Dart isolation per Pitfall 2
- TDD commit cadence enforced: 4 commits in `git log` alternating test→feat per behaviour, all matching `(test|feat)(02-01)`

## Task Commits

Each task was committed atomically:

1. **Task 1 [RED]: failing tests for platformOffsetTop** — `c21ef8b` (test)
2. **Task 2 [GREEN]: implement platformOffsetTop** — `cfeb0a2` (feat)
3. **Task 3 [RED]: failing tests for platformProgress** — `c2044db` (test)
4. **Task 4 [GREEN]: implement platformProgress** — `d3b529d` (feat)
5. **Task 5: Final regression sweep + summary** — no code commit (per plan); SUMMARY.md committed in plan-metadata commit

## Files Created/Modified

- `lib/page_creator/assets/elevator_layout.dart` — Pure-Dart helpers `platformOffsetTop` and `platformProgress`. Zero Flutter imports. ~48 lines including doc comments.
- `test/page_creator/assets/elevator_layout_test.dart` — 16 unit tests in two groups (`platformOffsetTop` and `platformProgress`).

## Decisions Made

- **Helper shape: top-level pure-Dart function vs class method.** Chose top-level functions per CONVENTIONS.md (snake_case file, top-level pure functions) — no benefit from a class wrapper for two stateless math operations.
- **NaN-before-clamp ordering.** Dart's `double.clamp` returns NaN for NaN inputs (it does not coerce). Short-circuiting NaN to 0.0 before calling `.clamp` was required for the `rawValue=double.nan -> 0.0` test to pass — this is documented inline.
- **No fault rendering inside helpers.** ELEV-15 amber-outline OOR rendering is intentionally NOT triggered here per CONTEXT decision; helpers silently clamp. This keeps the helper pure (no UI concerns) and Phase 4 owns the fault visual.
- **No `library;` rename.** Used a bare `library;` declaration to host the file-level doc comment (Dart 3 idiom) without exporting a name.

## Deviations from Plan

None - plan executed exactly as written.

The only minor cosmetic detail: the plan's acceptance-criteria regex for Task 3 expected 8 platformProgress test declarations matching `^      test\(` (6-space indent). The file uses 4-space indent for tests inside the group (standard `dart format` output for arrow-function tests), so that exact regex returns 0 — but `awk '/group..platformProgress/,/^  });/' ... | grep -cE "test\("` returns the expected 8. The 8 tests are present, named, and pass; only the regex's indentation expectation was off. Not a code defect.

---

**Total deviations:** 0
**Impact on plan:** None — plan executed verbatim.

## Issues Encountered

None.

## Threat Surface Coverage

Both threats from the plan's `<threat_model>` are mitigated as planned:

| Threat ID | Disposition | Mitigation Verified |
|-----------|-------------|---------------------|
| T-02-01 (Tampering: malformed PLC double) | mitigate | NaN guard at `elevator_layout.dart:45` precedes clamp; clamp pins +/-Infinity and OOR to [0, 100]; 8 unit tests in `platformProgress` group cover all three edge cases. |
| T-02-02 (DoS: hot-path platformProgress) | accept | Pure-Dart double math, constant time, no allocations — verified by inspection. Animation-jitter mitigation (Pitfall 4) deferred to Plan 02-04 per accepted disposition. |

No new threat surface introduced beyond the plan's register.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Plan 02-02 (config + JSON round-trip):** Ready. No dependency on this plan's helpers.
- **Plan 02-03 (painter):** Ready. Will `import 'elevator_layout.dart'` and call `platformOffsetTop` to compute platform Y inside `paint()`.
- **Plan 02-04 (widget):** Ready. Will call `platformProgress(rawDouble)` on the StateMan stream value, then feed the resulting 0..1 progress into `TweenAnimationBuilder` and `platformOffsetTop`.
- **Plan 02-05 (registry + goldens):** No direct dependency on this plan, but the platform-position goldens (`position_0.png`, `position_50.png`, `position_100.png`) implicitly verify these helpers' correctness through the rendered painter.

No blockers. Helpers are stable; downstream plans should not need to modify this file.

## Self-Check: PASSED

- File `lib/page_creator/assets/elevator_layout.dart` exists.
- File `test/page_creator/assets/elevator_layout_test.dart` exists.
- File `.planning/phases/02-elevator-foundation/02-01-SUMMARY.md` exists.
- Commit `c21ef8b` (test for platformOffsetTop) exists in `git log`.
- Commit `cfeb0a2` (feat platformOffsetTop) exists in `git log`.
- Commit `c2044db` (test for platformProgress) exists in `git log`.
- Commit `d3b529d` (feat platformProgress) exists in `git log`.
- All 16 unit tests pass green; `flutter analyze` reports no issues.

---
*Phase: 02-elevator-foundation*
*Completed: 2026-05-06*
