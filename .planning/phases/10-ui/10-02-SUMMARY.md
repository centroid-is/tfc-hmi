---
phase: 10-ui
plan: 02
subsystem: key-repository-ui
tags: [flutter, ui, m2400, key-repository, jbtm, rec, fld]
dependency_graph:
  requires: [phase-9-config-models, phase-5-field-catalog, 10-01]
  provides: [m2400-key-config-ui, device-type-distinction]
  affects: [lib/pages/key_repository.dart, pubspec.yaml]
tech_stack:
  added: [jbtm-package-dependency]
  patterns: [ChoiceChip-device-type, DropdownButtonFormField, expectedFields-filtering]
key_files:
  created: []
  modified:
    - lib/pages/key_repository.dart
    - pubspec.yaml
decisions:
  - Used ChoiceChip for device type selector (OPC UA vs M2400) instead of dropdown
  - Device type selector only shown when JBTM servers are configured
  - Expected fields tagged with green EXP badge in FLD dropdown for visual distinction
  - FLD null selection means full record subscription (all fields)
  - Switching device type resets node config but preserves collect config
  - Added jbtm as direct dependency in root pubspec.yaml (needed for M2400RecordType, M2400Field, expectedFields imports)
metrics:
  duration: ~5 minutes
  completed: 2026-03-04
---

# Phase 10 Plan 02: M2400 Key Repository Config Summary

Server picker distinguishes M2400 vs OPC UA devices with ChoiceChip selector. M2400 keys configured with REC type and FLD dropdowns, with field filtering by selected record type.

## What Was Done

### Task 1: Distinguish M2400 vs OPC UA in server picker and add REC/FLD dropdowns

**pubspec.yaml changes:**
- Added `jbtm: path: packages/jbtm` as a direct dependency (needed for M2400RecordType, M2400Field, expectedFields imports in UI code)

**lib/pages/key_repository.dart changes:**

1. **Import:** Added `import 'package:jbtm/jbtm.dart' show M2400RecordType, M2400Field, expectedFields;`

2. **_KeyMappingsSectionState:** Added `_jbtmServerAliases` getter that extracts aliases from `_stateManConfig!.jbtm` list. Updated `_filteredEntries` to also search M2400 server aliases.

3. **_KeyMappingCard:** Added `jbtmServerAliases` parameter, passed through from `_KeyMappingsSection`.

4. **_KeyMappingCardState:**
   - Added `_isM2400` getter (checks if entry has m2400Node)
   - Added `_updateM2400Config(M2400NodeConfig)` callback
   - Added `_switchToM2400()` and `_switchToOpcUa()` methods for device type switching
   - Updated `_buildSubtitle()` to show M2400-specific info (REC type, FLD, alias)
   - Updated `_toggleCollect()` and `_updateCollectEntry()` to preserve both node types
   - **Device type selector:** ChoiceChip pair (OPC UA / M2400) shown only when JBTM servers exist
   - **Conditional rendering:** Shows `_M2400ConfigSection` when M2400, `_OpcUaConfigSection` when OPC UA

5. **_M2400ConfigSection** (new StatefulWidget):
   - Server alias dropdown (JBTM servers only)
   - REC type dropdown: recBatch(103), recStat(14), recIntro(5), recLua(87) -- excludes `unknown`
   - FLD dropdown with null option ("Full record -- all fields"):
     - Expected fields shown first with green "EXP" badge (from `expectedFields` map)
     - Other fields shown below without badge
     - When REC type changes, resets FLD if not in new expected set
   - `_getExpectedFields()` and `_getOtherFields()` helper methods for field filtering

## Deviations from Plan

None - plan executed exactly as written.

## Verification

- `dart analyze lib/pages/key_repository.dart` -- 0 errors (4 pre-existing info-level deprecation warnings for `value` parameter on DropdownButtonFormField)
- `flutter test test/pages/key_repository_test.dart` -- 33/33 tests pass
- Server alias dropdown shows device type distinction via ChoiceChip
- M2400 key config shows REC dropdown with 4 record types
- FLD dropdown populated from M2400Field.values with displayName labels
- FLD dropdown filters by selected REC type using expectedFields map
- OPC UA keys show existing OPC UA config section unchanged
- Pre-existing test failure in `page_manager_test.dart` (compilation error in `graph.dart` widget, unrelated to phase 10 changes)

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 6ffa44b | feat(10-02): add M2400 device type distinction and REC/FLD dropdowns to key repository |
