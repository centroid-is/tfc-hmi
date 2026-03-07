---
phase: 09-stateman-integration
plan: 01
subsystem: api
tags: [modbus, stateman, routing, device-client, factory]

# Dependency graph
requires:
  - phase: 07-deviceclient-adapter
    provides: ModbusDeviceClientAdapter implementing DeviceClient interface
  - phase: 08-config-serialization
    provides: ModbusConfig, ModbusNodeConfig, ModbusPollGroupConfig JSON-serializable classes
provides:
  - buildSpecsFromKeyMappings function for config-to-spec translation
  - buildModbusDeviceClients factory for adapter creation with poll group pre-configuration
  - _resolveModbusDeviceClient routing helper in StateMan
  - Modbus key routing in subscribe(), read(), readMany(), write()
affects: [09-02, data-acquisition-isolate, flutter-ui-provider]

# Tech tracking
tech-stack:
  added: []
  patterns: [config-to-spec translation, multi-protocol key routing, DeviceClient partitioning in readMany]

key-files:
  created:
    - packages/tfc_dart/test/core/modbus_stateman_routing_test.dart
  modified:
    - packages/tfc_dart/lib/core/modbus_device_client.dart
    - packages/tfc_dart/lib/core/state_man.dart

key-decisions:
  - "readMany partitions keys into DeviceClient (Modbus/M2400) vs OPC UA before processing -- avoids OPC UA lookup errors for non-OPC keys"
  - "buildModbusDeviceClients pre-configures poll groups from ModbusConfig.pollGroups before adapter creation"
  - "_resolveModbusDeviceClient matches by serverAlias between modbusNode config and adapter instance"

patterns-established:
  - "Multi-protocol readMany: partition keys by protocol, resolve DeviceClient keys first, then pass remaining to OPC UA"
  - "Config-to-spec translation: buildSpecsFromKeyMappings as pure function for testability"

requirements-completed: [INTG-02, INTG-03, INTG-04, INTG-05, INTG-08, TEST-05]

# Metrics
duration: 11min
completed: 2026-03-07
---

# Phase 9 Plan 1: StateMan Integration Summary

**Modbus key routing in StateMan subscribe/read/readMany/write with buildSpecsFromKeyMappings config translation and buildModbusDeviceClients factory**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-07T07:22:22Z
- **Completed:** 2026-03-07T07:33:40Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- buildSpecsFromKeyMappings converts ModbusNodeConfig entries to ModbusRegisterSpec map filtered by serverAlias
- buildModbusDeviceClients factory creates one adapter per ModbusConfig with poll groups pre-configured
- StateMan subscribe/read/readMany/write all route Modbus keys to ModbusDeviceClientAdapter
- readMany handles mixed Modbus + M2400 + OPC UA keys by partitioning before OPC UA processing
- 20 TDD tests covering all routing behaviors, coexistence, and edge cases

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Write failing tests** - `c62abd5` (test)
2. **Task 2: GREEN -- Implement routing and factories** - `6e191e9` (feat)

**Plan metadata:** (pending) (docs: complete plan)

_Note: TDD tasks have RED/GREEN commits_

## Files Created/Modified
- `packages/tfc_dart/test/core/modbus_stateman_routing_test.dart` - 20 tests for buildSpecsFromKeyMappings, buildModbusDeviceClients, MockModbusDeviceClient routing, readMany partitioning, and protocol coexistence
- `packages/tfc_dart/lib/core/modbus_device_client.dart` - Added buildSpecsFromKeyMappings and buildModbusDeviceClients functions
- `packages/tfc_dart/lib/core/state_man.dart` - Added _resolveModbusDeviceClient, Modbus routing in subscribe/read/readMany/write

## Decisions Made
- readMany partitions keys into DeviceClient (Modbus/M2400) vs OPC UA before processing to avoid OPC UA lookup errors for non-OPC keys
- buildModbusDeviceClients pre-configures poll groups from ModbusConfig.pollGroups before adapter creation, so poll intervals are set before any subscribe calls
- _resolveModbusDeviceClient matches by serverAlias between modbusNode config and adapter instance, consistent with M2400 routing pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Modbus key routing fully operational in StateMan
- Ready for Plan 09-02 (data_acquisition_isolate wiring)
- buildModbusDeviceClients factory is the entry point both plans 09-02 and Flutter UI provider will use

## Self-Check: PASSED

All files found. All commits verified.

---
*Phase: 09-stateman-integration*
*Completed: 2026-03-07*
