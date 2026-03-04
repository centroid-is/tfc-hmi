---
phase: 05-m2400-field-catalog
plan: 01
subsystem: jbtm/m2400-fields
tags: [m2400, field-catalog, parsing, enums, tdd]
dependency_graph:
  requires: [m2400.dart (M2400Record, M2400RecordType)]
  provides: [M2400Field enum, FieldType enum, WeigherStatus enum, M2400ParsedRecord, parseTypedRecord, parseFieldValue, extractTimestamp, expectedFields]
  affects: [05-02 (stub server alignment), Phase 6 (DynamicValue conversion), Phase 10 (UI dropdowns)]
tech_stack:
  added: []
  patterns: [enhanced enum with fromId(), typed record wrapper, per-field type-safe parsing]
key_files:
  created:
    - packages/jbtm/lib/src/m2400_fields.dart
    - packages/jbtm/lib/src/m2400_field_parser.dart
    - packages/jbtm/test/m2400_fields_test.dart
    - packages/jbtm/test/m2400_field_parser_test.dart
  modified: []
decisions:
  - "Renamed enum value 'id' to 'recordId' to avoid shadowing the 'id' instance getter on M2400Field"
  - "Weight values parsed to double directly (no Decimal package) per context decision"
  - "Field 77 (SI Weight) classified as FieldType.string -- display-ready, no suffix stripping"
  - "Unknown field IDs logged at debug level (not warning) per context decision"
  - "Non-numeric field keys logged at debug level per context decision"
metrics:
  duration: 5min
  completed: 2026-03-04
---

# Phase 5 Plan 01: M2400 Field Catalog and Type-Specific Parsing Summary

M2400Field enum (54 values) with FieldType metadata and parseTypedRecord converting raw Map<String, String> to typed M2400ParsedRecord with double/int/String values.

## What Was Built

### Task 1: M2400Field, FieldType, WeigherStatus Enums (TDD)
- **FieldType enum** with 7 variants: decimal, integer, string, percentage, date, time, timeMs
- **M2400Field enum** with 54 values: 3 confirmed (weight/1, unit/2, siWeight/77), 7 device-observed provisionals (field6/6 through field81/81), 44 requirement-defined placeholders (id=0)
- **WeigherStatus enum** with 9 defined codes (bad through badOver) plus unknown fallback
- **expectedFields** map: recStat has 2 fields, recBatch has 10 fields
- **fromId()** returns null for placeholder IDs (<=0) and unknown IDs
- 34 tests covering all fromId lookups, fieldType metadata, enum completeness, and WeigherStatus codes

### Task 2: M2400ParsedRecord and parseTypedRecord (TDD)
- **M2400ParsedRecord** class with typedFields, unknownFields, rawFields, receivedAt, deviceTimestamp
- **parseFieldValue()** pure function: decimal->double, integer->int, string->passthrough, percentage->double, date/time/timeMs->string
- **parseTypedRecord()** converts M2400Record to M2400ParsedRecord with per-field error isolation
- **extractTimestamp()** combines date+time+timeMs fields into DateTime (null when absent)
- Convenience getters: weight, unitString, siWeight, weigherStatus
- 31 tests covering real WGT/STAT record parsing, unknown fields, parse failures, LUA records, timestamps

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Renamed enum value 'id' to 'recordId'**
- **Found during:** Task 1 implementation
- **Issue:** The enum value `id(0, 'ID', FieldType.integer)` shadowed the `id` instance getter on M2400Field, causing compilation errors when tests accessed `field.id`
- **Fix:** Renamed enum value to `recordId(0, 'ID', FieldType.integer)`
- **Files modified:** packages/jbtm/lib/src/m2400_fields.dart
- **Commit:** ddf7793

## Verification

```
cd packages/jbtm && dart test
158 tests passed (93 existing + 34 field + 31 parser)
```

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 RED | 258bada | test(05-01): add failing tests for M2400Field, FieldType, WeigherStatus enums |
| 1 GREEN | ddf7793 | feat(05-01): implement M2400Field, FieldType, WeigherStatus enums and expectedFields |
| 2 RED | 015fa4e | test(05-01): add failing tests for M2400ParsedRecord, parseTypedRecord, extractTimestamp |
| 2 GREEN | 3c36562 | feat(05-01): implement M2400ParsedRecord, parseTypedRecord, and extractTimestamp |
