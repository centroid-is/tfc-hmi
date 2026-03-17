# PLAN: Phase 3 — Web Platform (Stories 6-7)

**Phase:** 3 of 5 — mqtt-web plan
**Branch:** mqtt
**Date:** 2026-03-17

---

## Executive Summary

Make `flutter build web` succeed in `centroid-hmi/` and wire StaticConfig into the
provider chain for web config loading. The biggest technical challenge is the
`open62541` FFI dependency: `DynamicValue` (the universal data type) directly
imports `dart:ffi` and cannot be compiled for web. Every asset widget, the state
manager, and the MQTT adapter all depend on it. This plan addresses that blocker
first, then systematically breaks all native import chains.

---

## Implementation Order

### Step 0: Web directory scaffold
**Risk:** Low
**Files to create:** `centroid-hmi/web/` boilerplate

1. Run `flutter create --platforms=web .` in a temp directory
2. Copy the resulting `web/` folder into `centroid-hmi/`
3. Create `centroid-hmi/web/config/config.json` (example MQTT config):
   ```json
   {
     "opcua": [], "jbtm": [], "modbus": [],
     "mqtt": [{
       "host": "localhost", "port": 9001,
       "use_web_socket": true, "ws_path": "/mqtt",
       "client_id": "tfc-web", "keep_alive_period": 60
     }]
   }
   ```
4. Create `centroid-hmi/web/config/keymappings.json` (2 example MQTT keys)
5. Create `centroid-hmi/web/config/page-editor.json` (minimal home page)

**Validation:** Directory exists, files are valid JSON.

---

### Step 1: DynamicValue web shim (CRITICAL PATH)
**Risk:** HIGH — API surface compatibility
**Files to create:**
- `packages/tfc_dart/lib/core/dynamic_value_web.dart`
- `packages/tfc_dart/lib/core/dynamic_value.dart` (conditional import hub)
- `packages/tfc_dart/lib/core/open62541_types_web.dart` (NodeId, LocalizedText, etc. stubs)
- `packages/tfc_dart/lib/core/open62541_types.dart` (conditional import hub for all types)

**Why:** `DynamicValue` from `package:open62541/open62541.dart` directly imports
`dart:ffi` and transitively loads native shared libraries. It cannot compile for
web. Yet it's imported by ~20 files across the app. We must provide a web-safe
replacement with the same API surface.

**Approach:**

1. **Audit DynamicValue usage** in all 20 importing files. Catalog which constructors,
   methods, and properties are actually called. Expected subset:
   - Constructors: `DynamicValue(value)`, `DynamicValue.fromJson(map)`
   - Properties: `.value` (dynamic getter), `.sourceTimestamp`
   - Methods: `.toJson()`, `.toString()`
   - Type checks: value is int/double/String/bool/List/Map

2. **Create `dynamic_value_web.dart`**: Pure Dart class matching the API surface above.
   No `dart:ffi`, no `dart:io`. JSON round-trip compatible with the native version.
   Must handle the same JSON structure that `MqttDeviceClientAdapter` produces.

3. **Create `dynamic_value.dart`** (conditional import hub):
   ```dart
   export 'package:open62541/open62541.dart' show DynamicValue
       if (dart.library.js_interop) 'dynamic_value_web.dart';
   ```

4. **Create `open62541_types_web.dart`** — stubs for `NodeId`, `LocalizedText`,
   `EnumField`, `AttributeId`. On web these types exist for compilation but OPC UA
   code paths never execute.

5. **Create `open62541_types.dart`** (conditional import hub for all open62541 types):
   ```dart
   export 'package:open62541/open62541.dart'
       show DynamicValue, NodeId, LocalizedText, EnumField, AttributeId
       if (dart.library.js_interop) 'open62541_types_web.dart';
   ```

**Testing (TDD):**
- Write `packages/tfc_dart/test/core/dynamic_value_web_test.dart`:
  - JSON round-trip: `fromJson(map).toJson()` equals original
  - Value access: int, double, string, bool, nested map, list
  - Constructor: `DynamicValue(42).value == 42`
  - toString: produces readable output
  - Null handling: `DynamicValue(null).value == null`

**Validation:** `dart test` passes for dynamic_value_web_test.dart.

---

### Step 2: State model extraction
**Risk:** Medium — many downstream imports
**Files to create:**
- `packages/tfc_dart/lib/core/state_man_types.dart`

**Why:** `state_man.dart` contains both pure-Dart models (`StateManConfig`,
`KeyMappings`, `ConnectionStatus`, etc.) AND native-only code (`StateMan` class
using `ClientIsolate`, `NodeId` from open62541). Web code needs the models but
cannot import the file.

**Approach:**

1. **Extract to `state_man_types.dart`** (pure Dart, no open62541 imports):
   - `StateManConfig` + `fromJson`/`toJson`/`fromString`
   - `KeyMappings` + `KeyMappingEntry` + `fromJson`/`toJson`/`fromString`
   - `OpcUANodeConfig`, `JbtmServerConfig`, `ModbusConfig`, `ModbusNodeConfig`
   - `MqttConfig`, `MqttNodeConfig`, `MqttPayloadType`
   - `ConnectionStatus` enum
   - `DeviceClient` abstract interface (uses `DynamicValue` from the conditional hub)
   - The `part 'state_man.g.dart'` generated code for JSON serialization

2. **Modify `state_man.dart`**: Add `export 'state_man_types.dart';` at the top.
   Remove the extracted classes (they now live in the types file). The `StateMan`
   class stays in `state_man.dart` with its open62541 imports. All existing
   `import 'state_man.dart'` callers still get the types via the export.

3. **Update `config_source.dart`**: Change `import 'state_man.dart'` to
   `import 'state_man_types.dart'` — makes it web-safe.

4. **Update `mqtt_device_client.dart`**: Change `import 'package:open62541/open62541.dart' show DynamicValue`
   to `import 'dynamic_value.dart'` — makes it web-safe.

5. **Update `config_source_native.dart`**: Already uses `dart:io`, no change needed
   (it's native-only by design and not imported on web).

**Testing:** `cd packages/tfc_dart && dart test --exclude-tags=integration` — all existing tests still pass (no behavioral change, just file reorganization).

**Note on `state_man.g.dart`:** The generated JSON serialization code is produced by
`build_runner` from `@JsonSerializable` annotations. After moving models to
`state_man_types.dart`, the `part` directive must move too. Run
`dart run build_runner build --delete-conflicting-outputs` after extraction.

---

### Step 3: Update open62541 imports across the app
**Risk:** Medium — ~20 files to change, but each change is mechanical
**Files to modify:** All files importing `package:open62541/open62541.dart`

**Approach:**

Change every `import 'package:open62541/open62541.dart' show DynamicValue`
(and similar) to use the conditional import hub from Step 1.

**Files in `packages/tfc_dart/lib/core/`:**
| File | Current Import | New Import |
|------|---------------|------------|
| `boolean_expression.dart` | `open62541 show DynamicValue` | `dynamic_value.dart` |
| `collector.dart` | `open62541 show DynamicValue` | `dynamic_value.dart` |
| `mqtt_device_client.dart` | `open62541 show DynamicValue` | `dynamic_value.dart` |
| `modbus_device_client.dart` | `open62541 show DynamicValue, NodeId` | `open62541_types.dart` |

**Files in `lib/` (app layer) — change to `package:tfc_dart/core/open62541_types.dart`:**
| File | Types Used |
|------|-----------|
| `widgets/dynamic_value.dart` | DynamicValue |
| `widgets/opcua_array_index_field.dart` | NodeId, DynamicValue |
| `page_creator/assets/analog_box.dart` | DynamicValue |
| `page_creator/assets/arrow.dart` | DynamicValue |
| `page_creator/assets/beckhoff.dart` | DynamicValue |
| `page_creator/assets/button.dart` | DynamicValue, NodeId |
| `page_creator/assets/conveyor.dart` | DynamicValue |
| `page_creator/assets/conveyor_gate.dart` | DynamicValue, NodeId |
| `page_creator/assets/number.dart` | DynamicValue |
| `page_creator/assets/recipes.dart` | DynamicValue |
| `page_creator/assets/schneider.dart` | AttributeId, DynamicValue, LocalizedText, NodeId |
| `page_creator/assets/speedbatcher.dart` | DynamicValue |
| `page_creator/assets/start_stop_button.dart` | DynamicValue, NodeId |
| `page_creator/assets/text.dart` | DynamicValue |
| `mcp/state_man_state_reader.dart` | DynamicValue |

**Files that import `state_man.dart` for TYPES ONLY** (change to `state_man_types.dart`
via `package:tfc_dart/core/state_man_types.dart`):
- `lib/pages/server_config.dart` (uses StateManConfig, KeyMappings)
- `lib/pages/key_repository.dart` (uses KeyMappings, KeyMappingEntry)
- `lib/plc/plc_detail_panel.dart` (uses KeyMappingEntry, KeyMappings)
- `lib/widgets/key_mapping_sections.dart` (uses KeyMappingEntry etc.)
- `lib/widgets/connection_status_chip.dart` (uses ConnectionStatus)

**Files that need the full StateMan class** (keep importing `state_man.dart` —
these will be handled in Steps 7-8 via conditional imports):
- `lib/providers/state_man.dart`
- `lib/providers/mcp_bridge.dart`
- `lib/mcp/state_man_state_reader.dart`

**Testing:** `dart analyze --fatal-infos` in both `packages/tfc_dart/` and root.
All existing tests pass.

---

### Step 4: `io_stub.dart` and `dart:io` conditional imports
**Risk:** Low — well-understood pattern
**Files to create:**
- `lib/core/io_stub.dart`

**Files to modify:** All files in `lib/` that import `dart:io` and are reachable on web.

**`lib/core/io_stub.dart` content:**
```dart
/// Stub for dart:io on web.
class Platform {
  static bool get isLinux => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static Map<String, String> get environment => const {};
}

class File {
  final String path;
  File(this.path);
  Future<bool> exists() => throw UnsupportedError('File I/O not available on web');
  Future<String> readAsString() => throw UnsupportedError('File I/O not available on web');
}

final stderr = _StderrStub();
class _StderrStub {
  void writeln([Object? object]) {} // no-op on web
}
```

**Files needing conditional `dart:io` import** (pattern: `import 'dart:io' if (dart.library.js_interop) '...io_stub.dart'`):

| File | `dart:io` Usage |
|------|----------------|
| `lib/providers/state_man.dart` | `stderr.writeln` |
| `lib/providers/database.dart` | `io.stderr.writeln` |
| `lib/pages/server_config.dart` | Platform, File, stderr |
| `lib/pages/key_repository.dart` | Platform, File |
| `lib/pages/page_editor.dart` | `Platform` (already has kIsWeb guard) |
| `lib/widgets/base_scaffold.dart` | `dart:io` |
| `lib/widgets/nav_dropdown.dart` | `dart:io` |
| `lib/widgets/dynamic_value.dart` | `stderr` |
| `lib/widgets/preferences.dart` | `io.stderr` |
| `lib/widgets/searchable_pdf_viewer.dart` | `Platform` |
| `lib/page_creator/assets/led.dart` | `dart:io` |
| `lib/providers/chat.dart` | `dart:io as io` |
| `lib/tech_docs/tech_doc_library_section.dart` | `dart:io as io` |
| `lib/llm/gemini_provider.dart` | `dart:io` |
| `lib/drawings/drawing_upload_service.dart` | `dart:io` |
| `lib/plc/plc_code_upload_service.dart` | `dart:io` |

Each gets: `import 'dart:io' if (dart.library.js_interop) '../core/io_stub.dart';`
(adjust relative path per file location). Add `kIsWeb` guards around Platform/File usage.

**Important:** Some files use `import 'dart:io' as io;` — the stub must still work
with the `io.` prefix. The conditional import replaces the library, so `io.stderr`
resolves to `_StderrStub`.

**Testing:** `dart analyze --fatal-infos` passes.

---

### Step 5: Page stubs for native-only pages
**Risk:** Low — mechanical
**Files to create (6 stubs):**
- `lib/pages/dbus_login_stub.dart`
- `lib/pages/ip_settings_stub.dart`
- `lib/pages/about_linux_stub.dart`
- `lib/pages/config_edit_stub.dart`
- `lib/pages/config_list_stub.dart`
- `lib/pages/ipc_connections_stub.dart`

Each stub exports the same widget class with an identical constructor signature
but renders a "Not available on web" placeholder. Example:

```dart
import 'package:flutter/material.dart';

class IpSettingsPage extends StatelessWidget {
  final dynamic dbusClient; // match constructor signature
  const IpSettingsPage({super.key, required this.dbusClient});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('IP Settings is not available on web')),
    );
  }
}
```

For `LoginForm` (used in `dbus_login_stub.dart`), the stub must accept the
`onLoginSuccess` callback parameter to match the call site in `main.dart`.

---

### Step 6: MCP/Chat/Drawings subsystem web guard
**Risk:** Medium — complex provider wiring in main.dart
**Files to create:**
- `lib/providers/mcp_bridge_stub.dart`
- `lib/chat/chat_overlay_stub.dart`
- `lib/drawings/drawing_overlay_stub.dart`

**Why:** The MCP SSE server (`mcp_sse_server.dart`), chat providers, and drawing
upload service all use `dart:io` for HTTP server, process execution, etc. They're
wired into `main.dart`'s `MyApp.build()` via `ref.watch(mcpServerLifecycleProvider)`.

**Approach:**

1. **Create stub files** that export the same provider/widget names but with no-op
   implementations (e.g., `mcpBridgeProvider` returns a no-op notifier,
   `ChatOverlay` renders `SizedBox.shrink()`).

2. **Conditional imports in `main.dart`**:
   ```dart
   import 'package:tfc/providers/mcp_bridge.dart'
       if (dart.library.js_interop) 'package:tfc/providers/mcp_bridge_stub.dart';
   import 'package:tfc/chat/chat_overlay.dart'
       if (dart.library.js_interop) 'package:tfc/chat/chat_overlay_stub.dart';
   import 'package:tfc/drawings/drawing_overlay.dart'
       if (dart.library.js_interop) 'package:tfc/drawings/drawing_overlay_stub.dart';
   ```

3. **Guard MCP provider watches** in `MyApp.build()` with `if (!kIsWeb)`.

4. **Guard chat/drawing overlays** with `if (!kIsWeb)` in the Stack.

5. **Guard `_wireElicitationHandler(ref)`** with `if (!kIsWeb)`.

6. Also need stubs for:
   - `package:mcp_dart/mcp_dart.dart show ElicitResult` → `lib/core/mcp_stub.dart`
   - `package:tfc/chat/elicitation_dialog.dart` → stub or conditional
   - `package:tfc/providers/chat.dart` → stub
   - `package:tfc/providers/proposal_watcher.dart` → may need stub
   - `package:tfc/providers/proposal_state.dart` → may need stub

---

### Step 7: `main.dart` comprehensive web adaptation
**Risk:** HIGH — most complex file, many native deps
**File to modify:** `centroid-hmi/lib/main.dart`

**Imports requiring conditional stubs:**

| Import | Stub |
|--------|------|
| `dart:io` | `io_stub.dart` |
| `package:dbus/dbus.dart` | `lib/core/dbus_stub.dart` (stub `DBusClient` class) |
| `package:amplify_secure_storage_dart/...` | `lib/core/amplify_stub.dart` |
| `package:upgrader/upgrader.dart` | `lib/core/upgrader_stub.dart` |
| `package:microsoft_store_upgrader/...` | (covered by upgrader stub) |
| `package:pdfrx/pdfrx.dart` | `lib/core/pdfrx_stub.dart` |
| `package:tfc_dart/core/secure_storage/...` | `lib/core/secure_storage_stub.dart` |
| 6 native-only page imports | stubs from Step 5 |
| MCP/chat/drawing imports | stubs from Step 6 |
| `marionette_init.dart` | conditional or stub |

**Native-only initialization to guard in `_startApp()`:**

```dart
if (!kIsWeb) {
  pdfrxFlutterInitialize();
  AmplifySecureStorageDart.registerWith();
  if (Platform.isWindows) {
    SecureStorage.setInstance(OtherSecureStorage());
  }
}
final environmentVariableIsGod = !kIsWeb && Platform.environment['TFC_GOD'] == 'true';
```

**`main()` function split:**
```dart
void main() {
  if (kIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
    _startApp();
  } else if (_enableMarionette) {
    initMarionette();
    _startApp();
  } else {
    runZonedGuarded(() {
      WidgetsFlutterBinding.ensureInitialized();
      _startApp();
    }, (error, stackTrace) {
      stderr.writeln('Unhandled async error: $error');
    });
  }
}
```

**Upgrader guard:**
```dart
Widget app;
if (kIsWeb) {
  app = ProviderScope(child: MyApp(locationBuilder: locationBuilder));
} else {
  final upgrader = Upgrader(...);
  app = ProviderScope(child: UpgradeAlert(upgrader: upgrader, child: MyApp(...)));
}
runApp(app);
```

**Menu building changes:**
```dart
children: [
  if (!kIsWeb && Platform.isLinux)
    MenuItem(label: 'IP Settings', ...),
  if (!kIsWeb && Platform.isLinux)
    MenuItem(label: 'About Linux', ...),
  if (environmentVariableIsGod) MenuItem(label: 'Page Editor', ...),
  if (environmentVariableIsGod) MenuItem(label: 'Preferences', ...),
  if (environmentVariableIsGod) MenuItem(label: 'Alarm Editor', ...),
  MenuItem(label: 'History View', ...),
  MenuItem(label: 'Server Config', ...),
  MenuItem(label: 'Key Repository', ...),
  MenuItem(label: 'Knowledge Base', ...),
],
```

**dbusCompleter guard:** Wrap the `Completer<DBusClient>` declaration and all
D-Bus route logic in `if (!kIsWeb)` blocks. The route definitions for IP Settings
and About Linux should use the stub widgets on web (already handled by conditional
page imports).

---

### Step 8: Provider layer web support
**Risk:** Medium
**Files to modify:**
- `lib/providers/state_man.dart`
- `lib/providers/database.dart`

**Files to create:**
- `lib/providers/state_man_web_stubs.dart`

**`lib/providers/database.dart`:**
Add `if (kIsWeb) return null;` at the top of the provider function.
Change `import 'dart:io' as io` to conditional import.

**`lib/providers/state_man.dart`:**

This is complex because it imports:
- `package:tfc_dart/core/modbus_device_client.dart` (→ open62541 via NodeId)
- `package:tfc_dart/core/state_man.dart` (→ open62541)

**Solution:** Conditional imports for native-only modules:

```dart
import 'package:tfc_dart/core/state_man.dart'
    if (dart.library.js_interop) 'package:tfc_dart/core/state_man_types.dart';
import 'package:tfc_dart/core/modbus_device_client.dart'
    if (dart.library.js_interop) 'state_man_web_stubs.dart';
```

Create `lib/providers/state_man_web_stubs.dart`:
```dart
import 'package:tfc_dart/core/state_man_types.dart';
List<DeviceClient> createM2400DeviceClients(List<dynamic> configs) => [];
List<DeviceClient> buildModbusDeviceClients(List<dynamic> configs, KeyMappings km) => [];
```

Guard in the provider:
```dart
final m2400Clients = kIsWeb ? <DeviceClient>[] : createM2400DeviceClients(config.jbtm);
final modbusClients = kIsWeb ? <DeviceClient>[] : buildModbusDeviceClients(config.modbus, keyMappings);
final mqttClients = config.mqtt.map((c) => MqttDeviceClientAdapter(c, keyMappings)).toList();
```

**StateMan.create() on web:** `StateMan` class is in `state_man.dart` (native-only
due to open62541 imports for `ClientIsolate`, `NodeId`, `ClientState`). On web,
the conditional import routes to `state_man_types.dart` which does NOT export
`StateMan`. Two options:

**Option A (preferred):** Extract `StateMan`'s core routing logic into a web-safe
base class in `state_man_types.dart`. The `StateMan` class becomes:
```
state_man_types.dart: StateManBase (routing, subscribe/read/write, connection aggregation)
state_man.dart: StateMan extends StateManBase (adds OPC UA health check, ClientIsolate mgmt)
```
The provider creates `StateManBase` on web and `StateMan` on native. Asset widgets
use `StateManBase` (or an interface) for subscribe/read/write.

**Option B:** Create a separate `StateManWeb` class in the web stubs file that
reimplements the routing logic for MQTT-only use. Simpler but duplicates code.

**Decision:** Go with Option A. The StateMan class already delegates to DeviceClients
for the actual protocol work. The core routing (key → DeviceClient lookup, stream
management, connection status aggregation) is FFI-free. Extract that core, keep
OPC UA-specific code in the native subclass.

---

### Step 9 (Story 7): Config loader conditional imports
**Risk:** Low — clean new code
**Files to create:**
- `lib/core/config_loader.dart` (conditional import hub)
- `lib/core/config_loader_native.dart`
- `lib/core/config_loader_web.dart`

**`config_loader.dart`:**
```dart
export 'config_loader_native.dart'
    if (dart.library.js_interop) 'config_loader_web.dart';
```

**`config_loader_native.dart`:**
```dart
import 'dart:io';
import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/config_source_native.dart';

Future<StaticConfig?> loadStaticConfig() async {
  final configDir = Platform.environment['CENTROID_CONFIG_DIR'];
  if (configDir == null) return null;
  return staticConfigFromDirectory(configDir);
}
```

**`config_loader_web.dart`:**
```dart
import 'package:http/http.dart' as http;
import 'package:tfc_dart/core/config_source.dart';

Future<StaticConfig?> loadStaticConfig() async {
  final configResp = await http.get(Uri.parse('config/config.json'));
  final keyMappingsResp = await http.get(Uri.parse('config/keymappings.json'));
  final pageEditorResp = await http.get(Uri.parse('config/page-editor.json'));

  if (configResp.statusCode != 200 || keyMappingsResp.statusCode != 200) {
    return null;
  }

  return StaticConfig.fromStrings(
    configJson: configResp.body,
    keyMappingsJson: keyMappingsResp.body,
    pageEditorJson: pageEditorResp.statusCode == 200 ? pageEditorResp.body : null,
  );
}
```

**Dependency:** Add `http: ^1.0.0` to `pubspec.yaml`.

---

### Step 10 (Story 7): Static config provider + stateMan integration
**Risk:** Medium
**Files to create:**
- `lib/providers/static_config.dart`

**Files to modify:**
- `lib/providers/state_man.dart`

**`lib/providers/static_config.dart`:**
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/config_source.dart';
import '../core/config_loader.dart';

part 'static_config.g.dart';

@Riverpod(keepAlive: true)
Future<StaticConfig?> staticConfig(Ref ref) async {
  return loadStaticConfig();
}
```

**Modify `stateManProvider`:**
```dart
@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  final staticConfig = await ref.read(staticConfigProvider.future);

  if (staticConfig != null) {
    // Static mode: bypass preferences, MQTT clients only
    final mqttClients = staticConfig.stateManConfig.mqtt
        .map((c) => MqttDeviceClientAdapter(c, staticConfig.keyMappings))
        .toList();
    final stateMan = await StateMan.create(
      config: staticConfig.stateManConfig,
      keyMappings: staticConfig.keyMappings,
      deviceClients: mqttClients,
    );
    ref.onDispose(() async => await stateMan.close());
    return stateMan;
  }

  // Existing flow: load from preferences (unchanged)
  final prefs = await ref.read(preferencesProvider.future);
  // ... rest of current code
}
```

Run `dart run build_runner build --delete-conflicting-outputs` to generate
`static_config.g.dart`.

---

### Step 11 (Story 7): Page hiding in static mode
**Risk:** Low
**Files to modify:**
- `centroid-hmi/lib/main.dart`

**Menu changes:**
```dart
final isStaticMode = kIsWeb ||
    (!kIsWeb && Platform.environment.containsKey('CENTROID_CONFIG_DIR'));

children: [
  if (!kIsWeb && Platform.isLinux)
    MenuItem(label: 'IP Settings', ...),
  if (!kIsWeb && Platform.isLinux)
    MenuItem(label: 'About Linux', ...),
  if (!isStaticMode && environmentVariableIsGod)
    MenuItem(label: 'Page Editor', ...),
  if (!isStaticMode && environmentVariableIsGod)
    MenuItem(label: 'Preferences', ...),
  if (!isStaticMode && environmentVariableIsGod)
    MenuItem(label: 'Alarm Editor', ...),
  MenuItem(label: 'History View', ...),  // always visible
  if (!isStaticMode)
    MenuItem(label: 'Server Config', ...),
  if (!isStaticMode)
    MenuItem(label: 'Key Repository', ...),
  MenuItem(label: 'Knowledge Base', ...),  // always visible
],
```

---

### Step 12 (Story 7): PageManager static config integration
**Risk:** Low
**Files to modify:**
- `centroid-hmi/lib/main.dart`

**In `_startApp()`, change PageManager loading:**
```dart
final pageManager = PageManager(pages: {}, prefs: prefs);
if (kIsWeb) {
  final staticConfig = await loadStaticConfig();
  if (staticConfig?.pageEditorJson != null) {
    pageManager.fromJson(staticConfig!.pageEditorJson!);
  }
} else {
  await pageManager.load();
}
```

---

## Testing Strategy

### TDD Flow for Story 6
1. **Red:** Write `dynamic_value_web_test.dart` — tests fail (class doesn't exist)
2. **Green:** Implement `DynamicValue` web shim until tests pass
3. **Red:** Attempt `flutter build web` in `centroid-hmi/` — fails with import errors
4. **Green:** Fix imports iteratively until build succeeds
5. **Refactor:** Clean up any redundant stubs or guards

### TDD Flow for Story 7
1. **Red:** Write tests for `loadStaticConfig()` web variant (mock HTTP responses)
2. **Green:** Implement config_loader_web.dart
3. **Red:** Write test for stateManProvider with static config
4. **Green:** Implement provider changes
5. **Refactor:** Clean up provider code

### Validation Commands (run after each step)
```bash
# tfc_dart package (must never regress)
cd packages/tfc_dart && dart analyze --fatal-infos
cd packages/tfc_dart && dart test --exclude-tags=integration

# App analysis
cd centroid-hmi && flutter analyze --fatal-infos

# Web build (Story 6 gate)
cd centroid-hmi && flutter build web

# All native tests still pass
cd centroid-hmi && flutter test
```

---

## Risk Mitigation

### Risk 1: DynamicValue API Surface Mismatch (HIGH)
**Threat:** Web DynamicValue stub doesn't match all usage patterns in asset widgets.
**Mitigation:** Before implementing, grep ALL DynamicValue property/method access
across `lib/` to build the complete API contract. Write tests for each usage pattern.
**Fallback:** If the native DynamicValue API is too large to replicate, create a
`WebDynamicValue` wrapper that translates only the JSON-relevant subset, and use a
typedef alias.

### Risk 2: StateMan FFI Extraction (HIGH)
**Threat:** Extracting StateMan's core into an FFI-free base class introduces regressions.
**Mitigation:** This is the highest-risk refactor. Approach:
1. First, ensure ALL existing tests pass
2. Extract types file (Step 2) — run tests
3. Move StateMan routing core — run tests after each extraction
4. Keep the OPC UA health check in native-only code
**Fallback:** If StateMan split is too risky, create `StateManWeb` as a separate
class that implements the same interface using only MQTT DeviceClients. Asset widgets
would need to work with a common interface.

### Risk 3: open62541 as Direct Dependency in pubspec.yaml (MEDIUM)
**Threat:** Even with conditional imports in code, the web compiler may try to resolve
the `open62541` package from `pubspec.yaml` and fail when native libs are missing.
**Mitigation:** Test early — after Step 1, try `flutter build web` to see if the
dependency itself causes issues. If so:
- Dart's conditional imports should prevent compilation of unused code
- If the package itself triggers native lib loading at import time, may need
  `dependency_overrides` or package restructuring
- Worst case: fork open62541_dart to add a `types.dart` sub-library

### Risk 4: Transitive dart:io in Third-Party Packages (MEDIUM)
**Threat:** Packages like `postgres`, `drift_postgres`, `dartssh2`, `nm`, `dbus`
import `dart:io` and may cause web build failures even if our code doesn't call them.
**Mitigation:** These packages must not appear in the import chain on web. Conditional
imports must completely sever the chain. Test with `flutter build web --verbose` to
catch transitive failures early.

### Risk 5: Scope Creep from Deep Widget Dependencies (LOW)
**Threat:** Asset widgets import native-dependent files we didn't account for.
**Mitigation:** After Step 3, do a full `dart analyze` for web target to catch
remaining import chain issues before attempting the build.

---

## Dependency Graph

```
Step 0 (web scaffold) ─────────────────────────────────────────────────┐
                                                                       │
Step 1 (DynamicValue shim) ──→ Step 2 (state model extraction)        │
                                       │                               │
                                       ↓                               │
                              Step 3 (update open62541 imports)        │
                                       │                               │
                 ┌─────────────────────┼─────────────────────┐         │
                 ↓                     ↓                     ↓         │
         Step 4 (io_stub)     Step 5 (page stubs)    Step 6 (MCP)     │
                 │                     │                     │         │
                 └─────────────────────┼─────────────────────┘         │
                                       ↓                               │
                              Step 7 (main.dart adaptation) ←──────────┘
                                       │
                              Step 8 (provider web support)
                                       │
                    ═══════════════════════════════════ Story 6 done
                                       │
                              Step 9 (config loader)
                                       │
                              Step 10 (static config provider)
                                       │
                 ┌─────────────────────┤
                 ↓                     ↓
         Step 11 (page hiding) Step 12 (PageManager integration)
                                       │
                    ═══════════════════════════════════ Story 7 done
```

---

## File Summary

### New Files (~23)
| File | Step | Purpose |
|------|------|---------|
| `centroid-hmi/web/` (directory + boilerplate) | 0 | Web platform scaffold |
| `centroid-hmi/web/config/config.json` | 0 | Example MQTT config |
| `centroid-hmi/web/config/keymappings.json` | 0 | Example key mappings |
| `centroid-hmi/web/config/page-editor.json` | 0 | Example page layout |
| `packages/tfc_dart/lib/core/dynamic_value_web.dart` | 1 | Web-safe DynamicValue |
| `packages/tfc_dart/lib/core/dynamic_value.dart` | 1 | Conditional import hub |
| `packages/tfc_dart/lib/core/open62541_types_web.dart` | 1 | Web stubs for NodeId etc. |
| `packages/tfc_dart/lib/core/open62541_types.dart` | 1 | Conditional import hub |
| `packages/tfc_dart/lib/core/state_man_types.dart` | 2 | Extracted pure-Dart models |
| `lib/core/io_stub.dart` | 4 | dart:io stub for web |
| `lib/pages/dbus_login_stub.dart` | 5 | LoginForm web stub |
| `lib/pages/ip_settings_stub.dart` | 5 | IpSettingsPage web stub |
| `lib/pages/about_linux_stub.dart` | 5 | AboutLinuxPage web stub |
| `lib/pages/config_edit_stub.dart` | 5 | ConfigEditPage web stub |
| `lib/pages/config_list_stub.dart` | 5 | ConfigListPage web stub |
| `lib/pages/ipc_connections_stub.dart` | 5 | IpcConnectionsPage web stub |
| `lib/providers/mcp_bridge_stub.dart` | 6 | MCP no-op for web |
| `lib/chat/chat_overlay_stub.dart` | 6 | Chat no-op for web |
| `lib/drawings/drawing_overlay_stub.dart` | 6 | Drawing no-op for web |
| `lib/core/dbus_stub.dart` | 7 | DBusClient stub |
| `lib/core/upgrader_stub.dart` | 7 | Upgrader/UpgradeAlert stubs |
| `lib/providers/state_man_web_stubs.dart` | 8 | Native device client stubs |
| `lib/core/config_loader.dart` | 9 | Conditional import hub |
| `lib/core/config_loader_native.dart` | 9 | Native config loader |
| `lib/core/config_loader_web.dart` | 9 | Web config loader (HTTP) |
| `lib/providers/static_config.dart` | 10 | StaticConfig provider |

### Modified Files (~45)
- ~20 files: open62541 import → conditional import hub (Step 3)
- ~16 files: dart:io → conditional import (Step 4)
- `packages/tfc_dart/lib/core/state_man.dart` (Step 2)
- `packages/tfc_dart/lib/core/config_source.dart` (Step 2)
- `packages/tfc_dart/lib/core/mqtt_device_client.dart` (Step 2)
- `centroid-hmi/lib/main.dart` (Steps 7, 11, 12)
- `lib/providers/state_man.dart` (Steps 8, 10)
- `lib/providers/database.dart` (Step 8)
- `pubspec.yaml` (Step 9 — add http dependency)

---

## Notes for Orchestrator

This is the largest phase in the plan. Story 6 alone touches ~45 files. Consider:
1. **Sub-story splitting:** Steps 0-3 (foundational) → Steps 4-8 (compilation) as
   two sequential orchestrator runs
2. **Early web build attempt:** After Step 3, try `flutter build web` to discover
   remaining blockers before investing in Steps 4-8
3. **Context budget:** The DynamicValue audit (Step 1) and import updates (Step 3)
   are high-context operations. May need dedicated sessions.
