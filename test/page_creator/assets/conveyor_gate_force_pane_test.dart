import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

/// Widget tests for the gate force pane's tri-state Open / None / Close
/// selector.
///
/// Contract under test:
///   - tap on the gate opens the SidePane with the three force segments
///   - 'None' writes false to BOTH force keys (the unforce path — the old
///     two-button pane could only ever write true)
///   - 'Open' clears force-close BEFORE setting force-open (and vice versa)
///     so the PLC never sees both force commands high at once
///   - segment selection tracks the feedback keys; without feedback keys no
///     segment is highlighted
///   - a segment whose write key is unconfigured is disabled, and 'None'
///     only writes the keys that exist
void main() {
  Widget wrap({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Future<void> openPane(WidgetTester tester) async {
    await tester.tap(find.byType(ConveyorGate));
    await tester.pumpAndSettle();
  }

  Finder forceSegmented() => find.byWidgetPredicate(
        (w) => w is SegmentedButton && w.segments.length == 3,
      );

  // The pane chrome has its own 'Close' text, so segment lookups must be
  // scoped to the SegmentedButton.
  Finder segmentText(String label) => find.descendant(
        of: forceSegmented(),
        matching: find.text(label),
      );

  tearDown(closeSidePane);

  ConveyorGateConfig pusherConfig({
    String stateKey = '',
    String openKey = 'gate/force_open',
    String closeKey = 'gate/force_close',
    String openFbKey = '',
    String closeFbKey = '',
  }) {
    return ConveyorGateConfig(
      gateVariant: GateVariant.pusher,
      stateKey: stateKey,
      forceOpenKey: openKey,
      forceCloseKey: closeKey,
      forceOpenFeedbackKey: openFbKey,
      forceCloseFeedbackKey: closeFbKey,
    );
  }

  Widget gate(ConveyorGateConfig config, _FakeStateMan fake) {
    return wrap(
      overrides: [stateManProvider.overrideWith((_) async => fake)],
      child: SizedBox(
        width: 100,
        height: 100,
        child: ConveyorGate(config: config),
      ),
    );
  }

  group('force pane segments', () {
    testWidgets('tap on gate opens pane with Open / None / Close',
        (tester) async {
      final fake = _FakeStateMan();
      await tester.pumpWidget(gate(pusherConfig(), fake));
      await openPane(tester);

      expect(find.byType(SidePane), findsOneWidget);
      expect(forceSegmented(), findsOneWidget);
      expect(segmentText('Open'), findsOneWidget);
      expect(segmentText('None'), findsOneWidget);
      expect(segmentText('Close'), findsOneWidget);
    });

    testWidgets('None writes false to both force keys (unforce)',
        (tester) async {
      final fake = _FakeStateMan();
      await tester.pumpWidget(gate(pusherConfig(), fake));
      await openPane(tester);

      await tester.tap(segmentText('None'));
      await tester.pump();

      expect(
        fake.writes.map((w) => (w.key, w.value)),
        containsAll([
          ('gate/force_open', false),
          ('gate/force_close', false),
        ]),
      );
      expect(fake.writes.any((w) => w.value), isFalse,
          reason: 'None must never assert a force');
    });

    testWidgets('Open clears force-close before asserting force-open',
        (tester) async {
      final fake = _FakeStateMan();
      await tester.pumpWidget(gate(pusherConfig(), fake));
      await openPane(tester);

      await tester.tap(segmentText('Open'));
      await tester.pump();

      expect(
        fake.writes.map((w) => (w.key, w.value)).toList(),
        [
          ('gate/force_close', false),
          ('gate/force_open', true),
        ],
      );
    });

    testWidgets('Close clears force-open before asserting force-close',
        (tester) async {
      final fake = _FakeStateMan();
      await tester.pumpWidget(gate(pusherConfig(), fake));
      await openPane(tester);

      await tester.tap(segmentText('Close'));
      await tester.pump();

      expect(
        fake.writes.map((w) => (w.key, w.value)).toList(),
        [
          ('gate/force_open', false),
          ('gate/force_close', true),
        ],
      );
    });
  });

  group('feedback-driven selection', () {
    testWidgets('open feedback highlights the Open segment', (tester) async {
      final fake = _FakeStateMan();
      fake.push('gate/fo_fb', true);
      fake.push('gate/fc_fb', false);
      await tester.pumpWidget(gate(
        pusherConfig(openFbKey: 'gate/fo_fb', closeFbKey: 'gate/fc_fb'),
        fake,
      ));
      await openPane(tester);

      final seg = tester.widget<SegmentedButton>(forceSegmented());
      expect(seg.selected.length, 1);
      expect(seg.selected.first.toString(), endsWith('.open'));
    });

    testWidgets('no feedback active highlights None', (tester) async {
      final fake = _FakeStateMan();
      fake.push('gate/fo_fb', false);
      fake.push('gate/fc_fb', false);
      await tester.pumpWidget(gate(
        pusherConfig(openFbKey: 'gate/fo_fb', closeFbKey: 'gate/fc_fb'),
        fake,
      ));
      await openPane(tester);

      final seg = tester.widget<SegmentedButton>(forceSegmented());
      expect(seg.selected.length, 1);
      expect(seg.selected.first.toString(), endsWith('.none'));
    });

    testWidgets('without feedback keys no segment is highlighted',
        (tester) async {
      final fake = _FakeStateMan();
      await tester.pumpWidget(gate(pusherConfig(), fake));
      await openPane(tester);

      final seg = tester.widget<SegmentedButton>(forceSegmented());
      expect(seg.selected, isEmpty,
          reason: 'force state is unknown without feedback keys — '
              'the selector must not claim None');
    });
  });

  group('partial key configuration', () {
    testWidgets('missing close key disables Close; None writes only open key',
        (tester) async {
      final fake = _FakeStateMan();
      await tester.pumpWidget(gate(pusherConfig(closeKey: ''), fake));
      await openPane(tester);

      final seg = tester.widget<SegmentedButton>(forceSegmented());
      expect(seg.segments[2].enabled, isFalse,
          reason: 'Close segment must be disabled without a close key');

      await tester.tap(segmentText('None'));
      await tester.pump();

      expect(
        fake.writes.map((w) => (w.key, w.value)).toList(),
        [('gate/force_open', false)],
        reason: 'unforce must skip unconfigured keys',
      );
    });
  });

  group('pane header', () {
    testWidgets('active open force shows a Forced open chip', (tester) async {
      final fake = _FakeStateMan();
      fake.push('gate/state', true);
      fake.push('gate/fo_fb', true);
      fake.push('gate/fc_fb', false);
      await tester.pumpWidget(gate(
        pusherConfig(
          stateKey: 'gate/state',
          openFbKey: 'gate/fo_fb',
          closeFbKey: 'gate/fc_fb',
        ),
        fake,
      ));
      await openPane(tester);

      expect(
        find.descendant(
          of: find.byType(PaneStatusChip),
          matching: find.text('Forced open'),
        ),
        findsOneWidget,
        reason: 'an active force must be visible in the header, '
            'not only as a segment highlight',
      );
    });

    testWidgets('plain open state shows an Open chip', (tester) async {
      final fake = _FakeStateMan();
      fake.push('gate/state', true);
      fake.push('gate/fo_fb', false);
      fake.push('gate/fc_fb', false);
      await tester.pumpWidget(gate(
        pusherConfig(
          stateKey: 'gate/state',
          openFbKey: 'gate/fo_fb',
          closeFbKey: 'gate/fc_fb',
        ),
        fake,
      ));
      await openPane(tester);

      expect(
        find.descendant(
          of: find.byType(PaneStatusChip),
          matching: find.text('Open'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('subtitle is the variant, never the raw key', (tester) async {
      final fake = _FakeStateMan();
      fake.push('gate/state', false);
      await tester.pumpWidget(gate(
        pusherConfig(stateKey: 'gate/state'),
        fake,
      ));
      await openPane(tester);

      expect(find.text('Pusher gate'), findsOneWidget);
      expect(find.text('gate/state'), findsNothing,
          reason: 'panes show values, not wiring — '
              'no raw OPC UA key names in the pane');
    });
  });
}

class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};
  final List<_Write> writes = [];

  void push(String key, bool value) {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    s.add(DynamicValue(value: value, typeId: NodeId.boolean));
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    return s.stream;
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    writes.add(_Write(key, value.asBool));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
    );
  }
}

class _Write {
  final String key;
  final bool value;
  _Write(this.key, this.value);
}
