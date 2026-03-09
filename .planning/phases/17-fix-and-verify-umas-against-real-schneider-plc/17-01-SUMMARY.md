---
phase: 17-fix-and-verify-umas-against-real-schneider-plc
plan: 01
subsystem: protocol
tags: [umas, schneider, fc90, modbus, plc4x, pagination, wire-format]

# Dependency graph
requires:
  - phase: 14-umas-protocol-support-schneider-browse-via-fc90
    provides: "Initial UmasClient, UmasRequest, umas_types, stub server, e2e tests"
provides:
  - "Corrected UmasClient with readPlcId(), 13-byte 0x26 payload, pagination"
  - "UmasPlcIdent type for hardware identification"
  - "UmasDataTypeRef with classIdentifier and dataType fields"
  - "Updated stub server matching PLC4X mspec wire format"
  - "Updated e2e tests for readPlcId -> init -> DD03 -> DD02 browse sequence"
affects: [17-02, umas-live-test, key-repository-umas-browse]

# Tech tracking
tech-stack:
  added: []
  patterns: [offset-based-pagination, plc4x-mspec-wire-format, tdd-red-green]

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/umas_client.dart
    - packages/tfc_dart/lib/core/umas_types.dart
    - packages/tfc_dart/test/core/umas_client_test.dart
    - test/umas_stub_server.py
    - packages/tfc_dart/test/umas_e2e_test.dart

key-decisions:
  - "MockUmasSender uses response queues (List per subFunc) for pagination testing instead of single canned response"
  - "Data type IDs assigned sequentially as 100+i from DD03 record order -- real PLC IDs come from dictionary ordering"
  - "Null-terminated strings: parse stringLength bytes then strip trailing 0x00 bytes for safe handling"
  - "DD02 pagination via offset field (blockNo=0xFFFF, offset=nextAddress); DD03 pagination via blockNo field (blockNo=nextAddress, offset=0x0000)"

patterns-established:
  - "PLC4X mspec as authoritative wire format reference for UMAS protocol"
  - "Pagination loop: while (offset != 0 || firstMessage) for data dictionary reads"
  - "Response header parsing before records: range + nextAddress + unknown + noOfRecords"

requirements-completed: [FIX-01, FIX-02, FIX-03, FIX-04, FIX-05, FIX-06]

# Metrics
duration: 10min
completed: 2026-03-09
---

# Phase 17 Plan 01: Fix UMAS Protocol Bugs Summary

**Corrected all six UMAS wire format bugs: readPlcId(0x02) extraction, 13-byte 0x26 payload, offset-based pagination, mspec-aligned DD02/DD03 record parsing with response headers**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-09T14:13:09Z
- **Completed:** 2026-03-09T14:23:04Z
- **Tasks:** 2 (Task 1 TDD: RED+GREEN)
- **Files modified:** 5

## Accomplishments
- Fixed all six protocol bugs identified by PLC4X mspec comparison: 0x26 payload size (2->13 bytes), missing 0x02 call, no pagination, wrong response header parsing, wrong variable record order, wrong data type record fields
- Added readPlcId() method that extracts hardwareId (uint32) and memory block index from 0x02 response
- Implemented offset-based pagination for both DD02 (variable names) and DD03 (data types) with accumulation across pages
- Updated stub server to respond in corrected format and accept 13-byte 0x26 payloads
- 19 tests passing: 13 unit tests + 6 e2e tests against stub server

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD RED): Failing tests for corrected wire format** - `4af9116` (test)
2. **Task 1 (TDD GREEN): Implement corrected UMAS wire format** - `f980d29` (feat)
3. **Task 2: Update stub server and e2e tests** - `4d527e4` (feat)

_TDD task had separate RED and GREEN commits_

## Files Created/Modified
- `packages/tfc_dart/lib/core/umas_types.dart` - Added UmasPlcIdent type; added classIdentifier/dataType fields to UmasDataTypeRef (optional, backward-compatible)
- `packages/tfc_dart/lib/core/umas_client.dart` - Added readPlcId(), _build0x26Payload(), pagination loops, corrected record parsing, updated browse() sequence
- `packages/tfc_dart/test/core/umas_client_test.dart` - Rewritten with response queues, corrected payloads, pagination tests, 0x26 payload inspection, browse sequence verification
- `test/umas_stub_server.py` - Added 0x02 handler, corrected DD02/DD03 response format with headers, accepts 13-byte 0x26 payload
- `packages/tfc_dart/test/umas_e2e_test.dart` - Updated for readPlcId -> init -> DD03 -> DD02 sequence, added readPlcId test, verified variable data integrity

## Decisions Made
- MockUmasSender uses response queues (Map<int, List<Uint8List>>) consumed in order, with last response re-queued for single-page scenarios
- Data type record IDs assigned as 100+i from DD03 record order since the DD03 format does not include a type ID field -- the ordering defines the ID
- Null-terminated strings handled by parsing stringLength bytes then stripping trailing 0x00, safe for both null-terminated and non-null-terminated responses
- DD02 and DD03 use different pagination fields per PLC4X mspec: DD02 paginates via offset field, DD03 paginates via blockNo field

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- UmasClient is now protocol-correct per PLC4X mspec and ready for live hardware testing (Plan 02)
- The exact 0x02 response parsing offsets may need minor adjustment based on real PLC output -- the live test will validate
- Full test suite has 10 pre-existing failures in unrelated files (aggregator_performance_test.dart, connection_resilience_test.dart) -- not caused by this plan

## Self-Check: PASSED

All 5 modified files exist. All 3 task commits verified (4af9116, f980d29, 4d527e4).

---
*Phase: 17-fix-and-verify-umas-against-real-schneider-plc*
*Completed: 2026-03-09*
