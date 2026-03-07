# Phase 11: Key Repository UI - Research

**Researched:** 2026-03-07
**Domain:** Flutter widget UI -- extending key_repository.dart with Modbus protocol config section
**Confidence:** HIGH

## Summary

Phase 11 adds Modbus as a third protocol option in the existing key editor UI (alongside OPC UA and M2400). The codebase already has extremely well-established patterns for this: `_M2400ConfigSection` is a near-identical template for the new `_ModbusConfigSection`, and the protocol switching pattern (`_switchToM2400()` / `_switchToOpcUa()`) directly extends with `_switchToModbus()`. All data model classes (`ModbusNodeConfig`, `ModbusRegisterType`, `ModbusDataType`, `ModbusPollGroupConfig`) already exist from Phases 5-8.

The work is almost entirely UI-layer: adding a `_ModbusConfigSection` widget, extending the `_KeyMappingCardState` with protocol switching logic, updating `_buildSubtitle()` for Modbus keys, adding `_modbusServerAliases` getter, extending search filter extractors, and preserving `modbusNode` in `_toggleCollect` / `_updateCollectEntry`. Widget tests follow the exact pattern from `server_config_test.dart` (Phase 10) and `key_repository_test.dart` (existing tests).

**Primary recommendation:** Follow the M2400 config section pattern exactly. The Modbus config section is structurally identical (titled header, server dropdown, register type dropdown, address field, data type dropdown, poll group dropdown) with the addition of data type auto-locking logic for coil/discrete input register types.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Show the Device Type selector row when any non-OPC UA servers exist (JBTM or Modbus configured) -- extends current `jbtmServerAliases.isNotEmpty` check
- Discard old protocol config on switch (set new protocol's node config, null the old) -- matches existing `_switchToM2400()` / `_switchToOpcUa()` behavior
- New keys default to OPC UA with namespace 0, empty identifier -- same as current behavior
- Add a "Modbus" ChoiceChip alongside existing "OPC UA" and "M2400" chips
- Match the existing M2400 config section pattern: titled header ("Modbus Key Configuration"), then stacked fields
- Zero-based addressing (0, 1, 2...) -- register type dropdown determines function code, avoids 40001/30001 confusion, matches internal ModbusNodeConfig storage
- When coil or discrete input register type is selected, data type auto-locks to `bit`
- When switching from coil/discrete input to holding/input register, default data type is `uint16` (matches ModbusNodeConfig default)
- Switch silently -- no confirmation dialog when data type changes due to register type change
- Poll group dropdown populated from selected server's `ModbusConfig.pollGroups`
- If server has zero poll groups configured, use 'default' implicitly (backend auto-creates default group at 1s interval via lazy poll group creation from Phase 5)

### Claude's Discretion
- Subtitle format for Modbus keys in the collapsed card view (should be compact and scannable)
- Register type widget choice (dropdown vs chips) -- should match M2400 pattern
- Data type field appearance when auto-locked (greyed-out dropdown vs hidden)
- Helper text presence for auto-locked data type
- Poll group dropdown behavior when no server is selected (disabled with hint vs empty)
- Poll group reset behavior when server alias changes
- Whether poll group dropdown shows interval alongside group name (e.g., 'default (1000ms)')
- Search filter scope for Modbus keys (at minimum include server alias)
- Visual layout (stacked vs grid) -- should fit alongside existing OPC UA and M2400 sections
- Modbus server alias dropdown population from `StateManConfig.modbus` list

### Deferred Ideas (OUT OF SCOPE)
- Register browser / discovery tool to scan address ranges -- ADVUI-01 in v2
- Manual read/write test panel for debugging -- ADVUI-02 in v2
- Byte/word order configuration per device -- ADV-01 in v2
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| UIKY-01 | User can switch a key between OPC UA, M2400, and Modbus protocols | Extend Device Type row visibility check and add `_switchToModbus()` method following `_switchToM2400()` pattern |
| UIKY-02 | User can select Modbus server (by alias) for a key | Add `_modbusServerAliases` getter from `StateManConfig.modbus`, use `DropdownButtonFormField<String>` pattern from M2400 |
| UIKY-03 | User can configure register type (coil, discrete input, holding register, input register) | `ModbusRegisterType` enum already exists with 4 values. Use `DropdownButtonFormField<ModbusRegisterType>` |
| UIKY-04 | User can set register address | `ModbusNodeConfig.address` is int. Use `TextField` with `keyboardType: TextInputType.number` |
| UIKY-05 | User can select data type (auto-locked to bit for coil/discrete input) | `ModbusDataType` enum has 9 values. Auto-lock when register type is coil/discreteInput, default to uint16 when switching to holding/input |
| UIKY-06 | User can assign key to a poll group | Poll group dropdown from `ModbusConfig.pollGroups` for selected server. Falls back to 'default' when empty |
| TEST-07 | Key repository Modbus config UI has widget tests | Follow `server_config_test.dart` pattern with `buildTestableKeyRepository()` from test_helpers.dart |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter/material.dart | SDK | All UI widgets (DropdownButtonFormField, TextField, ChoiceChip, Card, etc.) | Standard Flutter material components |
| flutter_riverpod | existing | State management via providers | Already used throughout app |
| font_awesome_flutter | existing | Icons (FontAwesomeIcons.networkWired for Modbus section) | Already used in all config sections |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tfc_dart/core/state_man.dart | local | ModbusNodeConfig, ModbusRegisterType, ModbusConfig, ModbusPollGroupConfig, KeyMappingEntry | Data models for all Modbus config |
| tfc_dart/core/modbus_client_wrapper.dart | local | ModbusDataType enum | Data type options for dropdown |
| flutter_test | SDK | Widget test framework | All widget tests |

### Alternatives Considered
None -- this phase adds to existing UI patterns, no library decisions needed.

## Architecture Patterns

### Recommended Project Structure
```
lib/pages/key_repository.dart    # Modify: add _ModbusConfigSection, extend _KeyMappingCard
test/pages/key_repository_test.dart  # Modify: add Modbus-specific widget tests
test/helpers/test_helpers.dart    # Modify: add Modbus sample helpers, extend buildTestableKeyRepository
```

### Pattern 1: Protocol Config Section (from _M2400ConfigSection)
**What:** Self-contained StatefulWidget that receives a node config + server aliases + onChanged callback
**When to use:** Each protocol gets its own config section widget
**Example:**
```dart
// Source: key_repository.dart:1119 (_M2400ConfigSection pattern)
class _ModbusConfigSection extends StatefulWidget {
  final ModbusNodeConfig config;
  final List<String> modbusServerAliases;
  final List<ModbusConfig> modbusConfigs; // needed to look up poll groups for selected server
  final Function(ModbusNodeConfig) onChanged;

  const _ModbusConfigSection({
    required this.config,
    required this.modbusServerAliases,
    required this.modbusConfigs,
    required this.onChanged,
  });
}
```

### Pattern 2: Protocol Switching (from _KeyMappingCardState)
**What:** Create fresh node config for new protocol, null the others, preserve collect
**When to use:** When user taps a different protocol ChoiceChip
**Example:**
```dart
// Source: key_repository.dart:723-737 (_switchToM2400 / _switchToOpcUa pattern)
void _switchToModbus() {
  final updatedEntry = KeyMappingEntry(
    modbusNode: ModbusNodeConfig(
      registerType: ModbusRegisterType.holdingRegister,
      address: 0,
    ),
    collect: widget.entry.collect,
  );
  widget.onUpdate(updatedEntry);
}
```

### Pattern 3: Protocol Detection (from _isM2400)
**What:** Getter that checks which node config is non-null
**When to use:** Conditional rendering of config sections and subtitle
**Example:**
```dart
// Source: key_repository.dart:681
bool get _isModbus => widget.entry.modbusNode != null;
```

### Pattern 4: Config Update Callback (from _updateM2400Config)
**What:** Creates new KeyMappingEntry with updated protocol config, preserves collect
**When to use:** When any field in the config section changes
**Example:**
```dart
// Source: key_repository.dart:715-721
void _updateModbusConfig(ModbusNodeConfig config) {
  final updatedEntry = KeyMappingEntry(
    modbusNode: config,
    collect: widget.entry.collect,
  );
  widget.onUpdate(updatedEntry);
}
```

### Pattern 5: Server Alias Getter (from _jbtmServerAliases)
**What:** Extracts server aliases from StateManConfig for a specific protocol
**When to use:** Populating server alias dropdown in config section
**Example:**
```dart
// Source: key_repository.dart:349-355
List<String> get _modbusServerAliases {
  if (_stateManConfig == null) return [];
  return _stateManConfig!.modbus
      .where((c) => c.serverAlias != null && c.serverAlias!.isNotEmpty)
      .map((c) => c.serverAlias!)
      .toList();
}
```

### Pattern 6: Test Helper (from buildTestableKeyRepository)
**What:** Wraps content widget in ProviderScope with overrides for preferences and database
**When to use:** All widget tests
**Example:**
```dart
// Source: test/helpers/test_helpers.dart:97-115
Widget buildTestableKeyRepository({
  KeyMappings? keyMappings,
  StateManConfig? stateManConfig,
}) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((ref) => createTestPreferences(
            keyMappings: keyMappings,
            stateManConfig: stateManConfig,
          )),
      databaseProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      home: Scaffold(body: KeyRepositoryContent()),
    ),
  );
}
```

### Anti-Patterns to Avoid
- **Adding ConsumerStatefulWidget for _ModbusConfigSection:** The M2400 section is a plain StatefulWidget (not Consumer). Only OPC UA uses ConsumerStatefulWidget because it needs the browse dialog. Modbus does not need Riverpod access.
- **Not preserving modbusNode in _toggleCollect and _updateCollectEntry:** These currently only pass `opcuaNode` and `m2400Node`. Must also pass `modbusNode` to avoid data loss when toggling collection.
- **Not updating _filteredEntries search extractors:** The current search only covers OPC UA identifier and server alias. Modbus server alias must be added to the extractor list.
- **Forgetting three-way protocol detection:** The current code uses binary `_isM2400` / `!_isM2400`. With three protocols, need explicit checks for each: `_isModbus`, `_isM2400`, else OPC UA.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Protocol config data models | Custom classes | `ModbusNodeConfig`, `ModbusRegisterType`, `ModbusDataType` from state_man.dart | Already exist and are JSON-serializable |
| Poll group config | Custom poll group model | `ModbusPollGroupConfig` from state_man.dart | Already serializable with name + intervalMs |
| Server alias list | Custom server listing | `StateManConfig.modbus` list | Already the source of truth used by StateMan |
| Test infrastructure | Custom test setup | `buildTestableKeyRepository()` + `createTestPreferences()` from test_helpers.dart | Existing pattern handles provider overrides |

## Common Pitfalls

### Pitfall 1: Forgetting to preserve modbusNode in _toggleCollect / _updateCollectEntry
**What goes wrong:** Toggling data collection on a Modbus key replaces `modbusNode` with null because existing code only passes `opcuaNode` and `m2400Node`.
**Why it happens:** These methods were written before Modbus existed.
**How to avoid:** Update both methods to include `modbusNode: widget.entry.modbusNode` in the KeyMappingEntry constructor.
**Warning signs:** Toggling collection on a Modbus key silently switches it to an empty OPC UA key.

### Pitfall 2: Device Type row visibility logic
**What goes wrong:** Modbus ChoiceChip not visible even when Modbus servers exist, because the condition only checks `jbtmServerAliases.isNotEmpty`.
**Why it happens:** The original condition was designed for two protocols only.
**How to avoid:** Change condition to `widget.jbtmServerAliases.isNotEmpty || widget.modbusServerAliases.isNotEmpty`.
**Warning signs:** Users with only Modbus servers (no JBTM) cannot see the protocol selector.

### Pitfall 3: ChoiceChip selected state with three options
**What goes wrong:** With binary `_isM2400` / `!_isM2400`, OPC UA chip shows selected when Modbus is active.
**Why it happens:** Current logic treats "not M2400" as "is OPC UA".
**How to avoid:** Use explicit three-way check: `selected: !_isM2400 && !_isModbus` for OPC UA chip.
**Warning signs:** Both OPC UA and Modbus chips appear selected simultaneously.

### Pitfall 4: Data type auto-lock timing
**What goes wrong:** Data type is `bit` but register type has been changed to holdingRegister, leaving stale config.
**Why it happens:** Register type change handler doesn't update data type.
**How to avoid:** In register type onChanged: if new type is coil/discreteInput, force dataType to `bit`; if switching away from coil/discreteInput and dataType is currently `bit`, reset to `uint16`.
**Warning signs:** Saving a holdingRegister key with dataType `bit` (which is semantically wrong for multi-bit registers).

### Pitfall 5: Poll group dropdown stale after server alias change
**What goes wrong:** Poll group dropdown shows groups from previously selected server.
**Why it happens:** Poll group list is derived from selected server's config, but doesn't reset when server changes.
**How to avoid:** When server alias changes, reset poll group selection to 'default' (or the first available group).
**Warning signs:** Poll group name shown in dropdown doesn't exist in the newly selected server's config.

### Pitfall 6: _buildSubtitle not handling Modbus case
**What goes wrong:** Modbus keys show "No config" subtitle because the method falls through to the OPC UA else branch.
**Why it happens:** `_buildSubtitle` only checks `_isM2400` and assumes OPC UA otherwise.
**How to avoid:** Add `_isModbus` check before the OPC UA fallback.
**Warning signs:** All Modbus keys show "ns=0; id=" instead of meaningful Modbus info.

## Code Examples

### Device Type Selector with Three Protocols
```dart
// Source: key_repository.dart:851 (extended from existing two-chip pattern)
if (widget.jbtmServerAliases.isNotEmpty || widget.modbusServerAliases.isNotEmpty)
  Padding(
    padding: const EdgeInsets.only(bottom: 4.0),
    child: Row(
      children: [
        const FaIcon(FontAwesomeIcons.plug, size: 14),
        const SizedBox(width: 8),
        Text('Device Type', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('OPC UA'),
          selected: !_isM2400 && !_isModbus,
          onSelected: (selected) {
            if (selected && (_isM2400 || _isModbus)) _switchToOpcUa();
          },
        ),
        if (widget.jbtmServerAliases.isNotEmpty) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('M2400'),
            selected: _isM2400,
            onSelected: (selected) {
              if (selected && !_isM2400) _switchToM2400();
            },
          ),
        ],
        if (widget.modbusServerAliases.isNotEmpty) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Modbus'),
            selected: _isModbus,
            onSelected: (selected) {
              if (selected && !_isModbus) _switchToModbus();
            },
          ),
        ],
      ],
    ),
  ),
```

### Data Type Auto-Lock Logic
```dart
// Register type dropdown onChanged handler
onChanged: (ModbusRegisterType? value) {
  if (value == null) return;
  setState(() {
    _selectedRegisterType = value;
    // Auto-lock data type for boolean register types
    if (value == ModbusRegisterType.coil || value == ModbusRegisterType.discreteInput) {
      _selectedDataType = ModbusDataType.bit;
    } else if (_selectedDataType == ModbusDataType.bit) {
      // Switching away from boolean type -- reset to default
      _selectedDataType = ModbusDataType.uint16;
    }
  });
  _notifyChanged();
},
```

### Data Type Dropdown with Auto-Lock Appearance
```dart
// Data type dropdown -- disabled when auto-locked to bit
DropdownButtonFormField<ModbusDataType>(
  value: _selectedDataType,
  decoration: InputDecoration(
    labelText: _isBooleanRegisterType ? 'Data Type (auto)' : 'Data Type',
    prefixIcon: const FaIcon(FontAwesomeIcons.hashtag, size: 16),
  ),
  items: _isBooleanRegisterType
      ? [const DropdownMenuItem(value: ModbusDataType.bit, child: Text('bit'))]
      : ModbusDataType.values
            .map((dt) => DropdownMenuItem(value: dt, child: Text(dt.name)))
            .toList(),
  onChanged: _isBooleanRegisterType
      ? null  // null disables the dropdown
      : (value) {
          if (value == null) return;
          setState(() => _selectedDataType = value);
          _notifyChanged();
        },
),
```

### Poll Group Dropdown with Server-Dependent Options
```dart
// Poll group dropdown -- populated from selected server's config
DropdownButtonFormField<String>(
  value: _selectedPollGroup,
  decoration: const InputDecoration(
    labelText: 'Poll Group',
    prefixIcon: FaIcon(FontAwesomeIcons.clockRotateLeft, size: 16),
  ),
  items: _getAvailablePollGroups().map((pg) =>
    DropdownMenuItem(
      value: pg.name,
      child: Text('${pg.name} (${pg.intervalMs}ms)'),
    ),
  ).toList(),
  onChanged: _selectedAlias == null ? null : (value) {
    if (value == null) return;
    setState(() => _selectedPollGroup = value);
    _notifyChanged();
  },
),
```

### Modbus Subtitle Format
```dart
// Compact subtitle for collapsed card view
if (_isModbus) {
  final node = widget.entry.modbusNode!;
  var subtitle = '${node.registerType.name}[${node.address}]';
  subtitle += ' ${node.dataType.name}';
  if (node.serverAlias != null && node.serverAlias!.isNotEmpty) {
    subtitle += ' @ ${node.serverAlias}';
  }
  return subtitle;
}
// Example output: "holdingRegister[100] uint16 @ plc_1"
```

### Test Helper for Modbus Key Mappings
```dart
// Sample key mappings with Modbus keys for tests
KeyMappings sampleModbusKeyMappings() {
  return KeyMappings(nodes: {
    'modbus_temp': KeyMappingEntry(
      modbusNode: ModbusNodeConfig(
        serverAlias: 'plc_1',
        registerType: ModbusRegisterType.holdingRegister,
        address: 100,
        dataType: ModbusDataType.float32,
        pollGroup: 'default',
      ),
    ),
    'modbus_coil': KeyMappingEntry(
      modbusNode: ModbusNodeConfig(
        serverAlias: 'plc_1',
        registerType: ModbusRegisterType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
        pollGroup: 'default',
      ),
    ),
  });
}
```

### Updated _toggleCollect Preserving modbusNode
```dart
void _toggleCollect(bool enabled) {
  setState(() => _collectEnabled = enabled);
  final updatedEntry = KeyMappingEntry(
    opcuaNode: widget.entry.opcuaNode,
    m2400Node: widget.entry.m2400Node,
    modbusNode: widget.entry.modbusNode, // <-- MUST ADD THIS
    collect: enabled
        ? CollectEntry(
            key: widget.keyName,
            retention: const RetentionPolicy(
                dropAfter: Duration(days: 365), scheduleInterval: null),
          )
        : null,
  );
  widget.onUpdate(updatedEntry);
}
```

### Updated Search Filter Extractors
```dart
List<MapEntry<String, KeyMappingEntry>> get _filteredEntries {
  if (_keyMappings == null) return [];
  final entries = _keyMappings!.nodes.entries.toList();
  return fuzzyFilter(entries, _searchQuery, [
    (e) => e.key,
    (e) => e.value.opcuaNode?.identifier ?? '',
    (e) => e.value.opcuaNode?.serverAlias
        ?? e.value.m2400Node?.serverAlias
        ?? e.value.modbusNode?.serverAlias  // <-- ADD Modbus alias
        ?? '',
  ]);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Two-protocol binary check (`_isM2400`) | Three-protocol explicit checks (`_isM2400`, `_isModbus`, else OPC UA) | Phase 11 | All conditional rendering must use three-way logic |
| Device Type row shows only when JBTM exists | Device Type row shows when JBTM OR Modbus exists | Phase 11 | More users will see the protocol selector |

## Open Questions

1. **Poll group dropdown when server has no poll groups configured**
   - What we know: Backend auto-creates 'default' group at 1s interval (Phase 5 lazy creation)
   - What's unclear: Should UI show an empty dropdown with a "default (implicit)" hint, or a pre-populated 'default' entry?
   - Recommendation: Show 'default' in the dropdown always (since the backend will create it). If server has explicit poll groups, show those. If none, show just 'default'. The `ModbusNodeConfig.pollGroup` defaults to 'default' already.

2. **Whether to pass `modbusConfigs` list or just poll group names to _ModbusConfigSection**
   - What we know: Need to look up poll groups for the selected server alias
   - What's unclear: Whether to pass the full `List<ModbusConfig>` or pre-extract poll groups
   - Recommendation: Pass `List<ModbusConfig>` so the section can look up poll groups when server alias changes. This avoids the parent needing to track which server is selected.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK) |
| Config file | none (uses default `flutter test`) |
| Quick run command | `flutter test test/pages/key_repository_test.dart --reporter compact` |
| Full suite command | `flutter test test/pages/ --reporter compact` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UIKY-01 | Protocol switching between OPC UA, M2400, Modbus | widget | `flutter test test/pages/key_repository_test.dart --name "protocol switching" -x` | Will extend existing file |
| UIKY-02 | Modbus server alias selection from dropdown | widget | `flutter test test/pages/key_repository_test.dart --name "server alias" -x` | Will extend existing file |
| UIKY-03 | Register type dropdown selection | widget | `flutter test test/pages/key_repository_test.dart --name "register type" -x` | Will extend existing file |
| UIKY-04 | Register address entry | widget | `flutter test test/pages/key_repository_test.dart --name "register address" -x` | Will extend existing file |
| UIKY-05 | Data type auto-lock for coil/discrete input | widget | `flutter test test/pages/key_repository_test.dart --name "data type" -x` | Will extend existing file |
| UIKY-06 | Poll group assignment from dropdown | widget | `flutter test test/pages/key_repository_test.dart --name "poll group" -x` | Will extend existing file |
| TEST-07 | All Modbus UI widget tests pass | widget | `flutter test test/pages/key_repository_test.dart --reporter compact` | Will extend existing file |

### Sampling Rate
- **Per task commit:** `flutter test test/pages/key_repository_test.dart --reporter compact`
- **Per wave merge:** `flutter test test/pages/ --reporter compact`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/helpers/test_helpers.dart` -- add `sampleModbusKeyMappings()` and `sampleStateManConfigWithModbus()` helpers
- [ ] `test/pages/key_repository_test.dart` -- add Modbus protocol switching, config section, auto-lock, and search filter test groups

No new test framework installation needed. Existing `flutter_test` and `test_helpers.dart` infrastructure covers all requirements.

## Sources

### Primary (HIGH confidence)
- `lib/pages/key_repository.dart` -- Full source read (1647 lines). Contains all existing patterns: `_M2400ConfigSection`, `_OpcUaConfigSection`, `_KeyMappingCard`, protocol switching, search filtering, subtitle building.
- `packages/tfc_dart/lib/core/state_man.dart` -- ModbusNodeConfig (line 288), ModbusRegisterType (line 193), ModbusConfig (line 257), ModbusPollGroupConfig (line 235), KeyMappingEntry (line 400).
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` -- ModbusDataType enum (line 16), 9 values: bit, int16, uint16, int32, uint32, float32, int64, uint64, float64.
- `test/pages/key_repository_test.dart` -- Full source read (879 lines). 33 existing tests all passing. Establishes widget test patterns.
- `test/pages/server_config_test.dart` -- Full source read (517 lines). Phase 10 Modbus test patterns for widget testing.
- `test/helpers/test_helpers.dart` -- Full source read (179 lines). Test infrastructure: `buildTestableKeyRepository()`, `createTestPreferences()`, sample data helpers.

### Secondary (MEDIUM confidence)
- None needed -- this is entirely within existing project patterns.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already in use, no new dependencies
- Architecture: HIGH -- patterns copied directly from existing M2400/OPC UA sections in the same file
- Pitfalls: HIGH -- identified through direct code analysis of the 1647-line key_repository.dart
- Test approach: HIGH -- existing test infrastructure (33 tests passing) provides exact patterns to follow

**Research date:** 2026-03-07
**Valid until:** No expiration -- this research is based on the project's own codebase, not external libraries
