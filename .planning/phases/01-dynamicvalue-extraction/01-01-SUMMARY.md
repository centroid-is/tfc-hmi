---
phase: 01-dynamicvalue-extraction
plan: 01
subsystem: api
tags: [dart, opc-ua, binarize, serialization, refactoring]

# Dependency graph
requires: []
provides:
  - OpcUaDynamicValueSerializer class with extracted OPC UA binary serialization logic
  - Protocol-agnostic DynamicValue data container (no binarize dependency)
affects: [02-dynamicvalue-callers, 06-m2400-protocol]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Protocol-specific serializers as separate classes with static methods"
    - "DynamicValue as pure data container, serialization external"

key-files:
  created:
    - /Users/jonb/Projects/open62541_dart/lib/src/types/opcua_serializer.dart
  modified:
    - /Users/jonb/Projects/open62541_dart/lib/src/dynamic_value.dart
    - /Users/jonb/Projects/open62541_dart/lib/open62541.dart

key-decisions:
  - "Used static methods on OpcUaDynamicValueSerializer (no instance state needed)"
  - "autoDeduceType made private static (_autoDeduceType) on serializer since only used internally by serialize()"

patterns-established:
  - "Protocol serializer pattern: static deserialize/serialize methods taking DynamicValue schema + reader/writer"
  - "DynamicValue has no protocol imports -- only dart:collection and node_id.dart"

requirements-completed: [DV-01]

# Metrics
duration: 3min
completed: 2026-03-04
---

# Phase 1 Plan 01: DynamicValue Extraction Summary

**Extracted OPC UA serialization (get/set/fromDataTypeDefinition/autoDeduceType) into OpcUaDynamicValueSerializer, stripped DynamicValue of PayloadType inheritance and all binarize dependencies**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-04T10:38:20Z
- **Completed:** 2026-03-04T10:41:52Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created OpcUaDynamicValueSerializer with 4 static methods (deserialize, serialize, fromDataTypeDefinition, _autoDeduceType) extracted from DynamicValue
- Stripped DynamicValue of PayloadType<DynamicValue> inheritance, removing all binarize/FFI/OPC UA imports
- DynamicValue is now a pure data container with zero protocol dependencies (only dart:collection and node_id.dart)
- All recursive serialization calls updated to go through the new static serializer methods

## Task Commits

Each task was committed atomically:

1. **Task 1: Create OpcUaDynamicValueSerializer with extracted get/set/fromDataTypeDefinition** - `d6f8b22` (feat)
2. **Task 2: Strip DynamicValue of PayloadType inheritance and serialization methods** - `893672c` (refactor)

## Files Created/Modified
- `/Users/jonb/Projects/open62541_dart/lib/src/types/opcua_serializer.dart` - New file: OpcUaDynamicValueSerializer with deserialize, serialize, fromDataTypeDefinition, _autoDeduceType static methods
- `/Users/jonb/Projects/open62541_dart/lib/src/dynamic_value.dart` - Removed PayloadType inheritance, binarize imports, get/set/fromDataTypeDefinition/autoDeduceType methods (179 lines removed)
- `/Users/jonb/Projects/open62541_dart/lib/open62541.dart` - Added export of OpcUaDynamicValueSerializer

## Decisions Made
- Used static methods on a standalone class (not extension methods) because: (a) makes OPC UA dependency explicit, (b) can be tested independently, (c) future protocols create their own serializer classes, (d) matches stateless nature of current get/set
- Made autoDeduceType a private static (_autoDeduceType) since it is only called by serialize() internally
- Kept node_id.dart import on DynamicValue per locked decision (NodeId stays on DynamicValue for now)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- OpcUaDynamicValueSerializer is ready but call sites (common.dart, client.dart, test files) still reference the old DynamicValue.get/set methods
- Plan 02 should update all call sites to use the new serializer, then verify full test suite passes
- The make-dynamicvalue-more-generic branch in open62541_dart has both commits ready

## Self-Check: PASSED

- FOUND: /Users/jonb/Projects/open62541_dart/lib/src/types/opcua_serializer.dart
- FOUND: /Users/jonb/Projects/tfc-hmi3/.planning/phases/01-dynamicvalue-extraction/01-01-SUMMARY.md
- FOUND: commit d6f8b22 (Task 1)
- FOUND: commit 893672c (Task 2)

---
*Phase: 01-dynamicvalue-extraction*
*Completed: 2026-03-04*
