# Coding Conventions

**Analysis Date:** 2026-05-05

## Naming Patterns

**Files:**
- `snake_case.dart` for all Dart source files (e.g., `conveyor_gate.dart`, `state_man.dart`)
- Generated files: `<name>.g.dart` (json_serializable, riverpod_generator, drift)
- Test files: `<name>_test.dart` co-located in `test/` mirroring `lib/` structure
- Private test helpers/fakes prefixed with `_`: `_MockPlcCodeService`, `_FakeSecureStorage`

**Classes:**
- `PascalCase` for all classes, enums, mixins, typedefs
- Widget classes: suffix varies — `Widget`, `Page`, `Panel`, `Section`, `Tile`, `Dialog`, `Overlay` (no enforced single suffix)
- Private implementation classes (internal to a file): `_PascalCase` (e.g., `_TabbedDetailView`, `_CollapsibleSection`)
- Abstract interfaces: plain class name with abstract keyword (e.g., `StateReader`, `AlarmReader`, `LlmProvider`)
- Mock/fake implementations in tests: `Mock<X>` or `Fake<X>` or `_Mock<X>` pattern using `Fake` base class

**Functions and Methods:**
- `camelCase` for all functions, methods, and local variables
- Boolean-returning methods use `is`/`has`/`can` prefix (e.g., `hasCode`, `isError`, `isBroadcast`)
- Factory constructors: `ClassName.fromJson()`, `ClassName.create()`, `ClassName.inMemory()`, `ClassName.preview()`
- Async functions: no special prefix, `async` keyword is sufficient

**Variables:**
- `camelCase` for locals and instance fields
- Top-level constants: `kCamelCase` prefix (e.g., `kClaudeApiKey`, `kChatHistory`, `kSelectedProvider`)
- Dart `const` string sentinels without `k` prefix when used as JSON key names (e.g., `constAssetName = "asset_name"`)
- Riverpod providers: `camelCaseProvider` suffix (e.g., `stateManProvider`, `preferencesProvider`, `chatVisibleProvider`)

**Enums:**
- `PascalCase` for enum type; `camelCase` for values (e.g., `GateVariant.pneumatic`, `ChatStatus.idle`)
- Annotate with `@JsonEnum()` when serialized; use `@JsonKey(unknownEnumValue: ...)` on fields for forward compatibility

## Code Style

**Formatting:**
- Standard `dart format` (no custom config; enforced implicitly via CI)
- No explicit `.prettierrc` — Dart analyzer enforces style

**Linting:**
- Root package: `package:flutter_lints/flutter.yaml` (via `analysis_options.yaml`)
- Dart-only packages (`tfc_dart`, `jbtm`, `modbus_client*`): `package:lints/recommended.yaml`
- `tfc_mcp_server` adds stricter rules: `strict-casts: true`, `strict-raw-types: true`, `avoid_print: error`
- `avoid_print` is a lint error in `tfc_mcp_server` — never use `print()` there

## Import Organization

**Order (within each file):**
1. `dart:*` core library imports
2. `package:*` external package imports (alphabetical within group)
3. Local package imports (`package:tfc_dart/...`, `package:tfc/...`)
4. Relative imports (`'../core/preferences.dart'`, `'./common.dart'`)
5. `part` directives last (`part 'file.g.dart';`)

**Example from `lib/providers/state_man.dart`:**
```dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tfc_dart/core/state_man.dart';
import 'preferences.dart';
import 'collector.dart';

part 'state_man.g.dart';
```

**Path Aliases:**
- None. Packages are imported by package name (e.g., `package:tfc/...`, `package:tfc_dart/...`)

## Code Generation Patterns

**json_serializable:**
- Annotate class with `@JsonSerializable()` or `@JsonSerializable(explicitToJson: true)`
- Annotate enums with `@JsonEnum()`
- Always provide `factory ClassName.fromJson(Map<String, dynamic> json)` and `toJson()` methods
- Use `@JsonKey(unknownEnumValue: EnumType.fallback)` on enum fields to handle unknown values in JSON
- Use `@JsonKey(includeFromJson: false, includeToJson: false)` for computed/transient fields
- File must have `part 'filename.g.dart';` directive
- Run codegen: `dart run build_runner build` or `flutter pub run build_runner build`

**riverpod_generator:**
- Use `@Riverpod(keepAlive: true)` for long-lived app-level providers (network connections, DB, preferences)
- Use `@riverpod` for ephemeral/scoped providers
- Annotate the provider function (not a class) for simple async providers:
  ```dart
  @Riverpod(keepAlive: true)
  Future<Preferences> preferences(Ref ref) async { ... }
  ```
- Generated provider name: `XxxxProvider` from function `xxxx`
- Manual (non-generated) providers for UI state: `StateProvider<T>`, `FutureProvider<T>`, `Provider<T>`
- Manual `StateProvider` for simple boolean flags (e.g., `chatVisibleProvider`, `drawingVisibleProvider`)

**drift (ORM):**
- `build.yaml` configures: `store_date_time_values_as_text: true`, dialects: `[postgres, sqlite]`
- Generated files: `*.g.dart` alongside the database class file

## Error Handling

**Patterns:**
- `throw ArgumentError('message')` for invalid constructor arguments (e.g., empty API keys)
- `throw Exception('message')` for runtime failures in service code
- `throw StateError('...')` used in tests to stub providers that should not be reached
- `try`/`catch` in provider initializers; errors written to `stderr.writeln(...)` before rethrow
- Widget layer: `when(data:, loading:, error:)` on AsyncValue for provider states
- No global error boundary beyond Flutter's default; individual providers handle their own errors
- Use `rethrow` to propagate exceptions after logging (don't swallow)

**Logging:**
- `package:logger` (`Logger` class) for structured logging in library/service code
- `Logger().e(...)` for errors, `Logger().w(...)` for warnings
- `stderr.writeln(...)` in provider glue code (not library code) for initialization errors
- `io.stderr.writeln(...)` in provider files that import `dart:io` as `io`
- Never use `print()` in `tfc_mcp_server` (lint error); use `Logger` instead
- No centralized log configuration beyond `lib/core/log_config.dart` (environment-variable-driven log levels for OPC UA)

## Comments

**When to Comment:**
- Class-level `///` doc comments on all public classes and abstract interfaces (mandatory in `tfc_mcp_server`)
- Method-level `///` doc comments on non-obvious public methods, especially those with `Throws` behavior
- Inline `//` comments for non-obvious logic; `// This is the bug:` or `// Simulates:` in test code for intent
- Multi-line `///` class doc comments describe design decisions and cross-cutting concerns

**Example (from `packages/tfc_mcp_server/lib/src/interfaces/state_reader.dart`):**
```dart
/// Read-only interface for accessing live system state values.
///
/// In production, this is backed by IPC to the Flutter app's StateMan.
/// In tests, [MockStateReader] provides an in-memory implementation.
abstract class StateReader {
  /// All current key-value pairs in the state system.
  Map<String, dynamic> get currentValues;
}
```

## Function Design

**Size:** No enforced limit, but complex widgets are split into private `_ClassName` subclasses within the same file. Extracted when a `build()` method grows past ~50 lines or needs its own state.

**Parameters:**
- Named parameters used throughout (especially for config/model constructors)
- Required named parameters: `required this.field` in constructors
- Optional named parameters with defaults for configuration (e.g., `bool hasCode = false`)

**Return Values:**
- Nullable return `T?` when absence is a valid state (not an error)
- `null` return to signal "not found" (e.g., `getTagValue` returns `Map?`)
- Avoid returning empty sentinels; prefer null or throw

## Widget Design

**Base classes used:**
- `StatelessWidget` — pure UI with no mutable state
- `StatefulWidget` + `State<T>` — widgets with local mutable state (e.g., form fields, collapsible sections)
- `ConsumerWidget` — stateless widgets that read Riverpod providers
- `ConsumerStatefulWidget` + `ConsumerState<T>` — stateful widgets that also read providers

**Keys:**
- `ValueKey<String>('kebab-case-id')` for semantic widget keys used in tests (e.g., `'chat-close-button'`, `'chat-message-input'`, `'chat-title-picker'`)
- Key strings use kebab-case with domain prefix (e.g., `'chat-*'`, `'batch-*'`)
- Keys on interactive elements allow test finders to locate widgets reliably

## Module Design

**Exports:**
- Packages expose a single barrel entry point (e.g., `package:tfc_mcp_server/tfc_mcp_server.dart`)
- Internal implementation in `lib/src/` is not re-exported unless explicitly needed
- No barrel `index.dart` within `lib/` of the main `tfc` app — import directly by path

**Package boundaries:**
- `tfc_dart`: core Dart-only business logic (StateMan, database, alarms, converters)
- `tfc_mcp_server`: MCP server with strict linting (no `print`, strict casts/raw types)
- `jbtm`: M2400 device protocol
- `modbus_client`, `modbus_client_tcp`: Modbus protocol (local forks)
- `centroidx_upgrader`: version management

---

*Convention analysis: 2026-05-05*
