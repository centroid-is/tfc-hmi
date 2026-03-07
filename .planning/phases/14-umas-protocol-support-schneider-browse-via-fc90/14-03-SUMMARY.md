---
phase: 14-umas-protocol-support-schneider-browse-via-fc90
plan: 03
subsystem: ui
tags: [flutter, umas, modbus, browse-panel, adapter-pattern, schneider, fc90]

# Dependency graph
requires:
  - phase: 14-01
    provides: UmasClient with browse() returning UmasVariableTreeNode tree
  - phase: 14-02
    provides: BrowseDataSource interface, BrowsePanel widget, showBrowseDialog
provides:
  - UmasBrowseDataSource implementing BrowseDataSource for UMAS variable trees
  - browseUmasNode convenience function for opening UMAS browse dialog
  - ModbusConfig.umasEnabled field with JSON serialization
  - Schneider UMAS checkbox in Modbus server config card
  - Browse button in Modbus key config section for UMAS-enabled servers
  - Data type mapping from UMAS types (REAL, DINT, UINT etc.) to ModbusDataType
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [adapter-pattern, consumer-stateful-widget, null-safe-tcp-client]

key-files:
  created:
    - lib/widgets/umas_browse.dart
    - test/widgets/umas_browse_test.dart
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
    - packages/tfc_dart/lib/core/state_man.g.dart
    - lib/pages/server_config.dart
    - lib/pages/key_repository.dart
    - test/helpers/test_helpers.dart
    - test/pages/server_config_test.dart
    - test/pages/key_repository_test.dart

key-decisions:
  - "browseUmasNode null-checks wrapper.client before use, shows snackbar if not connected"
  - "_ModbusConfigSection converted from StatefulWidget to ConsumerStatefulWidget for stateManProvider access"
  - "_buildConfig helper centralizes ModbusConfig construction from card state (DRY, includes umasEnabled)"
  - "UMAS data type mapping uses switch on uppercase name with byteSize fallback for unknown types"
  - "stateManProvider override added to buildTestableKeyRepository to prevent timer leaks in tests"

patterns-established:
  - "UmasBrowseDataSource: caches full tree on first fetchRoots, serves subsequent calls from cache"
  - "browseUmasNode uses deviceClients.whereType<ModbusDeviceClientAdapter>() to find adapter by alias"
  - "Address calculation from UMAS: blockNo + offset for Modbus holding register address"

requirements-completed: [UMAS-07, UMAS-08, TEST-12]

# Metrics
duration: 10min
completed: 2026-03-07
---

# Phase 14 Plan 03: UMAS Browse Adapter and UI Wiring Summary

**UmasBrowseDataSource adapter connects UMAS variable tree to generic BrowsePanel; checkbox enables UMAS per-server, Browse button auto-fills register address and data type from selected variable**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-07T20:42:24Z
- **Completed:** 2026-03-07T20:52:49Z
- **Tasks:** 2 (1 auto + 1 auto-approved checkpoint)
- **Files modified:** 9

## Accomplishments
- UmasBrowseDataSource correctly adapts UmasClient variable tree to BrowseDataSource interface
- ModbusConfig.umasEnabled field persists through JSON round-trip, defaults false for backward compat
- Schneider UMAS checkbox in server config card toggles umasEnabled and triggers unsaved changes
- Browse button appears in key repository only for UMAS-enabled servers
- Selecting a UMAS variable populates register address (blockNo + offset), register type (holdingRegister), and data type
- 71 total tests passing: 10 umas_browse + 17 server_config + 44 key_repository (15 new tests total)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add umasEnabled to ModbusConfig, create UMAS browse adapter, wire UI** - `0c14a64` (feat)
2. **Task 2: Visual verification** - auto-approved (checkpoint)

## Files Created/Modified
- `lib/widgets/umas_browse.dart` - UmasBrowseDataSource adapter + browseUmasNode convenience function
- `packages/tfc_dart/lib/core/state_man.dart` - Added umasEnabled field to ModbusConfig
- `packages/tfc_dart/lib/core/state_man.g.dart` - Regenerated JSON serialization with umas_enabled
- `lib/pages/server_config.dart` - UMAS checkbox in _ModbusServerConfigCard, _buildConfig helper
- `lib/pages/key_repository.dart` - Browse button in _ModbusConfigSection, UMAS data type mapping
- `test/widgets/umas_browse_test.dart` - 10 tests for UmasBrowseDataSource and serialization
- `test/pages/server_config_test.dart` - 2 tests for UMAS checkbox
- `test/pages/key_repository_test.dart` - 3 tests for Browse button visibility
- `test/helpers/test_helpers.dart` - sampleStateManConfigWithUmas, stateManProvider override

## Decisions Made
- browseUmasNode null-checks wrapper.client before creating UmasClient -- shows snackbar if Modbus not connected
- _ModbusConfigSection converted to ConsumerStatefulWidget to access stateManProvider for browse dialog
- _buildConfig helper centralizes ModbusConfig construction in server config card (DRY, prevents umasEnabled from being lost)
- UMAS data type mapping uses uppercase switch with byteSize fallback for unknown types
- Added stateManProvider.overrideWith(throw) to buildTestableKeyRepository to prevent pending timer leaks

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added stateManProvider override to buildTestableKeyRepository**
- **Found during:** Task 1 (test execution)
- **Issue:** ConsumerStatefulWidget in _ModbusConfigSection caused stateManProvider to be read in tests, triggering real Modbus TCP connections and leaving pending timers
- **Fix:** Added `stateManProvider.overrideWith((ref) => throw StateError('No StateMan in tests'))` to buildTestableKeyRepository helper
- **Files modified:** test/helpers/test_helpers.dart
- **Verification:** All 44 key repository tests pass without pending timer errors
- **Committed in:** 0c14a64

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Test infrastructure fix. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Complete UMAS browse flow is functional: server config checkbox -> key repository Browse button -> variable tree -> auto-fill register config
- Phase 14 is fully complete (plans 01, 02, 03 all done)
- Ready for Phase 13 (manual test against a real device) to validate with actual Schneider PLC

---
*Phase: 14-umas-protocol-support-schneider-browse-via-fc90*
*Completed: 2026-03-07*
