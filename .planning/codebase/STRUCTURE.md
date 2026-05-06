# Codebase Structure

**Analysis Date:** 2026-05-05

## Directory Layout

```
tfc-hmi2/                          # Monorepo root
├── lib/                           # tfc library — all UI, providers, painters
│   ├── page_creator/              # Dynamic HMI page composition system
│   │   ├── page.dart              # PageManager, AssetPage, AssetListConverter
│   │   ├── page.g.dart            # json_serializable generated
│   │   └── assets/                # 30+ asset types (Config + Widget + Painter)
│   │       ├── common.dart        # Asset/BaseAsset abstract base + Coordinates/RelativeSize
│   │       ├── registry.dart      # AssetRegistry — central Type→factory map
│   │       ├── conveyor.dart      # ConveyorConfig + ConveyorPainter widget
│   │       ├── conveyor_gate.dart # ConveyorGateConfig, GateVariant, ChildGateEntry
│   │       ├── conveyor_gate_painter.dart
│   │       ├── led.dart           # LEDConfig + Led widget
│   │       ├── button.dart
│   │       ├── number.dart
│   │       ├── graph.dart
│   │       ├── [30+ more *.dart + *.g.dart]
│   │       └── helper/            # Shared mixins for asset widgets
│   │           ├── timeseries_cache.dart
│   │           └── timeseries_notify_mixin.dart
│   ├── pages/                     # Routed pages (Beamer destinations)
│   │   ├── page_view.dart         # AssetView + AssetStack (renders live pages)
│   │   ├── page_editor.dart       # TFC_GOD editor mode
│   │   ├── alarm_view.dart
│   │   ├── alarm_editor.dart
│   │   ├── history_view.dart
│   │   ├── server_config.dart
│   │   ├── key_repository.dart
│   │   ├── tech_doc_library.dart
│   │   └── [other admin pages]
│   ├── providers/                 # Riverpod keepAlive providers
│   │   ├── preferences.dart       # preferencesProvider (Preferences)
│   │   ├── state_man.dart         # stateManProvider (StateMan), substitutionsChangedProvider
│   │   ├── database.dart          # databaseProvider (Database?)
│   │   ├── alarm.dart             # alarmManProvider (AlarmMan)
│   │   ├── collector.dart         # collectorProvider (Collector?)
│   │   ├── page_manager.dart      # pageManagerProvider (PageManager)
│   │   ├── mcp_bridge.dart        # mcpBridgeProvider (McpBridgeNotifier)
│   │   ├── chat.dart              # chatLifecycleProvider, mcpChatEnabledProvider
│   │   ├── llm.dart               # llmProvider, apiKeyProviders
│   │   ├── theme.dart             # themeNotifierProvider
│   │   ├── plc.dart               # plcCodeIndexProvider
│   │   ├── proposal_state.dart
│   │   ├── proposal_watcher.dart
│   │   └── [*.g.dart generated files]
│   ├── widgets/                   # Reusable UI components
│   │   ├── base_scaffold.dart     # Shell: AppBar + nav dropdown + alarm badge
│   │   ├── nav_dropdown.dart      # Multi-level navigation menu
│   │   ├── alarm.dart
│   │   ├── zoomable_canvas.dart
│   │   ├── dynamic_value.dart
│   │   ├── boolean_expression.dart
│   │   ├── bit_mask_grid.dart
│   │   ├── key_mapping_sections.dart
│   │   └── [other widgets]
│   ├── painter/                   # Custom Flutter painters (hardware visualisations)
│   │   ├── beckhoff/              # Beckhoff EtherCAT hardware painters
│   │   │   ├── cx5010.dart
│   │   │   ├── ek1100.dart
│   │   │   ├── ethernet.dart
│   │   │   ├── io8.dart
│   │   │   └── usb.dart
│   │   ├── fish/                  # Fish processing equipment
│   │   │   └── trout.dart
│   │   └── schneider/             # Schneider drives
│   │       └── atv320.dart
│   ├── chat/                      # AI chat overlay UI
│   │   ├── chat_overlay.dart      # ChatOverlay widget + chatVisibleProvider
│   │   ├── chat_widget.dart
│   │   ├── elicitation_dialog.dart # Human-in-the-loop write confirmation
│   │   ├── asset_context_menu.dart
│   │   ├── proposal_action.dart
│   │   └── [other chat widgets]
│   ├── llm/                       # LLM provider abstraction
│   │   ├── llm_provider.dart      # LlmProvider abstract interface
│   │   ├── llm_models.dart        # ChatMessage, LlmResponse models
│   │   ├── claude_provider.dart
│   │   ├── openai_provider.dart
│   │   └── gemini_provider.dart
│   ├── mcp/                       # MCP server lifecycle + bridge
│   │   ├── mcp_bridge_notifier.dart # ChangeNotifier: spawn/stop subprocess
│   │   ├── mcp_sse_server.dart    # SSE wrapper for subprocess stdio
│   │   ├── mcp_lifecycle_state.dart
│   │   ├── alarm_man_alarm_reader.dart
│   │   └── state_man_state_reader.dart
│   ├── drawings/                  # Freehand drawing overlay
│   │   ├── drawing_overlay.dart
│   │   ├── drawing_viewer.dart
│   │   └── drawing_upload_service.dart
│   ├── dbus/                      # Linux D-Bus integrations
│   │   └── generated/             # dart_dbus generated bindings
│   │       ├── config.dart
│   │       ├── hostname1.dart
│   │       ├── ipc-ruler.dart
│   │       ├── login1.dart
│   │       └── operations.dart
│   ├── models/                    # Shared data models
│   │   ├── menu_item.dart         # MenuItem tree (label, path, icon, children)
│   │   └── history_models.dart
│   ├── tech_docs/                 # Technical document library UI
│   ├── plc/                       # PLC code upload/browse UI
│   ├── marionette/                # Test automation route logger
│   │   └── route_logger.dart
│   ├── converter/                 # JSON converters
│   │   ├── color_converter.dart
│   │   ├── icon.dart
│   │   └── pdfrx_text_extractor.dart
│   ├── core/                      # App-level (non-package) utilities
│   │   └── preferences.dart       # SharedPreferencesWrapper
│   │   └── secure_storage/        # Platform secure storage impl (non-Windows)
│   ├── route_registry.dart        # Singleton route + menu registry
│   ├── routes.dart                # AppRoutes constants
│   ├── theme.dart                 # Solarized theme factory
│   └── transition_delegate.dart   # No-animation Beamer transition
│
├── centroid-hmi/                  # Deployable Flutter application
│   ├── lib/
│   │   ├── main.dart              # Entry point: ProviderScope, routes, upgrader
│   │   ├── marionette_init.dart   # Marionette test agent setup
│   │   ├── marionette_nav.dart
│   │   └── pages/
│   │       └── version_manager_page.dart
│   └── pubspec.yaml               # name: centroidx — depends on tfc (path: ../)
│
├── packages/
│   ├── tfc_dart/                  # Core Dart library (no Flutter)
│   │   ├── lib/
│   │   │   ├── tfc_dart.dart      # Full barrel (FFI-enabled)
│   │   │   ├── tfc_dart_core.dart # FFI-free barrel (for MCP server)
│   │   │   └── core/
│   │   │       ├── state_man.dart # StateMan, DeviceClient, ClientWrapper
│   │   │       ├── collector.dart # Timeseries ingestion
│   │   │       ├── alarm.dart     # AlarmMan
│   │   │       ├── database.dart  # Database, DatabaseConfig
│   │   │       ├── database_drift.dart # Drift schema + AppDatabase
│   │   │       ├── preferences.dart # Preferences (dual-layer)
│   │   │       ├── boolean_expression.dart
│   │   │       ├── modbus_device_client.dart
│   │   │       ├── modbus_client_wrapper.dart
│   │   │       └── secure_storage/
│   │   ├── bin/main.dart          # Standalone CLI/test harness
│   │   └── test/                  # Unit + integration tests
│   │
│   ├── tfc_mcp_server/            # MCP AI tool server (standalone binary)
│   │   ├── lib/src/
│   │   │   ├── server.dart        # TfcMcpServer — wires all tools/services
│   │   │   ├── tools/             # alarm, config, tag, trend, asset write, page write...
│   │   │   ├── services/          # alarm, trend, drawing, config, proposal services
│   │   │   ├── resources/         # config snapshot, drawings, knowledge, tech docs
│   │   │   ├── prompts/           # diagnose_equipment, explain_alarm, shift_handover
│   │   │   ├── compiler/          # PLC code analysis
│   │   │   ├── safety/            # elicitation_risk_gate
│   │   │   └── audit/             # audit_log_service
│   │   ├── bin/tfc_mcp_server.dart # Binary entry point
│   │   └── test/
│   │
│   ├── jbtm/                      # M2400 weighing device client
│   │   └── lib/src/
│   │       ├── m2400.dart
│   │       ├── m2400_client_wrapper.dart
│   │       └── msocket.dart
│   │
│   ├── modbus_client/             # Modbus TCP client
│   │   └── lib/src/
│   │
│   └── centroidx_upgrader/        # Auto-update helpers
│       └── lib/src/
│           ├── github_release_store.dart
│           └── manager_launcher.dart
│
├── demo/                          # Minimal Flutter demo app
│   └── lib/main.dart
│
├── tools/
│   ├── centroidx-manager/         # Go binary: version management UI (separate process)
│   └── claude-proxy/              # Development proxy for Claude API
│
├── docker/
│   ├── backend/                   # PostgreSQL + backend config
│   ├── frontend/                  # HMI container
│   └── frontend-ivi/              # In-vehicle infotainment variant
│
├── assets/
│   ├── centroid.svg
│   └── fonts/TfcIcons.ttf         # Custom icon font
│
├── test/                          # tfc library tests (mirrors lib/)
│   ├── painter/                   # Golden tests for painters
│   ├── page_creator/
│   ├── widgets/
│   ├── providers/
│   └── fixtures/
│
├── scripts/                       # Windows cert scripts
├── pubspec.yaml                   # name: tfc (library)
└── .planning/codebase/            # GSD analysis documents
```

## Directory Purposes

**`lib/page_creator/assets/`:**
- Purpose: Every HMI component type lives here — its JSON config model, its widget, and (often) its custom painter
- Contains: `*Config` classes extending `BaseAsset`, generated `*.g.dart`, inline `StatefulWidget`/`ConsumerWidget` implementations
- Key files: `common.dart` (base contracts), `registry.dart` (factory maps), `conveyor.dart`, `conveyor_gate.dart`, `led.dart`
- Pattern: Each file owns a single asset family; `*Config` is the data model AND the entry point (calls `build(context)`)

**`lib/providers/`:**
- Purpose: Riverpod providers that wire infrastructure singletons into the widget tree
- Contains: One file per major service; all use `@Riverpod(keepAlive: true)` or `ChangeNotifierProvider`
- Key dependency chain: `database` ← `preferences` ← `state_man` ← `collector` / `alarm`

**`lib/painters/` (under `lib/painter/`):**
- Purpose: `CustomPainter` implementations for hardware topology diagrams (Beckhoff, Schneider, fish)
- Not the same as asset painters (those live inline in `lib/page_creator/assets/`)

**`packages/tfc_dart/`:**
- Purpose: Pure-Dart / Flutter-free infrastructure — all field device communication, persistence, alarms
- Key distinction: `tfc_dart.dart` vs `tfc_dart_core.dart` — only the latter is safe for the MCP server binary

**`packages/tfc_mcp_server/`:**
- Purpose: Standalone Dart executable; exposes TFC plant data as MCP tools for AI agents
- Compiled with `dart compile exe`; spawned as subprocess by `McpBridgeNotifier`

## Key File Locations

**Entry Points:**
- `centroid-hmi/lib/main.dart`: Production HMI start
- `packages/tfc_mcp_server/bin/tfc_mcp_server.dart`: MCP tool server start
- `packages/tfc_dart/bin/main.dart`: Standalone tfc_dart CLI

**Configuration:**
- `pubspec.yaml`: tfc library dependencies
- `centroid-hmi/pubspec.yaml`: CentroidX app (name: centroidx), depends on `tfc: path: ../`
- `packages/tfc_dart/lib/core/state_man.dart`: `StateManConfig` (OPC UA / Modbus / M2400 endpoints)

**Core Logic:**
- `packages/tfc_dart/lib/core/state_man.dart`: `StateMan` class, all device protocol handling
- `lib/page_creator/assets/registry.dart`: `AssetRegistry` — all asset types registered here
- `lib/page_creator/assets/common.dart`: `Asset`/`BaseAsset` interfaces
- `lib/page_creator/page.dart`: `PageManager`, `AssetPage`
- `lib/route_registry.dart`: `RouteRegistry` singleton

**Testing:**
- `test/`: tfc library tests, co-located mirror of `lib/`
- `packages/tfc_dart/test/`: Core state_man, converter, integration tests
- `packages/tfc_mcp_server/test/`: MCP server tool and service tests
- `test/painter/goldens/` and `test/widgets/goldens/`: Golden image files

## Naming Conventions

**Files:**
- `snake_case.dart` for all Dart source files
- `*.g.dart` for code-generated files (json_serializable, riverpod_generator, drift_dev) — never edit manually
- `*.dart.bak` for temporarily disabled files (e.g., `lib/pages/io_tinker.dart.bak`)

**Directories:**
- `snake_case` throughout
- Test directories mirror source structure (e.g., `test/page_creator/` mirrors `lib/page_creator/`)

**Classes:**
- `*Config` suffix for asset data models (`LEDConfig`, `ConveyorGateConfig`)
- `*Provider` suffix for Riverpod providers (generated: `stateManProvider`, `preferencesProvider`)
- `*Notifier` suffix for `ChangeNotifier` / `StateNotifier` classes
- `*Service` suffix for business logic classes in MCP server
- `*Page` suffix for full-screen routed widgets
- Painters: `*Painter` suffix for `CustomPainter` subclasses

## Where to Add New Code

**New HMI Asset Type (e.g., a new widget on the plant diagram):**
1. Create `lib/page_creator/assets/my_thing.dart` — define `MyThingConfig extends BaseAsset` and its widget
2. Add `part 'my_thing.g.dart';` and run `flutter pub run build_runner build`
3. Register in `lib/page_creator/assets/registry.dart` — add to `_fromJsonFactories` and `defaultFactories`
4. If the asset needs a custom painter, add `lib/page_creator/assets/my_thing_painter.dart`

**New Routed Page:**
1. Add page widget in `lib/pages/my_page.dart`
2. Register route in `centroid-hmi/lib/main.dart` in `createLocationBuilder()`
3. Add `MenuItem` to the relevant menu section in `_startApp()`
4. Add route constant to `lib/routes.dart` if shared across files

**New Riverpod Provider:**
1. Add `lib/providers/my_service.dart` with `@Riverpod(keepAlive: true)` annotation
2. Run `flutter pub run build_runner build` to generate `my_service.g.dart`
3. Use `ref.read` (not `ref.watch`) when reading infrastructure providers to avoid cascade invalidation

**New MCP Tool:**
1. Add tool class in `packages/tfc_mcp_server/lib/src/tools/my_tool.dart`
2. Register in `packages/tfc_mcp_server/lib/src/tools/tool_registry.dart`
3. Add to server wiring in `packages/tfc_mcp_server/lib/src/server.dart`

**New Device Protocol Support in StateMan:**
1. Implement `DeviceClient` interface in `packages/tfc_dart/lib/core/`
2. Add config class with `@JsonSerializable` to `packages/tfc_dart/lib/core/state_man.dart`
3. Add config field to `StateManConfig`
4. Wire factory in `lib/providers/state_man.dart`

**New Shared Widget:**
- Standalone UI helpers: `lib/widgets/my_widget.dart`
- Asset-specific painters: `lib/page_creator/assets/` alongside the asset config

**Utilities:**
- Shared helpers (no Flutter deps): `packages/tfc_dart/lib/core/`
- Flutter-specific helpers: `lib/widgets/` or `lib/converter/`

## Special Directories

**`.planning/codebase/`:**
- Purpose: GSD codebase analysis documents (this file)
- Generated: Yes (by GSD map-codebase command)
- Committed: Yes

**`lib/dbus/generated/`:**
- Purpose: dart_dbus code-generated DBus bindings
- Generated: Yes (by `dart-dbus generate-remote-object`)
- Committed: Yes

**`packages/*/lib/*.g.dart` and `lib/**/*.g.dart`:**
- Purpose: Code generated by `json_serializable`, `riverpod_generator`, `drift_dev`
- Generated: Yes (via `build_runner`)
- Committed: Yes

**`test/painter/goldens/` and `test/widgets/goldens/`:**
- Purpose: Flutter golden image baseline files for visual regression tests
- Generated: Yes (on first run or when updated with `--update-goldens`)
- Committed: Yes

**`centroid-hmi/assets/manager/`:**
- Purpose: Bundled `centroidx-manager` binary assets for the version manager page
- Generated: No
- Committed: Yes

**`docker/`:**
- Purpose: Docker Compose configs for backend (PostgreSQL) and frontend containers
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-05-05*
