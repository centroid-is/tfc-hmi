---
phase: 16-modbus-protocol-spec-research-find-bugs-and-missing-features
plan: 02
subsystem: modbus
tags: [modbus, validation, error-handling, address-range, unit-id, tdd]

# Dependency graph
requires:
  - phase: 05-modbusclientwrapper-reading
    provides: ModbusRegisterSpec, poll groups, subscribe/read API
  - phase: 06-modbusclientwrapper-writing
    provides: write/writeMultiple API with StateError on failure
  - phase: 10-server-config-ui
    provides: Server config UI with unit ID field
  - phase: 11-key-repository-ui
    provides: Key repository Modbus config section with address field
provides:
  - Address validation at spec, config, and UI layers (0-65535)
  - Rich write error messages with hex code and human-readable description
  - Expanded unit ID range 0-255 for Modbus TCP
affects: [modbus-wrapper, server-config, key-repository]

# Tech tracking
tech-stack:
  added: []
  patterns: [defensive-clamping-for-json-deserialized-configs, assertion-for-code-constructed-specs, rich-exception-description-helper]

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/modbus_client_wrapper.dart
    - packages/tfc_dart/lib/core/state_man.dart
    - lib/pages/server_config.dart
    - lib/pages/key_repository.dart
    - packages/tfc_dart/test/core/modbus_client_wrapper_test.dart

key-decisions:
  - "Assert for ModbusRegisterSpec (code-constructed), clamp for ModbusNodeConfig (JSON-deserialized) -- crash-safe on bad stored data"
  - "Unit ID 0-255 for TCP mode without warnings -- all values are spec-valid in TCP context"
  - "_describeException covers standard Modbus codes 0x01-0x0B plus library transport codes"

patterns-established:
  - "Defensive clamping: JSON-deserialized config classes clamp out-of-range values instead of asserting"
  - "Rich error messages: write failures include enum name, hex code, and human-readable description"

requirements-completed: [BUG-01, VAL-03, FEAT-03]

# Metrics
duration: 12min
completed: 2026-03-09
---

# Phase 16 Plan 02: Wrapper/UI Fixes Summary

**Address validation to 0-65535 at three layers, unit ID expanded to 0-255 for TCP, and write errors surfacing hex code with human-readable Modbus exception descriptions**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-09T10:45:08Z
- **Completed:** 2026-03-09T10:57:21Z
- **Tasks:** 2 (TDD: 4 commits -- 2 RED + 2 GREEN)
- **Files modified:** 5

## Accomplishments
- Address validated at three layers: assertion in ModbusRegisterSpec, clamping in ModbusNodeConfig, clamping in key repository UI
- Write error messages now include exception code name, hex value (e.g. 0x02), and plain English description
- Unit ID range expanded from 1-247 to 0-255 in both server config UI and ModbusConfig constructor
- 11 new tests covering address bounds, write error format, and unit ID clamping

## Task Commits

Each task was committed atomically:

1. **Task 1: Add address validation and rich write error messages (BUG-01 + FEAT-03)**
   - `bacaa6c` (test: failing tests for address validation and rich write errors)
   - `2e8deda` (feat: address validation at 3 layers + _describeException helper)
2. **Task 2: Expand unit ID range to 0-255 for TCP (VAL-03)**
   - `07da85a` (test: failing tests for unit ID range expansion)
   - `554bd2d` (feat: ModbusConfig clamp + UI range + hint text update)

## Files Created/Modified
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - Address assertion in ModbusRegisterSpec, rich write errors with _describeException helper
- `packages/tfc_dart/lib/core/state_man.dart` - ModbusNodeConfig address clamp 0-65535, ModbusConfig unitId clamp 0-255
- `lib/pages/server_config.dart` - Unit ID clamp 0-255, hint text '0-255'
- `lib/pages/key_repository.dart` - Address clamp 0-65535 in _notifyChanged
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - 11 new tests (4 address + 2 write error + 5 unit ID)

## Decisions Made
- **Assert vs clamp strategy:** ModbusRegisterSpec uses assertion (code-constructed, should catch programmer errors) while ModbusNodeConfig and ModbusConfig use clamping (JSON-deserialized, should not crash on bad stored data).
- **No warnings for unit ID 0 or 248-254:** These are valid TCP values per the Modbus Implementation Guide. Warnings would confuse users who intentionally use them.
- **_describeException covers transport codes too:** Added requestTimeout, connectionFailed, requestTxFailed, requestRxFailed beyond the standard 0x01-0x0B Modbus exception codes for completeness.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All three wrapper/UI fixes from the spec audit are complete
- Ready for Plan 03 (multi-register data type fixes) if present
- 186 core tests passing, no regressions

---
*Phase: 16-modbus-protocol-spec-research-find-bugs-and-missing-features*
*Completed: 2026-03-09*

## Self-Check: PASSED

All 5 modified files exist. All 4 task commits verified (bacaa6c, 2e8deda, 07da85a, 554bd2d).
