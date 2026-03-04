---
phase: 02-msocket-tcp-layer
plan: 02
subsystem: infra
tags: [tcp, socket, reconnect, backoff, exponential-backoff, dispose, resilience]

# Dependency graph
requires:
  - phase: 02-msocket-tcp-layer plan 01
    provides: "MSocket class with connection loop, BehaviorSubject status, TestTcpServer helper"
provides:
  - "9 reconnect lifecycle tests validating auto-reconnect, backoff timing, and dispose safety"
  - "TestTcpServer tolerant of shutdown() without prior start()"
affects: [03-m2400-framing, 08-resilience]

# Tech tracking
tech-stack:
  added: []
  patterns: [reconnect lifecycle test pattern, backoff timing verification with stopwatch, dispose-during-backoff test pattern]

key-files:
  created: []
  modified:
    - packages/jbtm/test/msocket_test.dart
    - packages/jbtm/test/test_tcp_server.dart

key-decisions:
  - "Plan 01 implementation already contained full reconnect logic; Plan 02 focused on comprehensive test coverage rather than code changes"
  - "Used generous timing tolerances (300-900ms for 500ms backoff, 0.5x-2.0x for cap verification) for CI stability"

patterns-established:
  - "Reconnect test pattern: connect, waitForClient, disconnectAll, wait for reconnect cycle via statusStream"
  - "Backoff timing verification: Stopwatch between disconnected and next connecting event"
  - "Dispose safety test: subscribe to statusStream, dispose, wait, verify no connecting/connected events"

requirements-completed: [TCP-03]

# Metrics
duration: 3min
completed: 2026-03-04
---

# Phase 2 Plan 02: MSocket Auto-Reconnect Tests Summary

**9 reconnect lifecycle and backoff timing tests validating auto-reconnect (500ms initial, 5s cap), backoff reset, data stream continuity, and dispose safety**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-04T12:04:28Z
- **Completed:** 2026-03-04T12:07:57Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- 9 new reconnect and backoff tests covering: auto-reconnect after server disconnect, data stream continuity across reconnects, full status transition cycle, backoff reset after successful reconnect, dispose during backoff, dispose during active connection, unreachable host retry, initial backoff timing (~500ms), and backoff cap at 5s
- Test file grew from 292 to 607 lines (12 to 21 tests total)
- Fixed TestTcpServer.shutdown() to handle uninitialized state gracefully (tests that skip server.start() no longer crash in tearDown)

## Task Commits

Each task was committed atomically:

1. **Task 1: Auto-reconnect with exponential backoff tests** - `cfe9315` (test)

_TDD task: implementation already in place from Plan 01; this plan delivered comprehensive test coverage._

## Files Created/Modified
- `packages/jbtm/test/msocket_test.dart` - Added 'reconnect' group (7 tests) and 'backoff timing' group (2 tests), 315 new lines
- `packages/jbtm/test/test_tcp_server.dart` - Changed `late ServerSocket _server` to `ServerSocket? _server` with null-safe shutdown

## Decisions Made
- **Tests-only plan:** Plan 01's MSocket implementation already contained the full reconnect loop with exponential backoff. Plan 02's value is comprehensive test coverage proving the behavior works correctly across all edge cases (9 tests).
- **Timing tolerances:** Used 300-900ms window for 500ms backoff verification and 8s ceiling for cap verification, avoiding flaky tests on CI.
- **TestTcpServer null-safety:** Changed `late ServerSocket` to nullable `ServerSocket?` so tests that never call `start()` (unreachable host tests) don't crash in tearDown.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed TestTcpServer crash when shutdown() called without start()**
- **Found during:** Task 1 (RED phase)
- **Issue:** Tests that connect to unreachable ports (no server started) crashed in tearDown because `late ServerSocket _server` was never initialized
- **Fix:** Changed `late ServerSocket _server` to `ServerSocket? _server` with null-safe `await _server?.close()` in shutdown()
- **Files modified:** packages/jbtm/test/test_tcp_server.dart
- **Verification:** All 21 tests pass including unreachable-host and backoff-cap tests
- **Committed in:** cfe9315 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary for test infrastructure correctness. No scope creep.

## Issues Encountered
None -- the existing MSocket reconnect implementation from Plan 01 passed all 9 new tests without code changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- MSocket is fully tested for TCP connect, disconnect detection, auto-reconnect with backoff, and dispose safety (21 tests)
- Ready for Phase 3 (M2400 framing layer) which will build on top of MSocket's dataStream
- TestTcpServer is robust enough for reuse in Phase 3 and Phase 4 tests

## Self-Check: PASSED

All 2 modified files exist. Commit cfe9315 verified in git log.

---
*Phase: 02-msocket-tcp-layer*
*Completed: 2026-03-04*
