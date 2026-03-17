# Context: Web Platform (Stories 6-7)

**Phase:** 3 of 5 — mqtt-web plan
**Branch:** mqtt
**Date:** 2026-03-17

## Prior Phase Results

Stories 1-5 completed successfully (all pass). Key artifacts:

| Story | Key Output |
|-------|-----------|
| 1 | `MqttConfig`, `MqttNodeConfig`, `MqttPayloadType` models in `state_man.dart` |
| 2 | `MqttDeviceClientAdapter` in `mqtt_device_client.dart` + conditional import pattern in `mqtt_client_factory.dart` |
| 3 | MQTT wired into `stateManProvider` alongside M2400 and Modbus clients |
| 4 | Mosquitto docker helpers + integration tests (tagged `integration`) |
| 5 | `StaticConfig` in `config_source.dart`, `staticConfigFromDirectory()` in `config_source_native.dart`, `fromString()` methods on `StateManConfig`/`KeyMappings` |

---

## Story 6: Web Conditional Imports + Compilation

### Goal
Make `flutter build web` succeed in `centroid-hmi/` by stubbing out all native-only code paths via conditional imports.

### Existing Conditional Import Pattern (proven in Story 2)

```dart
// packages/tfc_dart/lib/core/mqtt_client_factory.dart
export 'mqtt_client_factory_native.dart'
    if (dart.library.js_interop) 'mqtt_client_factory_web.dart';
```

Native file uses `MqttServerClient` (TCP), web file uses `MqttBrowserClient` (WebSocket). This is the pattern to replicate.

### Web Directory Status
**No `web/` directory exists** anywhere in the project. Must be created from scratch (`flutter create --platforms=web .` in temp dir, copy `web/` folder to `centroid-hmi/`).

### Files Requiring Stubs (6 pages — D-Bus/NM dependent)

| File | Widget | Native Deps |
|------|--------|-------------|
| `lib/pages/dbus_login.dart` | `LoginForm` | `dbus`, `Platform`, `dartssh2` |
| `lib/pages/ip_settings.dart` | `IpSettingsPage` | `nm`, `dbus` |
| `lib/pages/about_linux.dart` | `AboutLinuxPage` | `dbus`, `nm` |
| `lib/pages/config_edit.dart` | `ConfigEditPage` | `dbus` |
| `lib/pages/config_list.dart` | `ConfigListPage` | `dbus` |
| `lib/pages/ipc_connections.dart` | `IpcConnectionsPage` | `dbus` |

Each stub exports the same widget class with a "Not available on web" placeholder.

### Files Needing `kIsWeb` Guards (partial `dart:io` usage)

| File | What to Guard |
|------|---------------|
| `lib/pages/server_config.dart` | `Platform.isWindows/isLinux/isMacOS`, `File` for cert/export |
| `lib/pages/key_repository.dart` | `Platform.isWindows/isLinux/isMacOS` for export |
| `lib/pages/page_editor.dart` | Already has one `kIsWeb` guard (line 366), still imports `dart:io` |

These need `import 'dart:io' if (dart.library.js_interop) '../core/io_stub.dart'` + `!kIsWeb` guards around Platform/File usage.

### Critical: `centroid-hmi/lib/main.dart` (the app entry point)

This file has the heaviest native dependency surface:

**Direct `dart:io` usage:**
- `import 'dart:io'` (line 2)
- `Platform.isLinux` (lines 136, 138) — menu visibility
- `Platform.isWindows` (line 88) — SecureStorage init
- `Platform.environment['TFC_GOD']` (line 113) — dev mode flag
- `stderr.writeln()` (lines 76-77, 166) — error logging

**Native-only imports:**
- `package:dbus/dbus.dart` (line 8) — `DBusClient` type used in `dbusCompleter`
- `package:amplify_secure_storage_dart/...` (line 11) — `registerWith()`
- `package:upgrader/upgrader.dart` (line 12) — `Upgrader`, `UpgradeAlert`
- `package:microsoft_store_upgrader/...` (line 13) — `UpgraderWindowsStore`
- `package:tfc_dart/core/secure_storage/secure_storage.dart` (line 51)
- `package:tfc/core/secure_storage/other.dart` (line 52)
- `package:pdfrx/pdfrx.dart` (line 53) — `pdfrxFlutterInitialize()`
- 6 native-only page imports (dbus_login, ip_settings, about_linux, etc.)

**Strategy for main.dart:**
1. Conditional imports for the 6 native-only pages
2. Guard `Platform.*` calls with `!kIsWeb`
3. Conditional import for `dart:io` itself (`io_stub.dart` on web)
4. Guard native-only init (SecureStorage, pdfrx, Upgrader) with `!kIsWeb`
5. The `dbusCompleter` and D-Bus route logic must be guarded/stubbed
6. `UpgradeAlert` wrapper should be conditional (no app store on web)

### Provider Changes Needed for Web Compilation

**`lib/providers/state_man.dart`:**
- Imports `dart:io` (for `stderr`) — needs conditional import
- `createM2400DeviceClients()` and `buildModbusDeviceClients()` — skip on `kIsWeb`
- Only MQTT clients should be created on web

**`lib/providers/database.dart`:**
- Imports `dart:io as io` (for `io.stderr`) — needs guard
- On web: `databaseProvider` should return `null` immediately (no Postgres)

### `tfc_dart` Package — Web Compilation Scope

The `tfc_dart.dart` barrel export pulls in EVERYTHING including `state_man.dart` (→ open62541), `database_drift.dart` (→ isolates), `secure_storage.dart` (→ Platform). However:

- `mqtt_device_client.dart` already works: only imports `DynamicValue` from open62541 (a pure Dart class)
- `config_source.dart` is platform-agnostic (no `dart:io`)
- `config_source_native.dart` is native-only (uses `dart:io File`)
- The `tfc_dart_core.dart` barrel exists as an FFI-free subset

**Key question:** The app currently imports `package:tfc_dart/core/state_man.dart` directly (not through the barrel). `state_man.dart` imports `package:open62541/open62541.dart` which includes FFI bindings. On web, open62541's FFI code won't be tree-shaken because `state_man.dart` directly references OPC UA types (`ClientIsolate`, `NodeId`, etc.).

**Critical dependency chain for web:**
```
centroid-hmi/lib/main.dart
  → lib/providers/state_man.dart
    → tfc_dart/core/state_man.dart
      → package:open62541/open62541.dart (FFI! breaks web)
    → tfc_dart/core/modbus_device_client.dart
      → package:open62541/open62541.dart (FFI!)
    → tfc_dart/core/mqtt_device_client.dart
      → package:open62541/open62541.dart (only DynamicValue — may need stub)
```

The `open62541` package exposes `DynamicValue` which is used everywhere. If `DynamicValue` itself is pure Dart (no FFI), it may compile. But if the barrel `open62541.dart` transitively imports FFI bindings, the entire chain fails on web.

**Likely solution:** The `open62541` package needs to either:
1. Have `DynamicValue` in a separate import (e.g., `package:open62541/types.dart`)
2. Or: conditional imports in `state_man.dart` that route to a web-safe subset
3. Or: restructure so providers use a web-safe barrel on web

### Native-Only Dependencies in `centroid-hmi/pubspec.yaml`

These packages will try to compile for web:
- `open62541` (FFI) — **biggest blocker**
- `amplify_secure_storage_dart` — may have web support
- `upgrader` / `microsoft_store_upgrader` — Windows Store, no web
- `marionette_flutter` — test framework, can be excluded

### MCP Subsystem (~23 files)

The entire MCP subsystem (`lib/mcp/`, `lib/chat/`, `lib/drawings/`) uses `dart:io` for HTTP server, SSE, etc. All of this needs to be conditionally excluded on web. In `main.dart`, the MCP providers (`mcpServerLifecycleProvider`, `chatLifecycleProvider`, `mcpBridgeProvider`) are all watched in `MyApp.build()`.

---

## Story 7: Provider Integration — Static Config + Page Hiding

### Goal
Wire `StaticConfig` into the provider chain so the web app fetches config via HTTP and bypasses Preferences/SecureStorage entirely. Hide config editing pages when in static mode.

### Config Loading Architecture

```
config_loader.dart (conditional import hub)
├── config_loader_native.dart: reads CENTROID_CONFIG_DIR env var → staticConfigFromDirectory()
└── config_loader_web.dart: HTTP GET config/*.json → StaticConfig.fromStrings()
```

### Provider Chain (current → target)

**Current flow (native):**
```
databaseProvider → preferencesProvider → stateManProvider
                                       ↓
                              StateManConfig.fromPrefs(prefs)  [uses SecureStorage]
                              fetchKeyMappings(prefs)
                              createM2400DeviceClients()
                              buildModbusDeviceClients()
                              MqttDeviceClientAdapter()
```

**Target flow (web / static mode):**
```
staticConfigProvider (loadStaticConfig())
         ↓
stateManProvider checks staticConfig first:
  if non-null → bypass prefs, use StaticConfig directly, MQTT clients only
  if null → existing flow (fromPrefs, all device clients)
```

### New Providers Needed

1. **`staticConfigProvider`** — `@Riverpod(keepAlive: true)`, calls `loadStaticConfig()` from conditional import hub
2. **`pageManagerProvider`** (or modify existing PageManager init in main.dart) — uses `StaticConfig.pageEditorJson` when available

### Menu Changes for Static Mode

In `centroid-hmi/lib/main.dart` menu building (lines 130-149):

**Hide in static mode:**
- Server Config (line 145)
- Key Repository (line 146)
- Page Editor (line 139) — already gated on `environmentVariableIsGod`
- Preferences (line 141) — already gated
- Alarm Editor (line 143) — already gated

**Keep visible (read-only pages):**
- Home, Alarm View, History View, Knowledge Base
- Dynamic pages from PageManager

**Static mode detection:**
```dart
final isStaticMode = kIsWeb || Platform.environment.containsKey('CENTROID_CONFIG_DIR');
```

### PageManager Integration

Currently in `main.dart` (lines 120-128):
```dart
final prefs = SharedPreferencesWrapper(SharedPreferencesAsync());
final pageManager = PageManager(pages: {}, prefs: prefs);
await pageManager.load();
```

For static mode: `PageManager` needs to load from `StaticConfig.pageEditorJson` instead of from preferences. The `PageManager` class is in `lib/page_creator/page.dart`.

### Database on Web

`databaseProvider` (line 12-13) calls `DatabaseConfig.fromPrefs()` which uses `SharedPreferences`. On web, there's no Postgres connection possible, so it should return `null` early:
```dart
if (kIsWeb) return null;
```

---

## Key Patterns and Conventions

### Conditional Import Pattern
```dart
// hub file (no implementation, just routing)
export 'foo_native.dart'
    if (dart.library.js_interop) 'foo_web.dart';
```
- Uses `dart.library.js_interop` (not `dart.library.html` — that's deprecated)
- Native file imports `dart:io` freely
- Web file uses web-safe APIs only
- Both export identical public API surface

### Provider Pattern (Riverpod code generation)
```dart
@Riverpod(keepAlive: true)
Future<T> myProvider(Ref ref) async { ... }
```
Generated part files: `*.g.dart`. Run `build_runner build --delete-conflicting-outputs` after changes.

### Error Logging
Currently uses `stderr.writeln()` (dart:io). On web, should use `debugPrint()` or `logger` package instead.

### Testing Convention
- TDD: Red → Green → Refactor
- Unit tests in `test/` directories alongside source
- Integration tests tagged with `@Tags(['integration'])`
- Run with `dart test --exclude-tags=integration` for unit only

---

## Risks and Concerns

### Risk 1: `open62541` FFI Compilation on Web (HIGH)
The `open62541` package is a direct dependency in both `pubspec.yaml` and `centroid-hmi/pubspec.yaml`. Even if code paths are guarded with `kIsWeb`, the Dart compiler may still try to compile FFI bindings and fail. This is the single biggest risk for Story 6.

**Mitigation:** Check if `open62541` has separate type-only imports. If not, may need to create a `DynamicValue` stub for web or restructure imports. The `DynamicValue` class from open62541 is used pervasively (StateMan, DeviceClient interface, all assets).

### Risk 2: Transitive `dart:io` in Package Dependencies (MEDIUM)
Packages like `postgres`, `drift_postgres`, `dartssh2`, `nm`, `dbus` all import `dart:io`. Even if the app doesn't call them on web, Dart's tree-shaking may not prevent compilation errors from transitive imports.

**Mitigation:** These packages must not be transitively imported on web. Conditional imports must break the import chain completely.

### Risk 3: Scope Creep from MCP/Chat Subsystem (MEDIUM)
The MCP bridge, chat overlay, and related providers all use `dart:io`. They're wired into `main.dart` via provider watches. Stubbing all of this cleanly is non-trivial.

**Mitigation:** Create a conditional import for the entire MCP subsystem initialization. On web, providers return no-op/null implementations.

### Risk 4: `centroid-hmi/pubspec.yaml` Native Dependencies (MEDIUM)
`open62541`, `upgrader`, `microsoft_store_upgrader`, `amplify_secure_storage_dart` are direct dependencies in the centroid-hmi app. The web compiler may refuse to resolve these.

**Mitigation:** May need to make some deps conditional or move them to `dev_dependencies` if only used in tests/native paths. Or use dependency overrides for web builds.

### Risk 5: PageManager Initialization Timing (LOW)
PageManager is currently initialized eagerly in `_startApp()` before `runApp()`. With static config, it needs the HTTP-fetched config which is async. This may need restructuring to load inside the widget tree (via a provider or FutureBuilder).

**Mitigation:** Create a `pageManagerProvider` that handles both static and preferences-based loading, move initialization into the provider chain.

---

## File Reference

### Files to Create (Story 6)
- `centroid-hmi/web/index.html` + web boilerplate
- `centroid-hmi/web/config/config.json`, `keymappings.json`, `page-editor.json`
- `lib/pages/dbus_login_stub.dart`
- `lib/pages/ip_settings_stub.dart`
- `lib/pages/about_linux_stub.dart`
- `lib/pages/config_edit_stub.dart`
- `lib/pages/config_list_stub.dart`
- `lib/pages/ipc_connections_stub.dart`
- `lib/core/io_stub.dart`

### Files to Create (Story 7)
- `lib/core/config_loader.dart` (conditional import hub)
- `lib/core/config_loader_native.dart`
- `lib/core/config_loader_web.dart`

### Files to Modify (Story 6)
- `centroid-hmi/lib/main.dart` — conditional imports, `kIsWeb` guards, web init path
- `lib/pages/server_config.dart` — conditional `dart:io` import, `kIsWeb` guards
- `lib/pages/key_repository.dart` — conditional `dart:io` import, `kIsWeb` guards
- `lib/providers/state_man.dart` — skip native clients on web
- `lib/providers/database.dart` — return null on web
- `pubspec.yaml` — add `http: ^1.0.0`

### Files to Modify (Story 7)
- `lib/providers/state_man.dart` — check `staticConfigProvider` first
- `centroid-hmi/lib/main.dart` — web init path, menu hiding, PageManager from static config

### Key Existing Files
- `packages/tfc_dart/lib/core/config_source.dart` — `StaticConfig` class (platform-agnostic)
- `packages/tfc_dart/lib/core/config_source_native.dart` — `staticConfigFromDirectory()` (uses dart:io)
- `packages/tfc_dart/lib/core/mqtt_client_factory.dart` — conditional import pattern reference
- `packages/tfc_dart/lib/core/mqtt_device_client.dart` — `MqttDeviceClientAdapter` (285 lines)
- `packages/tfc_dart/lib/core/state_man.dart` — `StateMan`, models, config classes
- `lib/providers/state_man.dart` — `stateManProvider` (89 lines)
- `lib/providers/database.dart` — `databaseProvider` (60 lines)
- `lib/page_creator/page.dart` — `PageManager`
- `lib/route_registry.dart` — `RouteRegistry` singleton
- `lib/models/menu_item.dart` — `MenuItem` data class
- `centroid-hmi/lib/main.dart` — app entry point (483 lines)

### Validation Commands
```bash
# Story 6 validation:
cd packages/tfc_dart && dart analyze --fatal-infos
cd packages/tfc_dart && dart test --exclude-tags=integration
flutter analyze --fatal-infos
flutter build web

# Story 7 validation (same as above):
cd packages/tfc_dart && dart analyze --fatal-infos
cd packages/tfc_dart && dart test --exclude-tags=integration
flutter analyze --fatal-infos
flutter build web
```
