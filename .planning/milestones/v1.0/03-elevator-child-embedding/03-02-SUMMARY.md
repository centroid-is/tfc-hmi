---
phase: 03-elevator-child-embedding
plan: 02
subsystem: ui
tags: [flutter, dart, state-keys, allKeys, json_annotation, asset-registry, riverpod, opc-ua, alarms, collectors]

# Dependency graph
requires:
  - phase: 02-elevator-foundation
    provides: ElevatorConfig data model with positionKey + children list (Plan 02-02), painter/widget pipeline (02-03/02-04), AssetRegistry registration + dialog (02-05)
  - phase: 03-elevator-child-embedding
    provides: Plan 03-01 — Stack composition + Positioned children with ValueKey identity and polymorphic build
provides:
  - "ElevatorConfig.allKeys override flat-mapping positionKey + children's allKeys (ELEV-13)"
  - "Regression-guard test group 'allKeys flat-map (ELEV-13)' (6 tests) locking order, dedup, empty-filter, and back-compat semantics"
affects:
  - 03-03 (editor add/edit/remove UI for children — must keep allKeys contract intact when mutating children list)
  - alarms (alarm_man subscribes to assets' allKeys — now sees children's keys via the override)
  - collectors (collector subscribes to allKeys — same — picks up sensor detection/risingEdgeDelay/fallingEdgeDelay through an Elevator parent)
  - any future asset that embeds a List<WrapperEntry> of polymorphic BaseAssets (e.g., a future "ConveyorWithChildren" — must replicate this override pattern; default introspection won't work)

# Tech tracking
tech-stack:
  added: []  # No new libraries — purely a Dart override using existing dart:core Set + iterable patterns
  patterns:
    - "parent-asset allKeys override pattern: flat-map positionKey/topLevelKey with children.expand((e) => e.child.allKeys), dedup via LinkedHashSet (Set<String> literal), filter empty strings — applies to any asset embedding a wrapper-list of polymorphic BaseAssets"
    - "@JsonKey(includeFromJson: false, includeToJson: false) on getter overrides — mirrors BaseAsset.allKeys to keep json_serializable codegen from trying to roundtrip the computed getter"
    - "Regression-guard doc-comment style: @override docs reference the locking test-group name verbatim, so a future grep from the test side surfaces the implementation contract"

key-files:
  created: []
  modified:
    - "lib/page_creator/assets/elevator.dart — added @override @JsonKey List<String> get allKeys getter on ElevatorConfig (between toJson() and build()) with regression-guard docstring"
    - "test/page_creator/assets/elevator_config_test.dart — appended new group 'allKeys flat-map (ELEV-13)' (6 tests)"

key-decisions:
  - "Use Set<String> literal (LinkedHashSet) for dedup so insertion order is preserved without an explicit LinkedHashSet import — positionKey first, children in declaration order, automatic dedup"
  - "Implement via collection-literal `<String>{ if (positionKey.isNotEmpty) positionKey, for (final k in children.expand(...)) if (k.isNotEmpty) k }.toList(growable: false)` rather than imperative Set + add — concise, satisfies the planner's 'children.expand(' must-have token, and stays aligned with the locked CONTEXT §Editor & allKeys formula"
  - "Annotate the getter with both @override and @JsonKey(includeFromJson: false, includeToJson: false) — without the latter, json_serializable codegen would try to (de)serialize the computed list, breaking round-trip"

patterns-established:
  - "Parent-asset allKeys override pattern: any BaseAsset that embeds a List<WrapperEntry> where WrapperEntry contains a polymorphic BaseAsset child must override allKeys to walk into entry.child.allKeys — the default introspection in common.dart only matches top-level JSON field names against ^key$|^key\\d+$|Key$|_key$ and silently misses wrapper-list nested keys (Anti-Pattern 6 in research/ARCHITECTURE.md)"

requirements-completed: [ELEV-13, QUAL-08]

# Metrics
duration: ~7min
completed: 2026-05-06
---

# Phase 3 Plan 2: allKeys override + back-compat Summary

**ElevatorConfig.allKeys override flat-maps positionKey + children's keys via children.expand, dedup'd with a LinkedHashSet literal — alarms and collectors now discover state keys nested inside child assets without operators registering each child key separately.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-06T12:07:29Z (approx — derived from 5617c17~1 commit time)
- **Completed:** 2026-05-06T12:14:12Z
- **Tasks:** 2 (TDD: RED + GREEN; no separate REFACTOR commit needed)
- **Files modified:** 2 (1 source + 1 test)

## Accomplishments
- New `@override` `List<String> get allKeys` on `ElevatorConfig` correctly flat-maps `positionKey` plus every child's `allKeys` (recursive over the polymorphic wrapper list).
- Locks the contract with 6 regression-guard tests covering: empty-config back-compat, positionKey-only, one Sensor child surfacing all sensor keys, multiple children flat-map (parent first), duplicate-key dedup, and empty-positionKey filter.
- Closes ARCHITECTURE Anti-Pattern 6 (the default `BaseAsset.allKeys` does not recurse into wrapper-list children — verified by the original RED failure: only `'lift.pos'` returned even though three sensor keys were configured).
- TDD discipline preserved: the `test(03-02):` commit precedes `feat(03-02):` and three tests fail at RED time on the unmodified code path.

## Task Commits

Each task was committed atomically (TDD: RED → GREEN cadence):

1. **Task 1 [RED]: Write failing allKeys flat-map tests** — `5617c17` (test)
2. **Task 2 [GREEN]: Implement ElevatorConfig.allKeys override + regression-guard docstring** — `555aac5` (feat)

## Files Created/Modified
- `lib/page_creator/assets/elevator.dart` — Added `@override` `@JsonKey(includeFromJson: false, includeToJson: false)` `List<String> get allKeys` getter on `ElevatorConfig` (35 LOC inserted, no deletions). Implements the locked CONTEXT §Editor & allKeys contract: `<String>{ if (positionKey.isNotEmpty) positionKey, for (final k in children.expand((e) => e.child.allKeys)) if (k.isNotEmpty) k }.toList(growable: false)`. Doc-comment marks the method as a regression guard locked by the 6-test group in `elevator_config_test.dart`.
- `test/page_creator/assets/elevator_config_test.dart` — Appended new group `'allKeys flat-map (ELEV-13)'` with 6 tests (126 LOC inserted). Sensor key field names hardcoded from `sensor.dart` (`detectionKey`, `risingEdgeDelayKey`, `fallingEdgeDelayKey`).

## Decisions Made
- **Set<String> literal vs explicit LinkedHashSet:** Used `<String>{ ... }` collection-literal form because Dart guarantees this is a `LinkedHashSet` (insertion-order preserved). Avoids the `dart:collection` import while still meeting the locked ordering requirement (positionKey first, children in declaration order). Gives concise, declarative form matching the CONTEXT §Editor & allKeys formula.
- **`children.expand(...)` instead of nested for-loop:** Initial GREEN draft used a nested `for` loop; refactored to `children.expand((e) => e.child.allKeys)` to satisfy the planner's `must_haves` `contains_also: 'children.expand('` token AND the `key_links` regex `expand\\(.*\\.child\\.allKeys`. Both forms produce identical results; `expand` is more idiomatic Dart and reads as "flatten" inline.
- **`@JsonKey(includeFromJson: false, includeToJson: false)` on the override:** Mirrors `BaseAsset.allKeys` (common.dart:217). Without it, `json_serializable` codegen would emit a `'allKeys': ...` field in the generated JSON, breaking the deep-equality round-trip tests.

## Deviations from Plan

None - plan executed exactly as written.

The only mid-task adjustment was a small implementation refactor (nested `for` → `children.expand(...)`) to satisfy the planner's `must_haves.artifacts.contains_also` token list. Both forms produce identical behavior; the rewrite was caught by my own grep gate cross-check, not by a test failure. All 32 tests passed under both forms.

**Total deviations:** 0
**Impact on plan:** None — clean TDD execution.

## Issues Encountered

- **Worktree was off pre-Phase-3 commit on origin/main.** The worktree was created off `main` (4bbede3), but origin/main does not yet contain the Phase 1+2 + Plan 03-01 outputs (those live on `_w0301`). Resolved by `git rebase _w0301`, which applied cleanly with no conflicts and pulled in all required files (`elevator.dart`, `sensor.dart`, `elevator_config_test.dart`, `elevator_widget_test.dart`, `.planning/`). After the rebase, the baseline 26 pre-existing tests passed, confirming the rebase target was the correct integration point.
- **Test 5 (dedup) coincidentally passed at RED time.** The plan's RED expectation was that tests 3, 4, 5 would fail. Test 5 passed because `positionKey: 'shared'` is captured by the default `BaseAsset.allKeys` introspection AND the child's `'shared'` detectionKey is silently dropped (default doesn't recurse), so the result `['shared']` happens to satisfy the dedup assertion `where((k) => k == 'shared').length == 1`. Tests 3, 4, 6 all failed as expected, satisfying the plan's `≥3 fail` acceptance criterion. The test still has value: it locks dedup once the override exists, and at GREEN time it would have failed if the override returned duplicates.

## Verification Receipts

- `flutter test test/page_creator/assets/elevator_config_test.dart` → `+32: All tests passed!` (26 pre-existing + 6 new ELEV-13)
- `flutter test test/page_creator/assets/elevator_widget_test.dart` → `+23: All tests passed!` (Plan 03-01 regression-clean)
- `flutter analyze lib/page_creator/assets/elevator.dart` → `No issues found!`
- `git log --oneline | grep -cE "(test|feat)\(03-02\)"` → 2 (RED + GREEN)
- `grep -v '^[[:space:]]*//\|^[[:space:]]*///' lib/page_creator/assets/elevator.dart | grep -c "@override"` → 15 (baseline 14 + 1 for new allKeys)
- `grep -c "List<String> get allKeys" lib/page_creator/assets/elevator.dart` → 1
- `grep -c "children.expand(" lib/page_creator/assets/elevator.dart` → 2 (one in the doc-comment, one in the implementation)

## TDD Gate Compliance

- RED gate: `5617c17 test(03-02): add failing tests for ElevatorConfig.allKeys flat-map override (ELEV-13)` — 3 of 6 new tests failed on the unmodified code path (`one Sensor child surfaces all sensor keys`, `multiple children flat-map all keys, parent first`, `empty positionKey is filtered out`).
- GREEN gate: `555aac5 feat(03-02): override ElevatorConfig.allKeys to flat-map children's keys (ELEV-13, closes Anti-Pattern 6)` — all 6 tests now pass; no Phase-2 or Plan 03-01 regressions.
- REFACTOR gate: not applicable — the GREEN implementation is final-form and the plan does not require a separate refactor commit.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 03-03 (editor add/edit/remove UI for children) can proceed.
- Notable: ELEV-07 / ELEV-08 (editor add/edit/remove UI surfaces) remain deferred to Plan 03-03 as planned.
- The `allKeys` override is now stable and locked by the regression-guard test group, so 03-03's UI mutations to `children` will automatically be reflected in `allKeys` results without further code changes.

## Self-Check: PASSED

Verified before marking complete:
- `lib/page_creator/assets/elevator.dart` exists and contains `List<String> get allKeys` (1 match) and `children.expand(` (2 matches: doc + impl). VERIFIED.
- `test/page_creator/assets/elevator_config_test.dart` exists and contains `'allKeys flat-map (ELEV-13)'` group with 6 tests. VERIFIED.
- Commit `5617c17` (test/RED) present in `git log --oneline`. VERIFIED.
- Commit `555aac5` (feat/GREEN) present in `git log --oneline`. VERIFIED.

---
*Phase: 03-elevator-child-embedding*
*Completed: 2026-05-06*
