---
phase: 03-child-of-conveyor-integration
plan: 01
subsystem: data-model
tags: [json_serializable, build_runner, AssetListConverter, serialization]

# Dependency graph
requires:
  - phase: 02-full-feature-set
    provides: ConveyorGateConfig with all gate fields (variant, side, force keys, timing, colors)
provides:
  - position field on ConveyorGateConfig (double, default 0.5, JSON roundtrip)
  - gates list on ConveyorConfig (@AssetListConverter, polymorphic serialization)
  - backward-compatible deserialization for both new fields
affects: [03-02, conveyor-widget, conveyor-config-dialog]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@AssetListConverter() List<Asset> for child asset lists (same as BeckhoffEK1100Config)"
    - "List.of() in constructor to ensure mutable list from const deserialization defaults"

key-files:
  created: []
  modified:
    - lib/page_creator/assets/conveyor_gate.dart
    - lib/page_creator/assets/conveyor_gate.g.dart
    - lib/page_creator/assets/conveyor.dart
    - lib/page_creator/assets/conveyor.g.dart
    - test/page_creator/assets/conveyor_gate_test.dart

key-decisions:
  - "List.of(gates) in ConveyorConfig constructor to prevent unmodifiable list from generated const [] defaults"

patterns-established:
  - "Child asset list via @AssetListConverter with nullable constructor param and List.of() for mutability"

requirements-completed: [CHILD-01, CHILD-02]

# Metrics
duration: 3min
completed: 2026-03-07
---

# Phase 3 Plan 1: Data Model Fields Summary

**ConveyorGateConfig.position (double, default 0.5) and ConveyorConfig.gates (@AssetListConverter List<Asset>) with full JSON roundtrip and backward compatibility**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-07T16:03:36Z
- **Completed:** 2026-03-07T16:06:30Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 5

## Accomplishments
- Added `position` field (double, 0.0-1.0, default 0.5) to ConveyorGateConfig for belt placement fraction
- Added `gates` field (List<Asset> with @AssetListConverter) to ConveyorConfig for child gate serialization
- Both fields are backward compatible: missing field in JSON yields default value
- 7 new unit tests covering roundtrip, preview defaults, backward compat, and multi-gate serialization
- All 38 tests pass (31 existing + 7 new)

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Failing tests for position and gates** - `6f49166` (test)
2. **Task 1 GREEN: Implement position field and gates list** - `384210d` (feat)

_TDD task: test-first then implementation._

## Files Created/Modified
- `lib/page_creator/assets/conveyor_gate.dart` - Added `double position` field with default 0.5
- `lib/page_creator/assets/conveyor_gate.g.dart` - Regenerated for position field serialization
- `lib/page_creator/assets/conveyor.dart` - Added `@AssetListConverter() List<Asset> gates` field, import for page.dart
- `lib/page_creator/assets/conveyor.g.dart` - Regenerated for gates list serialization
- `test/page_creator/assets/conveyor_gate_test.dart` - Added 7 tests in 2 new groups

## Decisions Made
- Used `List.of(gates)` in ConveyorConfig constructor instead of direct assignment to ensure mutable list even when build_runner generates `const []` as the null default

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed unmodifiable list from const [] default in generated code**
- **Found during:** Task 1 GREEN (implementation)
- **Issue:** Using `this.gates = const []` in constructor made the list unmodifiable. The generated `_$ConveyorConfigFromJson` passes `const []` when JSON has no `gates` field, producing a list that throws on `.add()`.
- **Fix:** Changed constructor to `List<Asset>? gates`) : gates = gates != null ? List<Asset>.of(gates) : []` to always produce a mutable list
- **Files modified:** lib/page_creator/assets/conveyor.dart
- **Verification:** All tests pass including ones that call `.add()` on deserialized configs
- **Committed in:** 384210d

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for correctness -- without it, deserialized conveyors would crash when adding gates. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviation above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Data model fields ready for Plan 02 (conveyor config dialog gate management, widget composition, visual positioning)
- ConveyorGateConfig.position available for belt placement slider in gate config editor
- ConveyorConfig.gates available for child gate list management in conveyor config dialog

---
*Phase: 03-child-of-conveyor-integration*
*Completed: 2026-03-07*
