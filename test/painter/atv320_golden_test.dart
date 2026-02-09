import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/painter/schneider/atv320.dart';

void main() {
  group('ATV320 7-segment golden tests', () {
    Widget buildDisplay(String displayText, {String topLabel = ''}) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF2A2F2A),
          body: Center(
            child: SizedBox(
              width: 200,
              height: 600,
              child: ATV320Widget(
                name: 'ATV320',
                displayText: displayText,
                topLabel: topLabel,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('sto display', (tester) async {
      await tester.pumpWidget(buildDisplay('sto'));
      await expectLater(
        find.byType(ATV320Widget),
        matchesGoldenFile('goldens/atv320_sto.png'),
      );
    });

    testWidgets('STO uppercase display', (tester) async {
      await tester.pumpWidget(buildDisplay('STO'));
      await expectLater(
        find.byType(ATV320Widget),
        matchesGoldenFile('goldens/atv320_sto_upper.png'),
      );
    });

    testWidgets('cnf display', (tester) async {
      await tester.pumpWidget(buildDisplay('cnf'));
      await expectLater(
        find.byType(ATV320Widget),
        matchesGoldenFile('goldens/atv320_cnf.png'),
      );
    });

    testWidgets('CNF uppercase display', (tester) async {
      await tester.pumpWidget(buildDisplay('CNF'));
      await expectLater(
        find.byType(ATV320Widget),
        matchesGoldenFile('goldens/atv320_cnf_upper.png'),
      );
    });

    testWidgets('frequency display with decimal', (tester) async {
      await tester.pumpWidget(buildDisplay('50.0'));
      await expectLater(
        find.byType(ATV320Widget),
        matchesGoldenFile('goldens/atv320_freq.png'),
      );
    });

    testWidgets('display with top label', (tester) async {
      await tester.pumpWidget(buildDisplay('sto', topLabel: 'Line 1 Return'));
      await expectLater(
        find.byType(ATV320Widget),
        matchesGoldenFile('goldens/atv320_sto_label.png'),
      );
    });
  });
}
