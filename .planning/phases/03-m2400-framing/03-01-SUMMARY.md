---
phase: 03-m2400-framing
plan: 01
subsystem: protocol
tags: [stx-etx, frame-parser, stream-transformer, m2400, tcp-chunking]

# Dependency graph
requires:
  - phase: 02-msocket-tcp-layer
    provides: "MSocket with Stream<Uint8List> dataStream for raw TCP bytes"
provides:
  - "M2400FrameParser StreamTransformer<Uint8List, Uint8List> for STX/ETX frame extraction"
  - "parseM2400Frame pure function for tab-separated record parsing"
  - "M2400RecordType enum with known types and unknown variant"
  - "M2400Record immutable data class with type and fields map"
  - "recordTypeFieldKey configurable constant for protocol record type field"
affects: [04-stub-server, 05-field-catalog, 07-m2400-client-wrapper]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "StreamTransformer<Uint8List, Uint8List> for byte-level protocol parsing"
    - "BytesBuilder(copy: false) for efficient frame buffering"
    - "Pure function record parser separated from stateful frame extractor"
    - "Enhanced enum with fromId factory for protocol type discrimination"
    - "Configurable top-level constant for protocol field keys (recordTypeFieldKey)"

key-files:
  created:
    - packages/jbtm/lib/src/m2400.dart
    - packages/jbtm/test/m2400_test.dart
  modified:
    - packages/jbtm/lib/jbtm.dart

key-decisions:
  - "recordTypeFieldKey defined as 'REC' top-level constant -- easy to change if protocol docs reveal different key"
  - "Silent discard for inter-frame garbage (no logging to avoid log flood)"
  - "64KB max frame size (65536 bytes) -- 64x typical M2400 record size"
  - "parseM2400Frame logs 'no record type field' warning only when frame has >1 element (single-element frames are clearly malformed, separate concern)"

patterns-established:
  - "StreamTransformer bind() with fromHandlers for protocol frame parsing"
  - "Pure function record parser returning nullable typed record"
  - "TDD RED-GREEN cycle: stub types first, then implement"

requirements-completed: [M24-01, M24-02, M24-03, M24-10]

# Metrics
duration: 4min
completed: 2026-03-04
---

# Phase 3 Plan 1: M2400 Frame Parser and Record Parser Summary

**STX/ETX frame extraction StreamTransformer with tab-separated record parser, record type enum, and full TCP chunking coverage via TDD**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-04T12:43:44Z
- **Completed:** 2026-03-04T12:47:57Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 3

## Accomplishments
- M2400FrameParser StreamTransformer handles all TCP chunking edge cases: split frames, multi-frame chunks, inter-frame garbage, oversized frame protection, buffer reset on error/close
- parseM2400Frame pure function extracts tab-separated key-value pairs with CRLF handling, allowMalformed UTF-8, and odd element warnings
- M2400RecordType enum with fromId factory discriminates 4 known types and forwards-compatible unknown variant
- 27 comprehensive unit tests covering M24-01, M24-02, M24-03, M24-10 requirements
- Full test suite (48 tests) green with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: TDD RED - Failing tests** - `e49a0b0` (test)
2. **Task 2: TDD GREEN - Implementation** - `b731cbf` (feat)

_No refactor commit needed -- implementation was clean from first pass._

## Files Created/Modified
- `packages/jbtm/lib/src/m2400.dart` - M2400FrameParser, M2400Record, M2400RecordType, parseM2400Frame (176 lines)
- `packages/jbtm/test/m2400_test.dart` - 27 unit tests covering frame parsing, record parsing, type discrimination, unknown field handling (375 lines)
- `packages/jbtm/lib/jbtm.dart` - Added m2400.dart barrel export

## Decisions Made
- **recordTypeFieldKey = 'REC'**: Defined as prominent top-level constant with documentation noting it may need correction from protocol docs. Easy to find and change.
- **Silent garbage discard**: Inter-frame bytes between ETX and STX are silently discarded rather than logged, to avoid flooding logs on noisy connections.
- **64KB max frame size**: M2400 records are typically <1KB; 64KB provides generous headroom while protecting against unbounded buffer growth.
- **Warning suppression for single-element frames**: Single-element frames (no tabs) get unknown type without a "no record type field" warning, since the missing-type is obvious from the malformed input.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- M2400FrameParser ready for composition: `msocket.dataStream.transform(M2400FrameParser()).map(parseM2400Frame)`
- Phase 4 (stub server) can now produce valid STX/ETX framed data matching this parser
- Phase 5 (field catalog) will extend parsed records with field-level type parsing using the `fields` Map<String, String>
- recordTypeFieldKey ('REC') should be validated against real device captures before production use

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 03-m2400-framing*
*Completed: 2026-03-04*
