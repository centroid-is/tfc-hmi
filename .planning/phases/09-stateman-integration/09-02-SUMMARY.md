---
phase: 09-stateman-integration
plan: 02
subsystem: api
tags: [modbus, stateman, isolate, wiring, device-client, flutter-provider]

# Dependency graph
requires:
  - phase: 09-stateman-integration
    plan: 01
    provides: buildModbusDeviceClients factory and Modbus key routing in StateMan
  - phase: 08-config-serialization
    provides: ModbusConfig.fromJson/toJson for isolate config serialization
provides:
  - Modbus device client creation in data_acquisition_isolate entry point
  - spawnModbusDataAcquisitionIsolate function for isolate lifecycle management
  - Modbus isolate spawning in main.dart when config.modbus is non-empty
  - Modbus device client creation in Flutter UI provider alongside M2400 clients
affects: [10-end-to-end-testing, production-deployment]

# Tech tracking
tech-stack:
  added: []
  patterns: [isolate config serialization via JSON, combined device client lists]

key-files:
  created: []
  modified:
    - packages/tfc_dart/bin/data_acquisition_isolate.dart
    - packages/tfc_dart/bin/main.dart
    - lib/providers/state_man.dart

key-decisions:
  - "DataAcquisitionIsolateConfig.modbusJson defaults to const [] for backward compatibility with existing OPC UA and M2400 isolates"
  - "Isolate name fallback: 'jbtm' when jbtmJson is non-empty, 'modbus' when only modbusJson -- improved from blanket 'jbtm' fallback"
  - "All three creation paths (isolate, main.dart spawner, Flutter UI provider) use the same buildModbusDeviceClients factory"

patterns-established:
  - "Combined device clients: [...m2400Clients, ...modbusClients] spread into single list for StateMan.create()"
  - "Modbus isolate spawn follows exact same pattern as M2400: filter keyMappings by protocol, log key count, call spawn function"

requirements-completed: [INTG-08]

# Metrics
duration: 11min
completed: 2026-03-07
---

# Phase 9 Plan 2: StateMan Integration Wiring Summary

**Modbus device clients wired into data_acquisition_isolate, main.dart spawner, and Flutter UI provider using shared buildModbusDeviceClients factory**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-07T07:36:33Z
- **Completed:** 2026-03-07T07:48:27Z
- **Tasks:** 3 (1 skipped -- already done in Plan 01, 2 executed)
- **Files modified:** 3

## Accomplishments
- DataAcquisitionIsolateConfig extended with modbusJson field (backward-compatible default)
- Isolate entry point creates Modbus device clients and combines with M2400 clients before StateMan.create()
- spawnModbusDataAcquisitionIsolate function added following M2400 spawn pattern with auto-respawn
- main.dart spawns Modbus isolate when config.modbus is non-empty, filtering keyMappings to modbus-only keys
- Flutter UI provider creates Modbus device clients alongside M2400 and passes combined list to StateMan.create()
- All three paths use the same buildModbusDeviceClients factory from Plan 01

## Task Commits

Each task was committed atomically:

1. **Task 1: Add buildModbusDeviceClients helper** - Skipped (already exists from Plan 01)
2. **Task 2: Wire Modbus into data_acquisition_isolate and main.dart** - `11a04fb` (feat)
3. **Task 3: Wire Modbus into Flutter UI provider** - `1d2d6d2` (feat)

**Plan metadata:** (pending) (docs: complete plan)

## Files Created/Modified
- `packages/tfc_dart/bin/data_acquisition_isolate.dart` - Added modbusJson to config, Modbus client creation in entry point, spawnModbusDataAcquisitionIsolate function
- `packages/tfc_dart/bin/main.dart` - Modbus isolate spawning block, updated log line with Modbus count
- `lib/providers/state_man.dart` - Import modbus_device_client, create Modbus clients alongside M2400

## Decisions Made
- DataAcquisitionIsolateConfig.modbusJson defaults to const [] for backward compatibility -- existing OPC UA and M2400 isolate spawns are unaffected
- Improved isolate name fallback logic: 'modbus' when only modbusJson is present (was blanket 'jbtm' before)
- All three creation paths use the same buildModbusDeviceClients factory ensuring consistent adapter creation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed misleading isolate name for Modbus-only isolates**
- **Found during:** Task 2
- **Issue:** When no OPC UA server config, isolate name always defaulted to 'jbtm' even for Modbus-only isolates
- **Fix:** Added conditional: 'jbtm' when jbtmJson non-empty, 'modbus' otherwise
- **Files modified:** packages/tfc_dart/bin/data_acquisition_isolate.dart
- **Committed in:** 11a04fb (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Minor logging correctness fix. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All Modbus device client creation paths operational (isolate, spawner, Flutter UI)
- Phase 9 complete -- StateMan integration fully wired
- Ready for Phase 10 (end-to-end testing) or production deployment

## Self-Check: PASSED

All files found. All commits verified.

---
*Phase: 09-stateman-integration*
*Completed: 2026-03-07*
