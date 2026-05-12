<!-- GSD:project-start source:PROJECT.md -->
## Project

**Elevator & Sensor Assets**

Two new HMI assets for the tfc-hmi2 page creator: an **elevator** that translates child assets vertically based on a PLC-driven 0–100% position, and a **sensor** asset with a configurable kind (paired red light beam, optic field, inductive field) that visualises detection state from a bool state key. Built for industrial operators using the existing centroid-hmi Flutter app to monitor and configure conveyor lines that include lifting platforms and sensor instrumentation.

**Core Value:** Operators can place an elevator on a page, assign sensors and conveyors to it via the config dialog, and watch those children physically ride the platform up and down as the PLC's position value changes — with sensor detection states reflected accurately in real time.

### Constraints

- **Tech stack**: Must use existing Flutter + Riverpod + Asset Registry + StateMan stack — no new frameworks
- **Pattern fidelity**: Follow `ConveyorGate` painter and child-wrapper conventions; deviating breaks operator muscle memory and forces future rework
- **Backwards compatibility**: Existing saved pages must continue to load; any new config fields need defensible defaults
- **Codegen**: New configs require `*.g.dart` files via build_runner — must round-trip through JSON cleanly
- **State-key driven**: All live values (position, bool, edge delays) come from `StateMan` keys; no hard-coded values in production paths
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Dart 3.5–3.6 - All Flutter UI and business logic (`lib/`, `packages/tfc_dart/`, `packages/tfc_mcp_server/`, `packages/jbtm/`)
- Kotlin - Android platform host (`centroid-hmi/android/app/src/main/kotlin/`)
- Swift/Objective-C - iOS/macOS platform host (`centroid-hmi/ios/`, `centroid-hmi/macos/`)
- C/C++ (via build hooks) - `open62541` OPC UA native library compiled by `dart build` hooks
## Runtime
- Flutter (stable channel) — targets Linux (elinux/Wayland), macOS (arm64), Windows (x64), Android, iOS
- Dart SDK ^3.5.1 (root package) / ^3.6.0 (centroid-hmi app)
- Nix flake (`flake.nix`) provides dev shell with Flutter, libsecret, gtk3, pkg-config on NixOS 25.05
- Dart: `pub` (flutter pub / dart pub)
- Lockfiles: `pubspec.lock` present in each package (not listed in repo root — workspace managed per-package)
## Frameworks
- Flutter (Material) — full app framework for all platforms
- Beamer ^1.6–1.7 — declarative routing / deep linking
- Riverpod ^2.6.1 + riverpod_annotation + flutter_riverpod — reactive state, dependency injection
- Code generation: `riverpod_generator ^2.6.5`
- RxDart ^0.28.0 — BehaviorSubject streams for OPC UA / Modbus / M2400 data pipelines
- Drift ^2.28.0 — type-safe ORM for both SQLite (local) and PostgreSQL (remote via drift_postgres ^1.3.1)
- Build config (`build.yaml`): `store_date_time_values_as_text: true`, dialects: `postgres` + `sqlite`
- TimescaleDB (PostgreSQL 17 extension) — time-series hypertables for telemetry data storage (see `database_drift.dart` lines 855–887)
- `anthropic_sdk_dart ^1.2.0` — Claude API SDK
- `openai_dart ^1.1.0` — OpenAI/GPT API SDK
- Gemini: HTTP-based provider (uses `dart:io` HttpClient; no dedicated SDK package)
- `mcp_dart ^2.0.0` — Model Context Protocol (MCP) SDK for exposing HMI state as AI-readable tools
- `flutter_test` (SDK) — Flutter widget tests
- `dart test ^1.25.0` — Pure-Dart unit/integration tests (`packages/tfc_dart/`, `packages/tfc_mcp_server/`)
- `dart_test.yaml` — Test runner config (concurrency 1 for integration, 4 for units); golden tests skipped unless `--update-goldens`
- `build_runner ^2.4.15` — Code generation runner
- `json_serializable ^6.9.4` / `json_annotation ^4.9.0` — JSON serialization codegen
- `drift_dev ^2.28.0` — Drift ORM codegen
- `flutter_lints ^5.0.0` / `lints ^5.0.0` — Analysis/lint rules
- `msix ^3.16.12` — Windows MSIX package builder (centroid-hmi)
- `flutter_launcher_icons ^0.14.3` / `flutter_native_splash ^2.4.6` — App icon/splash code gen
## Key Dependencies
- `open62541` (git: `github.com/centroid-is/open62541_dart`, branch `main`) — OPC UA C library with Dart FFI bindings; compiled at build time via Dart native hooks; used for all PLC data subscriptions
- `tfc_dart` (path: `packages/tfc_dart`) — Core data-acquisition engine: OPC UA state machine, Modbus/UMAS client, Drift DB layer, alarm system, preferences
- `tfc_mcp_server` (path: `packages/tfc_mcp_server`) — MCP server exposing HMI tools to AI assistants
- `jbtm` (path: `packages/jbtm`) — M2400 weighing-device protocol (proprietary TCP binary protocol)
- `modbus_client_tcp` (path: `packages/modbus_client_tcp`) — Local fork of `cabbi/modbus_client_tcp` with frame-parsing and keepalive fixes
- `postgres` (git: `github.com/centroid-is/postgresql-dart`, branch `add-keepalive-test`) — Forked PostgreSQL driver with keepalive patches; `dependency_overrides` in all packages
- `rxdart ^0.28.0` — Reactive streams (BehaviorSubject) throughout data pipeline
- `amplify_secure_storage_dart ^0.5.6` — Cross-platform secure keyring (Linux: libsecret; Windows: custom `OtherSecureStorage`; macOS: Keychain)
- `cryptography ^2.7.0` + `cryptography_flutter ^2.3.2` — OPC UA certificate cryptography
- `basic_utils ^5.7.0` — X.509 certificate generation
- `drift_postgres ^1.3.1` — PostgreSQL backend for Drift ORM
- `shared_preferences ^2.3.5` — Lightweight local key-value storage (page config, menu layout)
- `beamer ^1.6.2` — Routing
- `pdfrx ^2.2.24` — PDF viewer (tech docs, knowledge base); requires `libpdfium.so` in Docker image
- `community_charts_flutter ^1.0.4` — Chart widgets for history view
- `cristalyse` (git: `github.com/centroid-is/cristalyse`, branch `dev`) — Custom chart library
- `board_datetime_picker` (git: `github.com/centroid-is/board_datetime_picker`, branch `subtitle-for-start-end-date`) — Custom date picker for history range
- `marionette_flutter ^0.4.0` — UI automation framework for agent-driven testing (gated by `--dart-define=MARIONETTE=true`)
- `nm ^0.5.0` — NetworkManager DBus bindings (Linux IP settings page)
- `dbus ^0.7.11` — DBus client for Linux system integration
- `dartssh2 ^2.11.0` — SSH client (used in `lib/dbus/remote.dart`)
- `font_awesome_flutter ^10.9.1` — Icon set
- `flutter_colorpicker ^1.1.0` — Color picker widget
- `file_picker ^10.3.3` — File selection dialogs
- `desktop_drop ^0.7.0` — Drag-and-drop file upload (drawings)
- `package_info_plus ^8.0.0` — App version info
- `intl ^0.20.2` — Internationalization / date formatting
## Configuration
- `CENTROID_PGHOST` — PostgreSQL host (required for backend `main.dart`)
- `CENTROID_PGPORT` — PostgreSQL port (default 5432)
- `CENTROID_PGDATABASE` — Database name (default `hmi`)
- `CENTROID_PGUSER` / `CENTROID_PGPASSWORD` / `CENTROID_PGSSLMODE` — DB auth
- `CENTROID_STATEMAN_FILE_PATH` — Path to `stateman.json` configuration file
- `CENTROID_LOG_LEVEL` — Log level override (trace/debug/info/warning/error)
- `CENTROID_OPCUA_LOG_LEVEL` — OPC UA stack log level
- `CENTROID_LOG_FILE` — Path to write log output
- `CENTROID_STDOUT` — Enable stdout logging (`1` or `true`)
- `CENTROID_DB_DEBUG` — Enable verbose DB query logging
- `TFC_GOD` — Enables god-mode features (Page Editor, Alarm Editor, Preferences)
- `SECRET_BACKEND` — Secure storage backend (`file` for Docker; default: platform keyring)
- `SECRET_FILE_TEST_PATH` / `SECRET_FILE_TEST_PASSWORD` — File-based keyring config
- `TIMESCALEDB_EXTERNAL` — Used in CI to skip Docker-based DB when native PG is available
- `MARIONETTE=true` — Enables `marionette_flutter` UI automation (agent testing mode)
- `build.yaml` — Drift codegen options (root + `packages/tfc_dart/`, `packages/tfc_mcp_server/`)
- `analysis_options.yaml` — `flutter_lints/flutter.yaml` base; formatter `page_width: 120`
- `dart_test.yaml` — Test runner concurrency settings; golden test skip tag
- `centroid-hmi/pubspec.yaml` `msix_config` section — Windows MSIX signing metadata
## Platform Requirements
- Flutter stable channel
- Nix devShell (`flake.nix`) or manual install of: libsecret, gtk3, pkg-config, cmake, python3, build-essential (for `open62541` native build hook)
- TimescaleDB (PostgreSQL 17 + timescaledb extension) for integration tests
- **Linux elinux/Wayland**: Docker image `ghcr.io/centroid-is/centroid-hmi` (Debian trixie-slim + Wayland stack), deployed via `docker-compose.yml` with Weston compositor
- **macOS arm64**: Signed `.dmg` (Developer ID Application, notarized via Apple Notary Service)
- **Windows x64**: Signed `.msix` (sideload certificate, published via `msix` tool)
- **Backend**: Dart CLI binary `main` in Docker image `ghcr.io/centroid-is/centroid-backend` (Debian bookworm-slim), run alongside TimescaleDB
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- `snake_case.dart` for all Dart source files (e.g., `conveyor_gate.dart`, `state_man.dart`)
- Generated files: `<name>.g.dart` (json_serializable, riverpod_generator, drift)
- Test files: `<name>_test.dart` co-located in `test/` mirroring `lib/` structure
- Private test helpers/fakes prefixed with `_`: `_MockPlcCodeService`, `_FakeSecureStorage`
- `PascalCase` for all classes, enums, mixins, typedefs
- Widget classes: suffix varies — `Widget`, `Page`, `Panel`, `Section`, `Tile`, `Dialog`, `Overlay` (no enforced single suffix)
- Private implementation classes (internal to a file): `_PascalCase` (e.g., `_TabbedDetailView`, `_CollapsibleSection`)
- Abstract interfaces: plain class name with abstract keyword (e.g., `StateReader`, `AlarmReader`, `LlmProvider`)
- Mock/fake implementations in tests: `Mock<X>` or `Fake<X>` or `_Mock<X>` pattern using `Fake` base class
- `camelCase` for all functions, methods, and local variables
- Boolean-returning methods use `is`/`has`/`can` prefix (e.g., `hasCode`, `isError`, `isBroadcast`)
- Factory constructors: `ClassName.fromJson()`, `ClassName.create()`, `ClassName.inMemory()`, `ClassName.preview()`
- Async functions: no special prefix, `async` keyword is sufficient
- `camelCase` for locals and instance fields
- Top-level constants: `kCamelCase` prefix (e.g., `kClaudeApiKey`, `kChatHistory`, `kSelectedProvider`)
- Dart `const` string sentinels without `k` prefix when used as JSON key names (e.g., `constAssetName = "asset_name"`)
- Riverpod providers: `camelCaseProvider` suffix (e.g., `stateManProvider`, `preferencesProvider`, `chatVisibleProvider`)
- `PascalCase` for enum type; `camelCase` for values (e.g., `GateVariant.pneumatic`, `ChatStatus.idle`)
- Annotate with `@JsonEnum()` when serialized; use `@JsonKey(unknownEnumValue: ...)` on fields for forward compatibility
## Code Style
- Standard `dart format` (no custom config; enforced implicitly via CI)
- No explicit `.prettierrc` — Dart analyzer enforces style
- Root package: `package:flutter_lints/flutter.yaml` (via `analysis_options.yaml`)
- Dart-only packages (`tfc_dart`, `jbtm`, `modbus_client*`): `package:lints/recommended.yaml`
- `tfc_mcp_server` adds stricter rules: `strict-casts: true`, `strict-raw-types: true`, `avoid_print: error`
- `avoid_print` is a lint error in `tfc_mcp_server` — never use `print()` there
## Import Organization
- None. Packages are imported by package name (e.g., `package:tfc/...`, `package:tfc_dart/...`)
## Code Generation Patterns
- Annotate class with `@JsonSerializable()` or `@JsonSerializable(explicitToJson: true)`
- Annotate enums with `@JsonEnum()`
- Always provide `factory ClassName.fromJson(Map<String, dynamic> json)` and `toJson()` methods
- Use `@JsonKey(unknownEnumValue: EnumType.fallback)` on enum fields to handle unknown values in JSON
- Use `@JsonKey(includeFromJson: false, includeToJson: false)` for computed/transient fields
- File must have `part 'filename.g.dart';` directive
- Run codegen: `dart run build_runner build` or `flutter pub run build_runner build`
- Use `@Riverpod(keepAlive: true)` for long-lived app-level providers (network connections, DB, preferences)
- Use `@riverpod` for ephemeral/scoped providers
- Annotate the provider function (not a class) for simple async providers:
- Generated provider name: `XxxxProvider` from function `xxxx`
- Manual (non-generated) providers for UI state: `StateProvider<T>`, `FutureProvider<T>`, `Provider<T>`
- Manual `StateProvider` for simple boolean flags (e.g., `chatVisibleProvider`, `drawingVisibleProvider`)
- `build.yaml` configures: `store_date_time_values_as_text: true`, dialects: `[postgres, sqlite]`
- Generated files: `*.g.dart` alongside the database class file
## Error Handling
- `throw ArgumentError('message')` for invalid constructor arguments (e.g., empty API keys)
- `throw Exception('message')` for runtime failures in service code
- `throw StateError('...')` used in tests to stub providers that should not be reached
- `try`/`catch` in provider initializers; errors written to `stderr.writeln(...)` before rethrow
- Widget layer: `when(data:, loading:, error:)` on AsyncValue for provider states
- No global error boundary beyond Flutter's default; individual providers handle their own errors
- Use `rethrow` to propagate exceptions after logging (don't swallow)
- `package:logger` (`Logger` class) for structured logging in library/service code
- `Logger().e(...)` for errors, `Logger().w(...)` for warnings
- `stderr.writeln(...)` in provider glue code (not library code) for initialization errors
- `io.stderr.writeln(...)` in provider files that import `dart:io` as `io`
- Never use `print()` in `tfc_mcp_server` (lint error); use `Logger` instead
- No centralized log configuration beyond `lib/core/log_config.dart` (environment-variable-driven log levels for OPC UA)
## Comments
- Class-level `///` doc comments on all public classes and abstract interfaces (mandatory in `tfc_mcp_server`)
- Method-level `///` doc comments on non-obvious public methods, especially those with `Throws` behavior
- Inline `//` comments for non-obvious logic; `// This is the bug:` or `// Simulates:` in test code for intent
- Multi-line `///` class doc comments describe design decisions and cross-cutting concerns
## Function Design
- Named parameters used throughout (especially for config/model constructors)
- Required named parameters: `required this.field` in constructors
- Optional named parameters with defaults for configuration (e.g., `bool hasCode = false`)
- Nullable return `T?` when absence is a valid state (not an error)
- `null` return to signal "not found" (e.g., `getTagValue` returns `Map?`)
- Avoid returning empty sentinels; prefer null or throw
## Widget Design
- `StatelessWidget` — pure UI with no mutable state
- `StatefulWidget` + `State<T>` — widgets with local mutable state (e.g., form fields, collapsible sections)
- `ConsumerWidget` — stateless widgets that read Riverpod providers
- `ConsumerStatefulWidget` + `ConsumerState<T>` — stateful widgets that also read providers
- `ValueKey<String>('kebab-case-id')` for semantic widget keys used in tests (e.g., `'chat-close-button'`, `'chat-message-input'`, `'chat-title-picker'`)
- Key strings use kebab-case with domain prefix (e.g., `'chat-*'`, `'batch-*'`)
- Keys on interactive elements allow test finders to locate widgets reliably
## Module Design
- Packages expose a single barrel entry point (e.g., `package:tfc_mcp_server/tfc_mcp_server.dart`)
- Internal implementation in `lib/src/` is not re-exported unless explicitly needed
- No barrel `index.dart` within `lib/` of the main `tfc` app — import directly by path
- `tfc_dart`: core Dart-only business logic (StateMan, database, alarms, converters)
- `tfc_mcp_server`: MCP server with strict linting (no `print`, strict casts/raw types)
- `jbtm`: M2400 device protocol
- `modbus_client`, `modbus_client_tcp`: Modbus protocol (local forks)
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | Key Files |
|-----------|----------------|-----------|
| `centroid-hmi` app | Production HMI binary; wires routes, menu, app shell | `centroid-hmi/lib/main.dart` |
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
## Pattern Overview
- Assets are pure data configs (`BaseAsset`) that carry both their serialized state (JSON) and a `build()` method returning a `Widget`. No separate ViewModel.
- All live process data flows through `StateMan.subscribe(key)` → `Stream<DynamicValue>`. Widgets read `stateManProvider` and call `stateMan.subscribe(key)`.
- Riverpod `keepAlive: true` providers (`preferencesProvider`, `stateManProvider`, `databaseProvider`, etc.) are singletons for the app lifetime — they are never auto-disposed.
- The MCP AI layer is a separate subprocess (`tfc_mcp_server`) that communicates with the Flutter app over SSE; it is not in-process.
## Layers
- Purpose: Dart/Flutter binary entry point; platform-specific setup, route wiring
- Location: `centroid-hmi/lib/`
- Contains: `main.dart`, `marionette_init.dart`
- Depends on: `tfc` library package at `../`
- Used by: End users, CI/CD pipelines
- Purpose: All reusable UI — pages, widgets, painters, asset components, providers
- Location: `lib/`
- Contains: pages, widgets, page_creator, providers, painter, chat, llm, mcp, drawings, dbus, tech_docs
- Depends on: `tfc_dart`, `tfc_mcp_server`, `jbtm`, `open62541`, Riverpod, Beamer
- Used by: `centroid-hmi` app
- Purpose: Bridge between UI and infrastructure; Riverpod async providers with `keepAlive`
- Location: `lib/providers/`
- Contains: `state_man.dart`, `preferences.dart`, `database.dart`, `alarm.dart`, `collector.dart`, `page_manager.dart`, `mcp_bridge.dart`, `chat.dart`, `theme.dart`, `llm.dart`
- Depends on: `tfc_dart` core, `tfc_mcp_server`
- Used by: All widgets via `ref.watch`/`ref.read`
- Purpose: Dynamic HMI page composition — JSON config → typed Widget
- Location: `lib/page_creator/`
- Contains: `page.dart` (PageManager, AssetPage), `assets/` (30+ asset configs + their painters/widgets), `assets/registry.dart` (AssetRegistry)
- Depends on: StateMan via `stateManProvider`, common.dart `Asset`/`BaseAsset` contracts
- Used by: `AssetView` in `lib/pages/page_view.dart`
- Purpose: Protocol-agnostic read/write/subscribe over OPC UA, Modbus TCP, M2400
- Location: `packages/tfc_dart/lib/core/`
- Key files: `state_man.dart`, `modbus_device_client.dart`, `modbus_client_wrapper.dart`, `collector.dart`, `alarm.dart`, `database.dart`, `preferences.dart`
- Depends on: `open62541` (FFI), `jbtm`, `modbus_client`, `drift`, PostgreSQL
- Used by: Provider layer
- Purpose: Exposes plant data as MCP tools for LLM agents (Claude, OpenAI, Gemini)
- Location: `packages/tfc_mcp_server/lib/src/`
- Contains: tools/, services/, resources/, prompts/, compiler/, safety/, audit/
- Depends on: `tfc_dart_core.dart` (FFI-free subset), `mcp_dart`, PostgreSQL
- Used by: `McpBridgeNotifier` via subprocess spawn; LLM clients via SSE
## Data Flow
### Primary HMI View Render
### Asset Config Serialisation / Deserialisation
### AI / MCP Tool Call Flow
### Key Substitution Flow
- Global singleton providers with `keepAlive: true` (Riverpod 2.x, code-generated with `@Riverpod`)
- No Redux/BLoC; providers are the state layer
- `AutoDisposingStream` in StateMan manages OPC UA subscriptions with 10-minute idle timeout
## Key Abstractions
- Purpose: Contract for all HMI asset components
- Interface: `lib/page_creator/assets/common.dart` (abstract `Asset`)
- Base impl: `BaseAsset` — handles coordinates, size, text, JSON serialization pattern
- Pattern: Every concrete type (e.g., `LEDConfig`, `ConveyorConfig`) extends `BaseAsset`, implements `build(context)` returning its widget and `configure(context)` returning its edit panel
- Purpose: Protocol-agnostic interface for subscribe/read/write to field devices
- Location: `packages/tfc_dart/lib/core/state_man.dart` (abstract class `DeviceClient`)
- Implementations: `M2400DeviceClientAdapter`, `ModbusDeviceClientAdapter`; OPC UA handled directly by `ClientWrapper`
- Purpose: Ref-counted OPC UA subscription that tears down the underlying monitored item when no Flutter widgets are listening
- Location: `packages/tfc_dart/lib/core/state_man.dart`
- Pattern: `ReplaySubject` (maxSize=1) with listener count tracking and 10-minute idle timer
- Purpose: Central factory registry; maps `Type → fromJson` and `Type → preview` factories
- Location: `lib/page_creator/assets/registry.dart`
- Pattern: Two static maps; `parse(json)` crawls JSON tree matching `asset_name` to factory
## Entry Points
- Location: `centroid-hmi/lib/main.dart`
- Triggers: Flutter runtime on Linux / Windows / macOS
- Responsibilities: SIGPIPE handling, log file setup, `ProviderScope` bootstrap, Beamer route wiring, GitHub upgrade check, Marionette test agent opt-in
- Location: `packages/tfc_mcp_server/bin/tfc_mcp_server.dart`
- Triggers: Spawned as subprocess by `McpBridgeNotifier`
- Responsibilities: Stdio MCP protocol, tool registration, audit logging, PostgreSQL connection for historical data
- Location: `packages/tfc_dart/bin/main.dart`
- Triggers: `dart run` for standalone testing
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
### Using `ref.watch` for infrastructure providers inside other infrastructure providers
### Registering assets in `centroid-hmi/lib/main.dart` instead of `AssetRegistry`
## Error Handling
- `StateManException` wraps all StateMan failures (key not found, write failure, connection error)
- Provider `AsyncValue.error` is handled in widgets with `.when(error: ...)` fallback UI
- Unhandled async errors caught at root zone in `centroid-hmi/lib/main.dart` with `runZonedGuarded`
- OPC UA subscription retries automatically (10-attempt loop in `StateMan._monitor`)
- Database connection retries via `_scheduleRetry` timer in `lib/providers/database.dart`
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
