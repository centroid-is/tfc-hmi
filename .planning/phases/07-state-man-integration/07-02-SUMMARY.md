---
phase: 07-state-man-integration
plan: 02
subsystem: jbtm, tfc_dart
tags: [m2400, state-man, device-client, integration-test, end-to-end]
dependency_graph:
  requires:
    - "Phase 7 Plan 01: M2400ClientWrapper with subscribe/status API"
    - "Phase 4: M2400StubServer for integration tests"
    - "Phase 6: DynamicValue conversion pipeline"
  provides:
    - "DeviceClient abstract interface in tfc_dart for protocol-agnostic device integration"
    - "StateMan.subscribe() routes DeviceClient keys before OPC UA fallback"
    - "11 end-to-end integration tests proving full M2400 pipeline"
  affects:
    - "Phase 8: connection resilience (DeviceClient interface available)"
    - "Phase 9: multi-device config (StateMan accepts DeviceClient list)"
    - "Phase 10: UI (connection status from DeviceClient)"
tech_stack:
  added: []
  patterns: ["abstract DeviceClient interface for protocol-agnostic device integration", "StateMan subscribe key routing: DeviceClient-first with OPC UA fallback"]
key_files:
  created:
    - packages/tfc_dart/test/core/device_client_routing_test.dart
    - packages/jbtm/test/m2400_integration_test.dart
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
decisions:
  - "DeviceClient interface in tfc_dart (not jbtm depending on tfc_dart) to avoid wrong-direction dependency"
  - "jbtm does NOT depend on tfc_dart -- adapter wrapping M2400ClientWrapper as DeviceClient lives at app layer"
  - "StateMan.subscribe() checks DeviceClient.canSubscribe() first, falls through to OPC UA _monitor()"
  - "Integration tests in jbtm package test through M2400ClientWrapper directly (self-contained pipeline verification)"
metrics:
  duration: "6min"
  completed: "2026-03-04"
  tasks_completed: 2
  tasks_total: 2
  tests_added: 17
  tests_total: 207
---

# Phase 7 Plan 02: StateMan Integration and End-to-End Tests Summary

DeviceClient abstract interface in tfc_dart enables protocol-agnostic device subscription routing in StateMan; 11 end-to-end integration tests verify the full M2400 pipeline from stub server TCP bytes to typed DynamicValue streams.

## What Was Built

### DeviceClient Interface (`packages/tfc_dart/lib/core/state_man.dart`)

Protocol-agnostic abstract class that any device protocol wrapper can implement:

```dart
abstract class DeviceClient {
  Set<String> get subscribableKeys;
  bool canSubscribe(String key);
  Stream<DynamicValue> subscribe(String key);
  ConnectionStatus get connectionStatus;
  Stream<ConnectionStatus> get connectionStream;
  void connect();
  void dispose();
}
```

### StateMan Integration (same file)

- Added `List<DeviceClient> deviceClients` field to StateMan
- `StateMan.create()` accepts optional `deviceClients` parameter and calls `connect()` on each
- `subscribe()` checks `DeviceClient.canSubscribe()` first, falls through to OPC UA `_monitor()` if no device client claims the key
- `close()` disposes all device clients before OPC UA cleanup

### End-to-End Integration Tests (`packages/jbtm/test/m2400_integration_test.dart`)

11 tests verifying the complete pipeline:

```
M2400StubServer -> TCP -> MSocket -> M2400FrameParser -> parseM2400Frame
  -> parseTypedRecord -> convertRecordToDynamicValue -> M2400ClientWrapper
  -> subscribe stream -> DynamicValue assertions
```

## Key Design Decisions

1. **DeviceClient in tfc_dart, not jbtm importing tfc_dart**: tfc_dart is the lower-level package. Making jbtm depend on tfc_dart would pull in heavy OPC UA native build dependencies. Instead, the DeviceClient interface lives in tfc_dart, and the adapter that makes M2400ClientWrapper implement DeviceClient will live at the application layer (where both packages are available).

2. **Subscribe routing: DeviceClient-first with OPC UA fallback**: StateMan.subscribe() iterates device clients first (O(n) where n is device client count, typically 1-2). If no device client claims the key, it falls through to the existing OPC UA `_monitor()` path. This is a simple if/else before existing code -- zero changes to OPC UA behavior.

3. **Integration tests through M2400ClientWrapper directly**: Since M2400ClientWrapper is already self-contained (owns the full pipeline from MSocket to subscribe streams), the integration tests don't need StateMan. They test through the wrapper directly, which is the real verification: does the pipeline work end-to-end?

## Tests

### DeviceClient Routing Tests (6 tests in tfc_dart)

- Subscribe routes to DeviceClient
- canSubscribe: true for known M2400 keys
- canSubscribe: false for unknown keys
- canSubscribe: true for dot-notation keys
- Connection status accessible
- StateMan accepts DeviceClient instances

### End-to-End Integration Tests (11 tests in jbtm)

- **Core pipeline** (3): batch/stat/intro record flow from stub to subscriber
- **Replay semantics** (2): STAT replays last value, BATCH is event-only
- **Dot-notation** (2): BATCH.weight extracts weight, STAT.unit extracts unit
- **Type isolation** (2): BATCH ignores STAT records, interleaved types routed correctly
- **Reconnection** (2): data resumes after disconnect/reconnect, status transitions correct

## Deviations from Plan

None -- plan executed exactly as written. The dependency analysis recommended in the plan was followed: tfc_dart cannot depend on jbtm, so DeviceClient interface was created in tfc_dart instead of directly importing M2400ClientWrapper.

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 90e36e5 | feat | Add DeviceClient interface and StateMan integration (6 tests) |
| 0a01798 | test | Add M2400 end-to-end integration tests (11 tests) |

## Verification

- `cd packages/tfc_dart && dart analyze` -- 0 new issues (4 pre-existing warnings in unrelated files)
- `cd packages/tfc_dart && dart test test/core/device_client_routing_test.dart` -- 6/6 pass
- `cd packages/jbtm && dart test test/m2400_integration_test.dart` -- 11/11 pass
- `cd packages/jbtm && dart test` -- 201/201 pass (no regressions)
- End-to-end pipeline verified: M2400StubServer -> TCP -> MSocket -> FrameParser -> RecordParser -> TypedParser -> DynamicValue -> subscribe stream
- M2400 keys and OPC UA keys do not conflict (DeviceClient checked first, OPC UA fallback untouched)

## Self-Check: PASSED

- [x] packages/tfc_dart/lib/core/state_man.dart -- FOUND (modified, DeviceClient interface + StateMan wiring)
- [x] packages/tfc_dart/test/core/device_client_routing_test.dart -- FOUND (6 tests)
- [x] packages/jbtm/test/m2400_integration_test.dart -- FOUND (11 tests)
- [x] Commit 90e36e5 -- FOUND
- [x] Commit 0a01798 -- FOUND
