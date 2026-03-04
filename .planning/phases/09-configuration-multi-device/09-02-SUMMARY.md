---
phase: 09-configuration-multi-device
plan: 02
subsystem: jbtm, tfc_dart
tags: [m2400, multi-device, state-man, device-client, adapter, stub-server]
dependency_graph:
  requires:
    - "Phase 7 Plan 01: M2400ClientWrapper (subscribe, connect, status API)"
    - "Phase 7 Plan 02: DeviceClient interface and StateMan routing"
    - "Phase 9 Plan 01: M2400Config, M2400NodeConfig, StateManConfig.jbtm"
  provides:
    - "M2400DeviceClientAdapter: bridges M2400ClientWrapper to DeviceClient interface"
    - "createM2400DeviceClients factory: creates DeviceClient list from M2400Config list"
    - "Multi-device M2400 support: N simultaneous connections with independent streams"
    - "Collector integration: M2400 BATCH records collectable via existing pattern"
  affects:
    - "Phase 10: UI (uses createM2400DeviceClients for device lifecycle)"
    - "Phase 8: connection resilience (adapter inherits MSocket reconnect)"
tech_stack:
  added: []
  patterns: ["adapter pattern for cross-package DeviceClient implementation", "ConnectionStatus enum mapping between packages"]
key_files:
  created:
    - packages/tfc_dart/test/m2400_multi_device_test.dart
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
key_decisions:
  - "M2400DeviceClientAdapter lives in tfc_dart (not jbtm) to keep dependency direction correct"
  - "ConnectionStatus mapped between jbtm and state_man enums via switch statement"
  - "createM2400DeviceClients is a top-level factory function, not a StateMan method, for flexibility"
  - "Collector integration works without any Collector code changes (existing pattern handles M2400 keys)"
patterns_established:
  - "Adapter pattern: M2400DeviceClientAdapter wraps M2400ClientWrapper as DeviceClient"
  - "Factory function pattern: createM2400DeviceClients creates adapters from config list"
requirements-completed: [SM-05, SM-06]
metrics:
  duration: "5min"
  completed: "2026-03-04"
  tasks_completed: 2
  tasks_total: 2
  tests_added: 12
  tests_total: 194
---

# Phase 9 Plan 02: Multi-Device M2400 Lifecycle Summary

**M2400DeviceClientAdapter bridges M2400ClientWrapper to DeviceClient for N-device support, with createM2400DeviceClients factory and verified Collector integration for BATCH record storage**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-04T14:55:00Z
- **Completed:** 2026-03-04T15:02:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- M2400DeviceClientAdapter wraps M2400ClientWrapper as DeviceClient with ConnectionStatus mapping
- createM2400DeviceClients factory creates one adapter per M2400Config entry
- Multi-device subscribe routing verified: 2 stub servers, 2 configs, independent data streams
- Collector integration confirmed: DeviceClient.subscribe returns streams consumable by Collector
- Independent connection status per device verified
- 12 integration tests with M2400StubServer for realistic device simulation

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests for multi-device lifecycle** - `0961ca3` (test)
2. **Tasks 1+2 (GREEN): Implement M2400DeviceClientAdapter and factory** - `57f8e87` (feat)

_Note: Tasks 1 and 2 from the plan were implemented together since the Collector integration works through the same DeviceClient.subscribe() path without any Collector code changes._

## Files Created/Modified
- `packages/tfc_dart/lib/core/state_man.dart` - Added M2400DeviceClientAdapter class and createM2400DeviceClients factory function
- `packages/tfc_dart/test/m2400_multi_device_test.dart` - 12 tests covering adapter, multi-device, and collector integration

## Decisions Made
- **Adapter in tfc_dart**: M2400DeviceClientAdapter lives in state_man.dart alongside DeviceClient, keeping the dependency direction correct (tfc_dart -> jbtm, not reverse).
- **ConnectionStatus mapping**: Since jbtm and tfc_dart each define their own ConnectionStatus enum, the adapter maps between them via an explicit switch. This avoids coupling the enum definitions.
- **Top-level factory function**: createM2400DeviceClients is a standalone function rather than a StateMan method, giving callers flexibility to create adapters without a StateMan instance.
- **Collector integration zero-change**: The existing Collector iterates keyMappings.nodes and calls stateMan.subscribe() for entries with collect != null. Since StateMan.subscribe() already routes to DeviceClients (Phase 7), M2400 keys with collect entries "just work" through the existing path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ConnectionStatus enum ambiguity between jbtm and tfc_dart**
- **Found during:** Task 1 (test compilation)
- **Issue:** Both jbtm (msocket.dart) and tfc_dart (state_man.dart) define `ConnectionStatus` enum. Importing both causes ambiguity errors.
- **Fix:** Used `import 'package:jbtm/jbtm.dart' as jbtm show ConnectionStatus` for the jbtm version, explicit mapping in adapter.
- **Files modified:** packages/tfc_dart/lib/core/state_man.dart, packages/tfc_dart/test/m2400_multi_device_test.dart
- **Verification:** All tests compile and pass
- **Committed in:** 57f8e87

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary for correct cross-package type usage. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Multi-device M2400 support fully functional in StateMan
- createM2400DeviceClients available for app-layer wiring
- Collector integration verified for BATCH record auto-storage
- Ready for Phase 10 UI to create config screens and key mapping dropdowns

---
*Phase: 09-configuration-multi-device*
*Completed: 2026-03-04*
