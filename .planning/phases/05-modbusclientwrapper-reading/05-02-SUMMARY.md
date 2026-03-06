---
phase: 05-modbusclientwrapper-reading
plan: 02
subsystem: networking
tags: [modbus-tcp, batch-coalescing, register-grouping, modbus-elements-group, tdd, scada]

# Dependency graph
requires:
  - phase: 05-modbusclientwrapper-reading-plan-01
    provides: "Individual poll-based reads, subscribe/read/unsubscribe API, _PollGroup, _RegisterSubscription, _onPollTick"
provides:
  - "_buildCoalescedGroups algorithm: groups contiguous same-type registers into ModbusElementsGroup batch reads"
  - "Gap handling: 10-register threshold for registers, 100-coil threshold for coils"
  - "Auto-split oversized batches exceeding 125 registers / 2000 coils per Modbus limits"
  - "Dirty flag optimization: _PollGroup._dirty triggers recalculation only on subscription changes"
  - "Batch read via ModbusElementsGroup.getReadRequest() replacing individual element reads"
  - "14 new TDD tests covering coalescing basics, gap handling, auto-split, dirty flag, and value delivery"
affects: [06-modbusclientwrapper-writing, 07-deviceclient-adapter]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "_buildCoalescedGroups: sort by address per type, merge within gap threshold, split at Modbus limits, cache until dirty"
    - "Batch value piping: after all groups read, pipe all subscription values once (shared element references)"
    - "registerOnSend helper in tests: factory for onSend handlers supporting both group and individual read requests"

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart
    - packages/tfc_dart/test/core/modbus_client_wrapper_test.dart

key-decisions:
  - "Gap thresholds: 10 registers / 100 coils -- balances bandwidth waste (20 bytes) vs TCP round-trip savings (~40ms)"
  - "Replace individual reads entirely with batch reads -- ModbusElementsGroup works fine with single elements too"
  - "Pipe all subscription values after ALL groups in a tick are read, not per-group -- simpler, no subscription-to-group matching needed"
  - "Existing Plan 01 tests updated to handle ModbusReadGroupRequest alongside ModbusReadRequest"

patterns-established:
  - "_buildCoalescedGroups: coalescing algorithm for contiguous same-type registers"
  - "Dirty flag pattern: _PollGroup._dirty + _cachedGroups for lazy recalculation"
  - "registerOnSend: test helper factory for dual group/individual request handlers"

requirements-completed: [READ-06]

# Metrics
duration: 19min
completed: 2026-03-06
---

# Phase 5 Plan 2: Batch Coalescing Summary

**Automatic batch coalescing merges contiguous same-type registers into ModbusElementsGroup reads with gap handling (10 reg / 100 coil threshold), auto-split at Modbus limits (125 reg / 2000 coil), and dirty flag optimization -- 69 TDD tests passing**

## Performance

- **Duration:** 19 min
- **Started:** 2026-03-06T17:43:49Z
- **Completed:** 2026-03-06T18:02:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Implemented _buildCoalescedGroups algorithm that groups contiguous same-type registers into batch reads via ModbusElementsGroup
- Gap handling reads through small gaps (10 registers / 100 coils) to reduce TCP round-trips
- Oversized batches automatically split at Modbus protocol limits (125 registers / 2000 coils)
- Dirty flag on _PollGroup prevents unnecessary group recalculation on every poll tick
- Full TDD workflow: 14 tests written first (RED), then implementation (GREEN)
- Updated all 17 existing Plan 01 read tests to support batch read requests

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Write failing tests for batch coalescing** - `611caaa` (test)
2. **Task 2: GREEN -- Implement batch coalescing algorithm** - `74a9f2e` (feat)

_TDD workflow: Task 1 = RED (14 new tests, 13 failing), Task 2 = GREEN (all 69 passing)_

## Files Created/Modified
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - Added _registerGapThreshold/coilGapThreshold constants, _dirty/_cachedGroups to _PollGroup, _buildCoalescedGroups algorithm, replaced _onPollTick individual reads with batch reads via ModbusElementsGroup
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - Updated MockModbusClient default send to handle ModbusReadGroupRequest, added 14 batch coalescing tests (basics, gap handling, auto-split, dirty flag, value delivery), updated 17 existing read tests with group request handlers, added registerOnSend helper factory

## Decisions Made
- Gap thresholds set to 10 registers / 100 coils: reading 10 extra registers wastes 20 bytes vs saving ~40ms TCP round-trip per avoided request
- Replaced individual reads entirely rather than keeping as fallback: ModbusElementsGroup handles single elements correctly, no need for dual paths
- Pipe subscription values after ALL groups in a tick are read (not per-group): simpler implementation, avoids subscription-to-group matching since elements are shared references
- Updated existing Plan 01 tests to handle both ModbusReadGroupRequest and ModbusReadRequest in onSend handlers

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated existing Plan 01 tests for batch read compatibility**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** 17 existing tests' onSend handlers only handled ModbusReadRequest but the wrapper now sends ModbusReadGroupRequest via batch coalescing. Tests failed because element values were never set through group requests.
- **Fix:** Updated all existing read test onSend handlers to also handle ModbusReadGroupRequest by writing data via internalSetElementData. Added registerOnSend helper factory for data type interpretation tests.
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** All 69 tests pass, dart analyze clean
- **Committed in:** 74a9f2e (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 test compatibility bug)
**Impact on plan:** Natural consequence of switching from individual to batch reads. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ModbusClientWrapper reading API is complete (individual reads + batch coalescing)
- Phase 5 complete -- all reading requirements fulfilled (READ-01 through READ-07)
- Phase 6 (writing) can add write methods alongside the existing read API
- Phase 7 (DeviceClient adapter) can wrap subscribe/read streams into DynamicValue

## Self-Check: PASSED

All 2 files exist, both commits found (611caaa, 74a9f2e), 69 tests passing, dart analyze clean.

---
*Phase: 05-modbusclientwrapper-reading*
*Completed: 2026-03-06*
