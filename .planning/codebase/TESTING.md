# Testing Patterns

**Analysis Date:** 2026-05-05

## Test Framework

**Runner (Dart-only packages):**
- `package:test` v1.25.0
- Config: `dart_test.yaml` per-package
- Packages: `tfc_dart`, `tfc_mcp_server`, `jbtm`, `modbus_client`, `modbus_client_tcp`

**Runner (Flutter packages):**
- `package:flutter_test` (bundled with Flutter SDK)
- Config: `dart_test.yaml` at repo root
- Packages: root `tfc` app, `centroidx_upgrader`

**Assertion Library:**
- Built-in `expect(actual, matcher)` from `package:test` / `flutter_test`
- Typed matchers: `isA<T>()`, `isA<T>().having(...)`, `containsPair(...)`, `hasLength(...)`, `contains(...)`, `isEmpty`, `isNull`, `isNotNull`, `isTrue`, `isFalse`, `throwsStateError`, `throwsA(isA<T>())`

**Run Commands:**
```bash
# Root Flutter package (tfc)
flutter test                              # Run all tests
flutter test test/chat/                   # Run specific directory
flutter test --update-goldens             # Update golden images

# Dart-only packages
dart test                                 # Run all tests in package
dart test test/core/state_man_test.dart   # Run specific file

# With concurrency control (tfc_dart is sequential for Docker integration tests)
cd packages/tfc_dart && dart test         # Uses concurrency: 1 from dart_test.yaml
cd packages/tfc_mcp_server && dart test  # Uses concurrency: 4 from dart_test.yaml
```

## Test File Organization

**Location:**
- Separate `test/` directory at root of each package — NOT co-located with source
- Root app: `test/` mirrors `lib/` structure (e.g., `lib/chat/` → `test/chat/`)
- `tfc_mcp_server`: `test/` has subdirectories per domain (`services/`, `tools/`, `parser/`, `compiler/`, `safety/`, `resources/`, `server/`, `smoke/`)
- `tfc_dart`: `test/` has `core/`, `converter/`, `integration/` subdirectories

**Naming:**
- `<source_file_name>_test.dart` (e.g., `alarm_service.dart` → `alarm_service_test.dart`)
- Exception: helper files in `test/helpers/` are NOT test files — they have no `_test` suffix (e.g., `mock_state_reader.dart`, `test_database.dart`)
- Helper files that ARE test files: `test/helpers/*_test.dart` (e.g., `mock_mcp_client_test.dart`) verify the helpers themselves

**Structure:**
```
test/                          # Root flutter test dir
├── chat/                      # Mirrors lib/chat/
│   ├── chat_widgets_test.dart
│   └── ...
├── helpers/                   # Shared test utilities
│   ├── test_helpers.dart      # Widget builders, fake stores, factory fns
│   └── mock_mcp_transport.dart
├── painter/
│   ├── goldens/               # Golden PNG files
│   └── auger_conveyor_test.dart
└── fixtures/                  # Static fixture files

packages/tfc_mcp_server/test/
├── helpers/                   # Shared helpers (NOT _test suffix)
│   ├── mock_state_reader.dart
│   ├── mock_alarm_reader.dart
│   ├── test_database.dart
│   └── ...
├── services/
├── tools/
└── ...
```

## Test Structure

**Suite Organization:**
```dart
void main() {
  // Group-level shared state
  late SomeService service;
  late MockDependency mock;

  setUp(() {
    mock = MockDependency();
    mock.setValue('key', 42);
    service = SomeService(mock);
  });

  tearDown(() async {
    await service.close();
  });

  group('SomeService', () {
    group('methodA', () {
      test('does X when Y', () {
        final result = service.methodA();
        expect(result, hasLength(1));
      });

      test('returns null for missing key', () {
        expect(service.methodA('nonexistent'), isNull);
      });
    });

    group('methodB', () {
      // ...
    });
  });
}
```

**Patterns:**
- `late` declarations for objects requiring `setUp` initialization
- `setUp` resets state for every test (never rely on cross-test state)
- `tearDown` / `addTearDown` for resource cleanup (DB close, subscription cancel)
- `addTearDown(container.dispose)` preferred over `tearDown` for ProviderContainer to scope teardown to the test
- Nested `group()` for sub-functionality (2 levels deep is common, 3+ rare)
- `group('methodName', ...)` inside `group('ClassName', ...)` for service tests

## Mocking

**Framework:** No external mocking library (no mockito, no mocktail). All mocks are hand-written.

**Patterns:**

Hand-written fakes implementing interfaces:
```dart
// Implement the abstract interface directly
class MockStateReader implements StateReader {
  final Map<String, dynamic> _values = {};

  void setValue(String key, dynamic value) => _values[key] = value;
  void clear() => _values.clear();

  @override
  Map<String, dynamic> get currentValues => Map.unmodifiable(_values);

  @override
  dynamic getValue(String key) => _values[key];

  @override
  List<String> get keys => _values.keys.toList();
}
```

`Fake` base class for partial stub (throw on unimplemented methods):
```dart
class _MockPlcCodeService extends Fake implements PlcCodeService {
  final bool _hasCode;
  _MockPlcCodeService({bool hasCode = false}) : _hasCode = hasCode;

  @override
  bool get hasCode => _hasCode;
  // Unimplemented methods throw automatically via Fake
}
```

Riverpod provider overrides (most common Flutter test pattern):
```dart
ProviderScope(
  overrides: [
    preferencesProvider.overrideWith((_) async => _createTestPreferences()),
    stateManProvider.overrideWith((ref) => throw StateError('No StateMan in tests')),
    databaseProvider.overrideWith((ref) async => null),
  ],
  child: MaterialApp(home: Scaffold(body: WidgetUnderTest())),
)
```

**What to Mock:**
- External I/O: databases (use in-memory SQLite via `ServerDatabase.inMemory()` or `AppDatabase.inMemoryForTest()`), network connections, secure storage
- Riverpod providers for heavy dependencies (StateMan, database) in widget tests
- Abstract interfaces (StateReader, AlarmReader, DrawingIndex) using hand-written implementations

**What NOT to Mock:**
- Business logic classes (test them directly with real instances and in-memory data)
- Simple data objects and models
- Pure functions

## Fixtures and Factories

**Test Data Factories (in `test/helpers/test_helpers.dart`):**
```dart
// Factory functions return real objects with sensible defaults
KeyMappings sampleKeyMappings() {
  return KeyMappings(nodes: {
    'temperature_sensor': KeyMappingEntry(
      opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'Temperature'),
    ),
  });
}

StateManConfig sampleStateManConfig() {
  return StateManConfig(opcua: [
    OpcUAConfig()
      ..endpoint = 'opc.tcp://localhost:4840'
      ..serverAlias = 'main_server',
  ]);
}
```

**In-memory Database Factory:**
```dart
// In tfc_mcp_server tests
ServerDatabase createTestDatabase() => ServerDatabase.inMemory();

// In root tfc tests
AppDatabase db = AppDatabase.inMemoryForTest();
```

**Fixture Files:**
- `packages/tfc_mcp_server/test/compiler/fixtures/` — XML/TwinCAT source files for parser tests
- `packages/tfc_mcp_server/test/fixtures/` — general fixture data
- `test/page_creator/assets/goldens/` — golden PNG files for page creator widget tests
- `test/painter/goldens/` — golden PNG files for custom painter tests
- `test/widgets/goldens/` — golden PNG files for widget tests

**Helper Functions (in `test/helpers/test_helpers.dart`):**
```dart
// Widget builders with provider overrides
Widget buildTestableKeyRepository({KeyMappings? keyMappings}) { ... }
Widget buildTestableServerConfig({StateManConfig? stateManConfig}) { ... }

// Async settlement helpers
Future<void> pumpAndLoad(WidgetTester tester, Widget widget) async { ... }
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
```

## Coverage

**Requirements:** None enforced — no coverage threshold configured.

**View Coverage:**
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Types

**Unit Tests (majority):**
- Test a single class or function in isolation
- Use in-memory dependencies (MockStateReader, in-memory DB)
- Fast, no I/O
- Examples: `packages/tfc_mcp_server/test/services/tag_service_test.dart`, `packages/tfc_dart/test/core/alarm_test.dart`

**Widget Tests:**
- Test Flutter widget trees with `flutter_test` and `WidgetTester`
- Use `ProviderScope(overrides: [...])` to replace heavy providers
- Use `pumpAndSettle()` for most interactions; use `pump()` + explicit delays when `CircularProgressIndicator` prevents settling
- Use semantic `ValueKey<String>` finders for interactive elements
- Examples: `test/chat/chat_widgets_test.dart`, `test/plc/plc_code_upload_dialog_test.dart`

**Golden Tests:**
- Visual regression via `expectLater(find.byKey(k), matchesGoldenFile('goldens/name.png'))`
- Skipped by default via `dart_test.yaml` tag: `tags: { golden: { skip: "Golden tests only run locally with --update-goldens" } }`
- Platform-guarded: `skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null`
- Update: `flutter test --update-goldens`
- Locations: `test/painter/goldens/`, `test/widgets/goldens/`, `test/page_creator/assets/goldens/`

**Integration Tests (tfc_dart):**
- Located in `packages/tfc_dart/test/integration/`
- Require Docker Compose (starts real PostgreSQL and OPC UA server)
- Use `startDockerCompose()` / `stopDockerCompose()` helpers in `test/integration/docker_compose.dart`
- Run sequentially (`concurrency: 1` in `dart_test.yaml`)
- Examples: `packages/tfc_dart/test/integration/database_integration_test.dart`

**Live Tests (hardware required):**
- Marked `skip: 'Live test -- requires Schneider PLC at $_host'`
- Never run in CI; used for local hardware validation
- Examples: `packages/tfc_dart/test/umas_live_test.dart`, `packages/tfc_dart/test/modbus_stateman_live_test.dart`

## Common Patterns

**Async Testing (Dart unit tests):**
```dart
test('emits values from raw stream to listeners', () async {
  ads = createADS();
  final raw = StreamController<DynamicValue>();
  ads.subscribe(raw.stream, null);

  final values = <DynamicValue>[];
  final sub = ads.stream.listen(values.add);

  raw.add(DynamicValue(value: 1));
  await Future.delayed(Duration.zero);  // Yield to event loop

  expect(values.length, 1);

  await sub.cancel();
  await raw.close();
});
```

**Async Testing (widget tests with indeterminate animations):**
```dart
// Use pump() + explicit delay instead of pumpAndSettle() when
// CircularProgressIndicator is present
await tester.pump();
await tester.pump(const Duration(milliseconds: 100));

// Or use the shared settle() helper from test_helpers.dart
await settle(tester);
```

**ProviderContainer Unit Tests (non-widget):**
```dart
test('initial state is idle', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final state = container.read(chatProvider);
  expect(state.status, ChatStatus.idle);
});
```

**Error Testing:**
```dart
test('resendLastValue fails after raw stream completes', () async {
  // ...setup...
  expect(
    () => ads.resendLastValue(),
    throwsStateError,
  );
});

test('throws ArgumentError for empty API key', () {
  expect(
    () => ClaudeProvider(apiKey: ''),
    throwsA(isA<ArgumentError>()),
  );
});
```

**Typed Matcher Chains (tfc_mcp_server parser tests):**
```dart
test('integer literal', () {
  final expr = parser.parseExpression('42');
  expect(expr, isA<IntLiteral>().having((e) => e.value, 'value', 42));
});
```

**Widget Finder by Semantic Key:**
```dart
await tester.tap(find.byKey(const ValueKey<String>('chat-close-button')));
await tester.pumpAndSettle();
expect(find.byKey(const ValueKey<String>('chat-config-section')), findsOneWidget);
```

**FlutterError Suppression (layout overflow noise in narrow test viewports):**
```dart
void suppressOverflow() {
  final origOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toString().contains('overflowed')) return;
    origOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = origOnError);
}
```

---

*Testing analysis: 2026-05-05*
