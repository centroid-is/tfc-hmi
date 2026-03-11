---
phase: 18-modbus-enhancements-address-base-bit-masking-multi-protocol-key-dialog
plan: 03
subsystem: core, ui
tags: [modbus, opcua, bitmask, stateman, flutter-widget]

# Dependency graph
requires:
  - phase: 18-modbus-enhancements-address-base-bit-masking-multi-protocol-key-dialog
    provides: "Address base feature (18-01), multi-protocol KeyMappingEntryDialog (18-02)"
provides:
  - "KeyMappingEntry.bitMask/bitShift fields with JSON serialization"
  - "StateMan.applyBitMask static helper (single-bit -> bool, multi-bit -> int)"
  - "Modbus adapter bit masking in _toDynamicValue and read-modify-write in write"
  - "OPC UA read() and _monitor() bit masking via shared applyBitMask helper"
  - "BitMaskGrid widget with toggleable bit buttons and hex display"
  - "Bit Mask ExpansionTile in key repository for Modbus and OPC UA numeric keys"
affects: [key-repository, state-man, modbus-adapter]

# Tech tracking
tech-stack:
  added: []
  patterns: ["protocol-agnostic bit masking via static helper", "read-modify-write for masked writes"]

key-files:
  created:
    - "lib/widgets/bit_mask_grid.dart"
    - "packages/tfc_dart/test/core/state_man_bitmask_test.dart"
  modified:
    - "packages/tfc_dart/lib/core/state_man.dart"
    - "packages/tfc_dart/lib/core/state_man.g.dart"
    - "packages/tfc_dart/lib/core/modbus_client_wrapper.dart"
    - "packages/tfc_dart/lib/core/modbus_device_client.dart"
    - "lib/pages/key_repository.dart"
    - "packages/tfc_dart/test/core/modbus_device_client_test.dart"
    - "test/pages/key_repository_test.dart"

key-decisions:
  - "applyBitMask as static method on StateMan for shared use by Modbus adapter and OPC UA paths"
  - "Single-bit mask (power-of-two) returns Boolean DynamicValue, multi-bit returns int"
  - "Bit mask section hidden for coil/discreteInput/bit types where masking is not applicable"
  - "bitMask/bitShift preserved through all update methods in key repository (8 places)"

patterns-established:
  - "Protocol-agnostic bit masking: single static helper used by both Modbus and OPC UA code paths"
  - "Read-modify-write pattern for masked writes: read current value, apply mask, write back"

requirements-completed: [MASK-01, MASK-02]

# Metrics
duration: 22min
completed: 2026-03-11
---

# Phase 18 Plan 03: Bit Masking Summary

**Protocol-agnostic bit mask extraction with visual BitMaskGrid UI for Modbus and OPC UA register keys**

## Performance

- **Duration:** 22 min
- **Started:** 2026-03-11T14:35:47Z
- **Completed:** 2026-03-11T14:57:47Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- KeyMappingEntry.bitMask/bitShift fields with backward-compatible JSON serialization (null defaults)
- StateMan.applyBitMask: single-bit mask returns bool, multi-bit returns unsigned int, non-numeric passthrough
- Modbus reads masked via shared helper in _toDynamicValue; writes use read-modify-write to preserve unmasked bits
- OPC UA read() and _monitor() subscribe paths apply bitMask/bitShift before returning values
- BitMaskGrid widget: toggleable bit buttons in rows of 8, hex mask display, bit range labels
- Bit Mask section in key repository UI for both Modbus and OPC UA numeric keys
- 34 backend tests + 47 widget tests all pass

## Task Commits

Each task was committed atomically:

1. **Task 1: TDD RED - failing tests** - `ff8e398` (test)
2. **Task 1: TDD GREEN - bitMask/bitShift data model + Modbus + OPC UA** - `72f2b92` (feat)
3. **Task 2: BitMaskGrid widget + key repository UI** - `b403f6b` (feat)

## Files Created/Modified
- `packages/tfc_dart/lib/core/state_man.dart` - KeyMappingEntry.bitMask/bitShift fields, StateMan.applyBitMask helper, OPC UA read/subscribe masking
- `packages/tfc_dart/lib/core/state_man.g.dart` - Regenerated JSON serialization with bit_mask/bit_shift
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - ModbusRegisterSpec.bitMask/bitShift fields
- `packages/tfc_dart/lib/core/modbus_device_client.dart` - _toDynamicValue masking, write read-modify-write, buildSpecs threading
- `lib/widgets/bit_mask_grid.dart` - New visual bit toggle grid widget
- `lib/pages/key_repository.dart` - Bit Mask ExpansionTile, _isBitType/_bitCountForDataType helpers, bitMask preservation in update methods
- `packages/tfc_dart/test/core/state_man_bitmask_test.dart` - 9 tests for applyBitMask helper + JSON round-trip
- `packages/tfc_dart/test/core/modbus_device_client_test.dart` - 6 new tests for masked reads/writes/buildSpecs
- `test/pages/key_repository_test.dart` - 3 new tests for Bit Mask section visibility + fix fragile ExpansionTile counts

## Decisions Made
- applyBitMask as static method on StateMan for shared use by Modbus adapter and OPC UA paths (avoids import cycles)
- Single-bit mask detection via power-of-two check: `bitMask != 0 && (bitMask & (bitMask - 1)) == 0`
- Bit mask section hidden for coil/discreteInput/bit types (masking is not applicable to inherently boolean registers)
- M2400 keys excluded from bit mask UI (non-integer structured record protocol)
- bitMask/bitShift preserved through all 8 update methods in _KeyMappingCardState to prevent data loss

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Preserve bitMask/bitShift in update methods**
- **Found during:** Task 2 (key repository UI integration)
- **Issue:** 8 update methods in _KeyMappingCardState created new KeyMappingEntry without bitMask/bitShift, losing the values on any config change
- **Fix:** Added bitMask/bitShift parameters to all KeyMappingEntry constructors in _updateOpcUaConfig, _updateModbusConfig, _switchToOpcUa, _switchToModbus, _updateCollectEntry, _toggleCollect
- **Files modified:** lib/pages/key_repository.dart
- **Verification:** Widget tests verify mask section renders; config changes don't lose mask values
- **Committed in:** b403f6b (Task 2 commit)

**2. [Rule 1 - Bug] Fix fragile ExpansionTile count assertions in existing tests**
- **Found during:** Task 2 (test verification)
- **Issue:** 3 existing tests counted ExpansionTile widgets to verify card count, but nested Bit Mask ExpansionTile (visible when card expanded) changed the count
- **Fix:** Replaced ExpansionTile counts with text-based finders that match actual key names
- **Files modified:** test/pages/key_repository_test.dart
- **Verification:** All 47 widget tests pass
- **Committed in:** b403f6b (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered
- NodeId.string does not exist in open62541 API (it is NodeId.uastring) -- fixed in test immediately

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 18 complete: all 3 plans delivered (address base, multi-protocol dialog, bit masking)
- Bit masking works for both Modbus and OPC UA keys
- Ready for production testing with real devices

---
*Phase: 18-modbus-enhancements-address-base-bit-masking-multi-protocol-key-dialog*
*Completed: 2026-03-11*
