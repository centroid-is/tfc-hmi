---
phase: 04-fix-gate-architecture-and-redesign-painters
plan: 01
subsystem: data-model
tags: [json_serializable, dart, conveyor-gate, backward-compat, migration]

# Dependency graph
requires:
  - phase: 03-child-of-conveyor-integration
    provides: ConveyorConfig.gates list and ConveyorGateConfig.position field
provides:
  - ChildGateEntry wrapper class with position, side, and gate fields
  - ConveyorConfig.gates typed as List<ChildGateEntry>
  - Backward-compatible _gatesFromJson migration for old JSON format
  - Clean separation of conveyor placement metadata from gate config
affects: [04-02, 04-03, conveyor-widget, config-dialog]

# Tech tracking
tech-stack:
  added: []
  patterns: [ChildGateEntry wrapper pattern for conveyor-specific placement metadata]

key-files:
  created: []
  modified:
    - lib/page_creator/assets/conveyor_gate.dart
    - lib/page_creator/assets/conveyor.dart
    - lib/page_creator/assets/conveyor_gate.g.dart
    - lib/page_creator/assets/conveyor.g.dart
    - test/page_creator/assets/conveyor_gate_test.dart
    - test/page_creator/assets/conveyor_config_gate_test.dart

key-decisions:
  - "ChildGateEntry uses @JsonKey(fromJson/toJson) helpers for nested gate, not @JsonSerializable on ConveyorGateConfig directly"
  - "Backward compat migration detects old format via asset_name key presence without gate sub-object"
  - "Belt Position slider removed from standalone gate config editor (position now on ChildGateEntry only)"

patterns-established:
  - "ChildGateEntry wrapper: conveyor placement metadata (position, side) lives on wrapper, not on gate config"
  - "Migration helper pattern: _gatesFromJson checks for old format marker (asset_name without gate key) and extracts fields"

requirements-completed: []

# Metrics
duration: 6min
completed: 2026-03-07
---

# Phase 04 Plan 01: ChildGateEntry Wrapper and Data Model Migration Summary

**ChildGateEntry wrapper class separating conveyor placement metadata from ConveyorGateConfig, with backward-compatible JSON deserialization for old flat-gate format**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-07T19:37:22Z
- **Completed:** 2026-03-07T19:43:24Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created ChildGateEntry class with position (double), side (GateSide), and gate (ConveyorGateConfig) fields
- Removed position field from ConveyorGateConfig, keeping side for standalone painter orientation
- Changed ConveyorConfig.gates from List<Asset> with @AssetListConverter to List<ChildGateEntry> with custom fromJson/toJson
- Added backward-compatible _gatesFromJson that handles both old flat-gate JSON and new wrapped format
- Updated conveyor widget and config dialog to use ChildGateEntry
- 47 tests passing across both test files including backward compatibility tests

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ChildGateEntry and migrate data models** - `f7e1a14` (feat)
2. **Task 2: Update serialization tests for ChildGateEntry and backward compat** - `93800c0` (test)

## Files Created/Modified
- `lib/page_creator/assets/conveyor_gate.dart` - Added ChildGateEntry class, removed position from ConveyorGateConfig, removed Belt Position slider from config editor
- `lib/page_creator/assets/conveyor.dart` - Changed gates to List<ChildGateEntry>, added _gatesFromJson/_gatesToJson migration helpers, updated config dialog and widget
- `lib/page_creator/assets/conveyor_gate.g.dart` - Regenerated: ChildGateEntry serialization, ConveyorGateConfig without position
- `lib/page_creator/assets/conveyor.g.dart` - Regenerated: uses _gatesFromJson/_gatesToJson instead of AssetListConverter
- `test/page_creator/assets/conveyor_gate_test.dart` - Replaced position field tests with ChildGateEntry tests, updated gates list tests, added backward compat tests
- `test/page_creator/assets/conveyor_config_gate_test.dart` - Updated all gate management tests to use ChildGateEntry wrapper

## Decisions Made
- ChildGateEntry uses @JsonKey(fromJson/toJson) helpers for the nested gate field to keep serialization clean
- Backward compatibility migration detects old format by checking for `asset_name` key without a `gate` sub-object
- Belt Position slider removed from standalone gate config editor since position is now conveyor-specific metadata on ChildGateEntry
- Side field kept on ConveyorGateConfig for standalone painter orientation, duplicated on ChildGateEntry for conveyor context

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Updated conveyor widget _positionedChildGate to use ChildGateEntry**
- **Found during:** Task 1 (data model migration)
- **Issue:** The Conveyor widget's build method and _positionedChildGate referenced ConveyorGateConfig.position and gates.whereType<ConveyorGateConfig>()
- **Fix:** Updated to use ChildGateEntry directly, reading position and side from entry, passing entry.gate to ConveyorGate widget
- **Files modified:** lib/page_creator/assets/conveyor.dart
- **Verification:** flutter analyze lib/ passes with no errors
- **Committed in:** f7e1a14 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Essential for compilation. The plan noted this task "intentionally breaks the conveyor widget" but fixing it inline was necessary for the analyze step to pass.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ChildGateEntry data model is clean and all serialization tests pass
- Plan 02 can proceed with widget composition updates (if any remain)
- Plan 03 can proceed with painter redesign using the clean data model

---
*Phase: 04-fix-gate-architecture-and-redesign-painters*
*Completed: 2026-03-07*

## Self-Check: PASSED
- All 6 source/test files exist
- Both task commits verified (f7e1a14, 93800c0)
- 04-01-SUMMARY.md exists
