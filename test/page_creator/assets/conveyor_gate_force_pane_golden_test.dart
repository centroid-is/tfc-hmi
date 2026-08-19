import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

/// Golden of the gate force pane with its tri-state Open / None / Close
/// selector — force-open feedback active, so the Open segment carries the
/// tertiary highlight.
void main() {
  group('gate force pane golden',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
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
