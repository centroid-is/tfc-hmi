---
phase: 06-modbusclientwrapper-writing
plan: 01
subsystem: modbus
tags: [modbus, tcp, write, FC05, FC06, FC15, FC16, scada, tdd]

# Dependency graph
requires:
  - phase: 04-modbusclientwrapper-connection
    provides: ModbusClientWrapper connection lifecycle, MockModbusClient, _createElement factory
  - phase: 05-modbusclientwrapper-reading
    provides: _subscriptions map, BehaviorSubject value streams, poll infrastructure
provides:
  - "write() method for single coil (FC05), single register (FC06), and auto-FC16 multi-register writes"
  - "writeMultiple() method for FC15 multi-coil and FC16 multi-register array writes"
  - "_validateWriteAccess() shared validation for disposed/disconnected/read-only checks"
affects: [07-deviceclient-adapter, 09-stateman-integration]

# Tech tracking
tech-stack:
  added: [dart:typed_data]
  patterns: [spec-based write API, optimistic BehaviorSubject update, shared validation extraction]

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart
    - packages/tfc_dart/test/core/modbus_client_wrapper_test.dart

key-decisions:
  - "Spec-based write API (not key-based) -- write-only registers may never be subscribed, spec carries all metadata"
  - "Shared _validateWriteAccess() extracts disposed/connected/read-only checks used by both write() and writeMultiple()"
  - "Optimistic BehaviorSubject update after successful write -- immediate UI feedback vs waiting for next poll tick"
  - "No write concurrency serialization -- Modbus TCP transport handles concurrent transactions via transaction IDs"

patterns-established:
  - "_validateWriteAccess pattern: check disposed -> check connected -> check read-only type, reusable for any gated operation"
  - "Write-without-subscribe: write() works for keys with no active subscription, enabling write-only control outputs"

requirements-completed: [WRIT-01, WRIT-02, WRIT-03, WRIT-04, WRIT-05]

# Metrics
duration: 6min
completed: 2026-03-06
---

# Phase 6 Plan 01: ModbusClientWrapper Writing Summary

**write() and writeMultiple() methods with SCADA-safe connection gating, read-only type rejection, and optimistic BehaviorSubject updates**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-06T19:27:09Z
- **Completed:** 2026-03-06T19:33:03Z
- **Tasks:** 1 (TDD: red-green-refactor)
- **Files modified:** 2

## Accomplishments
- write() handles FC05 (coil bool), FC06 (uint16/int16), and auto-FC16 (float32, int32, etc.)
- writeMultiple() handles FC15 (coils with explicit quantity) and FC16 (registers with raw bytes)
- SCADA-safe error handling: immediate rejection when disconnected (no write queuing), clear errors for read-only types
- Optimistic BehaviorSubject update after successful write for subscribed keys
- All 87 tests pass (69 existing + 18 new write tests)

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: TDD failing write tests** - `ae86b86` (test)
2. **Task 1 GREEN: Implement write and writeMultiple** - `bb10ffa` (feat)

_TDD task: test commit (RED) followed by implementation commit (GREEN). Refactoring was done inline during GREEN phase (_validateWriteAccess extraction)._

## Files Created/Modified
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - Added write(), writeMultiple(), _validateWriteAccess() methods with dart:typed_data import
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - Added 18 write tests in 7 sub-groups covering all WRIT requirements

## Decisions Made
- Spec-based write API: write(ModbusRegisterSpec, Object?) rather than key-based, because write-only registers may never be subscribed and the spec carries all metadata needed to construct elements
- Extracted _validateWriteAccess() for shared validation between write() and writeMultiple() -- DRY without over-abstracting
- Optimistic BehaviorSubject update chosen over wait-for-poll or read-after-write: write already succeeded on device, avoids 1-second stale window
- No write concurrency lock at wrapper level: Modbus TCP transport already handles concurrent transactions via transaction IDs (Phase 1 work)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed test tearDown pattern for write tests**
- **Found during:** Task 1 GREEN phase
- **Issue:** Write tests used destructured `final (:wrapper, :mock)` which created local variables shadowing the outer `late wrapper` needed by tearDown
- **Fix:** Changed to `final pair = createWrapperWithMock(); wrapper = pair.wrapper;` pattern matching existing read tests
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** All 87 tests pass
- **Committed in:** bb10ffa (GREEN commit)

**2. [Rule 1 - Bug] Fixed unused variable warning**
- **Found during:** Task 1 GREEN phase (dart analyze)
- **Issue:** `final stream = wrapper.subscribe(spec)` unused in optimistic update test
- **Fix:** Changed to `wrapper.subscribe(spec)` (return value not needed)
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** dart analyze shows no new warnings from this plan's changes
- **Committed in:** bb10ffa (GREEN commit)

---

**Total deviations:** 2 auto-fixed (2 bug fixes)
**Impact on plan:** Both fixes necessary for test correctness and clean analysis. No scope creep.

## Issues Encountered
None -- plan executed cleanly. TDD red-green cycle worked as expected.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ModbusClientWrapper now has full read/write capability
- Ready for Phase 7 (DeviceClient adapter) which will wrap write(spec, value) as DeviceClient.write(key, DynamicValue)
- All WRIT requirements fulfilled (WRIT-01 through WRIT-05)

---
*Phase: 06-modbusclientwrapper-writing*
*Completed: 2026-03-06*
