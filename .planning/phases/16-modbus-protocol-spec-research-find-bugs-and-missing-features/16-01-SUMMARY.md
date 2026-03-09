---
phase: 16-modbus-protocol-spec-research-find-bugs-and-missing-features
plan: 01
subsystem: protocol
tags: [modbus, validation, defense-in-depth, spec-compliance]

# Dependency graph
requires:
  - phase: 01-tcp-transport-fixes
    provides: MBAP frame parsing, _TcpResponse validation structure
  - phase: 02-fc15-coil-write-fix
    provides: getMultipleWriteRequest with quantity parameter
provides:
  - Response byte count validation for single-element reads
  - Unit ID validation in MBAP response header
  - Write quantity limit assertions per Modbus spec
affects: [modbus-client-wrapper, stateman-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [expectedResponseByteCount getter pattern for per-request-type validation]

key-files:
  created:
    - packages/modbus_client/test/modbus_write_limits_test.dart
  modified:
    - packages/modbus_client/lib/src/modbus_request.dart
    - packages/modbus_client/lib/src/modbus_element.dart
    - packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart
    - packages/modbus_client_tcp/test/modbus_client_tcp_test.dart

key-decisions:
  - "expectedResponseByteCount as nullable getter on ModbusElementRequest -- null means skip validation (used by group requests)"
  - "Unit ID validation inside header parsing block (fires once, not on every addResponseData call)"
  - "Write limit assertions (not exceptions) -- fail-fast in debug, zero cost in release"

patterns-established:
  - "Per-request-type validation via overridable getters on base request class"
  - "Defense-in-depth checks at _TcpResponse level (unit ID, transaction ID, protocol ID, length)"

requirements-completed: [BUG-02, BUG-03, BUG-05]

# Metrics
duration: 6min
completed: 2026-03-09
---

# Phase 16 Plan 01: Library Protocol Compliance Summary

**Response byte count validation, MBAP unit ID checks, and write quantity limit assertions per Modbus spec**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-09T10:45:01Z
- **Completed:** 2026-03-09T10:51:01Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Malformed read responses with wrong byte count are now rejected (returns requestRxFailed instead of silently accepting corrupt data)
- MBAP response unit ID validated against request unit ID (defense against cross-device response routing errors)
- Write quantity limits enforced: FC16 max 123 registers, FC15 max 1968 coils, byte count field max 246

## Task Commits

Each task was committed atomically:

1. **Task 1: Add response byte count and unit ID validation (BUG-02 + BUG-03)** - `6cfb85d` (test), `ea1626f` (feat)
2. **Task 2: Add write quantity limit assertions (BUG-05)** - `749dac0` (test), `0fb4c1c` (feat)

_TDD tasks each have RED (test) and GREEN (feat) commits._

## Files Created/Modified
- `packages/modbus_client/lib/src/modbus_request.dart` - Added expectedResponseByteCount getter on ModbusElementRequest, byte count validation in internalSetFromPduResponse for read responses
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart` - Added unit ID field to _TcpResponse, validation of MBAP byte 6 against expected unit ID
- `packages/modbus_client/lib/src/modbus_element.dart` - Added assert checks in getMultipleWriteRequest for FC16 (123 reg), FC15 (1968 coil), and byte count (246) limits
- `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart` - 6 new tests for BUG-02 and BUG-03; fixed existing tests to use correct byte counts
- `packages/modbus_client/test/modbus_write_limits_test.dart` - 6 new tests for BUG-05 write limits

## Decisions Made
- Used `expectedResponseByteCount` as a nullable getter (returns null for group requests to skip validation) rather than a separate flag -- cleaner API, zero risk of false positives on batch reads
- Placed unit ID check inside the header parsing block rather than as a separate check after it -- ensures single execution, no redundant checks on partial data
- Used `assert()` for write limits instead of throwing exceptions -- zero overhead in release builds, fail-fast in debug/test, consistent with existing quantity assertion

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed existing test response byte counts**
- **Found during:** Task 1 (GREEN phase)
- **Issue:** Existing TCPFIX-01 tests sent 3 registers (byte count=6) but used ModbusUint16Register (byteCount=2), which the new validation correctly rejected
- **Fix:** Updated test server responses to send 1 register (byte count=2) matching the element type; changed max-length test to use _Fc03RawRequest (bypasses element validation)
- **Files modified:** packages/modbus_client_tcp/test/modbus_client_tcp_test.dart
- **Verification:** All 23 TCP tests pass
- **Committed in:** ea1626f (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug in tests)
**Impact on plan:** Test data correction was required for correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Library-level protocol compliance hardened for BUG-02, BUG-03, BUG-05
- Remaining research items from 16-RESEARCH.md can proceed independently

## Self-Check: PASSED

All 5 created/modified files verified present. All 4 task commits verified in git log.

---
*Phase: 16-modbus-protocol-spec-research-find-bugs-and-missing-features*
*Completed: 2026-03-09*
