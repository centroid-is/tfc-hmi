---
phase: 09-configuration-multi-device
plan: 01
subsystem: jbtm, tfc_dart
tags: [m2400, config, state-man, json-serializable, key-mapping]
dependency_graph:
  requires:
    - "Phase 5: M2400 field catalog (M2400RecordType, M2400Field enums)"
  provides:
    - "M2400Config: JSON-serializable server config (host, port, server_alias)"
    - "M2400NodeConfig: JSON-serializable key addressing (record_type, field, server_alias)"
    - "StateManConfig.jbtm: parallel to opcua list, backwards compatible"
    - "KeyMappingEntry.m2400Node: alongside opcuaNode with unified server alias resolution"
  affects:
    - "Phase 9 Plan 02: multi-device lifecycle (consumes M2400Config)"
    - "Phase 10: UI (consumes M2400Config for server settings, M2400NodeConfig for key creation)"
tech_stack:
  added: ["jbtm dependency in tfc_dart"]
  patterns: ["M2400Config mirrors OpcUAConfig pattern", "backwards-compatible @JsonKey(defaultValue) for new list fields"]
key_files:
  created:
    - packages/tfc_dart/test/state_man_config_test.dart
  modified:
    - packages/tfc_dart/lib/core/state_man.dart
    - packages/tfc_dart/lib/core/state_man.g.dart
    - packages/tfc_dart/pubspec.yaml
key_decisions:
  - "tfc_dart depends on jbtm (path dependency) to import M2400RecordType and M2400Field enums directly"
  - "M2400NodeConfig uses enum name serialization (json_serializable default) for record_type and field"
  - "@JsonKey(defaultValue: []) on StateManConfig.jbtm ensures backwards compatibility with existing configs"
  - "KeyMappingEntry.server getter prioritizes opcuaNode.serverAlias over m2400Node.serverAlias"
patterns_established:
  - "M2400Config follows OpcUAConfig pattern: JSON-serializable with server_alias key"
  - "New list fields on StateManConfig use @JsonKey(defaultValue: []) for backwards compatibility"
requirements-completed: [CFG-01, CFG-02, CFG-03]
metrics:
  duration: "4min"
  completed: "2026-03-04"
  tasks_completed: 2
  tasks_total: 2
  tests_added: 24
  tests_total: 194
---

# Phase 9 Plan 01: M2400 Configuration Models Summary

**JSON-serializable M2400Config and M2400NodeConfig classes with backwards-compatible StateManConfig extension and unified server alias resolution in KeyMappingEntry**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-04T14:48:07Z
- **Completed:** 2026-03-04T14:55:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- M2400Config and M2400NodeConfig with full JSON round-trip serialization
- StateManConfig extended with jbtm list, backwards compatible with existing JSON
- KeyMappingEntry extended with m2400Node, unified server alias resolution
- KeyMappings.lookupServerAlias and filterByServer work for both OPC UA and M2400 entries
- 24 comprehensive tests covering serialization, defaults, backwards compatibility, and regression

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests for M2400 config models** - `7daff43` (test)
2. **Task 1 (GREEN): Implement M2400Config, M2400NodeConfig, extend StateManConfig and KeyMappingEntry** - `967cc94` (feat)
3. **Task 2: Verify build_runner and full test suite** - No commit needed (verification-only, no file changes)

## Files Created/Modified
- `packages/tfc_dart/lib/core/state_man.dart` - Added M2400Config, M2400NodeConfig classes; extended StateManConfig and KeyMappingEntry
- `packages/tfc_dart/lib/core/state_man.g.dart` - Regenerated serialization code for new types
- `packages/tfc_dart/pubspec.yaml` - Added jbtm path dependency
- `packages/tfc_dart/test/state_man_config_test.dart` - 24 tests for all M2400 config behaviors

## Decisions Made
- **tfc_dart depends on jbtm**: Added path dependency so M2400RecordType and M2400Field enums can be directly referenced in M2400NodeConfig serialization. This avoids duplicating enum definitions.
- **Enum name serialization**: json_serializable serializes M2400RecordType and M2400Field as their Dart enum names (e.g., "recBatch", "weight"). This matches the subscribe key naming convention established in Phase 7.
- **Backwards compatibility via @JsonKey(defaultValue)**: Existing StateManConfig JSON without a "jbtm" key deserializes cleanly with an empty list default.
- **Server alias precedence**: KeyMappingEntry.server returns opcuaNode.serverAlias first, falling through to m2400Node.serverAlias. This prevents confusion when both are set (unlikely but defensive).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- M2400Config and M2400NodeConfig are ready for Plan 02 (multi-device lifecycle)
- StateManConfig.jbtm available for createM2400DeviceClients factory
- KeyMappingEntry.m2400Node ready for subscribe routing in StateMan

---
*Phase: 09-configuration-multi-device*
*Completed: 2026-03-04*
