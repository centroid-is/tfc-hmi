---
phase: 15-code-review-fixes-security-performance-correctness-and-duplication
plan: 01
subsystem: core
tags: [modbus, umas, state-man, tcp, performance, security, dead-code]

# Dependency graph
requires:
  - phase: 14-umas-protocol-support-schneider-browse-via-fc90
    provides: UMAS client, types, and browse UI used in this plan's fixes
provides:
  - Immediate throw on key-not-found in StateMan (no 17-minute hang)
  - Bounded UMAS parsing with max name length and variable count limits
  - mapUmasDataTypeToModbus shared utility in domain layer
  - O(1) path-indexed tree lookup in UmasBrowseDataSource
  - BytesBuilder TCP incoming buffer replacing list concatenation
affects: [state-man, umas-client, modbus-tcp, key-repository, umas-browse]

# Tech tracking
tech-stack:
  added: []
  patterns: [BytesBuilder for TCP buffering, extension methods for list lookup, domain-layer utility extraction]

key-files:
  created: []
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
    - packages/tfc_dart/lib/core/umas_types.dart
    - packages/tfc_dart/lib/core/umas_client.dart
    - packages/tfc_dart/lib/core/modbus_device_client.dart
    - lib/pages/key_repository.dart
    - lib/widgets/umas_browse.dart
    - packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart

key-decisions:
  - "BytesBuilder with copy:false for zero-copy TCP buffer accumulation"
  - "findByAlias extension on List<ModbusConfig> keeps lookup local to key_repository.dart"
  - "Path index built once in fetchRoots(), reused for all subsequent lookups"

patterns-established:
  - "Domain utilities in umas_types.dart: shared mapping functions live in the types file, not in UI"
  - "Extension methods for config lookup: prefer typed extensions over cast/firstWhere patterns"

requirements-completed: [CORR-02, CORR-03, CORR-04, SEC-02, DUP-06, DUP-07, DUP-08, PERF-01, PERF-02]

# Metrics
duration: 11min
completed: 2026-03-08
---

# Phase 15 Plan 01: Code Review Fixes Summary

**Fixed 17-min hang bug in StateMan, hardened UMAS parsing with bounds, extracted domain utilities, and improved TCP/tree performance**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-08T07:20:18Z
- **Completed:** 2026-03-08T07:31:33Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Eliminated critical 17-minute hang in StateMan.read()/write() when key not found (CORR-02)
- Hardened UMAS response parsing with max name length (1024B) and max variable count (10000) limits (SEC-02)
- Replaced hardcoded hex sub-function codes with UmasSubFunction enum values (CORR-04)
- Removed dead createModbusDeviceClients function (DUP-06)
- Extracted mapUmasDataTypeToModbus to domain layer, removing UI-layer duplication (DUP-07)
- Added findByAlias extension eliminating unsafe cast/firstWhere pattern (DUP-08)
- O(1) path-indexed tree lookup replacing O(n) recursive search (PERF-01)
- BytesBuilder TCP incoming buffer replacing List<int> concatenation (PERF-02)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix critical correctness bugs and remove dead code** - `dcf7a51` (fix)
2. **Task 2: Harden UMAS parsing, extract domain utilities, improve performance** - `b5e0442` (feat)

## Files Created/Modified
- `packages/tfc_dart/lib/core/state_man.dart` - Removed Future.delayed(seconds: 1000) from read() and write()
- `packages/tfc_dart/lib/core/umas_types.dart` - Removed unused import, added mapUmasDataTypeToModbus utility
- `packages/tfc_dart/lib/core/umas_client.dart` - Enum refs for sub-functions, bounded parsing with limits
- `packages/tfc_dart/lib/core/modbus_device_client.dart` - Removed dead createModbusDeviceClients function
- `lib/pages/key_repository.dart` - Uses mapUmasDataTypeToModbus import, findByAlias extension
- `lib/widgets/umas_browse.dart` - Map-based O(1) path index replacing recursive search
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart` - BytesBuilder for incoming TCP buffer

## Decisions Made
- BytesBuilder with `copy: false` for zero-copy TCP buffer accumulation
- findByAlias extension on List<ModbusConfig> keeps lookup local to key_repository.dart (only used there)
- Path index built once in fetchRoots(), reused for all subsequent lookups

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All correctness, security, dead code, and performance fixes from Plan 01 are complete
- Ready for Plan 02 (remaining code review fixes)

---
*Phase: 15-code-review-fixes-security-performance-correctness-and-duplication*
*Completed: 2026-03-08*
