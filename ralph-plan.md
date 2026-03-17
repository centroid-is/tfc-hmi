# Ralph Loop Plan: MQTT Support + Web Platform

## Context

TFC-HMI is a Flutter HMI app with OPC UA / M2400 / Modbus connectivity via `StateMan`.
This plan adds MQTT as a first-class protocol (all platforms) and enables a Flutter web build
with static config files that bypass the preferences/secure-storage system entirely.

---

## Architecture Decisions

- **MQTT client**: Use `mqtt_client` Dart package (supports TCP + WebSocket)
- **Topic structure**: Custom hierarchical (e.g., `plant/line1/motor1/speed`), PLC publishes directly
- **MQTT works on ALL platforms**: desktop uses TCP, web uses WebSocket via `MqttBrowserClient`
- **Static config mode**: Bypass preferences entirely — load config from JSON files directly
  (same pattern the headless backend uses with `StateManConfig.fromFile()`).
  Config editing pages are hidden when in static mode.
  Works on native too (env var `CENTROID_CONFIG_DIR` for kiosk deployments).
- **Testing**: Mosquitto broker in docker-compose for E2E tests
- **TDD**: Every story follows Red→Green→Refactor. Write failing tests first, then implement until tests pass, then refactor.

---

## Codebase Architecture (READ THIS FIRST)

### Storage Layer — Two Different Paths Exist Today
The codebase has TWO config loading strategies. Understanding this is critical:

**Path 1: Headless backend** (`packages/tfc_dart/bin/main.dart`)
```dart
// Backend loads config from FILES + ENV VARS, no SharedPreferences at all:
final dbConfig = await DatabaseConfig.fromEnv();          // env vars
final smConfig = await StateManConfig.fromFile(filePath); // JSON file on disk
final keyMappings = await KeyMappings.fromPrefs(prefs);   // from Postgres-backed prefs
```

**Path 2: Flutter UI** (`centroid-hmi/lib/main.dart` + providers)
```dart
// UI loads config from Preferences (SecureStorage + InMemory + Postgres):
final prefs = await Preferences.create(db: db, localCache: localCache);
final config = await StateManConfig.fromPrefs(prefs);     // secret: true → SecureStorage
final keyMappings = await fetchKeyMappings(prefs);         // PreferencesApi → InMemory
// PageManager also loads from prefs key 'page_editor_data'
```

**CRITICAL: `state_man_config` uses `secret: true`**
- `StateManConfig.fromPrefs(prefs)` calls `prefs.getString(configKey, secret: true)`
- The `secret: true` flag routes reads to `SecureStorage` (OS keychain), NOT InMemory cache
- `PreferencesApi` interface does NOT have a `secret` parameter — only `Preferences` concrete class does
- This means wrapping `PreferencesApi` CANNOT intercept `state_man_config` reads
- **Solution**: Bypass preferences entirely for static config, following the backend's `fromFile()` pattern

### Preferences Architecture
- `PreferencesApi` (abstract) in `packages/tfc_dart/lib/core/preferences.dart`
- `Preferences` (concrete) — InMemory → SecureStorage → PostgreSQL + optional localCache
- `SharedPreferencesWrapper` in `lib/core/preferences.dart` — wraps `SharedPreferencesAsync`
- `Preferences.getString(key, {secret: false})`: if secret → SecureStorage; else → InMemory
- `Preferences.setString(key, value, {saveToDb: true, secret: false})`: routes accordingly

### Config Keys and Where They Actually Live
| Key | Content | Secret? | Read From | Written To |
|-----|---------|---------|-----------|------------|
| `state_man_config` | Server connections | Yes | **SecureStorage** (OS keychain) | SecureStorage only (saveToDb: false) |
| `key_mappings` | Key→node mappings | No | **InMemory** cache | InMemory + Postgres + localCache |
| `page_editor_data` | Page layouts | No | **InMemory** cache | InMemory + Postgres + localCache |
| `database_config` | DB credentials | Yes | **SecureStorage directly** (bypasses Preferences) | SecureStorage directly |

### Provider Chain (Riverpod)
```
databaseProvider (keepAlive) → DatabaseConfig.fromPrefs() → Database.connectWithRetry()
preferencesProvider (keepAlive) → databaseProvider → Preferences.create(db, localCache)
stateManProvider (keepAlive) → preferencesProvider → StateManConfig.fromPrefs() + fetchKeyMappings() + DeviceClients
pageManagerProvider (keepAlive) → preferencesProvider → PageManager.load()
```

### Existing fromFile / fromEnv Methods (REUSE THESE)
```dart
// Already exists in state_man.dart:342
static Future<StateManConfig> fromFile(String path) async {
  final file = File(path);
  if (!await file.exists()) throw Exception('Config file not found: $path');
  final contents = await file.readAsString();
  return StateManConfig.fromJson(jsonDecode(contents));
}

// Already exists in database.dart:107
static Future<DatabaseConfig> fromEnv() async {
  final host = Platform.environment['CENTROID_PGHOST']!;
  // ... reads CENTROID_PG* env vars
}
```

### Router Architecture (`centroid-hmi/lib/main.dart`)
- Routes built synchronously in `main()` BEFORE `runApp()`
- `RouteRegistry` singleton holds menu items
- Conditional visibility already exists: `Platform.isLinux` for IP/About pages, `TFC_GOD` env for editor pages
- Dynamic pages from `PageManager.getRootMenuItems()` rendered via `AssetView`
- Beamer (`RoutesLocationBuilder`) maps paths to pages

### DeviceClient Interface (in `state_man.dart:713`)
```dart
abstract class DeviceClient {
  Set<String> get subscribableKeys;
  bool canSubscribe(String key);
  Stream<DynamicValue> subscribe(String key);
  DynamicValue? read(String key);
  ConnectionStatus get connectionStatus;
  Stream<ConnectionStatus> get connectionStream;
  void connect();
  Future<void> write(String key, DynamicValue value);
  void dispose();
}
```

### Existing Adapters (follow these patterns exactly)
- `M2400DeviceClientAdapter` in `state_man.dart:750` — wraps M2400ClientWrapper
- `ModbusDeviceClientAdapter` in `modbus_device_client.dart:13` — wraps ModbusClientWrapper
- Both take a config + optional serverAlias, implement `canSubscribe` by checking key prefixes

### KeyMappingEntry (in `state_man.dart:409`)
```dart
class KeyMappingEntry {
  OpcUANodeConfig? opcuaNode;   // @JsonKey(name: 'opcua_node')
  M2400NodeConfig? m2400Node;   // @JsonKey(name: 'm2400_node')
  ModbusNodeConfig? modbusNode; // @JsonKey(name: 'modbus_node')
  bool? io;
  CollectEntry? collect;
  int? bitMask;                 // @JsonKey(name: 'bit_mask')
  int? bitShift;                // @JsonKey(name: 'bit_shift')

  String? get server =>
      opcuaNode?.serverAlias ?? m2400Node?.serverAlias ?? modbusNode?.serverAlias;
}
```

### Web Compilation Blockers (files with dart:io / native-only imports)
| File | Blocker | Needed on web? |
|------|---------|----------------|
| `lib/pages/dbus_login.dart` | `package:dbus`, `dartssh2`, `dart:io` | No |
| `lib/pages/ip_settings.dart` | `package:nm` | No |
| `lib/pages/about_linux.dart` | `dbus` + `nm` | No |
| `lib/pages/config_edit.dart` | `dbus` | No |
| `lib/pages/config_list.dart` | `dbus` | No |
| `lib/pages/ipc_connections.dart` | `dbus` | No |
| `lib/pages/key_repository.dart` | `dart:io` (File for export/import) | Partially (editing yes, file I/O no) |
| `lib/pages/server_config.dart` | `dart:io` (File for cert/export) | Partially (editing yes, file I/O no) |
| `lib/pages/page_editor.dart` | `dart:io show Platform` (already guarded with kIsWeb) | Yes |

### Config Classes to Follow (in `state_man.dart`)
- `OpcUAConfig` (line 110) — `@JsonSerializable`, endpoint/username/password/ssl/serverAlias
- `M2400Config` (line 136) — host/port/serverAlias
- `ModbusConfig` (line 257) — host/port/unitId/serverAlias/pollGroups/umasEnabled
- `ModbusNodeConfig` — registerType/address/dataType/pollGroup/serverAlias
- `M2400NodeConfig` (line 155) — recordType/field/serverAlias/statusFilter

---

## User Stories

### Story 1: MqttConfig and MqttNodeConfig models
**Priority:** 1
**Files to modify:** `packages/tfc_dart/lib/core/state_man.dart`
**Files to create:** `packages/tfc_dart/test/core/mqtt_config_test.dart`

**TDD Approach:** Write tests first with expected JSON structures and assertions. Classes won't exist yet, so tests won't compile. Then implement the models until all tests pass.

**Acceptance Criteria:**
- [ ] **RED: Write tests first** (`packages/tfc_dart/test/core/mqtt_config_test.dart`):
  - MqttConfig JSON round-trip with all fields populated
  - MqttConfig JSON round-trip with only defaults (empty JSON object with just host)
  - MqttNodeConfig JSON round-trip
  - MqttPayloadType enum serializes as string
  - KeyMappingEntry with mqttNode serializes correctly alongside opcuaNode
  - KeyMappingEntry.server returns mqttNode.serverAlias when others are null
  - KeyMappingEntry.copyWith preserves mqttNode
  - StateManConfig with mqtt list serializes correctly
  - StateManConfig with empty mqtt list defaults correctly
  - StateManConfig.fromFile works with mqtt config (create temp JSON file in test)
- [ ] Verify tests fail to compile (classes don't exist yet) — **RED confirmed**
- [ ] **GREEN: Implement models** — Create `MqttConfig` class in `state_man.dart` (near ModbusConfig, line ~290) with `@JsonSerializable(explicitToJson: true)`:
  - `String host` (default `''`)
  - `int port` (default `1883`)
  - `@JsonKey(name: 'server_alias') String? serverAlias`
  - `@JsonKey(name: 'use_tls') bool useTls` (default `false`)
  - `@JsonKey(name: 'use_web_socket') bool useWebSocket` (default `false`)
  - `@JsonKey(name: 'ws_path') String wsPath` (default `'/mqtt'`)
  - `String? username`
  - `String? password`
  - `@JsonKey(name: 'client_id') String? clientId`
  - `@JsonKey(name: 'keep_alive_period') int keepAlivePeriod` (default `60`)
  - Factory `fromJson` + `toJson` + `toString`
- [ ] Create `MqttPayloadType` enum: `json`, `raw`, `string` (default `json`)
- [ ] Create `MqttNodeConfig` class with `@JsonSerializable(explicitToJson: true)`:
  - `String topic`
  - `@JsonKey(defaultValue: 0) int qos`
  - `@JsonKey(name: 'server_alias') String? serverAlias`
  - `@JsonKey(defaultValue: MqttPayloadType.json) MqttPayloadType payloadType`
  - Factory `fromJson` + `toJson` + `toString`
- [ ] Add to `KeyMappingEntry`: `@JsonKey(name: 'mqtt_node') MqttNodeConfig? mqttNode`
- [ ] Update `KeyMappingEntry.server` getter: add `?? mqttNode?.serverAlias`
- [ ] Update `KeyMappingEntry.copyWith`: add `mqttNode` parameter
- [ ] Update `KeyMappingEntry.toString`: include mqttNode
- [ ] Add to `StateManConfig`: `@JsonKey(defaultValue: []) List<MqttConfig> mqtt`
- [ ] Update `StateManConfig` constructor to accept `mqtt` parameter (default `const []`)
- [ ] Run `cd packages/tfc_dart && dart run build_runner build --delete-conflicting-outputs`
- [ ] Verify generated `state_man.g.dart` includes mqtt serialization
- [ ] `cd packages/tfc_dart && dart test` — ALL tests pass (existing + new) — **GREEN confirmed**
- [ ] **REFACTOR:** Review model code for clarity, consistent naming, no duplication
- [ ] `cd packages/tfc_dart && dart analyze --fatal-infos` — no issues

---

### Story 2: MqttDeviceClientAdapter implementation
**Priority:** 2
**Depends on:** Story 1
**Files to create:**
- `packages/tfc_dart/lib/core/mqtt_device_client.dart`
- `packages/tfc_dart/lib/core/mqtt_client_factory.dart` (conditional import hub)
- `packages/tfc_dart/lib/core/mqtt_client_factory_native.dart`
- `packages/tfc_dart/lib/core/mqtt_client_factory_web.dart`
- `packages/tfc_dart/test/core/mqtt_device_client_test.dart`
**Files to modify:** `packages/tfc_dart/pubspec.yaml`

**TDD Approach:** Write tests with mock/fake MQTT client first. Define the adapter's expected behavior through tests before writing implementation.

**Acceptance Criteria:**
- [ ] Add `mqtt_client: ^10.0.0` to `packages/tfc_dart/pubspec.yaml` dependencies
- [ ] **RED: Write tests first** (`packages/tfc_dart/test/core/mqtt_device_client_test.dart`):
  - Create a `FakeMqttClient` that simulates MQTT message delivery without a real broker
  - `subscribableKeys` correctly filters by serverAlias
  - `subscribableKeys` returns empty set when no mqtt_nodes match
  - `canSubscribe` returns true for exact key match
  - `canSubscribe` returns true for dot-notation child key
  - `canSubscribe` returns false for unknown key
  - JSON payload parsing produces correct DynamicValue (int, string, bool, nested object)
  - String payload parsing produces DynamicValue string
  - `read()` returns null before any subscribe
  - `read()` returns last value after subscribe receives data
  - `write()` serializes DynamicValue to JSON bytes
  - Connection status starts as disconnected
- [ ] Verify tests fail (adapter class doesn't exist yet) — **RED confirmed**
- [ ] **GREEN: Implement** — Create `mqtt_client_factory.dart` with conditional imports:
  ```dart
  // Conditional import pattern:
  import 'mqtt_client_factory_native.dart'
      if (dart.library.js_interop) 'mqtt_client_factory_web.dart';
  ```
  - Exports a function `MqttClient createMqttClient(MqttConfig config)` that returns:
    - Native: `MqttServerClient(host, clientId)` with TCP port
    - Web: `MqttBrowserClient('ws://$host:$port$wsPath', clientId)`
  - If `config.useWebSocket` is true on native, use `MqttServerClient.withPort` with `useWebSocket = true`
- [ ] Create `MqttDeviceClientAdapter` in `mqtt_device_client.dart`:
  - Constructor: `MqttDeviceClientAdapter(this.config, this.keyMappings)`
  - Private fields: `MqttClient? _client`, `final _connectionController = BehaviorSubject<ConnectionStatus>`, `final Map<String, BehaviorSubject<DynamicValue>> _topicStreams = {}`, `final Map<String, DynamicValue> _lastValues = {}`
  - `subscribableKeys`: iterate `keyMappings.nodes`, collect keys where `mqttNode != null` and (`mqttNode.serverAlias == config.serverAlias` or both are null)
  - `canSubscribe(key)`: checks key exists in subscribableKeys OR key starts with a subscribable key prefix (dot notation)
  - `subscribe(key)`:
    1. Look up `mqttNode` from keyMappings for this key
    2. If not already subscribed to that MQTT topic, subscribe via `_client.subscribe(topic, qos)`
    3. Listen to `_client.updates` for messages on that topic
    4. Parse payload based on `payloadType`: JSON → `DynamicValue.fromJson()`, string → `DynamicValue(utf8string)`, raw → `DynamicValue(bytes)`
    5. Cache in `_lastValues[key]` and emit on `_topicStreams[key]`
    6. Return `_topicStreams[key]!.stream`
  - `read(key)`: return `_lastValues[key]`
  - `write(key, value)`:
    1. Look up topic from keyMappings
    2. Serialize DynamicValue to JSON string
    3. `_client.publishMessage(topic, MqttQos.values[qos], payload)`
  - `connect()`:
    1. Create client via `createMqttClient(config)`
    2. Set keepAlive, autoReconnect, onConnected/onDisconnected callbacks
    3. Build `MqttConnectMessage` with credentials if set
    4. Call `_client.connect()`
    5. Emit `ConnectionStatus.connected` on success
    6. On failure: emit `ConnectionStatus.disconnected`, schedule retry with backoff
  - Auto-reconnect: use mqtt_client's built-in `autoReconnect = true` + `onAutoReconnect`/`onAutoReconnected` callbacks → emit status changes
  - `dispose()`: disconnect client, close all BehaviorSubjects, close connection controller
  - `connectionStatus`: return `_connectionController.valueOrNull ?? ConnectionStatus.disconnected`
  - `connectionStream`: return `_connectionController.stream`
- [ ] `cd packages/tfc_dart && dart test` — ALL tests pass — **GREEN confirmed**
- [ ] **REFACTOR:** Review adapter for clean separation of concerns, proper stream lifecycle
- [ ] `cd packages/tfc_dart && dart analyze --fatal-infos` — no issues

---

### Story 3: StateMan MQTT integration + provider wiring
**Priority:** 3
**Depends on:** Story 2
**Files to modify:**
- `packages/tfc_dart/lib/core/state_man.dart` (minimal — just export)
- `lib/providers/state_man.dart`
**Files to create:** `packages/tfc_dart/test/core/mqtt_stateman_routing_test.dart`

**TDD Approach:** Write routing tests first using mock device clients. Verify the wiring works before touching provider code.

**Acceptance Criteria:**
- [ ] **RED: Write routing tests first** (`packages/tfc_dart/test/core/mqtt_stateman_routing_test.dart`):
  - Create `MockMqttDeviceClient implements DeviceClient` (similar pattern to existing `MockModbusDeviceClient` in `modbus_stateman_routing_test.dart`)
  - Test: Key with only `mqtt_node` routes to MqttDeviceClient
  - Test: Key with only `opcua_node` routes to OPC UA (no regression)
  - Test: Key with only `modbus_node` routes to ModbusDeviceClient (no regression)
  - Test: Key with both `mqtt_node` and `opcua_node` — verify which takes priority, document it
  - Test: `subscribe()` returns stream from MqttDeviceClient for mqtt-routed key
  - Test: `write()` delegates to MqttDeviceClient for mqtt-routed key
  - Test: `read()` delegates to MqttDeviceClient for mqtt-routed key
  - Test: Connection status from MqttDeviceClient appears in StateMan's device client list
- [ ] Verify tests fail (wiring doesn't exist yet) — **RED confirmed**
- [ ] **GREEN: Implement wiring** — In `lib/providers/state_man.dart`, after existing M2400/Modbus client creation:
  ```dart
  final mqttClients = config.mqtt.map((mqttConfig) =>
    MqttDeviceClientAdapter(mqttConfig, keyMappings)
  ).toList();
  ```
  Add to `deviceClients: [...m2400Clients, ...modbusClients, ...mqttClients]`
- [ ] Verify `KeyMappings.lookupServerAlias` already returns mqttNode alias (via `KeyMappingEntry.server` getter update from Story 1)
- [ ] `cd packages/tfc_dart && dart test` — ALL tests pass — **GREEN confirmed**
- [ ] **REFACTOR:** Review provider code for clean dependency injection
- [ ] `cd packages/tfc_dart && dart analyze --fatal-infos` — no issues

---

### Story 4: Mosquitto Dart test helpers + integration tests
**Priority:** 4
**Depends on:** Story 2
**Files to create:**
- `packages/tfc_dart/test/integration/mosquitto.conf`
- `packages/tfc_dart/test/integration/mosquitto_helpers.dart`
- `packages/tfc_dart/test/integration/mqtt_integration_test.dart`
**Files to modify:** `packages/tfc_dart/test/integration/docker-compose.yml`

**Design — Follow the TimescaleDB pattern:**
The existing `docker_compose.dart` helper manages TimescaleDB lifecycle from Dart using
`Process.run('docker', ['compose', 'up', '-d'])` with `setUpAll`/`tearDownAll`.
Create a similar `mosquitto_helpers.dart` with `startMosquitto()`, `stopMosquitto()`,
`waitForMosquittoReady()` that reuses the same docker-compose.yml (just adds the
mosquitto service). Tests manage their own broker lifecycle — no manual `docker compose up`.

**TDD Approach:** Write integration test expectations first (what the adapter SHOULD do against a real broker), then verify they pass with the implementation from Story 2.

**Acceptance Criteria:**
- [ ] Create `packages/tfc_dart/test/integration/mosquitto.conf`:
  ```
  listener 1883
  listener 9001
  protocol websockets
  allow_anonymous true
  ```
- [ ] Add to `packages/tfc_dart/test/integration/docker-compose.yml`:
  ```yaml
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: test-mosquitto
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
  ```
- [ ] Create `packages/tfc_dart/test/integration/mosquitto_helpers.dart` following the `docker_compose.dart` pattern:
  ```dart
  /// Starts Mosquitto via docker compose (no-op if MOSQUITTO_EXTERNAL=1).
  Future<void> startMosquitto() async { ... }

  /// Stops Mosquitto via docker compose.
  Future<void> stopMosquitto() async { ... }

  /// Polls localhost:1883 until MQTT connection succeeds (max 30 attempts, 1s delay).
  Future<void> waitForMosquittoReady() async { ... }
  ```
  - Uses same `dockerComposePath` as `docker_compose.dart`
  - Runs `docker compose up -d mosquitto` (only starts mosquitto service, not timescaledb)
  - `waitForMosquittoReady()` attempts TCP connect to `localhost:1883`, retries until success
  - Supports `MOSQUITTO_EXTERNAL=1` env var to skip Docker lifecycle (use external broker)
- [ ] **RED: Write integration tests first** (tagged `@Tags(['integration'])`) in `mqtt_integration_test.dart`:
  - `setUpAll`: `await startMosquitto(); await waitForMosquittoReady();`
  - `tearDownAll`: `await stopMosquitto();`
  - Test: TCP connect to `localhost:1883`, verify connected status
  - Test: Subscribe to `test/sensor/temperature`, publish `{"value": 42.5}`, verify DynamicValue received with correct value
  - Test: Write DynamicValue to `test/actuator/valve`, verify message arrives (use a second client to verify)
  - Test: Disconnect client, verify disconnected status, reconnect, verify reconnected
  - Test: WebSocket connect to `ws://localhost:9001/mqtt`, subscribe and receive message
  - Test: Multiple keys on different topics receive independent streams
  - Each test should have a 10-second timeout
- [ ] **GREEN:** Run `dart test --tags=integration` — Dart manages broker lifecycle automatically, all tests pass
- [ ] `cd packages/tfc_dart && dart test --exclude-tags=integration` — ALL existing tests still pass

---

### Story 5: Static config loading — fromString() methods + config source abstraction
**Priority:** 5
**Depends on:** Story 1

**Design — Bypass Preferences, Don't Wrap Them:**

The backend already loads config from files via `StateManConfig.fromFile(path)`,
completely bypassing Preferences/SecureStorage. We extend this pattern:

1. Add `fromString(jsonString)` convenience methods (file-system-free, works on web)
2. Add `KeyMappings.fromFile(path)` (following existing `StateManConfig.fromFile` pattern)
3. Create a `ConfigSource` that providers use to decide WHERE to load config from

The `state_man_config` key uses `secret: true` which goes to SecureStorage (OS keychain).
`PreferencesApi` has no `secret` parameter. So we CANNOT intercept it via a wrapper.
We MUST bypass preferences for static config. This is the correct architecture.

**Files to create:**
- `packages/tfc_dart/lib/core/config_source.dart`
- `packages/tfc_dart/test/core/config_source_test.dart`

**Files to modify:**
- `packages/tfc_dart/lib/core/state_man.dart` (add `fromString` to KeyMappings)

**TDD Approach:** Write tests for fromString/fromFile/StaticConfig methods first. They won't exist yet. Then implement each method until tests pass.

**Acceptance Criteria:**
- [ ] **RED: Write tests first** (`packages/tfc_dart/test/core/config_source_test.dart`):
  - `StateManConfig.fromString` parses valid JSON with mqtt config
  - `KeyMappings.fromString` parses valid JSON with mqtt_node entries
  - `KeyMappings.fromFile` reads JSON from temp file and parses correctly
  - `KeyMappings.fromFile` throws on missing file
  - `StaticConfig.fromStrings` creates valid StaticConfig from raw JSON
  - `StaticConfig.fromDirectory` loads all 3 files from temp directory
  - `StaticConfig.fromDirectory` works when page-editor.json is missing (optional)
  - Verify `StaticConfig.stateManConfig.mqtt` is populated correctly
  - Verify `StaticConfig.keyMappings.nodes` contains expected mqtt entries
- [ ] Verify tests fail to compile (methods/classes don't exist yet) — **RED confirmed**
- [ ] **GREEN: Implement** — Add `KeyMappings.fromString(String jsonString)` static method in `state_man.dart`:
  ```dart
  static KeyMappings fromString(String jsonString) {
    return KeyMappings.fromJson(jsonDecode(jsonString));
  }
  ```
- [ ] Add `KeyMappings.fromFile(String path)` static method (same pattern as `StateManConfig.fromFile`):
  ```dart
  static Future<KeyMappings> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('Key mappings file not found: $path');
    final contents = await file.readAsString();
    return KeyMappings.fromString(contents);
  }
  ```
- [ ] Add `StateManConfig.fromString(String jsonString)` convenience method:
  ```dart
  static StateManConfig fromString(String jsonString) {
    return StateManConfig.fromJson(jsonDecode(jsonString));
  }
  ```
- [ ] Create `config_source.dart` with `StaticConfig` class:
  ```dart
  /// Holds pre-loaded config data from static files.
  /// When non-null, providers use these instead of Preferences/SecureStorage.
  class StaticConfig {
    final StateManConfig stateManConfig;
    final KeyMappings keyMappings;
    final String? pageEditorJson; // Raw JSON string for PageManager

    const StaticConfig({
      required this.stateManConfig,
      required this.keyMappings,
      this.pageEditorJson,
    });

    /// Load from a directory containing config.json, keymappings.json, page-editor.json.
    /// Uses dart:io File — only works on native platforms.
    static Future<StaticConfig> fromDirectory(String dirPath) async {
      final configFile = File('$dirPath/config.json');
      final keyMappingsFile = File('$dirPath/keymappings.json');
      final pageEditorFile = File('$dirPath/page-editor.json');

      final config = await StateManConfig.fromFile(configFile.path);
      final keyMappings = await KeyMappings.fromFile(keyMappingsFile.path);
      final pageEditorJson = await pageEditorFile.exists()
          ? await pageEditorFile.readAsString()
          : null;

      return StaticConfig(
        stateManConfig: config,
        keyMappings: keyMappings,
        pageEditorJson: pageEditorJson,
      );
    }

    /// Load from raw JSON strings (works on all platforms including web).
    static StaticConfig fromStrings({
      required String configJson,
      required String keyMappingsJson,
      String? pageEditorJson,
    }) {
      return StaticConfig(
        stateManConfig: StateManConfig.fromString(configJson),
        keyMappings: KeyMappings.fromString(keyMappingsJson),
        pageEditorJson: pageEditorJson,
      );
    }
  }
  ```
- [ ] `cd packages/tfc_dart && dart test` — ALL tests pass — **GREEN confirmed**
- [ ] **REFACTOR:** Review for consistent error handling across fromFile/fromString methods
- [ ] `cd packages/tfc_dart && dart analyze --fatal-infos` — no issues

---

### Story 6: Web conditional imports + compilation
**Priority:** 6
**Depends on:** Story 5
**TDD Approach:** Write a compilation smoke test and web-specific unit tests first (e.g., stub classes return expected values, conditional imports resolve correctly). Then implement stubs and guards until `flutter build web` passes and tests are green.
**Files to create:**
- `web/index.html` (Flutter web defaults)
- `web/manifest.json`
- `web/config/config.json` (example MQTT config)
- `web/config/keymappings.json` (example)
- `web/config/page-editor.json` (example)
- Stub files for each native-only import (see list below)
- `lib/core/io_stub.dart` (stub for `dart:io` on web)
**Files to modify:**
- `centroid-hmi/lib/main.dart`
- Various page files (add conditional imports)
- `pubspec.yaml` (add `http` dependency for web config fetching)

**Native-only pages needing stubs (6 files):**

For each file below, create a stub that exports the same widget class but with a
"Not available on web" placeholder body. Use conditional imports at the usage site.

| Original File | Stub File | Widget Class |
|--------------|-----------|-------------|
| `lib/pages/dbus_login.dart` | `lib/pages/dbus_login_stub.dart` | `DbusLoginPage` |
| `lib/pages/ip_settings.dart` | `lib/pages/ip_settings_stub.dart` | `IpSettingsPage` |
| `lib/pages/about_linux.dart` | `lib/pages/about_linux_stub.dart` | `AboutLinuxPage` |
| `lib/pages/config_edit.dart` | `lib/pages/config_edit_stub.dart` | `ConfigEditPage` |
| `lib/pages/config_list.dart` | `lib/pages/config_list_stub.dart` | `ConfigListPage` |
| `lib/pages/ipc_connections.dart` | `lib/pages/ipc_connections_stub.dart` | `IpcConnectionsPage` |

For `key_repository.dart` and `server_config.dart`:
- Wrap `dart:io` File operations with `if (!kIsWeb)` guards
- Replace `Platform.isWindows || Platform.isLinux || Platform.isMacOS` with `!kIsWeb` check
- Import `dart:io` conditionally: `import 'dart:io' if (dart.library.js_interop) '../core/io_stub.dart'`

`lib/core/io_stub.dart` must export stubs for `Platform` and `File` classes that the page
files reference. `Platform.isLinux` etc. should return `false`. `File` should throw
`UnsupportedError`.

**Acceptance Criteria:**
- [ ] Create `web/` directory with Flutter web boilerplate (`flutter create --platforms=web .` in a temp dir, copy web/ folder)
- [ ] Create stub files for all 6 native-only page files (each exports the widget class as a simple Scaffold with "Not available on web" text)
- [ ] Create `lib/core/io_stub.dart` with Platform/File stubs for web compilation
- [ ] In `centroid-hmi/lib/main.dart` route builder, use conditional imports:
  ```dart
  import '../pages/dbus_login.dart' if (dart.library.js_interop) '../pages/dbus_login_stub.dart';
  ```
  (repeat for all 6 native-only pages)
- [ ] For `key_repository.dart`: wrap export/import file operations with `if (!kIsWeb)` guards, conditionally import `dart:io`
- [ ] For `server_config.dart`: wrap cert picker and export/import with `if (!kIsWeb)` guards, conditionally import `dart:io`
- [ ] In `centroid-hmi/lib/main.dart`, guard `Platform.isLinux` checks with `!kIsWeb &&`:
  ```dart
  if (!kIsWeb && Platform.isLinux) MenuItem(label: 'IP Settings', ...),
  ```
- [ ] Guard `Platform.environment['TFC_GOD']` with `!kIsWeb`
- [ ] In `lib/providers/state_man.dart`, skip OPC UA/M2400/Modbus client creation when `kIsWeb`:
  ```dart
  final m2400Clients = kIsWeb ? <DeviceClient>[] : createM2400DeviceClients(config.jbtm);
  final modbusClients = kIsWeb ? <DeviceClient>[] : buildModbusDeviceClients(...);
  // MQTT clients always created (work on all platforms)
  ```
- [ ] Create `web/config/config.json`:
  ```json
  {
    "opcua": [],
    "jbtm": [],
    "modbus": [],
    "mqtt": [
      {
        "host": "localhost",
        "port": 9001,
        "use_web_socket": true,
        "ws_path": "/mqtt",
        "client_id": "tfc-web",
        "keep_alive_period": 60
      }
    ]
  }
  ```
- [ ] Create `web/config/keymappings.json` with 2-3 example MQTT key mappings:
  ```json
  {
    "nodes": {
      "sensor.temperature": {
        "mqtt_node": { "topic": "plant/sensor/temperature", "qos": 0, "payloadType": "json" }
      },
      "actuator.valve": {
        "mqtt_node": { "topic": "plant/actuator/valve", "qos": 1, "payloadType": "json" }
      }
    }
  }
  ```
- [ ] Create `web/config/page-editor.json` with a simple home page layout
- [ ] Add `http: ^1.0.0` to `pubspec.yaml` dependencies (for fetching config on web)
- [ ] `flutter build web` compiles without errors
- [ ] `flutter analyze --fatal-infos` passes
- [ ] `cd packages/tfc_dart && dart test` — ALL existing tests still pass (native)
- [ ] `cd packages/tfc_dart && dart analyze --fatal-infos` — no issues

---

### Story 7: Provider integration — static config + page hiding
**Priority:** 7
**Depends on:** Story 5, Story 6
**TDD Approach:** Write provider unit tests first: staticConfigProvider returns expected config from test JSON, stateManProvider bypasses preferences when StaticConfig is present, pageManagerProvider loads from static JSON. Then implement provider changes until tests pass.
**Files to create:**
- `lib/core/config_loader.dart` (conditional import hub)
- `lib/core/config_loader_native.dart`
- `lib/core/config_loader_web.dart`
**Files to modify:**
- `lib/providers/state_man.dart`
- `lib/providers/page_manager.dart`
- `centroid-hmi/lib/main.dart`

**Design — Provider-Level Config Source Selection:**

Instead of wrapping Preferences with a read-only layer (which can't intercept SecureStorage),
the providers detect static config mode and bypass Preferences entirely:

**No database on web.** The web app doesn't need Postgres. `databaseProvider` returns `null`
on web. `Preferences.create(db: null)` already handles this — it just skips Postgres sync.
SecureStorage is also unavailable on web, but we don't need it since config comes from
static files.

**Use `kIsWeb` in `centroid-hmi/lib/main.dart`** to take a separate initialization path
for web: skip database, skip SecureStorage init, load static config, build simplified menu.

```
On web (kIsWeb == true):
  1. Skip SecureStorage.setInstance() and database init
  2. config_loader_web.dart fetches config/*.json via HTTP
  3. Creates StaticConfig from JSON strings
  4. stateManProvider uses StaticConfig directly (no fromPrefs, no SecureStorage)
  5. pageManagerProvider uses StaticConfig.pageEditorJson directly
  6. Config editing pages hidden in menu
  7. Only MQTT device clients created (no OPC UA, M2400, Modbus)

On native with CENTROID_CONFIG_DIR env var:
  1. config_loader_native.dart loads from directory
  2. Same StaticConfig bypass, database still initialized normally
  3. Config editing pages hidden

On native without env var:
  1. config_loader_native.dart returns null
  2. Existing behavior unchanged (fromPrefs, SecureStorage, database, etc.)
```

**Acceptance Criteria:**
- [ ] Create `config_loader.dart` with conditional import:
  ```dart
  export 'config_loader_native.dart'
      if (dart.library.js_interop) 'config_loader_web.dart';
  ```
  - Exports: `Future<StaticConfig?> loadStaticConfig()`
- [ ] `config_loader_native.dart`:
  ```dart
  Future<StaticConfig?> loadStaticConfig() async {
    final configDir = Platform.environment['CENTROID_CONFIG_DIR'];
    if (configDir == null) return null;
    return StaticConfig.fromDirectory(configDir);
  }
  ```
- [ ] `config_loader_web.dart`:
  ```dart
  Future<StaticConfig?> loadStaticConfig() async {
    // Fetch all 3 config files via HTTP relative to web root
    final configResp = await http.get(Uri.parse('config/config.json'));
    final keyMappingsResp = await http.get(Uri.parse('config/keymappings.json'));
    final pageEditorResp = await http.get(Uri.parse('config/page-editor.json'));

    if (configResp.statusCode != 200 || keyMappingsResp.statusCode != 200) {
      return null; // Config files not found, can't run
    }

    return StaticConfig.fromStrings(
      configJson: configResp.body,
      keyMappingsJson: keyMappingsResp.body,
      pageEditorJson: pageEditorResp.statusCode == 200 ? pageEditorResp.body : null,
    );
  }
  ```
- [ ] Create `staticConfigProvider` (keepAlive) in providers:
  ```dart
  @Riverpod(keepAlive: true)
  Future<StaticConfig?> staticConfig(Ref ref) async {
    return loadStaticConfig();
  }
  ```
- [ ] Modify `stateManProvider` to check for static config FIRST:
  ```dart
  final staticConfig = await ref.watch(staticConfigProvider.future);
  if (staticConfig != null) {
    // Bypass preferences entirely
    final stateMan = await StateMan.create(
      config: staticConfig.stateManConfig,
      keyMappings: staticConfig.keyMappings,
      deviceClients: [...mqttClients], // Only MQTT on web
    );
    return stateMan;
  }
  // Else: existing behavior (fromPrefs)
  ```
- [ ] Modify `pageManagerProvider` to check for static config:
  ```dart
  final staticConfig = await ref.watch(staticConfigProvider.future);
  if (staticConfig?.pageEditorJson != null) {
    final pageManager = PageManager(pages: {}, prefs: prefs);
    pageManager.fromJson(staticConfig!.pageEditorJson!);
    return pageManager;  // Don't call save() — pages are read-only
  }
  // Else: existing behavior (prefs.getString('page_editor_data'))
  ```
- [ ] In `centroid-hmi/lib/main.dart`, use `kIsWeb` for web-specific initialization:
  ```dart
  if (!kIsWeb) {
    // Native-only init: SecureStorage, TFC_GOD env var, Platform checks
    SecureStorage.setInstance(...);
    environmentVariableIsGod = Platform.environment['TFC_GOD'] == 'true';
  }
  ```
- [ ] Hide config editing pages when in static mode:
  ```dart
  final isStaticMode = kIsWeb || (!kIsWeb && Platform.environment['CENTROID_CONFIG_DIR'] != null);
  // In menu building:
  if (!isStaticMode) MenuItem(label: 'Server Config', ...),
  if (!isStaticMode) MenuItem(label: 'Key Repository', ...),
  if (!isStaticMode && environmentVariableIsGod) MenuItem(label: 'Page Editor', ...),
  ```
  - Keep visible: History View, Alarm View (read-only data pages)
- [ ] On web, `databaseProvider` should return `null` (no Postgres needed):
  - Guard `DatabaseConfig.fromPrefs()` with `if (kIsWeb) return null;`
  - `Preferences.create(db: null, localCache: localCache)` already works — skips Postgres sync
- [ ] `flutter build web` passes
- [ ] `flutter analyze --fatal-infos` passes
- [ ] `cd packages/tfc_dart && dart test` — ALL existing tests still pass

---

### Story 8: ImageFeedConfig asset
**Priority:** 8
**Depends on:** Story 3
**Files to create:**
- `lib/page_creator/assets/image_feed.dart`
- `test/widgets/image_feed_test.dart`
**Files to modify:**
- `lib/page_creator/assets/registry.dart`

**Design:**
The ImageFeed asset displays a grid of the most recent images received via MQTT.
Each image arrives as a JSON payload on the subscribed key with structure:
```json
{"image": "<base64_png_or_url>", "label": "cat", "confidence": 0.95, "latency_ms": 42}
```

The asset maintains a rolling buffer of the last N images. A `controlKey` property
allows another asset (like a ButtonConfig) to pause/resume the feed by writing
`true`/`false` to that key.

**Asset pattern to follow** (from existing codebase):
- Extend `BaseAsset` with `@JsonSerializable(explicitToJson: true)`
- Add `.preview()` constructor for editor preview
- Register in `registry.dart` `_fromJsonFactories` and `defaultFactories`
- Widget: `ConsumerStatefulWidget` that subscribes to StateMan

**Acceptance Criteria:**
- [ ] Create `ImageFeedConfig` extending `BaseAsset`:
  - `String key` — StateMan key that receives image inference results
  - `@JsonKey(name: 'control_key') String? controlKey` — optional key to pause/resume (listens for bool)
  - `@JsonKey(name: 'max_images') int maxImages` (default `9`)
  - `@JsonKey(name: 'grid_columns') int gridColumns` (default `3`)
  - `@JsonKey(name: 'show_confidence') bool showConfidence` (default `true`)
  - `@JsonKey(name: 'show_label') bool showLabel` (default `true`)
  - `@JsonKey(name: 'show_new_badge') bool showNewBadge` (default `true`)
  - `String get displayName => 'Image Feed'`
  - `String get category => 'Monitoring'`
  - `.preview()` constructor with sensible defaults
  - `fromJson` / `toJson` via json_serializable
  - `build()` returns `ImageFeedWidget(config: this)`
  - `configure()` returns config UI for editing properties in page editor
- [ ] Create `ImageFeedWidget` (`ConsumerStatefulWidget`):
  - Subscribes to `stateMan.subscribe(config.key)` for incoming image data
  - If `config.controlKey` is set, also subscribes to that key. When value is `false` (or `0`), stop adding new images (pause). When `true` (or `1`), resume.
  - Maintains `List<ImageEntry>` buffer (max `config.maxImages` items)
  - Each `ImageEntry` holds: decoded image bytes (or URL), label, confidence, timestamp
  - Renders as `GridView` with `config.gridColumns` columns
  - Each grid cell shows: image, optional label overlay at bottom, optional confidence %, optional "new" badge that fades after 1.2s
  - Confidence color coding: >= 80% green, >= 50% yellow, < 50% red
  - When paused, show a subtle "PAUSED" overlay
  - Handle missing/malformed payloads gracefully (skip, log warning)
- [ ] **RED: Write tests first** (`test/widgets/image_feed_test.dart`):
  - Test: ImageFeedConfig JSON round-trip serialization (model test — write first)
  - Test: ImageFeedWidget renders empty grid initially
  - Test: Adding image data via mock StateMan stream shows image in grid
  - Test: Grid respects maxImages limit (oldest removed when exceeded)
  - Test: Confidence color coding is correct (green/yellow/red)
  - Test: Pause via controlKey stops adding new images
  - Test: Resume via controlKey allows new images again
  - Test: Malformed payload doesn't crash widget
- [ ] Verify tests fail (classes don't exist yet) — **RED confirmed**
- [ ] **GREEN: Implement** ImageFeedConfig + ImageFeedWidget (as described above)
- [ ] Register in `registry.dart`:
  - Import `image_feed.dart`
  - Add `ImageFeedConfig` to `_fromJsonFactories`
  - Add `ImageFeedConfig.preview()` to `defaultFactories`
- [ ] Run `dart run build_runner build --delete-conflicting-outputs` (both packages)
- [ ] `flutter test` — ALL tests pass — **GREEN confirmed**
- [ ] **REFACTOR:** Review widget for performance (avoid unnecessary rebuilds), clean stream lifecycle
- [ ] `flutter analyze --fatal-infos` — no issues

---

### Story 9: InferenceLogConfig asset
**Priority:** 9
**Depends on:** Story 3
**Files to create:**
- `lib/page_creator/assets/inference_log.dart`
- `test/widgets/inference_log_test.dart`
**Files to modify:**
- `lib/page_creator/assets/registry.dart`

**Design:**
The InferenceLog asset shows a scrolling feed of recent inference results — like the
right panel of `image_inference_live_dashboard.html`. Each row shows a thumbnail,
class label, latency, confidence bar, and status badge (ok/warn/error).

Same MQTT payload format as ImageFeed. Same `controlKey` pause/resume mechanism.

**Acceptance Criteria:**
- [ ] Create `InferenceLogConfig` extending `BaseAsset`:
  - `String key` — StateMan key for inference results
  - `@JsonKey(name: 'control_key') String? controlKey` — pause/resume
  - `@JsonKey(name: 'max_entries') int maxEntries` (default `30`)
  - `@JsonKey(name: 'show_thumbnail') bool showThumbnail` (default `true`)
  - `@JsonKey(name: 'show_confidence_bar') bool showConfidenceBar` (default `true`)
  - `@JsonKey(name: 'show_latency') bool showLatency` (default `true`)
  - `String get displayName => 'Inference Log'`
  - `String get category => 'Monitoring'`
  - `.preview()` constructor
  - `fromJson` / `toJson`
  - `build()` returns `InferenceLogWidget(config: this)`
  - `configure()` returns config UI
- [ ] Create `InferenceLogWidget` (`ConsumerStatefulWidget`):
  - Subscribes to `stateMan.subscribe(config.key)`
  - If `controlKey` set, subscribes for pause/resume
  - Maintains `List<LogEntry>` buffer (max `config.maxEntries`)
  - New entries inserted at TOP (most recent first) with slide-in animation
  - Each row renders:
    - Optional 32x32 thumbnail (from image data)
    - Class label (bold) + latency/id subtext
    - Confidence bar (horizontal, colored: green >= 80%, yellow >= 50%, red < 50%)
    - Status badge: "ok" (green) for confidence >= 75%, "low" (yellow) for >= 50%, "error" (red) for < 50%
  - Scrollable via `ListView` with max height
  - When paused, show subtle indicator, stop adding entries
- [ ] **RED: Write tests first** (`test/widgets/inference_log_test.dart`):
  - Test: InferenceLogConfig JSON round-trip (model test — write first)
  - Test: Empty log renders placeholder
  - Test: Adding entries via stream shows rows
  - Test: Max entries respected (oldest removed)
  - Test: New entries appear at top
  - Test: Confidence bar color coding correct
  - Test: Status badge text/color correct for ok/low/error
  - Test: Pause via controlKey stops new entries
  - Test: Resume via controlKey allows entries
- [ ] Verify tests fail (classes don't exist yet) — **RED confirmed**
- [ ] **GREEN: Implement** InferenceLogConfig + InferenceLogWidget (as described above)
- [ ] Register in `registry.dart`:
  - Import `inference_log.dart`
  - Add `InferenceLogConfig` to `_fromJsonFactories`
  - Add `InferenceLogConfig.preview()` to `defaultFactories`
- [ ] Run `dart run build_runner build --delete-conflicting-outputs`
- [ ] `flutter test` — ALL tests pass — **GREEN confirmed**
- [ ] **REFACTOR:** Review widget for performance, clean animation lifecycle
- [ ] `flutter analyze --fatal-infos` — no issues

---

### Story 10: Inference dashboard page-editor.json + keymappings
**Priority:** 10
**Depends on:** Story 8, Story 9
**Files to modify:**
- `web/config/page-editor.json`
- `web/config/keymappings.json`

**Design:**
Create a page-editor.json that recreates the layout from `image_inference_live_dashboard.html`
using the existing asset types + new ImageFeed and InferenceLog assets:

Layout (normalized coordinates):
```
┌─────────────────────────────────────────────────────┐
│  [Number: processed] [Number: avg conf] [Number: latency] [Number: errors] │  ← 4 metric cards (top row)
│                                                     │
│  ┌──────────────────────┐  ┌────────────────────┐  │
│  │                      │  │                    │  │
│  │    ImageFeedConfig    │  │  InferenceLogConfig │  │
│  │    (3x3 grid)        │  │  (scrolling feed)  │  │
│  │                      │  │                    │  │
│  └──────────────────────┘  └────────────────────┘  │
│                                                     │
│  [Button: pause/resume]                             │  ← Controls the feed
└─────────────────────────────────────────────────────┘
```

**Acceptance Criteria:**
- [ ] Update `web/config/keymappings.json` with inference-specific keys:
  ```json
  {
    "nodes": {
      "inference.result": {
        "mqtt_node": { "topic": "inference/result", "qos": 0, "payloadType": "json" }
      },
      "inference.stats.processed": {
        "mqtt_node": { "topic": "inference/stats/processed", "qos": 0, "payloadType": "json" }
      },
      "inference.stats.avg_confidence": {
        "mqtt_node": { "topic": "inference/stats/avg_confidence", "qos": 0, "payloadType": "json" }
      },
      "inference.stats.latency_ms": {
        "mqtt_node": { "topic": "inference/stats/latency_ms", "qos": 0, "payloadType": "json" }
      },
      "inference.stats.errors": {
        "mqtt_node": { "topic": "inference/stats/errors", "qos": 0, "payloadType": "json" }
      },
      "inference.control.pause": {
        "mqtt_node": { "topic": "inference/control/pause", "qos": 1, "payloadType": "json" }
      }
    }
  }
  ```
- [ ] Create `web/config/page-editor.json` with the dashboard layout:
  - Home page ("/") with menu item "Inference Monitor"
  - 4x NumberConfig assets across top: processed, avg confidence, latency, errors
  - 1x ImageFeedConfig: key=`inference.result`, controlKey=`inference.control.pause`, gridColumns=3, maxImages=9
  - 1x InferenceLogConfig: key=`inference.result`, controlKey=`inference.control.pause`, maxEntries=30
  - 1x ButtonConfig: key=`inference.control.pause`, isToggle=true, text="Pause Feed"
  - All assets positioned using normalized coordinates matching the dashboard layout
- [ ] **RED: Write validation test first** that loads page-editor.json and verifies:
  - All asset types are recognized by the registry
  - Asset count matches expected (4 NumberConfig + 1 ImageFeed + 1 InferenceLog + 1 Button = 7)
  - Keys reference valid entries in keymappings.json
  - JSON is valid and can be parsed by `PageManager.fromJson()`
- [ ] Verify test fails (config files don't have the right content yet) — **RED confirmed**
- [ ] **GREEN:** Create/update the JSON config files until test passes
- [ ] `flutter analyze --fatal-infos` — no issues

---

### Story 11: Playwright E2E tests with stubbed MQTT data
**Priority:** 11
**Depends on:** Story 7, Story 10
**TDD Approach:** This story IS the test layer — write E2E specs that validate the full stack works end-to-end. These tests serve as the final acceptance gate for all previous stories.
**Files to create:**
- `test/e2e/playwright.config.ts`
- `test/e2e/package.json`
- `test/e2e/dashboard.spec.ts`
- `test/e2e/mqtt-stub.ts` (MQTT publisher script for test data)
- `test/e2e/run-e2e.sh` (orchestrator script)

**Design:**
Use Playwright to test the Flutter web app end-to-end with Mosquitto broker and
a stub MQTT publisher that sends synthetic inference data (like the `tick()` function
in the HTML dashboard).

**Important:** The Flutter web build MUST use `--web-renderer html` (not CanvasKit).
CanvasKit renders everything to a `<canvas>` element, making DOM-based Playwright
selectors (locators, text queries, accessibility checks) impossible. The HTML renderer
outputs real DOM elements that Playwright can query and assert against.

The stub publisher (`mqtt-stub.ts`) runs as a Node.js script that:
1. Connects to Mosquitto on localhost:1883
2. Publishes synthetic inference results every 600ms to `inference/result`
3. Publishes aggregated stats to `inference/stats/*` topics
4. Supports pause/resume by subscribing to `inference/control/pause`

Playwright tests verify the web UI responds to MQTT data correctly.

**Acceptance Criteria:**
- [ ] Create `test/e2e/package.json`:
  ```json
  {
    "devDependencies": {
      "@playwright/test": "^1.40.0",
      "mqtt": "^5.0.0"
    },
    "scripts": {
      "test": "npx playwright test",
      "stub": "npx tsx mqtt-stub.ts"
    }
  }
  ```
- [ ] Create `test/e2e/playwright.config.ts`:
  - Base URL: `http://localhost:8080`
  - Browser: chromium
  - Timeout: 30s per test
  - Web server: `python3 -m http.server 8080 -d ../../build/web`
- [ ] Create `test/e2e/mqtt-stub.ts`:
  - Connects to `mqtt://localhost:1883`
  - Defines CLASSES array (cat, dog, car, person, bird, etc.)
  - Publishes to `inference/result` every 600ms:
    ```json
    {"image": "<small base64 colored square>", "label": "cat", "confidence": 0.92, "latency_ms": 45}
    ```
  - Maintains running stats, publishes to `inference/stats/processed`, `inference/stats/avg_confidence`, etc.
  - Subscribes to `inference/control/pause` — stops publishing when `true`
  - Exports `startPublishing()` and `stopPublishing()` for programmatic control from tests
- [ ] Create `test/e2e/dashboard.spec.ts` with these test cases:

  **Test 1: App loads and renders dashboard**
  - Navigate to `/`
  - Wait for Flutter app to initialize (wait for specific element or text)
  - Verify page title / menu item "Inference Monitor" is visible
  - Verify 4 metric cards are present

  **Test 2: MQTT data updates metric cards**
  - Start MQTT stub publisher
  - Wait 3 seconds for data to flow
  - Verify "processed" metric shows a number > 0
  - Verify "avg confidence" shows a percentage
  - Verify "latency" shows a number
  - Stop publisher

  **Test 3: Image feed shows images**
  - Start MQTT stub publisher
  - Wait for at least 3 images to appear in the grid
  - Verify image count in grid <= maxImages (9)
  - Verify confidence labels are visible on images
  - Stop publisher

  **Test 4: Inference log shows entries**
  - Start MQTT stub publisher
  - Wait for at least 5 log entries
  - Verify newest entry is at the top
  - Verify each entry has a class label, confidence bar, and status badge
  - Stop publisher

  **Test 5: Pause button stops the feed**
  - Start MQTT stub publisher
  - Wait for data to appear
  - Click the "Pause Feed" button
  - Record current image count
  - Wait 3 seconds
  - Verify image count has NOT increased (paused)
  - Click "Pause Feed" again (resume)
  - Wait 2 seconds
  - Verify image count HAS increased (resumed)
  - Stop publisher

  **Test 6: Config pages are hidden on web**
  - Navigate to `/advanced` (or check menu)
  - Verify "Server Config" is NOT in the menu
  - Verify "Key Repository" is NOT in the menu
  - Verify "Page Editor" is NOT in the menu

- [ ] Create `test/e2e/run-e2e.sh` orchestrator:
  ```bash
  #!/bin/bash
  set -e
  # 1. Start Mosquitto
  cd ../../packages/tfc_dart/test/integration && docker compose up -d
  # 2. Build Flutter web
  cd ../../../.. && flutter build web --web-renderer html
  # 3. Copy config
  cp -r web/config build/web/config
  # 4. Install Playwright deps
  cd test/e2e && npm install && npx playwright install chromium
  # 5. Run tests
  npm test
  # 6. Cleanup
  cd ../../packages/tfc_dart/test/integration && docker compose down
  ```
- [ ] All Playwright tests pass when run via `test/e2e/run-e2e.sh`
- [ ] All existing Flutter tests still pass

---

## Validation Commands (run after EVERY story)

```bash
# 1. Codegen (must run first — generates .g.dart files)
cd packages/tfc_dart && dart run build_runner build --delete-conflicting-outputs

# 2. Analysis — both packages
cd packages/tfc_dart && dart analyze --fatal-infos
cd /Users/jonb/Projects/tfc-hmi && flutter analyze --fatal-infos

# 3. Unit tests (excludes integration tests needing docker)
cd packages/tfc_dart && dart test --exclude-tags=integration

# 4. Web build (Story 6+)
cd /Users/jonb/Projects/tfc-hmi && flutter build web --web-renderer html

# 5. Integration tests (Story 4+ only, requires docker compose up)
# cd packages/tfc_dart && dart test --tags=integration
```

**IMPORTANT:** If any validation command fails, fix it before moving to the next story.
Do NOT skip failing tests. Do NOT comment out tests. Do NOT use `// ignore` pragmas
unless absolutely necessary for web conditional compilation.

---

## Asset System Reference (for Stories 8-10)

### How to create a new asset type:
1. Create class extending `BaseAsset` with `@JsonSerializable(explicitToJson: true)` in `lib/page_creator/assets/`
2. Add `String key` property for StateMan data binding
3. Add `.preview()` constructor for editor preview
4. Implement `build()` → returns a `ConsumerStatefulWidget` that subscribes to StateMan
5. Implement `configure()` → returns config editing UI
6. Add `fromJson` / `toJson` via json_serializable
7. Register in `lib/page_creator/assets/registry.dart`:
   - Add import
   - Add to `_fromJsonFactories` map: `ImageFeedConfig: (json) => ImageFeedConfig.fromJson(json)`
   - Add to `defaultFactories` map: `ImageFeedConfig: () => ImageFeedConfig.preview()`
8. Run `dart run build_runner build --delete-conflicting-outputs`

### Asset data binding pattern:
```dart
class MyWidget extends ConsumerStatefulWidget {
  @override ConsumerState<MyWidget> createState() => _MyWidgetState();
}
class _MyWidgetState extends ConsumerState<MyWidget> {
  StreamSubscription<DynamicValue>? _sub;
  @override void initState() {
    super.initState();
    final stateMan = ref.read(stateManProvider).value;
    _sub = stateMan?.subscribe(widget.config.key).listen((value) {
      setState(() { /* update from value */ });
    });
  }
  @override void dispose() { _sub?.cancel(); super.dispose(); }
}
```

### Asset-to-asset communication (for pause button → feed):
A single ButtonConfig (isToggle=true) on the page writes to a StateMan key (e.g.,
`inference.control.pause`). Both ImageFeedConfig and InferenceLogConfig set their
`controlKey` to that SAME key. When the user toggles the button, both feeds
pause/resume together. This is the same pattern used by other assets that reference
shared variables — the `controlKey` is a reference to another asset's `key` on the page.

### JSON payload format for inference results:
```json
{"image": "<base64_png>", "label": "cat", "confidence": 0.95, "latency_ms": 42}
```
- `image`: base64-encoded PNG (small thumbnail, ~80x80px) or data URL
- `label`: classification label string
- `confidence`: float 0.0-1.0
- `latency_ms`: inference latency in milliseconds

---

## Completion Promise

All 11 user stories have passing acceptance criteria, all validation commands pass,
`flutter build web` succeeds, Playwright E2E tests pass, and the web app displays
a live inference monitoring dashboard with image feed, inference log, metric cards,
and pause/resume control — all receiving data via MQTT over WebSocket.
