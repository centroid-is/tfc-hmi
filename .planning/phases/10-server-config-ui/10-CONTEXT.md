# Phase 10: Server Config UI - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Operators can add, edit, remove, and monitor Modbus TCP servers through the settings UI. This adds a new "Modbus TCP Servers" section to the existing Server Config page alongside OPC UA and JBTM M2400 sections. Includes poll group management per server.

</domain>

<decisions>
## Implementation Decisions

### Card layout & fields
- Match the existing JBTM card layout style for consistency across all protocol sections
- Fields: host, port, unit ID (1-247), alias
- Claude decides the section header icon (FontAwesome, should fit alongside server icon for OPC UA and scale icon for JBTM)
- Default values for new server: Claude decides based on Modbus conventions
- Claude decides the validation approach for fields (inline vs on-save), fitting existing patterns

### Poll group editing
- Expandable/collapsible section at the bottom of each server card
- Shows "Poll Groups (N)" with expand arrow
- Each poll group has name (string) and interval in milliseconds (simple numeric text field labeled "Interval (ms)")
- New servers start with one poll group named "default" at 1000ms
- Deleting a poll group that has keys assigned: Claude decides the safest approach for operators

### Connection status display
- Same colored dot pattern as OPC UA and JBTM cards (green=connected, yellow=connecting, red=disconnected)
- Grey dot when StateMan hasn't been initialized yet (distinct from red "disconnected")
- Status dot only — no additional connection details (poll metrics are ADVUI-03, deferred to v2)
- Real-time updates via StreamBuilder on connectionStream (matches JBTM card behavior)

### Save/apply behavior
- Same Save button + "Unsaved Changes" orange badge pattern as OPC UA and JBTM sections
- Auto-reconnect on save: invalidate stateManProvider to recreate connections with new config
- Claude decides whether server removal requires a confirmation dialog (based on what OPC UA/JBTM do)
- Section placement: Claude decides the most logical position on the page

### Claude's Discretion
- FontAwesome icon for Modbus section header
- Default field values for new Modbus server
- Validation approach (inline vs on-save) — fit existing patterns
- Poll group deletion behavior when keys are assigned
- Server removal confirmation dialog behavior
- Section ordering on the Server Config page
- Empty state widget design for no Modbus servers configured

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_JbtmServersSection` (server_config.dart:830): Nearly identical pattern needed — ConsumerStatefulWidget that loads StateManConfig, manages add/edit/remove/save with unsaved changes tracking
- `_JbtmServerConfigCard` (server_config.dart:1127): Card widget with connection status dot, host/port/alias fields, delete button — can be used as template for Modbus card
- `_EmptyJbtmServersWidget` (server_config.dart:1101): Empty state placeholder — same pattern needed for Modbus
- `ConnectionStatus` enum and `connectionStream`: Already used by JBTM adapter, Modbus adapter has same interface

### Established Patterns
- Config persistence: `StateManConfig.fromPrefs()` / `.toPrefs()` via SharedPreferences
- Unsaved changes detection: JSON comparison between current and saved config
- Connection status lookup: Match adapter by serverAlias or host+port in `stateMan.deviceClients`
- Save flow: `toPrefs()` → `ref.invalidate(stateManProvider)` → snackbar confirmation
- Section layout: Card with header row (icon + title + unsaved badge + add button), server list, save button

### Integration Points
- `StateManConfig.modbus` list: Where Modbus server configs are stored (added in Phase 8)
- `ModbusDeviceClientAdapter`: Provides `connectionStatus` and `connectionStream` for status dot
- `stateManProvider`: Riverpod provider invalidated on save to trigger reconnection
- `ServerConfigPage.build()`: Where the new Modbus section gets added to the Column

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following the established JBTM card pattern.

</specifics>

<deferred>
## Deferred Ideas

- Poll performance metrics (response time, error rate) — ADVUI-03 in v2
- Register browser / discovery tool — ADVUI-01 in v2
- Manual read/write test panel — ADVUI-02 in v2

</deferred>

---

*Phase: 10-server-config-ui*
*Context gathered: 2026-03-07*
