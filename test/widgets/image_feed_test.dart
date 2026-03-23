import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/dynamic_value.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';

import 'package:tfc/page_creator/assets/image_feed.dart';
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
  String image =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
  String label = 'cat',
  double confidence = 0.95,
  int latencyMs = 42,
}) {
  return jsonEncode({
    'image': image,
    'label': label,
    'confidence': confidence,
    'latency_ms': latencyMs,
  });
}

Future<(StateMan, FakeDeviceClient)> _createTestStateMan(
    List<String> keys) async {
  final fake = FakeDeviceClient();
  // Pre-create controllers so canSubscribe works
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
  required ImageFeedConfig config,
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
          child: ImageFeedWidget(config: config),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ImageFeedConfig', () {
    test('JSON round-trip serialization', () {
      final config = ImageFeedConfig(
        key: 'plant/camera1/inference',
        controlKey: 'plant/camera1/pause',
        maxImages: 12,
        gridColumns: 4,
        showConfidence: false,
        showLabel: true,
        showNewBadge: false,
      );

      final json = config.toJson();
      final restored = ImageFeedConfig.fromJson(json);

      expect(restored.key, 'plant/camera1/inference');
      expect(restored.controlKey, 'plant/camera1/pause');
      expect(restored.maxImages, 12);
      expect(restored.gridColumns, 4);
      expect(restored.showConfidence, false);
      expect(restored.showLabel, true);
      expect(restored.showNewBadge, false);
      expect(restored.displayName, 'Image Feed');
      expect(restored.category, 'Monitoring');
    });

    test('JSON round-trip with defaults', () {
      final config = ImageFeedConfig(key: 'test/key');
      final json = config.toJson();
      final restored = ImageFeedConfig.fromJson(json);

      expect(restored.key, 'test/key');
      expect(restored.controlKey, isNull);
      expect(restored.maxImages, 9);
      expect(restored.gridColumns, 3);
      expect(restored.showConfidence, true);
      expect(restored.showLabel, true);
      expect(restored.showNewBadge, true);
    });

    test('preview() constructor has sensible defaults', () {
      final config = ImageFeedConfig.preview();
      expect(config.key, isNotEmpty);
      expect(config.maxImages, 9);
      expect(config.gridColumns, 3);
      expect(config.displayName, 'Image Feed');
      expect(config.category, 'Monitoring');
    });

    test('assetName matches type name', () {
      final config = ImageFeedConfig(key: 'k');
      expect(config.assetName, 'ImageFeedConfig');
    });
  });

  group('ImageFeedWidget', () {
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

    testWidgets('renders empty grid initially', (tester) async {
      await init(['cam/feed']);
      final config = ImageFeedConfig(key: 'cam/feed');

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('adding image data shows image in grid', (tester) async {
      await init(['cam/feed']);
      final config = ImageFeedConfig(key: 'cam/feed', showLabel: true);

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      fake.emit('cam/feed', _makePayload(label: 'cat', confidence: 0.95));
      await tester.pumpAndSettle();

      expect(find.text('cat'), findsOneWidget);
    });

    testWidgets('grid respects maxImages limit', (tester) async {
      await init(['cam/feed']);
      final config = ImageFeedConfig(key: 'cam/feed', maxImages: 3);

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        fake.emit('cam/feed', _makePayload(label: 'img$i'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Oldest 2 removed, newest 3 remain
      expect(find.text('img0'), findsNothing);
      expect(find.text('img1'), findsNothing);
      expect(find.text('img2'), findsOneWidget);
      expect(find.text('img3'), findsOneWidget);
      expect(find.text('img4'), findsOneWidget);
    });

    testWidgets('confidence color coding is correct', (tester) async {
      await init(['cam/feed']);
      final config = ImageFeedConfig(
        key: 'cam/feed',
        showConfidence: true,
        showLabel: false,
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Green: >= 80%
      fake.emit(
          'cam/feed', _makePayload(label: 'high', confidence: 0.90));
      await tester.pumpAndSettle();
      expect(find.text('90%'), findsOneWidget);

      // Yellow: >= 50% and < 80%
      fake.emit(
          'cam/feed', _makePayload(label: 'mid', confidence: 0.60));
      await tester.pumpAndSettle();
      expect(find.text('60%'), findsOneWidget);

      // Red: < 50%
      fake.emit(
          'cam/feed', _makePayload(label: 'low', confidence: 0.30));
      await tester.pumpAndSettle();
      expect(find.text('30%'), findsOneWidget);
    });

    testWidgets('pause via controlKey stops adding new images',
        (tester) async {
      await init(['cam/feed', 'cam/pause']);
      final config = ImageFeedConfig(
        key: 'cam/feed',
        controlKey: 'cam/pause',
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Add one image
      fake.emit('cam/feed', _makePayload(label: 'before'));
      await tester.pumpAndSettle();
      expect(find.text('before'), findsOneWidget);

      // Pause
      fake.emitRaw('cam/pause', DynamicValue(value: false));
      await tester.pumpAndSettle();

      // Try adding while paused
      fake.emit('cam/feed', _makePayload(label: 'during_pause'));
      await tester.pumpAndSettle();

      expect(find.text('during_pause'), findsNothing);
      expect(find.text('PAUSED'), findsOneWidget);
    });

    testWidgets('resume via controlKey allows new images', (tester) async {
      await init(['cam/feed', 'cam/pause']);
      final config = ImageFeedConfig(
        key: 'cam/feed',
        controlKey: 'cam/pause',
      );

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Pause then resume
      fake.emitRaw('cam/pause', DynamicValue(value: false));
      await tester.pumpAndSettle();
      fake.emitRaw('cam/pause', DynamicValue(value: true));
      await tester.pumpAndSettle();

      // Add image after resume
      fake.emit('cam/feed', _makePayload(label: 'after_resume'));
      await tester.pumpAndSettle();

      expect(find.text('after_resume'), findsOneWidget);
      expect(find.text('PAUSED'), findsNothing);
    });

    testWidgets('malformed payload does not crash widget', (tester) async {
      await init(['cam/feed']);
      final config = ImageFeedConfig(key: 'cam/feed');

      await tester.pumpWidget(_buildTestWidget(
        config: config,
        stateMan: stateMan,
      ));
      await tester.pumpAndSettle();

      // Send malformed data
      fake.emit('cam/feed', 'not valid json!!!');
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Valid payload after malformed still works
      fake.emit('cam/feed', _makePayload(label: 'recovered'));
      await tester.pumpAndSettle();
      expect(find.text('recovered'), findsOneWidget);
    });
  });
}
