---
phase: 01-tcp-transport-fixes
plan: 02
subsystem: networking
tags: [modbus-tcp, mbap, concurrency, transaction-id, tcp-pipelining, tdd]

# Dependency graph
requires:
  - phase: 01-tcp-transport-fixes plan 01
    provides: "Local modbus_client_tcp fork with corrected frame parsing, MBAP validation, TCP_NODELAY, keepalive, and ModbusTestServer"
provides:
  - "ModbusClientTcp with concurrent request support via _pendingResponses transaction ID map"
  - "MBAP frame router (_processIncomingBuffer) handling concatenated and partial TCP segments"
  - "13-test suite covering frame parsing, validation, socket options, keepalive, and concurrent transactions"
affects: [modbus-integration, tfc_dart]

# Tech tracking
tech-stack:
  added: []
  patterns: [Transaction ID map for concurrent Modbus TCP requests, MBAP frame router with incoming buffer, Narrowed lock scope (write-only lock)]

key-files:
  created: []
  modified:
    - packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart
    - packages/modbus_client_tcp/test/modbus_client_tcp_test.dart

key-decisions:
  - "MBAP parsing moved to router (_processIncomingBuffer) for multi-response routing; _TcpResponse retains defense-in-depth checks"
  - "Lock scope narrowed to protect only socket write, not response wait -- enables concurrent in-flight requests"
  - "Incoming buffer approach for TCP stream reassembly instead of per-response partial buffering"

patterns-established:
  - "_processIncomingBuffer: loop-based MBAP frame extraction from TCP stream buffer with length validation"
  - "_parseRequests helper in tests: parse concatenated MBAP requests from server-received data"

requirements-completed: [TCPFIX-02, TEST-01]

# Metrics
duration: 6min
completed: 2026-03-06
---

# Phase 1 Plan 2: Concurrent Modbus TCP Requests Summary

**Concurrent request support via transaction ID map with MBAP frame router, narrowed lock scope for pipelining, and concatenated/partial segment handling -- all TDD with 13 passing tests**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-06T13:22:09Z
- **Completed:** 2026-03-06T13:28:25Z
- **Tasks:** 2 (RED + GREEN; REFACTOR not needed)
- **Files modified:** 2

## Accomplishments
- Replaced single `_currentResponse` with `Map<int, _TcpResponse> _pendingResponses` for concurrent request routing
- Narrowed lock scope: socket write inside lock, response wait outside -- enables multiple in-flight requests
- Built MBAP frame router (`_processIncomingBuffer`) that handles concatenated responses (multiple frames in one TCP segment) and partial segments
- Unknown transaction ID responses discarded with warning (no crash, no corruption of other pending requests)
- All 9 existing Plan 01 tests continue to pass (zero regression)
- Added 4 new concurrent transaction tests (13 total)

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- failing tests for concurrent transactions** - `0f10333` (test)
2. **Task 2: GREEN -- implement concurrent support** - `1a9d399` (feat)

_TDD workflow: Task 1 = RED (4 failing tests), Task 2 = GREEN (implementation makes all 13 tests pass). REFACTOR phase evaluated but no changes needed -- defense-in-depth checks retained per plan guidance._

## Files Created/Modified
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart` - Replaced `_currentResponse` with `_pendingResponses` map, narrowed lock scope, added `_incomingBuffer` + `_processIncomingBuffer` MBAP router, updated `disconnect()` to clear state
- `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart` - Added "concurrent requests (TCPFIX-02)" group with 4 tests: out-of-order resolution, unknown transaction ID, concatenated TCP segments, backward compatibility

## Decisions Made
- MBAP frame parsing moved to router level (`_processIncomingBuffer`) for multi-response routing; kept defense-in-depth validation in `_TcpResponse.addResponseData` per plan guidance
- Router signals `requestRxFailed` to pending responses when invalid MBAP length detected (not just discards silently)
- Test server `onData` handlers updated with `_parseRequests` helper to handle concatenated requests from client (two MBAP frames in one TCP segment)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Router must signal failure on invalid MBAP length**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** Router discarded invalid-length frames and cleared buffer but didn't notify the pending response, causing timeout instead of `requestRxFailed`
- **Fix:** Added `pendingResponse.request.setResponseCode(requestRxFailed)` in the invalid-length branch of `_processIncomingBuffer`
- **Files modified:** packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart
- **Verification:** TCPFIX-03 length validation tests pass with `requestRxFailed` (not timeout)
- **Committed in:** 1a9d399 (part of Task 2 commit)

**2. [Rule 1 - Bug] Removed unused variable lint warning**
- **Found during:** Task 2 (dart analyze check)
- **Issue:** `requestCount` variable in "unknown transaction ID" test was declared but never read
- **Fix:** Removed the unused variable
- **Files modified:** packages/modbus_client_tcp/test/modbus_client_tcp_test.dart
- **Verification:** `dart analyze` reports zero issues
- **Committed in:** 1a9d399 (part of Task 2 commit)

**3. [Rule 3 - Blocking] Test server onData must handle concatenated requests**
- **Found during:** Task 2 (GREEN phase -- concurrent tests timing out)
- **Issue:** Test server's onData callback only parsed the first MBAP request from incoming data. When two concurrent client requests arrived concatenated in a single TCP segment, the second request was lost, causing `allRequestsReceived` to never complete.
- **Fix:** Added `_parseRequests` helper that extracts all MBAP requests from a data chunk using the length field for framing. Updated concurrent test onData handlers to use it.
- **Files modified:** packages/modbus_client_tcp/test/modbus_client_tcp_test.dart
- **Verification:** All concurrent tests pass
- **Committed in:** 1a9d399 (part of Task 2 commit)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All auto-fixes necessary for correctness. No scope creep.

## Issues Encountered
None -- deviations handled inline during GREEN phase.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 1 (TCP Transport Fixes) is complete: all 6 requirements addressed (TCPFIX-01 through TCPFIX-05 + TEST-01)
- modbus_client_tcp supports concurrent requests, correct frame parsing, MBAP validation, TCP_NODELAY, and keepalive
- 13 tests cover all fix areas with zero regressions
- Package ready for integration in Phase 5 (Modbus Provider) or Phase 8 (Integration)

## Self-Check: PASSED

All 2 files exist, both commits found (0f10333, 1a9d399), all key patterns verified (`_pendingResponses` map, `_processIncomingBuffer` router, `_incomingBuffer`), 13 tests pass.

---
*Phase: 01-tcp-transport-fixes*
*Completed: 2026-03-06*
