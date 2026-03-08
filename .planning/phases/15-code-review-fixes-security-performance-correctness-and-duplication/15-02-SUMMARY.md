---
phase: 15-code-review-fixes-security-performance-correctness-and-duplication
plan: 02
subsystem: config, modbus
tags: [modbus, server-config, async, port-validation, heartbeat]

requires:
  - phase: 10-server-config-ui
    provides: server_config.dart with three _saveConfig methods and Modbus config card
  - phase: 04-modbusclientwrapper-connection
    provides: ModbusClientWrapper with connection lifecycle
provides:
  - Awaited config saves preventing data-loss races in all three protocols
  - Port validation clamped to valid TCP range (1-65535)
  - Configurable heartbeat register address for ModbusClientWrapper
  - Properly async _cleanupClient with explicit unawaited at sync call sites
affects: [server-config, modbus-client-wrapper]

tech-stack:
  added: []
  patterns:
    - "unawaited() for documenting intentional fire-and-forget async calls"
    - "Synchronous status emission before stream close in dispose()"

key-files:
  created: []
  modified:
    - lib/pages/server_config.dart
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart

key-decisions:
  - "Emit disconnected synchronously in dispose() before closing BehaviorSubject to preserve listener ordering"
  - "unawaited() in disconnect() and dispose() documents intentional fire-and-forget (not accidental)"

patterns-established:
  - "Port validation: clamp(1, 65535) matching existing unitId clamp(1, 247) pattern"
  - "Async cleanup with unawaited: make method async, wrap in unawaited at sync call sites"

requirements-completed: [CORR-01, CORR-05, SEC-01, SEC-03]

duration: 9min
completed: 2026-03-08
---

# Phase 15 Plan 02: Config Save & Modbus Correctness Summary

**Awaited config saves in all three protocol sections, port clamped to 1-65535, configurable heartbeat address, and async cleanup with explicit unawaited**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-08T07:20:36Z
- **Completed:** 2026-03-08T07:29:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- All three _saveConfig methods (OPC UA, JBTM, Modbus) now await toPrefs -- preventing config save races that could lose data
- Modbus port number clamped to valid TCP range (1-65535) in _buildConfig
- heartbeatAddress constructor parameter added to ModbusClientWrapper (default 0) for devices where register 0 causes side-effects
- _cleanupClient made properly async with await on _cleanupClientInstance; sync callers use unawaited()

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix missing await and port validation in server_config.dart** - `a4f0dc2` (fix)
2. **Task 2: Make heartbeat configurable and fix unawaited cleanup** - `534d6cf` (fix)

## Files Created/Modified
- `lib/pages/server_config.dart` - Added await to 3 toPrefs calls, clamped port to 1-65535
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - heartbeatAddress param, async _cleanupClient, unawaited at sync call sites

## Decisions Made
- Emit disconnected synchronously in dispose() before closing BehaviorSubject, so listeners see final status before done event. The async _cleanupClient is guarded by isClosed and becomes a no-op for status emission.
- unawaited() explicitly documents fire-and-forget intent at disconnect() and dispose() call sites, rather than leaving the missing-await accidental.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed dispose() ordering for async _cleanupClient**
- **Found during:** Task 2 (async cleanup)
- **Issue:** Making _cleanupClient async and wrapping in unawaited() caused dispose() to close the BehaviorSubject before the async status emission ran, breaking the "dispose stops reconnect loop AND closes BehaviorSubject" test
- **Fix:** Emit ConnectionStatus.disconnected synchronously in dispose() before calling unawaited(_cleanupClient()), so the async cleanup's status-add becomes a guarded no-op
- **Files modified:** packages/tfc_dart/lib/core/modbus_client_wrapper.dart
- **Verification:** All 92 modbus_client_wrapper tests pass
- **Committed in:** 534d6cf (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary fix for async conversion correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Config save correctness and port validation in place
- Modbus heartbeat address configurable for production deployments
- Ready for remaining Phase 15 plans (deduplication, performance)

---
*Phase: 15-code-review-fixes-security-performance-correctness-and-duplication*
*Completed: 2026-03-08*
