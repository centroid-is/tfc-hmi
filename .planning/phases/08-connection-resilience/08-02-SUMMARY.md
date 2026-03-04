---
phase: 08-connection-resilience
plan: 02
subsystem: jbtm
tags: [pipeline-resilience, m2400, framing, throughput, end-to-end]
dependency_graph:
  requires:
    - "Phase 8 Plan 01: ConnectionHealthMetrics, TcpProxy"
    - "Phase 4: M2400StubServer"
    - "Phase 3: M2400FrameParser, parseM2400Frame"
    - "Phase 5: parseTypedRecord, M2400Field"
    - "Phase 6: convertRecordToDynamicValue"
    - "Phase 7: M2400ClientWrapper"
  provides:
    - "End-to-end pipeline resilience verification through full M2400 protocol stack"
    - "Proof that frame parser handles disconnect boundaries correctly"
    - "Burst throughput recovery verification"
  affects:
    - "Phase 10: UI (confidence in pipeline reliability)"
tech_stack:
  added: []
  patterns: ["Polling helper for async record count verification", "Cable pull helper method for reusable proxy restart pattern", "Unique weight values as record identity for duplicate detection"]
key_files:
  created:
    - packages/jbtm/test/pipeline_resilience_test.dart
  modified: []
decisions:
  - "Use M2400ClientWrapper.subscribe('BATCH') for record collection instead of building raw pipeline (tests the real integration path)"
  - "Unique weight values (1.000, 2.000, ...) as record identifiers for no-duplicate verification"
  - "Polling helper (_waitForRecords) instead of stream-based waits for simpler async record count verification"
  - "Health metrics tests use separate MSocket since M2400ClientWrapper hides its internal socket"
metrics:
  duration: "6min"
  completed: "2026-03-04"
  tasks_completed: 1
  tasks_total: 1
  tests_added: 7
  tests_total: 224
---

# Phase 8 Plan 02: End-to-End Pipeline Resilience Tests Summary

Full M2400 pipeline (StubServer -> TcpProxy -> MSocket -> FrameParser -> parseM2400Frame -> parseTypedRecord -> convertRecordToDynamicValue -> M2400ClientWrapper subscribe) proven resilient to cable pull and switch reboot with no duplicates, no data loss post-reconnect, and burst throughput recovery.

## What Was Built

### Pipeline Resilience Test Suite (`packages/jbtm/test/pipeline_resilience_test.dart`)

7 end-to-end tests verifying the complete M2400 protocol pipeline through network disruptions:

**Test setup pattern:**
```
M2400StubServer -> TcpProxy -> MSocket (inside M2400ClientWrapper)
  -> M2400FrameParser -> parseM2400Frame -> parseTypedRecord
  -> convertRecordToDynamicValue -> subscribe('BATCH') -> DynamicValue assertions
```

### Key Design Decisions

1. **Test through M2400ClientWrapper.subscribe()**: Rather than rebuilding the raw pipeline in tests, all tests subscribe through the wrapper's `subscribe('BATCH')` API. This tests the real integration path that production code uses.

2. **Unique weight values as record identity**: Each pushed record has a unique weight (1.000, 2.000, etc.). This enables verifying no duplicates and tracking which records were lost during outage vs received.

3. **Polling helper for record counts**: `_waitForRecords()` polls a list length with timeout, simpler than stream-based waits for count verification with multiple records.

4. **Health metrics via separate MSocket**: Since M2400ClientWrapper encapsulates its internal MSocket, health metrics tests create a parallel MSocket through the same proxy to verify ConnectionHealthMetrics integration.

## Tests

### Cable Pull - Full Pipeline (2 tests)

- **Records before/after, none during**: Push 5 records (1-5), cable pull, push 5 more (6-10, lost during outage), reconnect, push 5 more (11-15). Verify records 1-5 and 11-15 present, 6-10 absent.
- **No duplicate records**: Push 10 + cable pull/recover + 10 more. All 20 unique weights, no duplicates.

### Switch Reboot - Full Pipeline (1 test)

- **Records resume after delayed restart**: Push 5, proxy shutdown, wait 2s (reboot delay), proxy restart, push 5 more. All 10 arrive.

### Frame Boundary Resilience (1 test)

- **Partial frame at disconnect**: Push valid record, verify receipt, cable pull + recover, push another record. Second record parses correctly (FrameParser starts fresh at next STX after reconnect).

### Throughput Recovery (1 test)

- **Burst throughput**: pushBurst(50) before disconnect, pushBurst(50) after reconnect. All 100 records received.

### Health Metrics Through Pipeline (2 tests)

- **records/second**: Push 10 records rapidly, notifyRecord for each, verify recordsPerSecond > 0.
- **reconnectCount**: Track through cable pull cycle, verify increment.

## Deviations from Plan

None -- plan executed exactly as written.

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 9fc256a | test | Add end-to-end pipeline resilience tests (7 tests) |

## Verification

- `dart test test/pipeline_resilience_test.dart` -- 7/7 pass
- `dart test test/connection_health_test.dart test/connection_resilience_test.dart test/pipeline_resilience_test.dart` -- 23/23 pass (full Phase 8 suite)
- `dart test` -- 224/224 pass (no regressions)
- Pipeline verified end-to-end: M2400StubServer -> TcpProxy -> MSocket -> FrameParser -> RecordParser -> TypedParser -> DynamicValue -> subscribe stream

## Self-Check: PASSED

- [x] packages/jbtm/test/pipeline_resilience_test.dart -- FOUND (337 lines)
- [x] Commit 9fc256a -- FOUND
