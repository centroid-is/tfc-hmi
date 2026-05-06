<!-- refreshed: 2026-05-05 -->
# Architecture

**Analysis Date:** 2026-05-05

## System Overview

```text
┌────────────────────────────────────────────────────────────────────────┐
│                     centroid-hmi  (Flutter App)                        │
│                  centroid-hmi/lib/main.dart                            │
│            ProviderScope → UpgradeAlert → MyApp (Beamer)               │
├──────────────────┬──────────────────────┬──────────────────────────────┤
│   Pages/Routes   │   Overlay Widgets    │   Page Creator / Asset View  │
│  lib/pages/      │  lib/chat/           │  lib/page_creator/           │
│  (Beamer router) │  lib/drawings/       │  assets/ + page.dart         │
└────────┬─────────┴────────┬─────────────┴──────────────┬───────────────┘
         │                  │                             │
         ▼                  ▼                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Riverpod Provider Layer                            │
│                        lib/providers/                                  │
│  preferencesProvider → stateManProvider → collectorProvider            │
│  databaseProvider   → alarmManProvider → pageManagerProvider           │
│  mcpBridgeProvider  → chatLifecycleProvider → llmProvider              │
└────────┬───────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────┐
│               tfc_dart Package  (packages/tfc_dart)                    │
│  StateMan — OPC UA / Modbus / M2400 multiplexer                        │
│  Collector — timeseries ingestion                                      │
│  AlarmMan  — alarm evaluation                                          │
│  Database  — PostgreSQL via Drift                                      │
│  Preferences — shared_prefs + encrypted secure storage                 │
└────────┬────────────────────┬────────────────────────────────────────--┘
         │                    │
         ▼                    ▼
┌────────────────┐  ┌──────────────────────────────────────────────────-┐
│  OPC UA Server │  │  tfc_mcp_server Package (packages/tfc_mcp_server)  │
│  (open62541    │  │  Subprocess spawned by McpBridgeNotifier           │
│   via isolate) │  │  Exposes MCP tools over SSE for LLM agents         │
│                │  └──────────────────────────────────────────────────-┘
│  Modbus TCP    │
│  M2400 (jbtm)  │
└────────────────┘
```

## Component Responsibilities

| Component | Responsibility | Key Files |
|-----------|----------------|-----------|
| `centroid-hmi` app | Production HMI binary; wires routes, menu, upgrade flow | `centroid-hmi/lib/main.dart` |
| `tfc` library | All UI, providers, painters, page creator — consumed by app | `lib/` root |
| `StateMan` | Protocol multiplexer: OPC UA + Modbus + M2400 subscribe/read/write | `packages/tfc_dart/lib/core/state_man.dart` |
| `AssetRegistry` | Deserialises JSON pages into typed `Asset` widgets | `lib/page_creator/assets/registry.dart` |
| `PageManager` | Load/save `AssetPage` definitions from preferences | `lib/page_creator/page.dart` |
| `RouteRegistry` | Singleton that holds all Beamer routes + nav menu tree | `lib/route_registry.dart` |
| `BaseScaffold` | Shell widget: app bar, nav dropdown, alarm badge | `lib/widgets/base_scaffold.dart` |
| `McpBridgeNotifier` | Spawns `tfc_mcp_server` subprocess, manages SSE lifecycle | `lib/mcp/mcp_bridge_notifier.dart` |
| `tfc_mcp_server` | Standalone Dart binary: MCP tool server for AI agents | `packages/tfc_mcp_server/` |
| `Collector` | Subscribes to StateMan keys, writes time-series to PostgreSQL | `packages/tfc_dart/lib/core/collector.dart` |
| `AlarmMan` | Evaluates boolean expressions against live values, fires alarms | `packages/tfc_dart/lib/core/alarm.dart` |
| `Preferences` | Dual-layer storage: SharedPreferences (local) + PostgreSQL (sync) | `packages/tfc_dart/lib/core/preferences.dart` |
| `centroidx_upgrader` | GitHub release store + ManagerLauncher for auto-update flow | `packages/centroidx_upgrader/lib/src/` |

## Pattern Overview

**Overall:** Plugin-style Asset Registry with Riverpod dependency injection and a multi-protocol device abstraction layer.

**Key Characteristics:**
- Assets are pure data configs (`BaseAsset`) that carry both their serialized state (JSON) and a `build()` method returning a `Widget`. No separate ViewModel.
- All live process data flows through `StateMan.subscribe(key)` → `Stream<DynamicValue>`. Widgets read `stateManProvider` and call `stateMan.subscribe(key)`.
- Riverpod `keepAlive: true` providers (`preferencesProvider`, `stateManProvider`, `databaseProvider`, etc.) are singletons for the app lifetime — they are never auto-disposed.
- The MCP AI layer is a separate subprocess (`tfc_mcp_server`) that communicates with the Flutter app over SSE; it is not in-process.

## Layers

**App Layer (centroid-hmi):**
- Purpose: Dart/Flutter binary entry point; platform-specific setup, route wiring, upgrade orchestration
- Location: `centroid-hmi/lib/`
- Contains: `main.dart`, `marionette_init.dart`, `pages/version_manager_page.dart`
- Depends on: `tfc` library package at `../`
- Used by: End users, CI/CD pipelines

**UI Library (tfc):**
- Purpose: All reusable UI — pages, widgets, painters, asset components, providers
- Location: `lib/`
- Contains: pages, widgets, page_creator, providers, painter, chat, llm, mcp, drawings, dbus, tech_docs
- Depends on: `tfc_dart`, `tfc_mcp_server`, `jbtm`, `open62541`, Riverpod, Beamer
- Used by: `centroid-hmi` app

**Provider Layer:**
- Purpose: Bridge between UI and infrastructure; Riverpod async providers with `keepAlive`
- Location: `lib/providers/`
- Contains: `state_man.dart`, `preferences.dart`, `database.dart`, `alarm.dart`, `collector.dart`, `page_manager.dart`, `mcp_bridge.dart`, `chat.dart`, `theme.dart`, `llm.dart`
- Depends on: `tfc_dart` core, `tfc_mcp_server`
- Used by: All widgets via `ref.watch`/`ref.read`

**Page Creator / Asset System:**
- Purpose: Dynamic HMI page composition — JSON config → typed Widget
- Location: `lib/page_creator/`
- Contains: `page.dart` (PageManager, AssetPage), `assets/` (30+ asset configs + their painters/widgets), `assets/registry.dart` (AssetRegistry)
- Depends on: StateMan via `stateManProvider`, common.dart `Asset`/`BaseAsset` contracts
- Used by: `AssetView` in `lib/pages/page_view.dart`

**Device Abstraction (tfc_dart core):**
- Purpose: Protocol-agnostic read/write/subscribe over OPC UA, Modbus TCP, M2400
- Location: `packages/tfc_dart/lib/core/`
- Key files: `state_man.dart`, `modbus_device_client.dart`, `modbus_client_wrapper.dart`, `collector.dart`, `alarm.dart`, `database.dart`, `preferences.dart`
- Depends on: `open62541` (FFI), `jbtm`, `modbus_client`, `drift`, PostgreSQL
- Used by: Provider layer

**MCP Tool Server (subprocess):**
- Purpose: Exposes plant data as MCP tools for LLM agents (Claude, OpenAI, Gemini)
- Location: `packages/tfc_mcp_server/lib/src/`
- Contains: tools/, services/, resources/, prompts/, compiler/, safety/, audit/
- Depends on: `tfc_dart_core.dart` (FFI-free subset), `mcp_dart`, PostgreSQL
- Used by: `McpBridgeNotifier` via subprocess spawn; LLM clients via SSE

## Data Flow

### Primary HMI View Render

1. App starts → `_startApp()` in `centroid-hmi/lib/main.dart` bootstraps `ProviderScope`
2. `preferencesProvider` initialises Preferences (SharedPrefs + PostgreSQL) (`lib/providers/preferences.dart`)
3. `stateManProvider` reads `StateManConfig` from Preferences, creates `StateMan` with OPC UA / Modbus / M2400 clients (`lib/providers/state_man.dart`)
4. `pageManagerProvider` loads `AssetPage` JSON from Preferences → `PageManager` (`lib/providers/page_manager.dart`)
5. Beamer routes → `AssetView(pageName)` (`lib/pages/page_view.dart`)
6. `AssetView` watches `pageManagerProvider`, renders `AssetStack` with positioned asset widgets
7. Each asset widget (e.g., `Led`) calls `stateMan.subscribe(key)` → `Stream<DynamicValue>` → StreamBuilder updates UI

### Asset Config Serialisation / Deserialisation

1. Page JSON stored in Preferences under `page_editor_data` key
2. `PageManager.load()` calls `AssetRegistry.parse(json)` (`lib/page_creator/assets/registry.dart`)
3. Registry crawls JSON, matches `asset_name` field to registered `Type → fromJson` factory
4. Each `BaseAsset.fromJson()` (generated by `json_serializable`) reconstructs config
5. `asset.build(context)` returns a live Flutter `Widget`

### AI / MCP Tool Call Flow

1. `McpBridgeNotifier` spawns `tfc_mcp_server` binary as subprocess (`lib/mcp/mcp_bridge_notifier.dart`)
2. Flutter SSE server wraps subprocess stdio → `lib/mcp/mcp_sse_server.dart`
3. LLM chat panel (`lib/chat/chat_overlay.dart`) sends messages via `LlmProvider.complete()`
4. Tool calls returned by LLM are forwarded to MCP server; responses streamed back
5. Write-capable tools invoke `ElicitationDialog` for human-in-the-loop confirmation (`lib/chat/elicitation_dialog.dart`)
6. MCP server reads plant state via `StateReader` interface; writes page/alarm/config JSON via proposal tools

### Key Substitution Flow

1. `OptionVariableConfig` asset calls `stateMan.setSubstitution(varName, value)`
2. `StateMan._substitutions` map updated; `_subsMap$` BehaviorSubject emits
3. `substitutionsChangedProvider` (StreamProvider) propagates change to widgets
4. Assets with `$varName` in their key call `stateMan.resolveKey(key)` before subscribing

**State Management:**
- Global singleton providers with `keepAlive: true` (Riverpod 2.x, code-generated with `@Riverpod`)
- No Redux/BLoC; providers are the state layer
- `AutoDisposingStream` in StateMan manages OPC UA subscriptions with 10-minute idle timeout

## Key Abstractions

**`Asset` / `BaseAsset`:**
- Purpose: Contract for all HMI asset components
- Interface: `lib/page_creator/assets/common.dart` (abstract `Asset`)
- Base impl: `BaseAsset` — handles coordinates, size, text, JSON serialization pattern
- Pattern: Every concrete type (e.g., `LEDConfig`, `ConveyorConfig`) extends `BaseAsset`, implements `build(context)` returning its widget and `configure(context)` returning its edit panel

**`DeviceClient`:**
- Purpose: Protocol-agnostic interface for subscribe/read/write to field devices
- Location: `packages/tfc_dart/lib/core/state_man.dart` (abstract class `DeviceClient`)
- Implementations: `M2400DeviceClientAdapter`, `ModbusDeviceClientAdapter`; OPC UA handled directly by `ClientWrapper`

**`AutoDisposingStream<T>`:**
- Purpose: Ref-counted OPC UA subscription that tears down the underlying monitored item when no Flutter widgets are listening
- Location: `packages/tfc_dart/lib/core/state_man.dart`
- Pattern: `ReplaySubject` (maxSize=1) with listener count tracking and 10-minute idle timer

**`AssetRegistry`:**
- Purpose: Central factory registry; maps `Type → fromJson` and `Type → preview` factories
- Location: `lib/page_creator/assets/registry.dart`
- Pattern: Two static maps; `parse(json)` crawls JSON tree matching `asset_name` to factory

## Entry Points

**Production HMI:**
- Location: `centroid-hmi/lib/main.dart`
- Triggers: Flutter runtime on Linux / Windows / macOS
- Responsibilities: SIGPIPE handling, log file setup, `ProviderScope` bootstrap, Beamer route wiring, GitHub upgrade check, Marionette test agent opt-in

**MCP Tool Server:**
- Location: `packages/tfc_mcp_server/bin/tfc_mcp_server.dart`
- Triggers: Spawned as subprocess by `McpBridgeNotifier`
- Responsibilities: Stdio MCP protocol, tool registration, audit logging, PostgreSQL connection for historical data

**tfc_dart CLI / Test Harness:**
- Location: `packages/tfc_dart/bin/main.dart`
- Triggers: `dart run` for standalone testing

**Demo App:**
- Location: `demo/lib/main.dart`
- Triggers: Minimal Flutter scaffold for widget previewing (no OPC UA)

## Architectural Constraints

- **Threading:** OPC UA client runs in a Dart isolate (`ClientIsolate`) to prevent FFI blocking the UI thread. Modbus and M2400 run in the main isolate via async polling. MCP server runs as a separate OS process.
- **Global state:** `RouteRegistry._instance` is a module-level singleton (`lib/route_registry.dart`). `globalScaffoldMessengerKey` and `NavDropdown.isAnyMenuOpen` are global `ValueNotifier`s. Provider singletons via Riverpod `ProviderScope`.
- **Circular imports:** `tfc_dart` has two barrel exports: `tfc_dart.dart` (full, with FFI) and `tfc_dart_core.dart` (FFI-free for MCP server). Mixing these causes link errors.
- **DB reconnect isolation:** `stateManProvider` uses `ref.read` (not `ref.watch`) for `preferencesProvider` to prevent OPC UA connections from being torn down on PostgreSQL reconnect events.
- **Key substitution:** OPC UA keys support `$varName` template syntax resolved at subscribe time by `StateMan.resolveKey()`. All asset keys referencing dynamic positions must use this pattern.

## Anti-Patterns

### Mixing `tfc_dart.dart` and `tfc_dart_core.dart` imports

**What happens:** Code in `tfc_mcp_server` imports from `tfc_dart.dart` instead of `tfc_dart_core.dart`.
**Why it's wrong:** `tfc_dart.dart` pulls in `open62541` (FFI) and `amplify_secure_storage_dart`, which cause link errors when compiling the MCP server as a standalone `dart compile exe` binary.
**Do this instead:** Import `package:tfc_dart/tfc_dart_core.dart` in all MCP server code. See `packages/tfc_dart/lib/tfc_dart_core.dart` for the allowed exports.

### Using `ref.watch` for infrastructure providers inside other infrastructure providers

**What happens:** A keepAlive provider watches `databaseProvider` causing it to re-run when the DB reconnects.
**Why it's wrong:** Cascades invalidation — a transient PostgreSQL outage tears down all OPC UA connections and subscriptions.
**Do this instead:** Use `ref.read(someProvider.future)` for one-time initialisation reads inside `@Riverpod(keepAlive: true)` providers. See `lib/providers/state_man.dart` line 35 and `lib/providers/alarm.dart` line 13.

### Registering assets in `centroid-hmi/lib/main.dart` instead of `AssetRegistry`

**What happens:** Commented-out `AssetRegistry.registerFromJsonFactory` calls exist in `centroid-hmi/lib/main.dart` (lines 151–165).
**Why it's wrong:** Asset types not in the registry are silently ignored when loading saved pages; customers lose page data.
**Do this instead:** Add new asset types directly to `AssetRegistry._fromJsonFactories` and `AssetRegistry.defaultFactories` in `lib/page_creator/assets/registry.dart`.

## Error Handling

**Strategy:** Propagate with typed exceptions; log at site; surface to UI via provider `AsyncError` state.

**Patterns:**
- `StateManException` wraps all StateMan failures (key not found, write failure, connection error)
- Provider `AsyncValue.error` is handled in widgets with `.when(error: ...)` fallback UI
- Unhandled async errors caught at root zone in `centroid-hmi/lib/main.dart` with `runZonedGuarded`
- OPC UA subscription retries automatically (10-attempt loop in `StateMan._monitor`)
- Database connection retries via `_scheduleRetry` timer in `lib/providers/database.dart`

## Cross-Cutting Concerns

**Logging:** `package:logger` (`Logger` class) throughout. Log level configurable via `CENTROID_LOG_LEVEL` env var. `CENTROID_LOG_FILE` redirects output to file (MSIX mode).
**Validation:** JSON schema validated via `json_serializable`-generated `fromJson`. Boolean alarm expressions parsed by `BooleanExpression` in `packages/tfc_dart/lib/core/boolean_expression.dart`.
**Authentication:** OPC UA supports username/password and SSL cert auth (config in `OpcUAConfig`). DBus Linux system calls require PAM login flow (`lib/pages/dbus_login.dart`). Secrets stored via `Preferences` with `secret: true` flag (encrypted storage).

---

*Architecture analysis: 2026-05-05*
