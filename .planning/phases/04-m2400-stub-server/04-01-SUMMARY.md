---
phase: 04-m2400-stub-server
plan: 01
subsystem: testing
tags: [tcp, m2400, stub-server, tdd, dart]

# Dependency graph
requires:
  - phase: 03-m2400-framing
    provides: M2400FrameParser, parseM2400Frame, M2400RecordType, recordTypeFieldKey
  - phase: 02-msocket-tcp-layer
    provides: MSocket, ConnectionStatus, TestTcpServer
provides:
  - M2400StubServer class wrapping TestTcpServer with M2400 protocol awareness
  - buildM2400Frame() top-level function for STX-framed record construction
  - Record factory functions (makeWeightFields, makeIntroFields, makeStatFields, makeLuaFields)
  - TestTcpServer promoted to lib/src with onConnect callback
  - Malformed data helpers for error-path testing
  - Periodic push and burst mode for scheduling tests
affects: [05-field-catalog-parser, 06-device-connection-manager, 07-state-man-integration, 08-hmi-live-display]

# Tech tracking
tech-stack:
  added: []
  patterns: [composition-wrapper, per-client-socket-write, record-factory-pattern]

key-files:
  created:
    - packages/jbtm/lib/src/m2400_stub_server.dart
    - packages/jbtm/test/m2400_stub_server_test.dart
  modified:
    - packages/jbtm/lib/src/test_tcp_server.dart
    - packages/jbtm/lib/jbtm.dart
    - packages/jbtm/test/msocket_test.dart
    - packages/jbtm/test/m2400_test.dart

key-decisions:
  - "TestTcpServer moved from test/ to lib/src/ for importability by external packages"
  - "onConnect callback on TestTcpServer enables per-client INTRO without broadcast"
  - "utf8.encode used instead of .codeUnits in buildM2400Frame for non-ASCII correctness"
  - "M2400StubServer uses composition (wraps TestTcpServer) not inheritance"
  - "Nullable _server field (not late) so shutdown() is safe before start()"

patterns-established:
  - "Record factory pattern: makeXxxFields() returns Map<String,String> with recordTypeFieldKey set"
  - "Per-client socket write: _sendToSocket for INTRO, _send (broadcast) for everything else"
  - "Stub server composition: M2400StubServer wraps TestTcpServer with onConnect callback"

requirements-completed: [M24-09]

# Metrics
duration: 7min
completed: 2026-03-04
---

# Phase 4 Plan 1: M2400 Stub Server Summary

**M2400StubServer with auto-INTRO, record factories, malformed data helpers, and periodic/burst push modes for TDD infrastructure**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-04T13:19:25Z
- **Completed:** 2026-03-04T13:26:25Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 7

## Accomplishments
- M2400StubServer binds to OS-assigned port, auto-sends INTRO per-client on connect
- Record factories produce valid STX-framed bytes that round-trip through M2400FrameParser + parseM2400Frame
- Malformed data helpers at 4 levels: raw garbage, garbled frame content, unknown record type, missing REC field
- Periodic push (timer-based) and burst mode (rapid-fire) for scheduling tests
- TestTcpServer promoted to lib/src with onConnect callback, importable by external packages
- All 73 tests pass (51 existing + 22 new), zero analysis errors

## Task Commits

Each task was committed atomically (TDD RED-GREEN):

1. **Task 1 RED: Failing tests for M2400StubServer** - `086115b` (test)
2. **Task 1 GREEN: Implement M2400StubServer** - `7a5eda7` (feat)

## Files Created/Modified
- `packages/jbtm/lib/src/m2400_stub_server.dart` - M2400StubServer class, buildM2400Frame, record factories
- `packages/jbtm/lib/src/test_tcp_server.dart` - Moved from test/, added onConnect callback
- `packages/jbtm/lib/jbtm.dart` - Barrel exports for test_tcp_server and m2400_stub_server
- `packages/jbtm/test/m2400_stub_server_test.dart` - 22 tests covering all stub server features
- `packages/jbtm/test/msocket_test.dart` - Updated import to barrel
- `packages/jbtm/test/m2400_test.dart` - Updated import to barrel

## Decisions Made
- TestTcpServer moved from test/ to lib/src/ for importability by external packages (needed for downstream phases)
- onConnect callback on TestTcpServer enables per-client INTRO writes without broadcast
- utf8.encode used instead of .codeUnits in buildM2400Frame for correct non-ASCII handling
- M2400StubServer uses composition (wraps TestTcpServer) not inheritance
- Nullable _server field (not late) so shutdown() is safe when start() was never called

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed shutdown crash when start() never called**
- **Found during:** Task 1 GREEN (buildM2400Frame unit test)
- **Issue:** `late TestTcpServer _server` threw LateInitializationError in tearDown when test never called start()
- **Fix:** Changed to nullable `TestTcpServer? _server` with null-safe shutdown: `await _server?.shutdown()`
- **Files modified:** packages/jbtm/lib/src/m2400_stub_server.dart
- **Verification:** buildM2400Frame test passes without starting stub server
- **Committed in:** 7a5eda7

**2. [Rule 1 - Bug] Fixed sendRawGarbage test receiving auto-INTRO instead of garbage**
- **Found during:** Task 1 GREEN (test verification)
- **Issue:** Test used `socket.dataStream.first` which received auto-INTRO bytes, not the garbage bytes
- **Fix:** Collect all raw data chunks and assert on the second chunk (first is auto-INTRO)
- **Files modified:** packages/jbtm/test/m2400_stub_server_test.dart
- **Verification:** Test correctly validates raw garbage bytes are received
- **Committed in:** 7a5eda7

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes essential for correctness. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- M2400StubServer fully operational as TDD infrastructure for downstream phases
- All record types (WGT, INTRO, STAT, LUA) and malformed data scenarios covered
- TestTcpServer and M2400StubServer importable via `package:jbtm/jbtm.dart`
- Ready for Phase 5 (Field Catalog Parser) which will use stub server for realistic protocol data

---
*Phase: 04-m2400-stub-server*
*Completed: 2026-03-04*
