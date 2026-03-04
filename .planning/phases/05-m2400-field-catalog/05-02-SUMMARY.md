---
phase: 05-m2400-field-catalog
plan: 02
subsystem: jbtm/m2400-stub-server
tags: [m2400, stub-server, barrel-exports, integration-test]
dependency_graph:
  requires: [05-01 (M2400Field enum, parseTypedRecord)]
  provides: [realistic stub server factories, barrel exports for downstream phases]
  affects: [Phase 6 (DynamicValue conversion), Phase 7 (state_man integration), Phase 10 (UI)]
tech_stack:
  added: []
  patterns: [enum-driven field IDs as single source of truth]
key_files:
  created: []
  modified:
    - packages/jbtm/lib/src/m2400_stub_server.dart
    - packages/jbtm/lib/jbtm.dart
    - packages/jbtm/test/m2400_stub_server_test.dart
decisions:
  - "makeIntroFields uses string keys ('devId', 'firmware') since INTRO record field IDs not confirmed from device"
  - "Stub server imports M2400Field enum directly as single source of truth for field IDs"
metrics:
  duration: 3min
  completed: 2026-03-04
---

# Phase 5 Plan 02: Stub Server Alignment and Barrel Exports Summary

Stub server factories aligned to real M2400Field IDs with round-trip integration tests proving end-to-end typed parsing.

## What Was Built

### Task 1: Update stub server, barrel exports, round-trip tests
- **Removed** 5 placeholder constants (_kWeight='100', _kStatus='101', _kDevId='102', _kFirmware='103', _kUnit='104')
- **makeWeightFields()** updated to produce all 10 observed WGT fields using M2400Field.id (1, 2, 77, 6, 11, 59, 78, 79, 80, 81)
- **makeStatFields()** updated with real field IDs for weight(1) + unit(2), with realistic defaults
- **makeIntroFields()** uses string keys (INTRO field IDs not yet confirmed from device)
- **jbtm.dart** barrel now exports m2400_fields.dart and m2400_field_parser.dart
- **Round-trip WGT test**: stub server -> MSocket -> M2400FrameParser -> parseM2400Frame -> parseTypedRecord -> assert weight==12.5, unit=='kg', siWeight=='11.00kg', unknownFields empty
- **Round-trip STAT test**: stub server -> full pipeline -> assert weight==12.37, unit=='kg'
- Updated existing tests for new API signatures (no more `status` parameter on pushWeightRecord/pushStatRecord)

## Deviations from Plan

None - plan executed exactly as written.

## Verification

```
cd packages/jbtm && dart test
160 tests passed (93 original + 34 field + 31 parser + 2 round-trip)
grep for placeholder constants in m2400_stub_server.dart returns empty
```

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 83195bd | feat(05-02): align stub server with real M2400Field IDs, add barrel exports, add round-trip tests |
