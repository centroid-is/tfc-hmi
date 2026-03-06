---
phase: 01-tcp-transport-fixes
plan: 01
subsystem: networking
tags: [modbus-tcp, mbap, tcp-nodelay, keepalive, socket, tdd]

# Dependency graph
requires: []
provides:
  - "Local modbus_client_tcp package with corrected frame parsing, MBAP validation, TCP_NODELAY, and keepalive"
  - "ModbusTestServer mock server for Modbus TCP unit tests"
  - "9-test suite covering frame parsing, validation, socket options, keepalive"
affects: [02-tcp-transport-fixes, modbus-integration]

# Tech tracking
tech-stack:
  added: [modbus_client_tcp (local fork)]
  patterns: [ModbusTestServer for Modbus TCP testing, MBAP frame builder helpers]

key-files:
  created:
    - packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart
    - packages/modbus_client_tcp/test/modbus_client_tcp_test.dart
    - packages/modbus_client_tcp/test/modbus_test_server.dart
    - packages/modbus_client_tcp/pubspec.yaml
    - packages/modbus_client_tcp/lib/modbus_client_tcp.dart
  modified:
    - packages/tfc_dart/pubspec.yaml

key-decisions:
  - "Forked modbus_client_tcp from pub cache into packages/ for proper version control and TDD workflow"
  - "MBAP length upper bound set to 254 per Modbus spec (1 unit ID + 253 max PDU), not 256"
  - "keepAliveIdle defaults to 5s and keepAliveInterval to 2s to match MSocket values"

patterns-established:
  - "ModbusTestServer: bind to loopback, OS-assigned port, onData callback for crafting responses"
  - "MBAP frame builders: buildResponse() and buildRawFrame() for testing valid and malformed frames"

requirements-completed: [TCPFIX-01, TCPFIX-03, TCPFIX-04, TCPFIX-05, TEST-01]

# Metrics
duration: 5min
completed: 2026-03-06
---

# Phase 1 Plan 1: TCP Transport Fixes Summary

**Fixed Modbus TCP frame parsing (+6 MBAP offset), added MBAP length validation (1-254), TCP_NODELAY, and separate keepalive idle/interval (5s/2s/3) matching MSocket -- all TDD with 9 passing tests**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-06T13:13:38Z
- **Completed:** 2026-03-06T13:19:01Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Forked modbus_client_tcp into packages/ with path dependency in tfc_dart
- Fixed off-by-6 frame length bug that caused partial responses to be treated as complete (TCPFIX-01)
- Added MBAP length field validation rejecting 0 and >254 (TCPFIX-03)
- Enabled TCP_NODELAY after socket connect to eliminate Nagle latency (TCPFIX-04)
- Separated keepAliveIdle (5s) from keepAliveInterval (2s) to match MSocket defaults (TCPFIX-05)
- Built ModbusTestServer with MBAP frame builder helpers for crafting test responses
- Wrote 9 unit tests covering frame parsing (including split segments and byte-at-a-time), length validation, TCP_NODELAY smoke test, and keepalive API/defaults

## Task Commits

Each task was committed atomically:

1. **Task 1: Fork modbus_client_tcp and build test infrastructure** - `53b7214` (test)
2. **Task 2: Implement TCPFIX-01, TCPFIX-03, TCPFIX-04, TCPFIX-05** - `835635e` (feat)

_TDD workflow: Task 1 = RED (failing tests), Task 2 = GREEN (fixes applied, tests pass)_

## Files Created/Modified
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart` - Fixed frame parsing, added validation, TCP_NODELAY, separated keepalive params
- `packages/modbus_client_tcp/lib/modbus_client_tcp.dart` - Barrel export (unchanged from upstream)
- `packages/modbus_client_tcp/pubspec.yaml` - Package definition with test dependency
- `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart` - 9 unit tests across 4 groups
- `packages/modbus_client_tcp/test/modbus_test_server.dart` - Mock Modbus TCP server with MBAP helpers
- `packages/modbus_client_tcp/CHANGELOG.md` - Upstream changelog preserved
- `packages/modbus_client_tcp/LICENSE` - BSD-3 license preserved
- `packages/modbus_client_tcp/analysis_options.yaml` - Lint configuration preserved
- `packages/tfc_dart/pubspec.yaml` - Added modbus_client_tcp path dependency

## Decisions Made
- Forked from pub cache into packages/ instead of maintaining git dependency -- enables proper TDD and version control
- Used 254 as MBAP length upper bound (per Modbus spec: 1 unit ID + 253 max PDU) rather than 256
- Default keepAliveIdle = 5s, keepAliveInterval = 2s, keepAliveCount = 3 to match MSocket values for ~11s dead connection detection

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed unused import and missing curly braces lint warnings**
- **Found during:** Task 2 (after applying fixes)
- **Issue:** dart:io import unused in test file; curly braces missing on if-return in _enableKeepAlive
- **Fix:** Removed unused import, added curly braces
- **Files modified:** test/modbus_client_tcp_test.dart, lib/src/modbus_client_tcp.dart
- **Verification:** `dart analyze` reports zero issues
- **Committed in:** 835635e (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (lint cleanup)
**Impact on plan:** Trivial lint fix. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- modbus_client_tcp is a local package ready for Plan 02 (concurrent request support via transaction ID map)
- ModbusTestServer is reusable for additional tests in Plan 02
- tfc_dart resolves correctly with the path dependency

## Self-Check: PASSED

All 7 files exist, both commits found, all 4 fix patterns verified in source, path dependency confirmed.

---
*Phase: 01-tcp-transport-fixes*
*Completed: 2026-03-06*
