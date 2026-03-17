import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';

import 'package:tfc/page_creator/assets/inference_log.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/providers/state_man.dart';

// ---------------------------------------------------------------------------
// FakeDeviceClient — controllable device client for testing
// ---------------------------------------------------------------------------

class FakeDeviceClient extends DeviceClient {
  final Map<String, StreamController<DynamicValue>> _controllers = {};

  StreamController<DynamicValue> controllerFor(String key) =>
      _controllers.putIfAbsent(
          key, () => StreamController<DynamicValue>.broadcast());

  void emit(String key, String jsonPayload) {
    controllerFor(key).add(DynamicValue(value: jsonPayload));
  }

  void emitRaw(String key, DynamicValue dv) {
    controllerFor(key).add(dv);
  }

  @override
  Set<String> get subscribableKeys => _controllers.keys.toSet();

  @override
  bool canSubscribe(String key) => true;

  @override
  Stream<DynamicValue> subscribe(String key) => controllerFor(key).stream;

  @override
  DynamicValue? read(String key) => null;

  @override
  ConnectionStatus get connectionStatus => ConnectionStatus.connected;

  @override
  Stream<ConnectionStatus> get connectionStream =>
      Stream.value(ConnectionStatus.connected);

  @override
  void connect() {}

  @override
  Future<void> write(String key, DynamicValue value) async {}

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _makePayload({
  String label = 'cat',
  double confidence = 0.95,
  int latencyMs = 42,
  String? image,
  int? id,
}) {
  return jsonEncode({
    if (image != null) 'image': image,
    'label': label,
    'confidence': confidence,
    'latency_ms': latencyMs,
    if (id != null) 'id': id,
  });
}

Future<(StateMan, FakeDeviceClient)> _createTestStateMan(
    List<String> keys) async {
  final fake = FakeDeviceClient();
  for (final k in keys) {
    fake.controllerFor(k);
  }

  final keyMappings = KeyMappings(nodes: {
    for (final k in keys)
      k: KeyMappingEntry(mqttNode: MqttNodeConfig(topic: k)),
  });

  final stateMan = await StateMan.create(
    config: StateManConfig(opcua: [], jbtm: [], modbus: [], mqtt: []),
    keyMappings: keyMappings,
    deviceClients: [fake],
  );
  return (stateMan, fake);
}

Widget _buildTestWidget({
  required InferenceLogConfig config,
  required StateMan stateMan,
}) {
  return ProviderScope(
    overrides: [
      stateManProvider.overrideWith((ref) async => stateMan),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 600,
          child: InferenceLogWidget(config: config),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('InferenceLogConfig', () {
    test('JSON round-trip serialization', () {
      final config = InferenceLogConfig(
        key: 'inference.result',
        controlKey: 'inference.control.pause',
        maxEntries: 20,
        showThumbnail: false,
        showConfidenceBar: true,
        showLatency: false,
      );

      final json = config.toJson();
      final restored = InferenceLogConfig.fromJson(json);

      expect(restored.key, 'inference.result');
      expect(restored.controlKey, 'inference.control.pause');
      expect(restored.maxEntries, 20);
      expect(restored.showThumbnail, false);
      expect(restored.showConfidenceBar, true);
      expect(restored.showLatency, false);
      expect(restored.displayName, 'Inference Log');
      expect(restored.category, 'Monitoring');
    });

    test('JSON round-trip with defaults', () {
      final config = InferenceLogConfig(key: 'test/key');
      final json = config.toJson();
      final restored = InferenceLogConfig.fromJson(json);

      expect(restored.key, 'test/key');
      expect(restored.controlKey, isNull);
      expect(restored.maxEntries, 30);
      expect(restored.showThumbnail, true);
      expect(restored.showConfidenceBar, true);
      expect(restored.showLatency, true);
    });

    test('preview() constructor has sensible defaults', () {
      final config = InferenceLogConfig.preview();
      expect(config.key, isNotEmpty);
      expect(config.maxEntries, 30);
      expect(config.showThumbnail, true);
      expect(config.showConfidenceBar, true);
      expect(config.showLatency, true);
      expect(config.displayName, 'Inference Log');
      expect(config.category, 'Monitoring');
    });

    test('assetName matches type name', () {
      final config = InferenceLogConfig(key: 'k');
      expect(config.assetName, 'InferenceLogConfig');
    });
  });

  group('AssetRegistry with InferenceLogConfig', () {
    test('createDefaultAssetByName returns InferenceLogConfig', () {
      final asset =
          AssetRegistry.createDefaultAssetByName('InferenceLogConfig');
      expect(asset, isNotNull);
      expect(asset, isA<InferenceLogConfig>());
    });

    test('parse succeeds with full InferenceLogConfig JSON', () {
      final assets = AssetRegistry.parse({
        'assets': [
          {
            'asset_name': 'InferenceLogConfig',
            'key': 'inference.result',
            'max_entries': 20,
            'show_thumbnail': true,
            'show_confidence_bar': true,
            'show_latency': true,
            'coordinates': {'x': 0.5, 'y': 0.5},
            'size': {'width': 0.4, 'height': 0.8},
          }
        ],
      });
      expect(assets, hasLength(1));
      expect(assets.first, isA<InferenceLogConfig>());
      expect((assets.first as InferenceLogConfig).key, 'inference.result');
      expect((assets.first as InferenceLogConfig).maxEntries, 20);
    });
  });

  group('InferenceLogWidget', () {
    late StateMan stateMan;
    late FakeDeviceClient fake;

    Future<void> init(List<String> keys) async {
      final result = await _createTestStateMan(keys);
      stateMan = result.$1;
      fake = result.$2;
    }

    tearDown(() async {
      fake.dispose();
      await stateMan.close();
    });

    testWidgets('empty log renders placeholder', (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(key: 'inference/result');

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Should show some kind of empty state
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('adding entries via stream shows rows', (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(key: 'inference/result');

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      fake.emit('inference/result',
          _makePayload(label: 'cat', confidence: 0.95, latencyMs: 42));
      await tester.pumpAndSettle();

      expect(find.text('cat'), findsOneWidget);
    });

    testWidgets('max entries respected (oldest removed)', (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(key: 'inference/result', maxEntries: 3);

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        fake.emit('inference/result', _makePayload(label: 'item$i'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Oldest 2 removed, newest 3 remain
      expect(find.text('item0'), findsNothing);
      expect(find.text('item1'), findsNothing);
      expect(find.text('item2'), findsOneWidget);
      expect(find.text('item3'), findsOneWidget);
      expect(find.text('item4'), findsOneWidget);
    });

    testWidgets('new entries appear at top', (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(key: 'inference/result');

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      fake.emit('inference/result', _makePayload(label: 'first'));
      await tester.pumpAndSettle();
      fake.emit('inference/result', _makePayload(label: 'second'));
      await tester.pumpAndSettle();

      // The most recent entry ('second') should appear before 'first'
      final firstPos = tester.getTopLeft(find.text('first'));
      final secondPos = tester.getTopLeft(find.text('second'));
      expect(secondPos.dy, lessThan(firstPos.dy));
    });

    testWidgets('confidence bar color coding correct', (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(
        key: 'inference/result',
        showConfidenceBar: true,
        maxEntries: 3,
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Green: >= 80%
      fake.emit('inference/result',
          _makePayload(label: 'high', confidence: 0.90));
      await tester.pumpAndSettle();

      // Yellow: >= 50% and < 80%
      fake.emit('inference/result',
          _makePayload(label: 'mid', confidence: 0.60));
      await tester.pumpAndSettle();

      // Red: < 50%
      fake.emit('inference/result',
          _makePayload(label: 'low', confidence: 0.30));
      await tester.pumpAndSettle();

      // Verify confidence percentages are displayed
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
    });

    testWidgets('status badge text/color correct for ok/low/error',
        (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(
        key: 'inference/result',
        maxEntries: 3,
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // ok: >= 75%
      fake.emit('inference/result',
          _makePayload(label: 'good', confidence: 0.80));
      await tester.pumpAndSettle();
      expect(find.text('ok'), findsOneWidget);

      // low: >= 50% and < 75%
      fake.emit('inference/result',
          _makePayload(label: 'medium', confidence: 0.60));
      await tester.pumpAndSettle();
      expect(find.text('low'), findsOneWidget);

      // error: < 50%
      fake.emit('inference/result',
          _makePayload(label: 'bad', confidence: 0.30));
      await tester.pumpAndSettle();
      expect(find.text('error'), findsOneWidget);
    });

    testWidgets('pause via controlKey stops new entries', (tester) async {
      await init(['inference/result', 'inference/pause']);
      final config = InferenceLogConfig(
        key: 'inference/result',
        controlKey: 'inference/pause',
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Add one entry
      fake.emit(
          'inference/result', _makePayload(label: 'before'));
      await tester.pumpAndSettle();
      expect(find.text('before'), findsOneWidget);

      // Pause
      fake.emitRaw('inference/pause', DynamicValue(value: false));
      await tester.pumpAndSettle();

      // Try adding while paused
      fake.emit('inference/result',
          _makePayload(label: 'during_pause'));
      await tester.pumpAndSettle();

      expect(find.text('during_pause'), findsNothing);
      expect(find.text('PAUSED'), findsOneWidget);
    });

    testWidgets('resume via controlKey allows entries', (tester) async {
      await init(['inference/result', 'inference/pause']);
      final config = InferenceLogConfig(
        key: 'inference/result',
        controlKey: 'inference/pause',
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Pause then resume
      fake.emitRaw('inference/pause', DynamicValue(value: false));
      await tester.pumpAndSettle();
      fake.emitRaw('inference/pause', DynamicValue(value: true));
      await tester.pumpAndSettle();

      // Add entry after resume
      fake.emit('inference/result',
          _makePayload(label: 'after_resume'));
      await tester.pumpAndSettle();

      expect(find.text('after_resume'), findsOneWidget);
      expect(find.text('PAUSED'), findsNothing);
    });

    testWidgets('malformed payload does not crash widget', (tester) async {
      await init(['inference/result']);
      final config = InferenceLogConfig(key: 'inference/result');

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Send malformed data
      fake.emit('inference/result', 'not valid json!!!');
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Valid payload after malformed still works
      fake.emit('inference/result', _makePayload(label: 'recovered'));
      await tester.pumpAndSettle();
      expect(find.text('recovered'), findsOneWidget);
    });
  });
}
