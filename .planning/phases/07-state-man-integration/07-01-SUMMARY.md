---
phase: 07-state-man-integration
plan: 01
subsystem: jbtm
tags: [m2400, state-man, client-wrapper, streams, dynamic-value]
dependency_graph:
  requires:
    - "Phase 2: MSocket TCP layer"
    - "Phase 3: M2400 framing (M2400FrameParser, parseM2400Frame)"
    - "Phase 5: M2400 field catalog (parseTypedRecord, M2400Field)"
    - "Phase 6: DynamicValue conversion (convertRecordToDynamicValue)"
  provides:
    - "M2400ClientWrapper: connect/disconnect/dispose/subscribe/statusStream API"
    - "Per-type DynamicValue streams with replay semantics"
    - "Dot-notation field access for subscribe keys"
  affects:
    - "Phase 7 Plan 02: state_man provider integration"
    - "Phase 8: connection resilience"
    - "Phase 10: UI"
tech_stack:
  added: []
  patterns: ["BehaviorSubject for current-state replay", "broadcast StreamController for event-only streams", "wrapper-owned status subject surviving connection cycles"]
key_files:
  created:
    - packages/jbtm/lib/src/m2400_client_wrapper.dart
  modified:
    - packages/jbtm/lib/jbtm.dart
    - packages/jbtm/test/m2400_client_wrapper_test.dart
decisions:
  - "Wrapper-owned BehaviorSubject for status (not delegating to MSocket) to survive connect/disconnect cycles"
  - "Route by DynamicValue.name (set to M2400RecordType.name by converter) rather than carrying record type separately"
  - "STAT/INTRO use BehaviorSubject (replay last); BATCH/LUA use broadcast StreamController (event-only)"
  - "Dot-notation uses DynamicValue[] operator to traverse child hierarchy"
metrics:
  duration: "4min"
  completed: "2026-03-04"
  tasks_completed: 1
  tasks_total: 1
  tests_added: 15
  tests_total: 190
---

# Phase 7 Plan 01: M2400ClientWrapper Summary

M2400ClientWrapper bridges raw M2400 TCP data into subscribable DynamicValue streams with per-record-type routing, BehaviorSubject replay for STAT/INTRO, and dot-notation field access.

## What Was Built

### M2400ClientWrapper (`packages/jbtm/lib/src/m2400_client_wrapper.dart`)

Core integration component that wires the full M2400 parsing pipeline end-to-end:

```
MSocket.dataStream
  -> M2400FrameParser()        (Phase 3: STX/ETX framing)
  -> parseM2400Frame()         (Phase 3: tab-separated field extraction)
  -> where(r != null)
  -> parseTypedRecord()        (Phase 5: typed field parsing)
  -> convertRecordToDynamicValue()  (Phase 6: DynamicValue conversion)
  -> _route()                  (dispatch to per-type streams)
```

**API:**
- `M2400ClientWrapper(host, port, {socketFactory?})` -- constructor with optional test injection
- `connect()` -- creates MSocket, wires pipeline, starts connection
- `disconnect()` -- tears down socket but keeps controllers alive (reusable)
- `dispose()` -- terminal: tears down everything
- `subscribe(key)` -- returns `Stream<DynamicValue>` for the given key
- `status` / `statusStream` -- connection status with replay

**Subscribe keys:**
- `'BATCH'` -- completed weighing events (event-only, no replay)
- `'STAT'` -- live weight (BehaviorSubject, replays last)
- `'INTRO'` -- device identity (BehaviorSubject, replays last)
- `'LUA'` -- LUA events (event-only, no replay)
- Dot-notation: `'BATCH.weight'`, `'STAT.unit'`, etc. for child field access

### Key Design Decisions

1. **Wrapper-owned status BehaviorSubject**: Rather than delegating directly to MSocket's statusStream (which dies on disconnect), the wrapper maintains its own BehaviorSubject that pipes MSocket status changes and survives connect/disconnect cycles.

2. **Routing by DynamicValue.name**: The Phase 6 converter sets `DynamicValue.name` to the `M2400RecordType.name` (e.g., 'recBatch', 'recStat'). The router switches on this name to dispatch to the correct stream. No need to carry record type metadata separately.

3. **Replay semantics via rxdart BehaviorSubject**: Consistent with existing tfc_dart patterns (MSocket already uses BehaviorSubject for status). STAT/INTRO represent "current state" and replay to new subscribers. BATCH/LUA represent "events" and use plain broadcast StreamControllers.

## Tests

15 tests in `packages/jbtm/test/m2400_client_wrapper_test.dart`:

- **Connection lifecycle** (3): connect transitions, disconnect transitions, status mapping
- **Stream routing** (3): BATCH emits on recBatch, STAT emits on recStat, type isolation (BATCH ignores STAT)
- **Replay semantics** (4): STAT replays, BATCH no replay, INTRO replays (auto-INTRO on connect), LUA no replay
- **Dot-notation** (2): BATCH.weight extracts weight child, BATCH.unit extracts unit child
- **Error handling** (2): unknown key throws ArgumentError, unknown dot-notation root throws
- **Stream sharing** (1): multiple subscribers to same key both receive events

All tests use M2400StubServer for realistic device simulation with Completer-based sync.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Status stream not surviving connect/disconnect cycles**
- **Found during:** Task 1 implementation
- **Issue:** Initial implementation delegated statusStream directly to MSocket, but MSocket is destroyed on disconnect. Subscribing before connect() returned a single-value stream that completed.
- **Fix:** Added wrapper-owned BehaviorSubject for status that pipes MSocket status changes and survives across connection cycles.
- **Files modified:** packages/jbtm/lib/src/m2400_client_wrapper.dart
- **Commit:** 8b5f7b1

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 281817b | test | Add failing tests for M2400ClientWrapper (TDD RED) |
| 8b5f7b1 | feat | Implement M2400ClientWrapper with pipeline, stream routing, subscribe API (TDD GREEN) |

## Verification

- `dart test test/m2400_client_wrapper_test.dart` -- 15/15 pass
- `dart test` -- 190/190 pass (no regressions)
- `dart analyze` -- 0 new issues (2 pre-existing info-level in unrelated file)
- M2400ClientWrapper exported from `packages/jbtm/lib/jbtm.dart`
