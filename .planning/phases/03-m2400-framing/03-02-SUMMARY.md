---
phase: 03-m2400-framing
plan: 02
subsystem: protocol
tags: [integration-test, tcp-pipeline, stx-etx, m2400, msocket, test-tcp-server]

# Dependency graph
requires:
  - phase: 03-m2400-framing
    plan: 01
    provides: "M2400FrameParser, parseM2400Frame, M2400Record, M2400RecordType"
  - phase: 02-msocket-tcp-layer
    provides: "MSocket with Stream<Uint8List> dataStream, TestTcpServer"
provides:
  - "End-to-end integration tests proving MSocket -> M2400FrameParser -> parseM2400Frame pipeline"
  - "Validated composable stream chain: msocket.dataStream.transform(M2400FrameParser()).map(parseM2400Frame)"
affects: [04-stub-server, 05-field-catalog, 07-m2400-client-wrapper]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Completer-based test synchronization for broadcast stream pipelines"
    - "frameRecord helper for constructing STX/ETX test data from field maps"

key-files:
  created: []
  modified:
    - packages/jbtm/test/m2400_test.dart

key-decisions:
  - "Used Completer pattern instead of stream.first for integration test assertions (broadcast streams can miss events with cold .first subscriptions)"
  - "Barrel export already in place from Plan 01 -- no modification needed to jbtm.dart"

patterns-established:
  - "Integration test pattern: TestTcpServer + MSocket + pipeline.listen with Completer for assertion sync"
  - "frameRecord helper builds STX-framed records from Map<String, String> fields"

requirements-completed: [M24-01, M24-02, M24-03]

# Metrics
duration: 3min
completed: 2026-03-04
---

# Phase 3 Plan 2: M2400 Integration Tests Summary

**End-to-end integration tests proving TCP-to-record pipeline with TestTcpServer, MSocket, M2400FrameParser, and parseM2400Frame**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-04T12:50:39Z
- **Completed:** 2026-03-04T12:53:37Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Three integration tests validating the full TCP-to-record pipeline with real socket connections
- Single record test: STX-framed weight record flows through MSocket -> FrameParser -> RecordParser with correct type and fields
- Burst test: 3 records sent in rapid succession all arrive with correct types (recWgt, recStat, recLua) and fields
- Split-write test: record split across two TCP writes reassembles correctly into single M2400Record
- Full test suite green: 51 tests (21 msocket + 27 m2400 unit + 3 m2400 integration), 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Barrel export and integration tests** - `8daafec` (feat)

## Files Created/Modified
- `packages/jbtm/test/m2400_test.dart` - Added integration test group with 3 end-to-end tests (534 lines total)

## Decisions Made
- **Completer pattern for test assertions**: Used Completer-based listener pattern instead of `pipeline.first` for integration tests because `dataStream` is a broadcast stream -- `.first` creates a new cold subscription that can miss events emitted before the subscription starts.
- **Barrel export already present**: `jbtm.dart` already exported `m2400.dart` from Plan 01, so no modification was needed. Plan specified adding it but it was already there.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed broadcast stream race condition in split-write test**
- **Found during:** Task 1 (integration tests)
- **Issue:** Using `pipeline.first` on a broadcast stream-derived pipeline caused TimeoutException because the subscription was created after data was already flowing, missing the emitted record.
- **Fix:** Changed all three integration tests to use Completer-based listener pattern (subscribe before sending data, complete on first record arrival).
- **Files modified:** packages/jbtm/test/m2400_test.dart
- **Verification:** All 51 tests pass
- **Committed in:** 8daafec (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Necessary for test reliability with broadcast streams. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full M2400 pipeline validated end-to-end: TCP bytes -> MSocket -> M2400FrameParser -> parseM2400Frame -> M2400Record
- Phase 4 (stub server) can produce valid STX/ETX framed data matching this parser
- Phase 5 (field catalog) will extend parsed records with field-level type parsing
- Phase 7 (m2400-client-wrapper) can compose the validated pipeline into a client class

## Self-Check: PASSED

All files exist, all commits verified, barrel export confirmed, integration test group confirmed.

---
*Phase: 03-m2400-framing*
*Completed: 2026-03-04*
