# Technology Stack

**Analysis Date:** 2026-05-05

## Languages

**Primary:**
- Dart 3.5–3.6 - All Flutter UI and business logic (`lib/`, `packages/tfc_dart/`, `packages/tfc_mcp_server/`, `packages/jbtm/`)
- Go 1.26 - `centroidx-manager` update manager tool (`tools/centroidx-manager/`)

**Secondary:**
- Kotlin - Android platform host (`centroid-hmi/android/app/src/main/kotlin/`)
- Swift/Objective-C - iOS/macOS platform host (`centroid-hmi/ios/`, `centroid-hmi/macos/`)
- C/C++ (via build hooks) - `open62541` OPC UA native library compiled by `dart build` hooks

## Runtime

**Environment:**
- Flutter (stable channel) — targets Linux (elinux/Wayland), macOS (arm64), Windows (x64), Android, iOS
- Dart SDK ^3.5.1 (root package) / ^3.6.0 (centroid-hmi app)
- Go 1.26.1 (centroidx-manager only)
- Nix flake (`flake.nix`) provides dev shell with Flutter, libsecret, gtk3, pkg-config on NixOS 25.05

**Package Manager:**
- Dart: `pub` (flutter pub / dart pub)
- Lockfiles: `pubspec.lock` present in each package (not listed in repo root — workspace managed per-package)
- Go: `go.mod` / `go.sum` at `tools/centroidx-manager/`

## Frameworks

**Core UI:**
- Flutter (Material) — full app framework for all platforms
- Beamer ^1.6–1.7 — declarative routing / deep linking

**State Management:**
- Riverpod ^2.6.1 + riverpod_annotation + flutter_riverpod — reactive state, dependency injection
- Code generation: `riverpod_generator ^2.6.5`

**Reactive Programming:**
- RxDart ^0.28.0 — BehaviorSubject streams for OPC UA / Modbus / M2400 data pipelines

**Database / ORM:**
- Drift ^2.28.0 — type-safe ORM for both SQLite (local) and PostgreSQL (remote via drift_postgres ^1.3.1)
- Build config (`build.yaml`): `store_date_time_values_as_text: true`, dialects: `postgres` + `sqlite`
- TimescaleDB (PostgreSQL 17 extension) — time-series hypertables for telemetry data storage (see `database_drift.dart` lines 855–887)

**AI / LLM:**
- `anthropic_sdk_dart ^1.2.0` — Claude API SDK
- `openai_dart ^1.1.0` — OpenAI/GPT API SDK
- Gemini: HTTP-based provider (no dedicated SDK package; uses `http`)
- `mcp_dart ^2.0.0` — Model Context Protocol (MCP) SDK for exposing HMI state as AI-readable tools

**Testing:**
- `flutter_test` (SDK) — Flutter widget tests
- `dart test ^1.25.0` — Pure-Dart unit/integration tests (`packages/tfc_dart/`, `packages/tfc_mcp_server/`)
- `dart_test.yaml` — Test runner config (concurrency 1 for integration, 4 for units); golden tests skipped unless `--update-goldens`

**Build/Dev:**
- `build_runner ^2.4.15` — Code generation runner
- `json_serializable ^6.9.4` / `json_annotation ^4.9.0` — JSON serialization codegen
- `drift_dev ^2.28.0` — Drift ORM codegen
- `flutter_lints ^5.0.0` / `lints ^5.0.0` — Analysis/lint rules
- `msix ^3.16.12` — Windows MSIX package builder (centroid-hmi)
- `flutter_launcher_icons ^0.14.3` / `flutter_native_splash ^2.4.6` — App icon/splash code gen

**Go UI (centroidx-manager):**
- `gioui.org v0.9.0` — Immediate-mode GUI for the native update manager
- `github.com/Masterminds/semver/v3 v3.4.0` — Semantic version comparison
- `github.com/google/go-github/v84 v84.0.0` — GitHub Releases API client

## Key Dependencies

**Critical:**
- `open62541` (git: `github.com/centroid-is/open62541_dart`, branch `main`) — OPC UA C library with Dart FFI bindings; compiled at build time via Dart native hooks; used for all PLC data subscriptions
- `tfc_dart` (path: `packages/tfc_dart`) — Core data-acquisition engine: OPC UA state machine, Modbus/UMAS client, Drift DB layer, alarm system, preferences
- `tfc_mcp_server` (path: `packages/tfc_mcp_server`) — MCP server exposing HMI tools to AI assistants
- `jbtm` (path: `packages/jbtm`) — M2400 weighing-device protocol (proprietary TCP binary protocol)
- `modbus_client_tcp` (path: `packages/modbus_client_tcp`) — Local fork of `cabbi/modbus_client_tcp` with frame-parsing and keepalive fixes
- `postgres` (git: `github.com/centroid-is/postgresql-dart`, branch `add-keepalive-test`) — Forked PostgreSQL driver with keepalive patches; `dependency_overrides` in all packages

**Infrastructure:**
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
- `centroidx_upgrader` (path: `packages/centroidx_upgrader`) — GitHub Releases update check + manager launcher
- `upgrader ^11.5.1` — Update dialog UI (wraps centroidx_upgrader)
- `http ^1.6.0` — HTTP client (upgrader, Gemini provider)

## Configuration

**Environment (runtime):**
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

**Dart-define build flags:**
- `MARIONETTE=true` — Enables `marionette_flutter` UI automation (agent testing mode)

**Build:**
- `build.yaml` — Drift codegen options (root + `packages/tfc_dart/`, `packages/tfc_mcp_server/`)
- `analysis_options.yaml` — `flutter_lints/flutter.yaml` base; formatter `page_width: 120`
- `dart_test.yaml` — Test runner concurrency settings; golden test skip tag
- `centroid-hmi/pubspec.yaml` `msix_config` section — Windows MSIX signing metadata

## Platform Requirements

**Development:**
- Flutter stable channel
- Nix devShell (`flake.nix`) or manual install of: libsecret, gtk3, pkg-config, cmake, python3, build-essential (for `open62541` native build hook)
- Go 1.26+ for `tools/centroidx-manager/`
- TimescaleDB (PostgreSQL 17 + timescaledb extension) for integration tests

**Production Targets:**
- **Linux elinux/Wayland**: Docker image `ghcr.io/centroid-is/centroid-hmi` (Debian trixie-slim + Wayland stack), deployed via `docker-compose.yml` with Weston compositor
- **macOS arm64**: Signed `.dmg` (Developer ID Application, notarized via Apple Notary Service)
- **Windows x64**: Signed `.msix` (sideload certificate, published via `msix` tool)
- **Backend**: Dart CLI binary `main` in Docker image `ghcr.io/centroid-is/centroid-backend` (Debian bookworm-slim), run alongside TimescaleDB

---

*Stack analysis: 2026-05-05*
