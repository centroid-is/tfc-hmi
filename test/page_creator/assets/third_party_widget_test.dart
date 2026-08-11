import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/third_party.dart';

void main() {
  // ProviderScope + MaterialApp so showDialog has a Navigator. No provider
  // overrides — these tests exercise the stale path (no value from the stream
  // yet), so no real StateMan is needed. Mirrors `sensor_widget_test.dart`.
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  LEDPainter ledPainterOf(WidgetTester tester) {
    final paints = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter is LEDPainter);
    expect(paints, hasLength(1),
        reason: 'Exactly one run-status LED per asset.');
    return paints.single.painter! as LEDPainter;
  }

  group('Run-status LED', () {
    testWidgets('renders the unknown state when no run key is configured',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: '');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      // A null colour is LEDPainter's unknown state (grey + "!"). Claiming
      // "stopped" when we simply have no signal would be a lie on an HMI.
      expect(ledPainterOf(tester).color, isNull);
    });

    testWidgets('renders the unknown state while the stream has no value',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: 'ST301.MV01.Running');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      expect(ledPainterOf(tester).color, isNull);
    });

    testWidgets('body resolves running and stopped to the configured colours',
        (tester) async {
      // ThirdPartyEquipmentBody is the seam the live widget feeds — asserting
      // here keeps the colour mapping covered without a StateMan.
      for (final entry in {
        Colors.green: 'running',
        Colors.red: 'stopped',
      }.entries) {
        await tester.pumpWidget(wrap(ThirdPartyEquipmentBody(
          painter: thirdPartyPainterFor(ThirdPartyEquipmentKind.multivac,
              color: Colors.blueGrey, strokeWidth: 2),
          paintSize: const Size(300, 100),
          ledColor: entry.key,
        )));
        expect(ledPainterOf(tester).color, entry.key,
            reason: 'LED must show the ${entry.value} colour.');
      }
    });
  });

  group('Stream lifecycle', () {
    testWidgets('the stream is hoisted once and survives rebuilds',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: 'ST301.MV01.Running');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      final dynamic state = tester.state(find.byType(ThirdPartyEquipment));
      final first = state.debugRunStream;
      expect(first, isNotNull);

      // Rebuild with the same config instance — the editor mutates configs in
      // place, so this is the common case. Recreating the stream here would
      // mean an OPC UA monitored-item create/cancel every frame.
      await tester.pump();
      expect(identical(state.debugRunStream, first), isTrue);
    });

    testWidgets('changing the run key re-hoists the stream', (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: 'ST301.MV01.Running');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      final dynamic state = tester.state(find.byType(ThirdPartyEquipment));
      final first = state.debugRunStream;

      config.runKey = 'ST301.MV01.Stopped';
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      expect(identical(state.debugRunStream, first), isFalse);
    });

    testWidgets('clearing the run key drops the stream entirely',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: 'ST301.MV01.Running');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      final dynamic state = tester.state(find.byType(ThirdPartyEquipment));
      config.runKey = '';
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      expect(state.debugRunStream, isNull);
    });
  });

  group('Tap for more information', () {
    testWidgets('tap opens the read-only details dialog, not the editor',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.strappingLine,
        runKey: 'ST301.PK01.STRAP01.Running',
        tag: 'STRAP-01',
        notes: 'Three Strapex heads in series.',
      );
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 200,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Equipment'), findsOneWidget);
      expect(find.text('Footprint'), findsOneWidget);
      expect(find.text('Run status key'), findsOneWidget);
      expect(find.text('Tag'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);

      // Negative locks — the runtime tap must never expose editor controls.
      expect(find.byType(DropdownButton<ThirdPartyEquipmentKind>), findsNothing,
          reason: 'Runtime tap must NOT open the config editor.');
      expect(find.text('Run Status Key'), findsNothing,
          reason: 'The editor KeyField label must not appear at runtime.');
    });

    testWidgets('details dialog reports unknown run status when there is no key',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: '');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      expect(find.text('no key configured'), findsOneWidget);
    });

    testWidgets('Close dismisses the dialog', (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: '');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Config editor', () {
    testWidgets('kind dropdown lists every machine and switches the drawing',
        (tester) async {
      final config = ThirdPartyEquipmentConfig();
      await tester.pumpWidget(wrap(
        Builder(builder: (context) => config.configure(context)),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<ThirdPartyEquipmentKind>));
      await tester.pumpAndSettle();

      for (final kind in ThirdPartyEquipmentKind.values) {
        expect(find.text(kind.label), findsWidgets,
            reason: '${kind.name} must be offered in the dropdown.');
      }

      await tester.tap(find.text(ThirdPartyEquipmentKind.boxErector.label).last);
      await tester.pumpAndSettle();

      expect(config.kind, ThirdPartyEquipmentKind.boxErector);
    });
  });
}
