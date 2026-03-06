---
phase: 04-modbusclientwrapper-connection
plan: 01
subsystem: networking
tags: [modbus-tcp, connection-lifecycle, reconnect, backoff, rxdart, behaviorsubject, tdd]

# Dependency graph
requires:
  - phase: 01-tcp-transport-fixes
    provides: "Local modbus_client_tcp package with corrected frame parsing and keepalive"
provides:
  - "ModbusClientWrapper with persistent connection lifecycle (connect/disconnect/dispose)"
  - "Auto-reconnect with exponential backoff (500ms initial, 5s max)"
  - "BehaviorSubject<ConnectionStatus> status streaming with replay"
  - "Factory injection for ModbusClientTcp enabling mock-based testing"
  - "25-test TDD suite covering all connection lifecycle behaviors"
affects: [05-modbusclientwrapper-reading, 06-modbusclientwrapper-writing, 07-deviceclient-adapter]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ModbusClientWrapper connection loop pattern (MSocket-derived)"
    - "Factory injection for ModbusClientTcp testability"
    - "MockModbusClient extending ModbusClientTcp for unit testing"
    - "Poll-based disconnect detection (250ms isConnected check)"

key-files:
  created:
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart
    - packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
  modified: []

key-decisions:
  - "Own connection loop with doNotConnect mode -- ModbusClientTcp autoConnectAndKeepConnected has no status stream or backoff control"
  - "Poll isConnected every 250ms for disconnect detection -- simpler than hooking into ModbusClientTcp socket internals"
  - "TCP keepalive only (no app-level health probe) -- keepalive already configured at 5s/2s/3 probes from Phase 1"
  - "MockModbusClient (extends ModbusClientTcp) for unit tests -- no real TCP needed for connection lifecycle testing"

patterns-established:
  - "ModbusClientWrapper: connect/disconnect/dispose lifecycle with BehaviorSubject status streaming"
  - "MockModbusClient: controllable mock for Modbus connection testing via factory injection"

requirements-completed: [CONN-01, CONN-02, CONN-03, CONN-05, TEST-03]

# Metrics
duration: 10min
completed: 2026-03-06
---

# Phase 4 Plan 1: ModbusClientWrapper Connection Lifecycle Summary

**ModbusClientWrapper with auto-reconnect (500ms/5s exponential backoff), BehaviorSubject status streaming, and dual lifecycle (disconnect/dispose) -- 25 TDD tests passing**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-06T15:31:47Z
- **Completed:** 2026-03-06T15:42:33Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created ModbusClientWrapper with persistent connection lifecycle wrapping ModbusClientTcp
- Implemented auto-reconnect loop with exponential backoff (500ms initial, 5s max, reset on success, retry forever)
- BehaviorSubject<ConnectionStatus> streams status with replay to new subscribers
- Factory injection pattern enables clean unit testing with MockModbusClient
- Dual lifecycle: disconnect() stops loop but keeps streams alive for reuse; dispose() is terminal
- Full TDD workflow: 25 test cases written first (RED), then implementation (GREEN)

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Write failing tests** - `832728b` (test)
2. **Task 2: GREEN -- Implement ModbusClientWrapper** - `3d47511` (feat)

_TDD workflow: Task 1 = RED (25 tests, 19 failing), Task 2 = GREEN (all 25 passing)_

## Files Created/Modified
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - Connection lifecycle wrapper around ModbusClientTcp with auto-reconnect, status streaming, factory injection
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - 25 unit tests: constructor (3), connect (5), disconnect detection (2), reconnect with backoff (5), disconnect() (4), dispose() (3), multiple instances (3)

## Decisions Made
- Used `connectionMode: ModbusConnectionMode.doNotConnect` so the wrapper owns the entire connection loop, not the built-in auto-connect
- Poll `isConnected` every 250ms for disconnect detection rather than trying to hook into ModbusClientTcp's internal socket listener (breaks encapsulation)
- TCP keepalive only for dead connection detection (5s/2s/3 probes from Phase 1) -- no app-level health read needed at this stage
- MockModbusClient extends ModbusClientTcp rather than using Mockito/Mocktail -- simpler, matches M2400ClientWrapper test pattern
- Log + status transition on errors (no wrapper-specific exception types) -- matches MSocket and M2400ClientWrapper patterns

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed dispose() test assertion for BehaviorSubject behavior**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Test expected `emitsDone` immediately after dispose, but BehaviorSubject replays its last value to new subscribers before the done event
- **Fix:** Changed test to expect `emitsInOrder([ConnectionStatus.disconnected, emitsDone])` to match actual BehaviorSubject semantics
- **Files modified:** packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
- **Verification:** All 25 tests pass
- **Committed in:** 3d47511 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (test assertion correction)
**Impact on plan:** Trivial test fix matching BehaviorSubject replay semantics. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ModbusClientWrapper is ready for Phase 5 (reading) to add read operations on top of the connection lifecycle
- Factory injection pattern is established for testing -- Phase 5 can extend MockModbusClient with send() behavior
- `client` getter exposes the underlying ModbusClientTcp for Phase 5/6 to call send() on
- Existing tfc_dart tests unaffected (182 passing, pre-existing integration test failures unchanged)

## Self-Check: PASSED

All 2 files exist, both commits found (832728b, 3d47511), 25 tests passing, dart analyze clean.

---
*Phase: 04-modbusclientwrapper-connection*
*Completed: 2026-03-06*
