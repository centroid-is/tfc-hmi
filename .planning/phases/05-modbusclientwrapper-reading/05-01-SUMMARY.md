---
phase: 05-modbusclientwrapper-reading
plan: 01
subsystem: networking
tags: [modbus-tcp, polling, register-reads, behaviorsubject, tdd, timer-periodic, scada]

# Dependency graph
requires:
  - phase: 04-modbusclientwrapper-connection
    provides: "ModbusClientWrapper with connection lifecycle, BehaviorSubject status streaming, factory injection"
provides:
  - "ModbusDataType enum with 9 data types (bit, int16, uint16, int32, uint32, float32, int64, uint64, float64)"
  - "ModbusRegisterSpec immutable config class for register subscription configuration"
  - "Named poll groups with Timer.periodic and configurable intervals"
  - "subscribe/read/unsubscribe API on ModbusClientWrapper"
  - "Connection-lifecycle-tied polling (auto-start on connect, stop on disconnect, resume on reconnect)"
  - "BehaviorSubject<Object?> per-key value streams with SCADA last-known-value preservation"
  - "30 new TDD tests covering all register types, data types, poll lifecycle, failure handling"
affects: [05-modbusclientwrapper-reading-plan-02, 06-modbusclientwrapper-writing, 07-deviceclient-adapter]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Named poll groups with Timer.periodic per group, _pollInProgress guard against concurrent sends"
    - "_createElement factory mapping ModbusDataType to correct ModbusElement subclass"
    - "Connection-lifecycle-tied polling via connectionStream listener"
    - "BehaviorSubject<Object?> per subscription with last-known-value preservation on read failure"

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart
    - packages/tfc_dart/test/core/modbus_client_wrapper_test.dart

key-decisions:
  - "Object? as BehaviorSubject value type -- bool/int/double are all Object; Phase 7 adapter wraps to DynamicValue"
  - "Individual element reads per poll tick (not batch) -- batch coalescing is Plan 02"
  - "Lazy poll group creation -- subscribe() auto-creates default group at 1s interval if not explicitly configured"
  - "ModbusNumRegister returns num (double due to multiplier formula) -- tests expect num not int for numeric registers"
  - "Poll lifecycle listener initialized lazily on first subscribe(), not in constructor"

patterns-established:
  - "ModbusRegisterSpec: immutable config class for register subscription"
  - "subscribe/read/unsubscribe: stream + sync read API for register values"
  - "addPollGroup: named poll groups with independent intervals"
  - "_onPollTick: guarded async poll callback with per-element reads and failure handling"

requirements-completed: [READ-01, READ-02, READ-03, READ-04, READ-05, READ-07]

# Metrics
duration: 15min
completed: 2026-03-06
---

# Phase 5 Plan 1: ModbusClientWrapper Reading Summary

**Poll-based reading of all 4 Modbus register types (coil/discrete input/holding/input) with 9 data types, named poll groups, BehaviorSubject value streams, and SCADA last-known-value preservation -- 55 TDD tests passing**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-06T17:23:32Z
- **Completed:** 2026-03-06T17:39:03Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Extended ModbusClientWrapper with subscribe/read/unsubscribe API for all four Modbus register types
- Implemented ModbusDataType enum (9 types) and ModbusRegisterSpec immutable config class
- Named poll groups with Timer.periodic fire at configurable intervals (default 1s)
- Polling auto-starts on connect, stops on disconnect, resumes on reconnect
- Read failures preserve last-known values in BehaviorSubject (SCADA behavior)
- Full TDD workflow: 30 tests written first (RED), then implementation (GREEN)

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Write failing tests** - `99e080b` (test)
2. **Task 2: GREEN -- Implement poll groups, register reads, and data types** - `ba3995c` (feat)

_TDD workflow: Task 1 = RED (30 new tests, all failing), Task 2 = GREEN (all 55 passing)_

## Files Created/Modified
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - Extended with ModbusDataType, ModbusRegisterSpec, _RegisterSubscription, _PollGroup, subscribe/read/unsubscribe API, poll lifecycle management, _createElement factory
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - Extended MockModbusClient with send()/onSend, added 30 new tests across 10 groups: ModbusRegisterSpec (4), ModbusDataType (1), poll group lifecycle (7), coil reads (2), discrete input reads (1), holding register reads (1), input register reads (1), data type interpretation (9), read failure handling (2), dynamic subscription (2)

## Decisions Made
- Used `Object?` for BehaviorSubject value type -- simplest approach for bool/int/double; Phase 7 adapter wraps to DynamicValue
- Individual element reads per poll tick instead of batch coalescing -- batch optimization deferred to Plan 02
- Lazy poll lifecycle initialization: `_initPollLifecycle()` called on first `subscribe()`, not in constructor
- Poll groups created lazily when referenced by a spec's pollGroup field

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed uint64 test value exceeding Dart int range**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Test used literal `18000000000000000000` which exceeds Dart's 64-bit signed int limit (max 9,223,372,036,854,775,807)
- **Fix:** Changed test value to `4000000000` which fits in uint64 range but exceeds int32 range
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** All tests pass, dart analyze clean
- **Committed in:** ba3995c (Task 2 commit)

**2. [Rule 1 - Bug] Fixed test expectations for ModbusNumRegister value types**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Tests expected integer register types to return `int`, but ModbusNumRegister.setValueFromBytes applies `* multiplier + offset` formula where multiplier is `double`, converting result to `double`/`num`
- **Fix:** Changed holding register and input register tests to expect `num` instead of `int`, and adjusted equality comparisons
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** All 55 tests pass
- **Committed in:** ba3995c (Task 2 commit)

**3. [Rule 1 - Bug] Fixed dispose test expecting emitsDone on BehaviorSubject stream**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Test used `emitsDone` on a BehaviorSubject value stream, but BehaviorSubject replays its last value to new subscribers before done, causing matcher mismatch
- **Fix:** Changed test to use a listener collecting events and checking `isDone` flag after dispose
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** All 55 tests pass
- **Committed in:** ba3995c (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 test assertion bugs)
**Impact on plan:** All fixes are test assertion corrections matching actual library behavior. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ModbusClientWrapper reading API is complete for Plan 01 (individual reads)
- Plan 02 can add batch coalescing via ModbusElementsGroup on top of this infrastructure
- Phase 6 (writing) can add write methods alongside the existing read API
- Phase 7 (DeviceClient adapter) can wrap subscribe/read streams into DynamicValue

## Self-Check: PASSED

All 2 files exist, both commits found (99e080b, ba3995c), 55 tests passing, dart analyze clean.

---
*Phase: 05-modbusclientwrapper-reading*
*Completed: 2026-03-06*
