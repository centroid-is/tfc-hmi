import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/sensor.dart';
import 'package:tfc/page_creator/assets/third_party.dart';
import 'package:tfc/page_creator/assets/third_party_painter.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

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

  group('Tap opens the side pane', () {
    // A docked SidePane rather than a dialog: this is equipment on a running
    // line, and a modal barrier would hide the machine being diagnosed.
    tearDown(closeSidePane);

    testWidgets('tap opens a read-only pane, not the editor', (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.strappingLine,
        strapMachines: 2,
        runKey: 'ST301.PK01.STRAP01.Running',
        tag: 'STRAP-01',
        notes: 'Two Strapex heads in series.',
      );
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 200,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      expect(find.byType(SidePane), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'The pane must not be a modal dialog.');

      // Header carries the tag, and the machine name follows the head count
      // into a real model number. showTag is off (the default), so the tag
      // reaches the operator through the pane while the page label — which
      // scales with the asset's big bounding box — stays unpainted.
      expect(config.showTag, isFalse);
      expect(config.text, isNull,
          reason: 'AssetStack must see no label while showTag is off.');
      expect(find.text('STRAP-01'), findsOneWidget);
      expect(
          find.textContaining('2 x Strapex'), findsWidgets,
          reason: 'Strapper count must reach the pane title.');
      expect(find.text('NOTES'), findsOneWidget);

      // Negative locks — the runtime tap must never expose editor controls.
      expect(find.byType(DropdownButton<ThirdPartyEquipmentKind>), findsNothing,
          reason: 'Runtime tap must NOT open the config editor.');
      expect(find.text('Run Status Key'), findsNothing,
          reason: 'The editor KeyField label must not appear at runtime.');
    });

    testWidgets('tapping the same machine again toggles the pane shut',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: '');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(), isTrue);

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(), isFalse);
    });

    testWidgets('pane status chip reflects an unconfigured key',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: '');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      expect(find.text('No key'), findsOneWidget);
    });

    testWidgets('pane status chip is Stale while the stream has no value',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: 'ST301.MV01.Running');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      // Not "Stopped" — we have no signal, which is a different thing.
      expect(find.text('Stale'), findsOneWidget);
      expect(find.text('Stopped'), findsNothing);
    });

    testWidgets('the pane lists what is placed inside the box',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        runKey: '',
        children: [ThirdPartyChildEntry(child: ConveyorConfig.preview())],
      );
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 400,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      expect(find.text('INSIDE THE BOX'), findsOneWidget);
    });

    testWidgets('the pane does not outlive the asset that opened it',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(runKey: '');
      await tester.pumpWidget(wrap(SizedBox(
        width: 300,
        height: 160,
        child: ThirdPartyEquipment(config: config),
      )));

      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(), isTrue);

      // Navigating away disposes the asset. A docked pane lives in the root
      // overlay, so without the dispose hook it would keep showing a machine
      // that is no longer on screen.
      await tester.pumpWidget(wrap(const SizedBox(width: 300, height: 160)));
      await tester.pumpAndSettle();

      expect(isSidePaneOpen(), isFalse);
    });
  });

  group('Children inside the box', () {
    testWidgets('a child asset is built inside the machine area',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        children: [
          ThirdPartyChildEntry(
            offsetX: 0.25,
            offsetY: 0.65,
            child: ConveyorConfig.preview(),
          ),
        ],
      );
      await tester.pumpWidget(wrap(SizedBox(
        width: 320,
        height: 600,
        child: ThirdPartyEquipment(config: config),
      )));
      await tester.pump();

      expect(find.byType(Conveyor), findsOneWidget,
          reason: 'A live Conveyor must render inside the dotted box.');
    });

    testWidgets('an upright readout stays level when the machine is rotated',
        (tester) async {
      // The machine gets rotated to match the plant layout; the numbers must
      // not follow it round.
      const paintSize = Size(320, 600);
      await tester.pumpWidget(wrap(ThirdPartyEquipmentBody(
        painter: thirdPartyPainterFor(ThirdPartyEquipmentKind.speedBatcher,
            color: Colors.blueGrey, strokeWidth: 2),
        paintSize: paintSize,
        ledColor: Colors.green,
        parentAngleDegrees: 90,
        children: [
          ThirdPartyChildEntry(
            keepUpright: true,
            child: NumberConfig(key: ''),
          ),
        ],
      )));
      await tester.pump();

      final rotations = tester
          .widgetList<Transform>(find.byType(Transform))
          .map((t) => t.transform)
          .toList();
      // Somewhere in the subtree the readout is turned back by -90 degrees.
      expect(
        rotations.any((m) => (m.getRotation().entry(0, 1) - 1.0).abs() < 1e-6),
        isTrue,
        reason: 'A parent at 90 degrees must counter-rotate its readouts.',
      );
    });

    testWidgets('machinery children are NOT counter-rotated', (tester) async {
      const paintSize = Size(320, 600);
      await tester.pumpWidget(wrap(ThirdPartyEquipmentBody(
        painter: thirdPartyPainterFor(ThirdPartyEquipmentKind.speedBatcher,
            color: Colors.blueGrey, strokeWidth: 2),
        paintSize: paintSize,
        ledColor: Colors.green,
        parentAngleDegrees: 90,
        children: [
          ThirdPartyChildEntry(child: SensorConfig.preview()),
        ],
      )));
      await tester.pump();

      // A sensor belongs to the machine and must turn with it, so the body
      // adds no counter-rotation of its own.
      final counterRotations = tester
          .widgetList<Transform>(find.byType(Transform))
          .where((t) =>
              (t.transform.getRotation().entry(0, 1) - 1.0).abs() < 1e-6);
      expect(counterRotations, isEmpty);
    });

    testWidgets('the child sits within the drawing, clear of the LED header',
        (tester) async {
      const paintSize = Size(320, 600);
      final entry = ThirdPartyChildEntry(
        offsetX: 0.5,
        offsetY: 0.5,
        child: SensorConfig.preview(),
      );
      await tester.pumpWidget(wrap(ThirdPartyEquipmentBody(
        painter: thirdPartyPainterFor(ThirdPartyEquipmentKind.speedBatcher,
            color: Colors.blueGrey, strokeWidth: 2),
        paintSize: paintSize,
        ledColor: Colors.green,
        children: [entry],
      )));
      await tester.pump();

      final area = thirdPartyMachineArea(paintSize);
      final childCentre = tester.getCenter(find.byType(Sensor));
      final bodyTopLeft = tester.getTopLeft(find.byType(ThirdPartyEquipmentBody));
      final local = childCentre - bodyTopLeft;

      // offset 0.5/0.5 must land at the centre of the MACHINE AREA, not of
      // the whole asset rect — otherwise children drift when the LED header
      // changes height.
      expect(local.dx, closeTo(area.center.dx, 1.0));
      expect(local.dy, closeTo(area.center.dy, 1.0));
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

    testWidgets('SpeedBatcher box is static — no free-form add buttons',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
      );
      await tester.pumpWidget(wrap(
        Builder(builder: (context) => config.configure(context)),
      ));
      await tester.pumpAndSettle();

      // The station's contents are the scaffold and nothing else — the
      // operator points the scaffolded children at tags, but cannot place
      // arbitrary assets inside the box.
      expect(find.widgetWithText(FilledButton, 'Readout'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Conveyor'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sensor'), findsNothing);
      // Scaffold recovery stays available.
      expect(find.text('Build checkweighers'), findsOneWidget);
    });

    testWidgets('other kinds keep the free-form add buttons', (tester) async {
      final config = ThirdPartyEquipmentConfig(); // multivac
      await tester.pumpWidget(wrap(
        Builder(builder: (context) => config.configure(context)),
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Readout'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Conveyor'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sensor'), findsOneWidget);
      expect(find.text('Build checkweighers'), findsNothing);
    });
  });
}
