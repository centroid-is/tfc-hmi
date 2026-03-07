# Phase 10: Server Config UI - Research

**Researched:** 2026-03-07
**Domain:** Flutter widget development -- Modbus TCP server configuration UI
**Confidence:** HIGH

## Summary

Phase 10 adds a "Modbus TCP Servers" section to the existing Server Config page (`lib/pages/server_config.dart`). The implementation is a near-direct clone of the `_JbtmServersSection` pattern (lines 834-1379), extended with Modbus-specific fields (unit ID) and an expandable poll groups editor per server card.

The existing codebase provides an exact template: `_JbtmServersSection` is a `ConsumerStatefulWidget` that loads `StateManConfig` from SharedPreferences, tracks unsaved changes via JSON comparison, and saves with `ref.invalidate(stateManProvider)` for auto-reconnect. The `_JbtmServerConfigCard` shows host/port/alias fields with a connection status chip driven by `StreamSubscription<ConnectionStatus>`. The Modbus version adds `unitId` (1-247) and collapsible poll group management.

**Primary recommendation:** Clone the `_JbtmServersSection` + `_JbtmServerConfigCard` pattern verbatim, adding unit ID field and expandable poll groups section. Reuse existing test infrastructure from `test/helpers/test_helpers.dart` for widget tests, extending `createTestPreferences` to include Modbus config.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Match the existing JBTM card layout style for consistency across all protocol sections
- Fields: host, port, unit ID (1-247), alias
- Default values for new server: Claude decides based on Modbus conventions
- Expandable/collapsible section at the bottom of each server card for poll groups
- Shows "Poll Groups (N)" with expand arrow
- Each poll group has name (string) and interval in milliseconds (simple numeric text field labeled "Interval (ms)")
- New servers start with one poll group named "default" at 1000ms
- Same colored dot pattern as OPC UA and JBTM cards (green=connected, yellow=connecting, red=disconnected)
- Grey dot when StateMan hasn't been initialized yet (distinct from red "disconnected")
- Status dot only -- no additional connection details
- Real-time updates via StreamBuilder on connectionStream (matches JBTM card behavior)
- Same Save button + "Unsaved Changes" orange badge pattern as OPC UA and JBTM sections
- Auto-reconnect on save: invalidate stateManProvider to recreate connections with new config

### Claude's Discretion
- FontAwesome icon for Modbus section header
- Default field values for new Modbus server
- Validation approach (inline vs on-save) -- fit existing patterns
- Poll group deletion behavior when keys are assigned
- Server removal confirmation dialog behavior
- Section ordering on the Server Config page
- Empty state widget design for no Modbus servers configured

### Deferred Ideas (OUT OF SCOPE)
- Poll performance metrics (response time, error rate) -- ADVUI-03 in v2
- Register browser / discovery tool -- ADVUI-01 in v2
- Manual read/write test panel -- ADVUI-02 in v2
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| UISV-01 | User can add a Modbus TCP server with host, port, unit ID, and alias | Clone `_addServer()` pattern from JBTM section; `ModbusConfig` constructor with defaults |
| UISV-02 | User can edit existing Modbus server configuration | Clone `_JbtmServerConfigCard` field editing + `_updateServer()` callback pattern |
| UISV-03 | User can remove a Modbus server | Clone JBTM delete button + confirmation dialog pattern |
| UISV-04 | User can see live connection status per Modbus server | Clone JBTM `connectionStatus`/`connectionStream` subscription; match `ModbusDeviceClientAdapter` by `serverAlias` or host+port |
| UISV-05 | User can configure poll groups per server (name + interval in ms) | New expandable section in card; operates on `ModbusConfig.pollGroups` list of `ModbusPollGroupConfig` |
| TEST-08 | Server config Modbus section has widget tests | Extend existing `test/helpers/test_helpers.dart` with `buildTestableServerConfig()` helper; follow `key_repository_test.dart` patterns |
</phase_requirements>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | 3.x | UI framework | Project framework |
| flutter_riverpod | 2.x | State management | Used throughout project; `ConsumerStatefulWidget` pattern |
| font_awesome_flutter | latest | Icons | Used for all section headers and field prefixes |
| flutter_test | sdk | Widget testing | Standard Flutter test framework |

### Supporting (already in project)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shared_preferences | N/A | Config persistence (via `Preferences` wrapper) | `StateManConfig.fromPrefs()` / `.toPrefs()` |
| tfc_dart | local | `StateManConfig`, `ModbusConfig`, `ModbusPollGroupConfig`, `ConnectionStatus` | All data models and config persistence |

### No New Dependencies Needed
This phase uses only existing project dependencies. No `npm install` or `flutter pub add` required.

## Architecture Patterns

### Existing Section Pattern (JBTM -- the template to clone)

```
_JbtmServersSection (ConsumerStatefulWidget)
  |-- _config: StateManConfig?           (mutable working copy)
  |-- _savedConfig: StateManConfig?       (last-saved snapshot)
  |-- _hasUnsavedChanges: bool            (JSON comparison)
  |
  |-- _loadConfig()                       (fromPrefs on initState)
  |-- _saveConfig()                       (toPrefs + invalidate stateManProvider)
  |-- _addServer()                        (append to _config.jbtm)
  |-- _updateServer(index, config)        (replace at index)
  |-- _removeServer(index)                (removeAt index)
  |
  |-- build() returns Card:
  |     Header: [icon] [title] [unsaved badge?] [spacer] [Add button]
  |     Body:   Empty widget OR ListView of server cards
  |     Footer: Save button (disabled when no changes)
  |
  |-- _JbtmServerConfigCard (StatefulWidget)
       |-- TextEditingControllers for host, port, alias
       |-- StreamSubscription<ConnectionStatus> for status dot
       |-- Connection status chip (colored dot + label)
       |-- ExpansionTile: icon, title (alias or host:port), status chip, delete button
       |-- Expanded: host/port/alias TextFields with onChanged -> _updateServer()
```

### Modbus Extension of This Pattern

The Modbus section adds two things beyond JBTM:

1. **Unit ID field** (int, 1-247) -- simple TextField with numeric keyboard, like port
2. **Poll Groups sub-section** -- expandable/collapsible list inside each server card

```
_ModbusServersSection (ConsumerStatefulWidget)
  |-- Same structure as _JbtmServersSection
  |-- _addServer() creates ModbusConfig(host: 'localhost', port: 502, unitId: 1)
  |       with pollGroups: [ModbusPollGroupConfig(name: 'default', intervalMs: 1000)]
  |
  |-- _ModbusServerConfigCard (StatefulWidget)
       |-- Same as _JbtmServerConfigCard PLUS:
       |-- TextEditingController for unitId
       |-- _pollGroupsExpanded: bool (for collapse toggle)
       |-- Poll Groups section:
       |     Header: "Poll Groups (N)" with expand/collapse arrow
       |     Each group: [name field] [interval field] [delete button]
       |     Add button: "Add Poll Group"
```

### Connection Status Lookup Pattern

Exact same pattern as JBTM (server_config.dart lines 923-937):

```dart
// In _buildModbusServerList:
ModbusDeviceClientAdapter? adapter;
if (stateMan != null) {
  final server = config.modbus[index];
  adapter = stateMan.deviceClients
      .whereType<ModbusDeviceClientAdapter>()
      .cast<ModbusDeviceClientAdapter?>()
      .firstWhere(
        (dc) =>
            (server.serverAlias != null &&
                server.serverAlias!.isNotEmpty &&
                dc!.serverAlias == server.serverAlias) ||
            (dc!.wrapper.host == server.host &&
                dc.wrapper.port == server.port),
        orElse: () => null,
      );
}
```

**Note:** `ModbusDeviceClientAdapter.wrapper` is a `ModbusClientWrapper` which has `.host` and `.port` getters. Need to verify these exist. The adapter has `.serverAlias` directly (line 17 of modbus_device_client.dart).

### Widget Test Pattern

Existing pattern from `test/helpers/test_helpers.dart` and `test/pages/key_repository_test.dart`:

```dart
// test/helpers/test_helpers.dart provides:
// - FakeSecureStorage
// - createTestPreferences(keyMappings, stateManConfig)
// - sampleKeyMappings(), sampleStateManConfig()

// For server config tests, create similar helper:
Widget buildTestableServerConfig({
  StateManConfig? stateManConfig,
}) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((ref) => createTestPreferences(
            stateManConfig: stateManConfig,
          )),
      databaseProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      home: Scaffold(
        // Need to figure out: wrap just _ModbusServersSection or full ServerConfigPage
        body: SingleChildScrollView(child: _ModbusServersSection()),
      ),
    ),
  );
}
```

**Challenge:** `_ModbusServersSection` is a private widget (underscore prefix). Widget tests either need to:
1. Test through `ServerConfigPage` (finds Modbus section within full page), OR
2. Make the section testable by using a `@visibleForTesting` annotation or extracting to a separate file

The JBTM section is also private and has no tests. The key_repository_test.dart tests `KeyRepositoryContent` which is a public widget. Looking at the pattern: for widget tests we should test via the full `ServerConfigPage` and find our widgets within it.

### Anti-Patterns to Avoid
- **Don't create a separate config load per section:** Each section independently calls `StateManConfig.fromPrefs()` in `initState()`. This is the existing pattern -- do NOT try to share config state between sections via a provider. Follow the pattern.
- **Don't use StreamBuilder in the card:** The JBTM card uses `StreamSubscription` + `setState()` (not `StreamBuilder`). Follow this pattern for consistency.
- **Don't break the single-file convention:** All server config UI lives in `server_config.dart`. Add Modbus section to the same file.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config persistence | Custom file I/O | `StateManConfig.fromPrefs()` / `.toPrefs()` | Already handles encryption, migration, backward compat |
| Connection status streaming | Custom polling | `ModbusDeviceClientAdapter.connectionStream` | Already implemented in Phase 7 |
| Unsaved changes detection | Deep equality | JSON encode + string compare | Existing pattern, handles nested objects correctly |
| Config deep copy | Manual field copy | `StateManConfig.fromJson(toJson())` via `.copy()` | Already implemented |
| Auto-reconnect | Manual client lifecycle | `ref.invalidate(stateManProvider)` | Tears down + rebuilds all device clients |

**Key insight:** Every infrastructure piece needed already exists. This phase is pure UI widget code following an established template.

## Common Pitfalls

### Pitfall 1: Poll Group List Mutation
**What goes wrong:** Modifying `ModbusConfig.pollGroups` (which defaults to `const []`) throws because const lists are unmodifiable.
**Why it happens:** `ModbusConfig` constructor has `this.pollGroups = const []`. After JSON round-trip via `.copy()` it becomes a growable list, but a freshly constructed `ModbusConfig` has an immutable default.
**How to avoid:** When creating a new server in `_addServer()`, always provide an explicit mutable list:
```dart
_config?.modbus.add(ModbusConfig(
  host: 'localhost',
  port: 502,
  unitId: 1,
  pollGroups: [ModbusPollGroupConfig(name: 'default', intervalMs: 1000)],
));
```
**Warning signs:** `Unsupported operation: Cannot add to an unmodifiable list` error at runtime.

### Pitfall 2: StateManConfig.modbus Default is `const []`
**What goes wrong:** Similar to above -- `StateManConfig.modbus` defaults to `const []`. Calling `_config!.modbus.add(...)` throws on a fresh config with no prior Modbus entries.
**Why it happens:** `StateManConfig({..., this.modbus = const []})` constructor.
**How to avoid:** After loading config, ensure `modbus` is a mutable list. The `.copy()` method (JSON round-trip) converts to mutable. But check: does `_addServer` ever execute before `_savedConfig` is set? The JBTM pattern does `_config = await StateManConfig.fromPrefs(...)` then `_savedConfig = _config?.copy()`. The `fromPrefs` goes through JSON deserialization which creates mutable lists. So this should be safe as long as config is loaded first. But `_addServer` button is only shown after `_isLoading` is false, which is after `_loadConfig` completes. Safe.

### Pitfall 3: Unit ID Validation Range
**What goes wrong:** Modbus unit ID must be 1-247 (0 is broadcast, 248-255 reserved). Invalid values cause connection issues.
**Why it happens:** Free-form text field with no validation.
**How to avoid:** Use `InputFormatters` to restrict to numeric + clamp. The existing pattern uses no validation for port/host (JBTM just uses `int.tryParse` with a fallback). For consistency, follow the same approach: parse with fallback, but add hint text showing valid range. The JBTM pattern does inline-on-change updates (no form validation).
**Recommendation:** Match existing pattern (no formal validators), use hint text "1-247" and `int.tryParse` with `clamp(1, 247)` in `_updateServer()`.

### Pitfall 4: ModbusClientWrapper Host/Port Access
**What goes wrong:** Connection status lookup needs to match by host+port, but `ModbusClientWrapper` may not expose these.
**Why it happens:** The adapter lookup in JBTM uses `dc.wrapper.host` and `dc.wrapper.port`.
**How to avoid:** Verify `ModbusClientWrapper` exposes host and port getters before writing the lookup. If not, fall back to `serverAlias`-only matching.

### Pitfall 5: Widget Test Provider Overrides
**What goes wrong:** Server config page depends on `stateManProvider`, `preferencesProvider`, `databaseProvider`, and `refreshKeyProvider`. Missing overrides cause async loading that never resolves in tests.
**Why it happens:** Real providers hit secure storage, database, and network.
**How to avoid:** Override all providers in test setup. Use existing `createTestPreferences` helper. For `stateManProvider`, either override with a mock or skip (tests focused on UI rendering don't need a real StateMan).

## Claude's Discretion Recommendations

### FontAwesome Icon for Modbus Section Header
**Recommendation:** `FontAwesomeIcons.networkWired`
**Rationale:** Modbus is a network protocol. The `networkWired` icon (wired network symbol) fits alongside `server` (OPC UA) and `scaleBalanced` (JBTM weigher). Alternative: `FontAwesomeIcons.plug` (electrical connection).

### Default Field Values for New Modbus Server
**Recommendation:**
- host: `'localhost'` (matches JBTM default)
- port: `502` (Modbus TCP standard port)
- unitId: `1` (most common default slave address)
- serverAlias: `null` (matches JBTM -- optional)
- pollGroups: `[ModbusPollGroupConfig(name: 'default', intervalMs: 1000)]` (per user decision)

### Validation Approach
**Recommendation:** Inline-on-change with `_updateServer()` callback (match existing JBTM pattern). No form validators. Parse with defaults in `_updateServer()`:
- port: `int.tryParse(...) ?? 502`
- unitId: `(int.tryParse(...) ?? 1).clamp(1, 247)`

### Poll Group Deletion When Keys Are Assigned
**Recommendation:** Allow deletion with a warning dialog: "Keys assigned to this poll group will fall back to the 'default' poll group. Continue?" This is safest for operators -- no data loss, keys still work.
However, the config UI doesn't have access to KeyMappings (that's in a different provider/page). So the UI cannot actually check if keys are assigned. Simpler approach: just allow deletion. If the poll group referenced by keys is removed, `ModbusClientWrapper.subscribe()` creates a lazy default group anyway (per decision from 05-01). No dialog needed -- the system is already resilient.

### Server Removal Confirmation Dialog
**Recommendation:** Yes -- use a confirmation dialog, matching the JBTM pattern exactly (server_config.dart lines 1266-1284). JBTM already uses `showDialog` with "Remove Server" / "Cancel" / "Remove" buttons.

### Section Ordering on Server Config Page
**Recommendation:** Add Modbus section between JBTM and Import/Export:
```dart
// Current order in ServerConfigPage.build():
DatabaseConfigWidget,
_OpcUAServersSection,
_JbtmServersSection,
_ModbusServersSection,  // <-- NEW, after JBTM
ImportExportCard,
```
Rationale: Industrial protocol sections are grouped together (OPC UA, JBTM, Modbus), with Modbus last as the newest addition. Import/Export stays at the bottom as a utility.

### Empty State Widget
**Recommendation:** Clone `_EmptyJbtmServersWidget` pattern:
```dart
class _EmptyModbusServersWidget extends StatelessWidget {
  const _EmptyModbusServersWidget();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FaIcon(FontAwesomeIcons.networkWired, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No Modbus servers configured', ...),
          const SizedBox(height: 8),
          const Text('Add your first Modbus TCP server to get started', ...),
        ],
      ),
    );
  }
}
```

## Code Examples

### New Server Addition (from JBTM pattern, adapted for Modbus)
```dart
// Source: server_config.dart line 910-912 (JBTM pattern)
void _addServer() {
  setState(() => _config?.modbus.add(ModbusConfig(
    host: 'localhost',
    port: 502,
    unitId: 1,
    pollGroups: [ModbusPollGroupConfig(name: 'default', intervalMs: 1000)],
  )));
}
```

### Server Update Callback (adapted for Modbus)
```dart
// Source: server_config.dart line 951-953 (JBTM pattern)
void _updateServer(int index, ModbusConfig server) {
  setState(() => _config!.modbus[index] = server);
}
```

### Connection Status Chip (reused from JBTM card)
```dart
// Source: server_config.dart lines 1191-1228 (JBTM card)
Color _connectionStatusColor() {
  if (_connectionStatus == null) {
    return widget.stateManLoading ? Colors.orange : Colors.grey;
  }
  return switch (_connectionStatus!) {
    ConnectionStatus.connected => Colors.green,
    ConnectionStatus.connecting => Colors.orange,
    ConnectionStatus.disconnected => Colors.red,
  };
}
```

### Poll Group Expansion Section (new for Modbus)
```dart
// Poll groups expandable section inside server card
ExpansionTile(
  title: Text('Poll Groups (${widget.server.pollGroups.length})'),
  initiallyExpanded: false,
  children: [
    ...widget.server.pollGroups.asMap().entries.map((entry) {
      final i = entry.key;
      final pg = entry.value;
      return ListTile(
        title: TextField(
          controller: _pollGroupNameControllers[i],
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => _updatePollGroup(i),
        ),
        subtitle: TextField(
          controller: _pollGroupIntervalControllers[i],
          decoration: const InputDecoration(labelText: 'Interval (ms)'),
          keyboardType: TextInputType.number,
          onChanged: (_) => _updatePollGroup(i),
        ),
        trailing: IconButton(
          icon: const FaIcon(FontAwesomeIcons.trash, size: 16),
          onPressed: () => _removePollGroup(i),
        ),
      );
    }),
    TextButton.icon(
      icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
      label: const Text('Add Poll Group'),
      onPressed: _addPollGroup,
    ),
  ],
)
```

### Widget Test Setup (extending existing helpers)
```dart
// Source: test/helpers/test_helpers.dart pattern
StateManConfig sampleModbusStateManConfig() {
  return StateManConfig(
    opcua: [],
    modbus: [
      ModbusConfig(
        host: '192.168.1.100',
        port: 502,
        unitId: 1,
        serverAlias: 'plc_1',
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
          ModbusPollGroupConfig(name: 'fast', intervalMs: 100),
        ],
      ),
    ],
  );
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| N/A | Clone JBTM pattern for Modbus | Phase 10 | Consistent UI across all protocols |

No deprecated APIs or outdated patterns. The existing codebase patterns are current and should be followed exactly.

## Open Questions

1. **Does `ModbusClientWrapper` expose `host` and `port` getters?**
   - What we know: JBTM uses `dc.wrapper.host` and `dc.wrapper.port` for fallback matching. `ModbusDeviceClientAdapter` has `.wrapper` of type `ModbusClientWrapper`.
   - What's unclear: Whether `ModbusClientWrapper` has these getters (they would come from the underlying `ModbusClientTcp` or be added fields).
   - Recommendation: Check during implementation. If not available, use `serverAlias`-only matching (which is the primary path anyway -- the host+port fallback is just defensive).

2. **Poll group TextEditingController lifecycle management**
   - What we know: Each poll group needs a name and interval controller. The JBTM card manages 3 controllers (host, port, alias).
   - What's unclear: With a dynamic list of poll groups, controllers need to be created/disposed as groups are added/removed.
   - Recommendation: Maintain `List<TextEditingController>` pairs that sync with `widget.server.pollGroups.length` in `didUpdateWidget`.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) |
| Config file | none -- standard Flutter test setup |
| Quick run command | `flutter test test/pages/server_config_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements --> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UISV-01 | Add Modbus server with host/port/unitId/alias | widget | `flutter test test/pages/server_config_test.dart --name "add server"` | No -- Wave 0 |
| UISV-02 | Edit existing Modbus server config | widget | `flutter test test/pages/server_config_test.dart --name "edit server"` | No -- Wave 0 |
| UISV-03 | Remove a Modbus server | widget | `flutter test test/pages/server_config_test.dart --name "remove server"` | No -- Wave 0 |
| UISV-04 | Live connection status per server | widget | `flutter test test/pages/server_config_test.dart --name "connection status"` | No -- Wave 0 |
| UISV-05 | Configure poll groups per server | widget | `flutter test test/pages/server_config_test.dart --name "poll group"` | No -- Wave 0 |
| TEST-08 | Server config Modbus section has widget tests | meta | All above pass | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/pages/server_config_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/pages/server_config_test.dart` -- Modbus section widget tests (covers UISV-01 through UISV-05, TEST-08)
- [ ] `test/helpers/test_helpers.dart` -- extend with `sampleModbusStateManConfig()` and `buildTestableServerConfig()` helpers
- [ ] No framework install needed -- `flutter_test` already in dev_dependencies

## Sources

### Primary (HIGH confidence)
- `lib/pages/server_config.dart` (lines 834-1379) -- JBTM section pattern (complete template)
- `packages/tfc_dart/lib/core/state_man.dart` (lines 257-282) -- `ModbusConfig` model
- `packages/tfc_dart/lib/core/state_man.dart` (lines 235-251) -- `ModbusPollGroupConfig` model
- `packages/tfc_dart/lib/core/modbus_device_client.dart` (lines 12-67) -- `ModbusDeviceClientAdapter` interface
- `lib/providers/state_man.dart` -- `stateManProvider` with Modbus client creation
- `test/helpers/test_helpers.dart` -- existing test infrastructure
- `test/pages/key_repository_test.dart` -- widget test patterns

### Secondary (MEDIUM confidence)
- Modbus TCP standard port 502, unit ID range 1-247 -- well-known protocol constants

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already in project, no new deps
- Architecture: HIGH -- exact template exists in same file (JBTM section)
- Pitfalls: HIGH -- identified from direct code inspection of data models
- Testing: HIGH -- existing test infrastructure and patterns provide clear template

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- internal project patterns, not external dependencies)
