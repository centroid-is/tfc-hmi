import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../../helpers/golden_tolerance.dart';

/// Loads a real font so the pane's labels render as letterforms instead of
/// the test font's solid boxes — same pattern as `third_party_golden_test`.
Future<void> loadRealFont() async {
  final data = File('lib/fonts/roboto-mono/RobotoMono-Regular.ttf')
      .readAsBytesSync()
      .buffer
      .asByteData();
  final loader = FontLoader('Roboto')..addFont(Future.value(data));
  await loader.load();
}

/// Golden of the gate force pane with its tri-state Open / None / Close
/// selector — force-open feedback active, so the Open segment carries the
/// tertiary highlight.
void main() {
  // This golden is a full 800×600 app surface with real text, so the
  // cross-Flutter-version antialiasing drift the default 0.01% tolerance
  // absorbs on small painter goldens is not enough here (CI measured 0.03%
  // on the text-free version). A real regression — a missing segment or a
  // moved highlight — shifts well over 1% of the frame.
  useTolerantGoldenComparator(tolerance: 0.002);

  group('gate force pane golden',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    setUpAll(loadRealFont);
    tearDown(closeSidePane);

    testWidgets('force pane with open force active', (tester) async {
      final fake = _FakeStateMan();
      fake.push('gate/state', true);
      fake.push('gate/fo_fb', true);
      fake.push('gate/fc_fb', false);

      final config = ConveyorGateConfig(
        gateVariant: GateVariant.pusher,
        stateKey: 'gate/state',
        forceOpenKey: 'gate/force_open',
        forceCloseKey: 'gate/force_close',
        forceOpenFeedbackKey: 'gate/fo_fb',
        forceCloseFeedbackKey: 'gate/fc_fb',
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: ConveyorGate(config: config),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(ConveyorGate));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conveyor_gate_force_pane.png'),
      );
    });
  });
}

class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};

  void push(String key, bool value) {
    _streams
        .putIfAbsent(key, () => BehaviorSubject<DynamicValue>())
        .add(DynamicValue(value: value, typeId: NodeId.boolean));
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    return _streams
        .putIfAbsent(key, () => BehaviorSubject<DynamicValue>())
        .stream;
  }

  @override
  Future<void> write(String key, DynamicValue value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
    );
  }
}
