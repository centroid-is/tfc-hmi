import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/providers/state_man.dart';

// Regression test: "Simulate batches" toggle must start the simulation timer
// even when no PLC keys are configured.
//
// BUG: In the runtime Conveyor widget, the start/stop logic for the batch
// simulation timer was buried inside StreamBuilder.builder, which only fires
// once at least one stream has data. With no keys configured, the widget
// early-returned before reaching the simulation toggle check, so flipping
// `simulateBatches` had no visible effect.
//
// We verify behavior by reaching into the painter's `batches` map: the timer
// inserts a Batch on its first tick, so a non-empty map after pumping a few
// frames proves the simulation timer is running.

/// Walks the rendered tree from [tester] looking for a [CustomPaint] whose
/// painter exposes a `batches` field (i.e. the internal _ConveyorPainter).
/// Returns the painter or null if not found.
dynamic _findConveyorPainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  for (final cp in paints) {
    final painter = cp.painter;
    if (painter == null) continue;
    // Duck-typed access; _ConveyorPainter is library-private.
    try {
      final dyn = painter as dynamic;
      final batches = dyn.batches;
      if (batches is Map) return painter;
    } catch (_) {
      // Wrong painter type — keep looking.
    }
  }
  return null;
}

Widget _wrap(ConveyorConfig config) {
  return ProviderScope(
    overrides: [
      // No real StateMan — provider future will not complete, but the
      // Conveyor widget should still react to the simulateBatches flag.
      stateManProvider.overrideWith(
        (ref) => throw StateError('No StateMan in tests'),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 80,
            child: Conveyor(config),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'simulateBatches=true with no PLC keys still starts the simulation timer',
    (tester) async {
      final config = ConveyorConfig(simulateBatches: true)
        ..size = const RelativeSize(width: 1.0, height: 1.0);

      await tester.pumpWidget(_wrap(config));

      // First frame: timer should be scheduled but hasn't ticked yet.
      // Pump a few frames to allow the 20ms periodic timer to fire.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      final painter = _findConveyorPainter(tester);
      expect(painter, isNotNull,
          reason: 'Could not locate _ConveyorPainter in widget tree');

      final batches = (painter as dynamic).batches as Map;
      expect(batches.isNotEmpty, isTrue,
          reason:
              'simulateBatches=true must populate the batches map even with no PLC keys');
    },
  );

  testWidgets(
    'simulateBatches=false leaves the batches map empty',
    (tester) async {
      final config = ConveyorConfig(simulateBatches: false)
        ..size = const RelativeSize(width: 1.0, height: 1.0);

      await tester.pumpWidget(_wrap(config));

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      final painter = _findConveyorPainter(tester);
      expect(painter, isNotNull);
      final batches = (painter as dynamic).batches as Map;
      expect(batches, isEmpty,
          reason:
              'simulateBatches=false must not populate the batches map');
    },
  );

  testWidgets(
    'simulateBatches keeps simulating when only batchesKey is configured but no data arrives',
    (tester) async {
      // batchesKey present, but stateManProvider throws so no stream data
      // ever arrives. Simulation toggle must still drive the painter.
      final config = ConveyorConfig(
        batchesKey: 'irrelevant',
        simulateBatches: true,
      )..size = const RelativeSize(width: 1.0, height: 1.0);

      await tester.pumpWidget(_wrap(config));

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }

      final painter = _findConveyorPainter(tester);
      expect(painter, isNotNull);
      final batches = (painter as dynamic).batches as Map;
      expect(batches.isNotEmpty, isTrue,
          reason:
              'simulateBatches must run regardless of whether stream data has arrived');
    },
  );
}

