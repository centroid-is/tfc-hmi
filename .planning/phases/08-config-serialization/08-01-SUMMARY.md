---
phase: 08-config-serialization
plan: 01
subsystem: config
tags: [json-serializable, modbus, config, serialization, backward-compat]

# Dependency graph
requires:
  - phase: 07-deviceclient-adapter
    provides: ModbusDeviceClientAdapter, DeviceClient interface, createModbusDeviceClients factory
provides:
  - ModbusRegisterType enum with ModbusElementType conversion
  - ModbusPollGroupConfig JSON-serializable class
  - ModbusConfig JSON-serializable class (host, port, unitId, serverAlias, pollGroups)
  - ModbusNodeConfig JSON-serializable class (serverAlias, registerType, address, dataType, pollGroup)
  - StateManConfig.modbus field with backward-compatible empty default
  - KeyMappingEntry.modbusNode field with backward-compatible null default
  - KeyMappings.lookupServerAlias with Modbus fallback
  - createModbusDeviceClients updated to accept typed ModbusConfig
affects: [09-stateman-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [json-serializable-enum-pattern, backward-compat-defaultValue-pattern]

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
    - packages/tfc_dart/lib/core/state_man.g.dart
    - packages/tfc_dart/lib/core/modbus_device_client.dart
    - packages/tfc_dart/test/state_man_config_test.dart

key-decisions:
  - "ModbusRegisterType as separate Dart enum (not reusing ModbusElementType) for clean camelCase JSON serialization"
  - "Default case with ArgumentError in fromModbusElementType to satisfy non-exhaustive switch on external enum"
  - "createModbusDeviceClients uses named record with ModbusConfig instead of anonymous field record"

patterns-established:
  - "Modbus config follows M2400Config pattern: @JsonSerializable with snake_case JSON keys, defaultValue for backward compat"
  - "Three-way server alias chain: opcua >> m2400 >> modbus precedence in KeyMappingEntry.server and KeyMappings.lookupServerAlias"

requirements-completed: [INTG-06, INTG-07, TEST-06]

# Metrics
duration: 11min
completed: 2026-03-06
---

# Phase 8 Plan 1: Config Serialization Summary

**ModbusConfig, ModbusNodeConfig, and ModbusPollGroupConfig JSON-serializable classes integrated into StateManConfig and KeyMappingEntry with zero-regression backward compatibility**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-06T20:50:15Z
- **Completed:** 2026-03-06T21:01:17Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Four new JSON-serializable types (ModbusRegisterType, ModbusPollGroupConfig, ModbusConfig, ModbusNodeConfig) following established M2400Config pattern
- StateManConfig and KeyMappingEntry extended with Modbus fields, fully backward-compatible with existing config.json and keymappings.json formats
- 20 new tests covering all serialization behaviors, register types, data types, defaults, and backward compatibility
- All 44 config serialization tests pass; all 280 tests in full suite pass (1 pre-existing unrelated failure in connection_resilience_test.dart)

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Failing tests for ModbusConfig, ModbusNodeConfig, and backward compatibility** - `1b10f57` (test)
2. **Task 2: GREEN -- Implement config classes, update StateManConfig/KeyMappingEntry, regenerate, pass all tests** - `1071564` (feat)

## Files Created/Modified
- `packages/tfc_dart/lib/core/state_man.dart` - Added ModbusRegisterType enum, ModbusPollGroupConfig, ModbusConfig, ModbusNodeConfig classes; updated StateManConfig, KeyMappingEntry, KeyMappings with Modbus fields
- `packages/tfc_dart/lib/core/state_man.g.dart` - Regenerated JSON serialization code for all new and modified classes
- `packages/tfc_dart/lib/core/modbus_device_client.dart` - Updated createModbusDeviceClients to accept typed ModbusConfig instead of anonymous record
- `packages/tfc_dart/test/state_man_config_test.dart` - Added 20 new tests across 7 Modbus test groups

## Decisions Made
- **ModbusRegisterType as separate Dart enum:** Not reusing ModbusElementType from modbus_client package because json_serializable needs a Dart enum for camelCase string serialization. Added toModbusElementType/fromModbusElementType converters for runtime conversion.
- **Default case with ArgumentError in fromModbusElementType:** ModbusElementType is an external enum that the Dart compiler cannot verify exhaustively in switch statements. Added default throw to satisfy the non-null return type requirement.
- **createModbusDeviceClients signature:** Changed from anonymous record fields `({String host, int port, int unitId, ...})` to `({ModbusConfig config, Map<String, ModbusRegisterSpec> specs})` for type safety and consistency with the new config model.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added default case to fromModbusElementType switch**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Switch on ModbusElementType (external enum) was non-exhaustive from the compiler's perspective, causing "A non-null value must be returned" error
- **Fix:** Added `default: throw ArgumentError('Unsupported ModbusElementType: $type');`
- **Files modified:** packages/tfc_dart/lib/core/state_man.dart
- **Verification:** dart analyze passes, all tests pass
- **Committed in:** 1071564 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Trivial compiler-level fix. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviation above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Config data contract complete: ModbusConfig and ModbusNodeConfig persist through JSON round-tripping
- Phase 9 (StateMan integration) can now use these types to instantiate Modbus adapters from config files
- createModbusDeviceClients accepts typed ModbusConfig, ready for Phase 9 wiring

## Self-Check: PASSED

All files exist. All commits verified.

---
*Phase: 08-config-serialization*
*Completed: 2026-03-06*
