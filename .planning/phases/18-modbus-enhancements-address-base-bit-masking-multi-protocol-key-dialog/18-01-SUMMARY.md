---
phase: 18-modbus-enhancements-address-base-bit-masking-multi-protocol-key-dialog
plan: 01
subsystem: modbus
tags: [modbus, addressing, config, ui, dropdown]

# Dependency graph
requires:
  - phase: 16-modbus-protocol-spec-research-find-bugs-and-missing-features
    provides: ModbusRegisterSpec endianness field pattern, buildSpecsFromKeyMappings optional params
provides:
  - ModbusConfig.addressBase field with JSON serialization (0 or 1)
  - Wire-level address offset in _createElement (address - addressBase)
  - Address Base dropdown in Modbus server config UI
  - buildSpecsFromKeyMappings addressBase parameter
affects: [18-02, 18-03]

# Tech tracking
tech-stack:
  added: []
  patterns: [per-device addressBase offset applied at wire level in _createElement]

key-files:
  created:
    - test/pages/server_config_address_base_test.dart
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
    - packages/tfc_dart/lib/core/state_man.g.dart
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart
    - packages/tfc_dart/lib/core/modbus_device_client.dart
    - lib/pages/server_config.dart
    - packages/tfc_dart/test/core/modbus_client_wrapper_test.dart
    - packages/tfc_dart/test/core/modbus_device_client_test.dart

key-decisions:
  - "addressBase applied in _createElement as address-addressBase with debug assert >= 0"
  - "Address Base dropdown positioned between Byte Order and UMAS checkbox (follows existing config section pattern)"

patterns-established:
  - "Per-device config fields flow: ModbusConfig -> buildSpecsFromKeyMappings -> ModbusRegisterSpec -> _createElement wire offset"

requirements-completed: [ADDR-01]

# Metrics
duration: 12min
completed: 2026-03-11
---

# Phase 18 Plan 01: Address Base Summary

**Configurable 0/1-based Modbus register addressing per server with wire offset subtraction and UI dropdown**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-11T14:20:59Z
- **Completed:** 2026-03-11T14:33:00Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- ModbusConfig.addressBase field (int, default 0) persists through JSON with backward compatibility
- Wire address = UI address - addressBase applied in _createElement with debug assert
- Address Base dropdown with "0 (Protocol Default)" and "1 (Modicon/Schneider)" options plus vendor info tooltip
- 11 new tests (8 backend + 3 widget) all pass, 133 existing backend tests unaffected

## Task Commits

Each task was committed atomically:

1. **Task 1: Add addressBase to data model and apply wire offset** - `4a5a161` (test) + `43c097f` (feat)
2. **Task 2: Add Address Base dropdown to Modbus server config UI** - `0b3f1a9` (test) + `80c6d71` (feat)

_Note: TDD tasks have two commits each (test RED -> feat GREEN)_

## Files Created/Modified
- `packages/tfc_dart/lib/core/state_man.dart` - Added addressBase field to ModbusConfig with @JsonKey
- `packages/tfc_dart/lib/core/state_man.g.dart` - Regenerated with address_base JSON serialization
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - Added addressBase to ModbusRegisterSpec, wire offset in _createElement
- `packages/tfc_dart/lib/core/modbus_device_client.dart` - Added addressBase param to buildSpecsFromKeyMappings, threaded through buildModbusDeviceClients
- `lib/pages/server_config.dart` - Address Base dropdown with _addressBase state, info tooltip, _buildConfig integration
- `test/pages/server_config_address_base_test.dart` - 3 widget tests for dropdown rendering, selection, and info icon
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - 5 tests for JSON round-trip and wire offset
- `packages/tfc_dart/test/core/modbus_device_client_test.dart` - 3 tests for spec builder and client builder

## Decisions Made
- addressBase applied in _createElement as `address - addressBase` with debug assert >= 0 (crash-safe in debug, no-op in release)
- Address Base dropdown positioned between Byte Order and UMAS checkbox (follows existing config section layout pattern)
- Used same `value` parameter pattern as existing Byte Order dropdown (pre-existing deprecation, not introduced here)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Address base feature complete and tested
- Ready for Phase 18 Plan 02 (bit masking) and Plan 03 (multi-protocol key dialog)
- No blockers

---
*Phase: 18-modbus-enhancements-address-base-bit-masking-multi-protocol-key-dialog*
*Completed: 2026-03-11*

## Self-Check: PASSED

All 8 files verified present. All 4 commits (4a5a161, 43c097f, 0b3f1a9, 80c6d71) verified in git log.
