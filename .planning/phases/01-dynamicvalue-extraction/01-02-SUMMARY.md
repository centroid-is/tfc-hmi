---
phase: 01-dynamicvalue-extraction
plan: 02
subsystem: api
tags: [dart, opc-ua, binarize, serialization, refactoring]

# Dependency graph
requires:
  - phase: 01-01
    provides: OpcUaDynamicValueSerializer class with extracted serialization methods
provides:
  - All open62541_dart call sites wired to OpcUaDynamicValueSerializer
  - Full test suite passing with serializer-based calls
  - tfc-hmi3 verified compatible with updated open62541_dart
affects: [06-m2400-protocol]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Production code calls OpcUaDynamicValueSerializer static methods for OPC UA binary serialization"
    - "Test files import opcua_serializer.dart and use static serialize/deserialize calls"

key-files:
  created: []
  modified:
    - /Users/jonb/Projects/open62541_dart/lib/src/common.dart
    - /Users/jonb/Projects/open62541_dart/lib/src/client.dart
    - /Users/jonb/Projects/open62541_dart/test/dynamic_value_test.dart
    - /Users/jonb/Projects/open62541_dart/test/encode_for_write_test.dart

key-decisions:
  - "Removed unnecessary direct import of opcua_serializer.dart from common.dart since barrel export already provides it"
  - "Verified tfc-hmi3 downstream compatibility using temporary local path override (reverted after verification)"

patterns-established:
  - "All OPC UA serialization goes through OpcUaDynamicValueSerializer -- DynamicValue has no serialization awareness"

requirements-completed: [DV-01]

# Metrics
duration: 7min
completed: 2026-03-04
---

# Phase 1 Plan 02: DynamicValue Call Site Updates Summary

**Wired all open62541_dart call sites and tests to OpcUaDynamicValueSerializer, verified zero regression across both open62541_dart (57 tests) and tfc-hmi3 downstream**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-04T10:44:17Z
- **Completed:** 2026-03-04T10:51:40Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Updated common.dart valueToVariant/variantToValue to use OpcUaDynamicValueSerializer.serialize/deserialize instead of removed DynamicValue.set/get
- Updated client.dart's 2 fromDataTypeDefinition call sites to use OpcUaDynamicValueSerializer
- Updated all serialization calls in dynamic_value_test.dart (10 calls) and encode_for_write_test.dart (1 call) to use serializer
- Verified full test suite passes: 57 tests pass, 2 pre-existing skips, 0 failures
- Verified tfc-hmi3 compiles clean against updated open62541_dart (only pre-existing graph widget errors, none related to our changes)
- Confirmed zero remaining references to DynamicValue.get/set/fromDataTypeDefinition outside opcua_serializer.dart

## Task Commits

Each task was committed atomically:

1. **Task 1: Update production call sites (common.dart and client.dart)** - `ecfa158` (feat)
2. **Task 2: Update tests and verify full regression suite passes** - `448ed81` (test)

## Files Created/Modified
- `/Users/jonb/Projects/open62541_dart/lib/src/common.dart` - valueToVariant/variantToValue now call OpcUaDynamicValueSerializer.serialize/deserialize
- `/Users/jonb/Projects/open62541_dart/lib/src/client.dart` - 2 fromDataTypeDefinition calls updated to OpcUaDynamicValueSerializer, added serializer import
- `/Users/jonb/Projects/open62541_dart/test/dynamic_value_test.dart` - All .get()/.set() serialization calls replaced with OpcUaDynamicValueSerializer static methods
- `/Users/jonb/Projects/open62541_dart/test/encode_for_write_test.dart` - DynamicValue.fromDataTypeDefinition replaced with OpcUaDynamicValueSerializer

## Decisions Made
- Removed the explicit `import 'types/opcua_serializer.dart'` from common.dart because the barrel export `package:open62541/open62541.dart` already exports OpcUaDynamicValueSerializer -- dart analyze flagged it as unnecessary_import
- Used temporary local path override in both pubspec.yaml files (tfc-hmi3 and tfc_dart) to verify downstream compatibility, then reverted to git refs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- DynamicValue extraction is fully complete: DynamicValue is now a protocol-agnostic data container with zero binarize/OPC UA dependencies
- The make-dynamicvalue-more-generic branch in open62541_dart has 4 clean commits ready for review/merge
- Phase 1 is complete -- all DV-01 requirements fulfilled
- Future protocols (M2400, M3000, etc.) can now implement their own serializers without touching DynamicValue

## Self-Check: PASSED

- FOUND: /Users/jonb/Projects/open62541_dart/lib/src/common.dart
- FOUND: /Users/jonb/Projects/open62541_dart/lib/src/client.dart
- FOUND: /Users/jonb/Projects/open62541_dart/test/dynamic_value_test.dart
- FOUND: /Users/jonb/Projects/open62541_dart/test/encode_for_write_test.dart
- FOUND: /Users/jonb/Projects/tfc-hmi3/.planning/phases/01-dynamicvalue-extraction/01-02-SUMMARY.md
- FOUND: commit ecfa158 (Task 1) in open62541_dart
- FOUND: commit 448ed81 (Task 2) in open62541_dart

---
*Phase: 01-dynamicvalue-extraction*
*Completed: 2026-03-04*
