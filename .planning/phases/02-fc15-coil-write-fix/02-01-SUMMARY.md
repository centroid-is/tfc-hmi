---
phase: 02-fc15-coil-write-fix
plan: 01
subsystem: modbus-library
tags: [modbus, fc15, coils, pdu-encoding, tdd, dart]

# Dependency graph
requires: []
provides:
  - "Fixed getMultipleWriteRequest with optional quantity parameter for FC15"
  - "Local modbus_client 1.4.4 fork in packages/modbus_client/"
  - "FC15 PDU encoding tests for 1, 8, 9, 15, 16, 17, 32, 64 coils"
  - "FC16 regression tests confirming backward compatibility"
  - "FC15 response parsing test"
affects: [06-writing, modbus_client, modbus_client_tcp]

# Tech tracking
tech-stack:
  added: [modbus_client 1.4.4 (local fork)]
  patterns: [PDU byte inspection testing, optional quantity parameter for multi-element writes]

key-files:
  created:
    - packages/modbus_client/ (full fork from pub cache)
    - packages/modbus_client/test/modbus_fc15_test.dart
  modified:
    - packages/modbus_client/lib/src/modbus_element.dart
    - packages/modbus_client/pubspec.yaml
    - packages/modbus_client_tcp/pubspec.yaml

key-decisions:
  - "Optional quantity parameter approach over ModbusBitElement override -- parameter is the only way to accurately convey coil count since it cannot be recovered from packed byte count"
  - "Added publish_to: none to both fork pubspec.yaml files to satisfy dart analyze with path dependencies"

patterns-established:
  - "PDU byte inspection for FC15: inspect protocolDataUnit[3:4] for quantity, [5] for byte count"
  - "Parameterized test helper (testCoilQuantity) for boundary case coverage"

requirements-completed: [LIBFIX-01, TEST-02]

# Metrics
duration: 3min
completed: 2026-03-06
---

# Phase 2 Plan 01: FC15 Coil Write Fix Summary

**Fixed FC15 Write Multiple Coils quantity encoding via optional `quantity` parameter in getMultipleWriteRequest, with TDD boundary tests for 1-64 coils**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-06T14:18:26Z
- **Completed:** 2026-03-06T14:21:31Z
- **Tasks:** 2
- **Files modified:** 3 (modbus_element.dart, 2x pubspec.yaml) + 1 new test file + full fork

## Accomplishments
- FC15 (Write Multiple Coils) correctly encodes quantity for all tested coil counts (1, 8, 9, 15, 16, 17, 32, 64)
- FC16 (Write Multiple Registers) backward compatibility preserved via null-coalescing fallback
- Local modbus_client 1.4.4 fork established in packages/ with proper dependency chain
- All 29 modbus_client tests pass, all 13 modbus_client_tcp tests pass, dart analyze clean

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Fork modbus_client and write failing FC15 tests** - `fb0526f` (test)
2. **Task 2: GREEN -- Fix getMultipleWriteRequest quantity parameter** - `20445b0` (feat)

## Files Created/Modified
- `packages/modbus_client/` - Full fork of modbus_client 1.4.4 from pub cache
- `packages/modbus_client/test/modbus_fc15_test.dart` - 12 tests: 8 FC15 quantity boundary, 2 FC16 regression, 1 FC15 response parsing, 1 helper
- `packages/modbus_client/lib/src/modbus_element.dart` - Added optional `quantity` parameter to `getMultipleWriteRequest`, changed quantity encoding to `quantity ?? bytes.length ~/ 2`
- `packages/modbus_client/pubspec.yaml` - Added `publish_to: none`, updated modbus_client_tcp dev dep to path
- `packages/modbus_client_tcp/pubspec.yaml` - Changed modbus_client dep from `^1.4.2` to `path: ../modbus_client`, added `publish_to: none`

## Decisions Made
- Used optional `quantity` parameter approach (not ModbusBitElement override) because coil count cannot be recovered from packed byte count
- Added `publish_to: none` to both fork pubspec.yaml files to eliminate dart analyze warnings about path dependencies in publishable packages
- Added `assert(quantity == null || quantity > 0)` for debug-mode validation of caller input

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added publish_to: none to fork pubspec.yaml files**
- **Found during:** Task 2 (dart analyze step)
- **Issue:** dart analyze warned about path dependencies in publishable packages
- **Fix:** Added `publish_to: none` to both `packages/modbus_client/pubspec.yaml` and `packages/modbus_client_tcp/pubspec.yaml`
- **Files modified:** packages/modbus_client/pubspec.yaml, packages/modbus_client_tcp/pubspec.yaml
- **Verification:** `dart analyze` returns zero issues in both packages
- **Committed in:** 20445b0 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Necessary for clean analyzer output. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- modbus_client local fork is ready for future modifications (Phase 6: Writing will use getMultipleWriteRequest with quantity for FC15 coil writes)
- modbus_client_tcp correctly depends on the local fork (path dependency chain verified)
- All tests green across both packages

## Self-Check: PASSED

All files verified present. All commits verified in git log. Test file 112 lines (min: 40).

---
*Phase: 02-fc15-coil-write-fix*
*Completed: 2026-03-06*
