---
phase: 11-key-repository-ui
plan: 01
subsystem: ui
tags: [flutter, modbus, widget-test, key-repository, choice-chip, dropdown]

# Dependency graph
requires:
  - phase: 08-config-serialization
    provides: ModbusNodeConfig, ModbusRegisterType, ModbusDataType, ModbusPollGroupConfig, ModbusConfig serialization
  - phase: 10-server-config-ui
    provides: Server config UI patterns, buildTestableServerConfig helper, Modbus poll group config UI
provides:
  - _ModbusConfigSection widget with 5 config fields (server alias, register type, address, data type, poll group)
  - Three-way protocol switching (OPC UA / M2400 / Modbus) via ChoiceChips
  - Data type auto-lock for coil/discreteInput register types
  - Poll group dropdown populated from selected server's ModbusConfig
  - Modbus-aware subtitle, search filter, and collection toggle
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Three-way protocol switching with explicit _isModbus/_isM2400 checks (not binary)"
    - "Data type auto-lock pattern: coil/discreteInput -> bit, switching away resets to uint16"
    - "Poll group dropdown derived from ModbusConfig lookup by selected serverAlias"

key-files:
  created: []
  modified:
    - lib/pages/key_repository.dart
    - test/pages/key_repository_test.dart
    - test/helpers/test_helpers.dart

key-decisions:
  - "Modbus subtitle format: registerType[address] dataType @ serverAlias (compact, scannable)"
  - "Poll group dropdown disabled when no server alias selected, reset to 'default' on server change"
  - "Data type dropdown shows 'Data Type (auto)' label when auto-locked, single 'bit' item, onChanged null"
  - "Test adjusted subtitle assertion to findsNWidgets(2) since both sample keys share same server alias"

patterns-established:
  - "Three-way protocol config rendering: if (_isModbus) ... else if (_isM2400) ... else OPC UA"
  - "_ModbusConfigSection follows _M2400ConfigSection pattern: StatefulWidget with config + aliases + onChanged"

requirements-completed: [UIKY-01, UIKY-02, UIKY-03, UIKY-04, UIKY-05, UIKY-06, TEST-07]

# Metrics
duration: 5min
completed: 2026-03-07
---

# Phase 11 Plan 01: Key Repository Modbus Config Summary

**_ModbusConfigSection with three-way protocol switching, data type auto-lock, and poll group dropdown from server config**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-07T14:00:12Z
- **Completed:** 2026-03-07T14:05:48Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- _ModbusConfigSection widget with all 5 Modbus config fields (server alias, register type, address, data type, poll group)
- Three-way protocol switching via ChoiceChips with correct selected state logic
- Data type auto-locks to bit for coil/discreteInput, resets to uint16 on switch
- Poll group dropdown populated from selected server's ModbusConfig.pollGroups
- modbusNode preserved in _toggleCollect and _updateCollectEntry (bug fix for missing field)
- Search filter extended to include Modbus server alias
- 8 new widget tests covering all Modbus config behaviors

## Task Commits

Each task was committed atomically:

1. **Task 1: Write widget tests for Modbus key repository config (RED)** - `d27c01e` (test)
2. **Task 2: Implement Modbus config section and protocol switching (GREEN)** - `aa3e18e` (feat)

## Files Created/Modified
- `lib/pages/key_repository.dart` - Added _ModbusConfigSection, _isModbus, _switchToModbus, _updateModbusConfig, extended subtitle/search/collect
- `test/pages/key_repository_test.dart` - 8 new Modbus protocol configuration tests
- `test/helpers/test_helpers.dart` - sampleModbusKeyMappings() and sampleStateManConfigWithModbus() helpers

## Decisions Made
- Modbus subtitle format: `holdingRegister[100] float32 @ plc_1` -- compact and scannable
- Poll group dropdown disabled when no server alias selected, reset to 'default' on server change
- Data type auto-locked dropdown shows 'Data Type (auto)' label with single 'bit' item and null onChanged
- FontAwesomeIcons.networkWired icon for Modbus config section header

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed subtitle test assertion for multiple matching keys**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Test expected `findsOneWidget` for '@ plc_1' but both sample Modbus keys share the same server alias
- **Fix:** Changed assertion to `findsNWidgets(2)` since both modbus_temp and modbus_coil have '@ plc_1' in subtitle
- **Files modified:** test/pages/key_repository_test.dart
- **Verification:** Test passes
- **Committed in:** aa3e18e (Task 2 commit)

**2. [Rule 1 - Bug] Fixed poll group dropdown test to scroll and use ancestor finder**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Poll group dropdown not found because it was off-screen and test was tapping wrong DropdownButtonFormField<String>
- **Fix:** Added scrollUntilVisible and ancestor-based finder to locate poll group dropdown specifically
- **Files modified:** test/pages/key_repository_test.dart
- **Verification:** Test passes
- **Committed in:** aa3e18e (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 test assertion fixes)
**Impact on plan:** Both fixes were test-level adjustments, no production code changes. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Modbus config UI complete, ready for Phase 11 Plan 02 (if any remaining)
- All 175 tests pass across full suite (no regressions)
- Key repository now supports all three protocols: OPC UA, M2400, Modbus

---
*Phase: 11-key-repository-ui*
*Completed: 2026-03-07*
