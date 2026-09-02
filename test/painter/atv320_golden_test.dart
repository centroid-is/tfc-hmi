import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/painter/schneider/atv320.dart';

/// Records drawParagraph calls so the label-line layout can be asserted
/// without goldens (which only run on macOS).
class _ParagraphRecordingCanvas implements Canvas {
  final List<ui.Paragraph> paragraphs = [];
  final List<Offset> offsets = [];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    paragraphs.add(paragraph);
    offsets.add(offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ATV320 7-segment golden tests', skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
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

  group('ATV320.splitTopLabel', () {
    test('label without newline is unchanged (single line)', () {
      expect(ATV320.splitTopLabel('CN01.FD01'), ['CN01.FD01']);
    });

    test('single word longer than 14 chars still truncates with ellipsis',
        () {
      expect(
        ATV320.splitTopLabel('ABCDEFGHIJKLMNOP'),
        ['ABCDEFGHIJKLMN...'],
      );
    });

    test('space heuristic without newline is unchanged (two lines)', () {
      expect(
        ATV320.splitTopLabel('Line 1 Return'),
        ['Line 1 Return'],
      );
      expect(
        ATV320.splitTopLabel('Conveyor Drive Cabinet North'),
        ['Conveyor Drive', 'Cabinet North'],
      );
    });

    test('explicit newline splits into two stacked lines', () {
      expect(ATV320.splitTopLabel('CN01\nFD01'), ['CN01', 'FD01']);
    });

    test('explicit newline takes precedence over the space heuristic', () {
      expect(
        ATV320.splitTopLabel('CN01 north\nFD01 south'),
        ['CN01 north', 'FD01 south'],
      );
    });

    test('more than two explicit lines are capped with ellipsis on line 2',
        () {
      expect(ATV320.splitTopLabel('A\nB\nC'), ['A', 'B...']);
      expect(
        ATV320.splitTopLabel('CN01\nFD01 long tail line\nFD02'),
        ['CN01', 'FD01 long t...'],
      );
    });

    test('trailing newline alone does not create a second line', () {
      expect(ATV320.splitTopLabel('CN01\n'), ['CN01']);
      expect(ATV320.splitTopLabel('CN01\n\n'), ['CN01']);
    });

    test('blank explicit lines are dropped', () {
      expect(ATV320.splitTopLabel('CN01\n\nFD01'), ['CN01', 'FD01']);
    });

    test('explicit lines longer than 14 chars are clipped', () {
      expect(
        ATV320.splitTopLabel('ABCDEFGHIJKLMNOP\nFD01'),
        ['ABCDEFGHIJKLMN...', 'FD01'],
      );
    });
  });

  group('ATV320 label painting', () {
    // Painter design space: 96 dpi over mm, before the fit-to-box transform.
    const double pxPerMm = 96.0 / 25.4;
    const Size size = Size(200, 600);

    _ParagraphRecordingCanvas paintWithLabel(String topLabel) {
      final canvas = _ParagraphRecordingCanvas();
      ATV320(name: 'ATV320', displayText: 'sto', topLabel: topLabel)
          .paint(canvas, size);
      return canvas;
    }

    // The painter always draws one paragraph for the ESC button; label
    // lines come on top of that.
    late final int baseParagraphs = paintWithLabel('').paragraphs.length;

    test('label with explicit newline paints two stacked lines', () {
      final canvas = paintWithLabel('CN01\nFD01');
      expect(canvas.paragraphs.length, baseParagraphs + 2);

      // Line 1 at 8mm from the top of the drive, line 2 at 15mm.
      final labelOffsets = canvas.offsets.take(2).toList();
      expect(labelOffsets[0].dy, moreOrLessEquals(8.0 * pxPerMm));
      expect(labelOffsets[1].dy, moreOrLessEquals(15.0 * pxPerMm));
    });

    test('label without newline paints a single line at 8mm', () {
      final canvas = paintWithLabel('CN01.FD01');
      expect(canvas.paragraphs.length, baseParagraphs + 1);
      expect(canvas.offsets.first.dy, moreOrLessEquals(8.0 * pxPerMm));
    });

    test('more than two explicit lines still paint only two', () {
      final canvas = paintWithLabel('CN01\nFD01\nFD02\nFD03');
      expect(canvas.paragraphs.length, baseParagraphs + 2);
    });
  });
}
