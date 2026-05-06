import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tfc/page_creator/assets/elevator.dart';
import 'package:tfc/page_creator/assets/elevator_painter.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 200, height: 300, child: child),
            ),
          ),
        ),
      );

  group('Tap to configure', () {
    testWidgets('tap opens placeholder config dialog', (tester) async {
      final config = ElevatorConfig();
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Configure Elevator'), findsOneWidget);
    });

    testWidgets('GestureDetector exists with HitTestBehavior.opaque',
        (tester) async {
      final config = ElevatorConfig();
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      // Find the GestureDetector child of the Elevator subtree.
      final gd = tester.widget<GestureDetector>(find.byType(GestureDetector).first);
      expect(gd.behavior, HitTestBehavior.opaque);
    });
  });

  group('Stale paths', () {
    testWidgets('empty positionKey → painter.isStale=true', (tester) async {
      final config = ElevatorConfig(positionKey: '');
      await tester.pumpWidget(wrap(Elevator(config: config)));
      await tester.pump(Duration.zero);
      // Descend into the Elevator subtree so we don't pick up the
      // CustomPaint instances belonging to the MaterialApp chrome
      // (Scaffold / Overlay), which have no painter set.
      final cp = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Elevator),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(cp.painter, isA<ElevatorPainter>());
      expect((cp.painter as ElevatorPainter).isStale, isTrue);
    });
  });
}
