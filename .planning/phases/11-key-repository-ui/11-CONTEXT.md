# Phase 11: Key Repository UI - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Operators can assign Modbus register addresses to display keys through the key configuration UI. This adds Modbus as a third protocol option in the existing key editor (alongside OPC UA and M2400), with fields for server alias, register type, address, data type, and poll group. Includes widget tests.

</domain>

<decisions>
## Implementation Decisions

### Protocol switching UX
- Show the Device Type selector row when any non-OPC UA servers exist (JBTM or Modbus configured) — extends current `jbtmServerAliases.isNotEmpty` check
- Discard old protocol config on switch (set new protocol's node config, null the old) — matches existing `_switchToM2400()` / `_switchToOpcUa()` behavior
- New keys default to OPC UA with namespace 0, empty identifier — same as current behavior
- Add a "Modbus" ChoiceChip alongside existing "OPC UA" and "M2400" chips

### Modbus field layout
- Match the existing M2400 config section pattern: titled header ("Modbus Key Configuration"), then stacked fields
- Zero-based addressing (0, 1, 2...) — register type dropdown determines function code, avoids 40001/30001 confusion, matches internal ModbusNodeConfig storage

### Data type auto-locking
- When coil or discrete input register type is selected, data type auto-locks to `bit`
- When switching from coil/discrete input to holding/input register, default data type is `uint16` (matches ModbusNodeConfig default)
- Switch silently — no confirmation dialog when data type changes due to register type change (matches current silent behavior when switching protocols)

### Poll group selection
- Poll group dropdown populated from selected server's `ModbusConfig.pollGroups`
- If no server selected, poll group field behavior is Claude's discretion
- If server has zero poll groups configured, use 'default' implicitly (backend auto-creates default group at 1s interval via lazy poll group creation from Phase 5)
- When server alias changes, poll group reset behavior is Claude's discretion

### Claude's Discretion
- Subtitle format for Modbus keys in the collapsed card view (should be compact and scannable)
- Register type widget choice (dropdown vs chips) — should match M2400 pattern
- Data type field appearance when auto-locked (greyed-out dropdown vs hidden)
- Helper text presence for auto-locked data type
- Poll group dropdown behavior when no server is selected (disabled with hint vs empty)
- Poll group reset behavior when server alias changes
- Whether poll group dropdown shows interval alongside group name (e.g., 'default (1000ms)')
- Search filter scope for Modbus keys (at minimum include server alias)
- Visual layout (stacked vs grid) — should fit alongside existing OPC UA and M2400 sections
- Modbus server alias dropdown population from `StateManConfig.modbus` list

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_M2400ConfigSection` (key_repository.dart:1119): Nearly identical pattern — titled header, server dropdown, record type dropdown, field dropdown. Template for `_ModbusConfigSection`.
- `_OpcUaConfigSection` (key_repository.dart:915): Server alias dropdown pattern reusable for Modbus server selection.
- `_KeyMappingCard` (key_repository.dart:610): Already has `_switchToM2400()` / `_switchToOpcUa()` — need to add `_switchToModbus()` and `_updateModbusConfig()`.
- `_jbtmServerAliases` getter (key_repository.dart:349): Pattern for creating `_modbusServerAliases` getter from `StateManConfig.modbus`.
- `_buildSubtitle()` (key_repository.dart:683): Already handles OPC UA and M2400 format — extend with Modbus case.

### Established Patterns
- Protocol detection: `_isM2400` checks `widget.entry.m2400Node != null` — add `_isModbus` checking `widget.entry.modbusNode != null`
- Config update: `_updateM2400Config()` creates new `KeyMappingEntry(m2400Node: config, collect: ...)` — same pattern for Modbus
- Protocol switch: `_switchToM2400()` creates fresh config, nulls OPC UA — add `_switchToModbus()` creating fresh `ModbusNodeConfig`
- Search filter: `_filteredEntries` uses `fuzzyFilter` with key name, identifier, and server alias extractors — extend with Modbus fields
- Server alias dropdown: `DropdownButtonFormField<String>` populated from `widget.jbtmServerAliases` — same for `modbusServerAliases`

### Integration Points
- `KeyMappingEntry.modbusNode` field (state_man.dart:406): Already exists, nullable `ModbusNodeConfig`
- `ModbusNodeConfig` (state_man.dart:288): `serverAlias`, `registerType` (ModbusRegisterType), `address` (int), `dataType` (ModbusDataType), `pollGroup` (String)
- `ModbusRegisterType` enum (state_man.dart:193): coil, discreteInput, holdingRegister, inputRegister
- `ModbusDataType` enum (modbus_client_wrapper.dart:16): bit, int16, uint16, int32, uint32, float32, int64, uint64, float64
- `StateManConfig.modbus` list (state_man.dart:322): Source of Modbus server aliases and poll group configs
- `ModbusPollGroupConfig` (on ModbusConfig.pollGroups): Provides group names and intervals for dropdown
- `_KeyMappingCard` receives `serverAliases` and `jbtmServerAliases` — needs `modbusServerAliases` parameter
- `_KeyMappingCardState._toggleCollect` and `_updateCollectEntry` reference both opcuaNode and m2400Node — must also preserve modbusNode

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following the established M2400 config section pattern.

</specifics>

<deferred>
## Deferred Ideas

- Register browser / discovery tool to scan address ranges — ADVUI-01 in v2
- Manual read/write test panel for debugging — ADVUI-02 in v2
- Byte/word order configuration per device — ADV-01 in v2

</deferred>

---

*Phase: 11-key-repository-ui*
*Context gathered: 2026-03-07*
