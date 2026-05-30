// _ConveyorPainter.shouldRepaint contract — content equality on `batches`.
//
// Production bug: the `_batches` map is passed by reference to
// `_ConveyorPainter` (lib/page_creator/assets/conveyor.dart:1002:
// `batches: _batches`) and `shouldRepaint` only compared
// color/showExclamation/bidirectional/showFrequency/frequency — NEVER
// `batches`. As a result, the item-position listener writes
// `_batches['item'] = batch` (correct), the StreamBuilder rebuilds the
// CustomPaint with a new `_ConveyorPainter`, but the framework asks
// `shouldRepaint(old)` which returns FALSE because the same map reference is
// held by both painters AND no other field changed. The conveyor freezes.
//
// Confirmed in production via debug2.log on 2026-05-29: 4 conveyors on
// screen, only the one whose frequency was actively changing animated; the
// other three never re-rendered after their first paint despite the
// item-position stream emitting correct values.
//
// This test asserts the contract directly via `@visibleForTesting` helpers
// in `conveyor.dart`. Both painters must use content-equality on `batches`
// so that swapping a Batch for one with different start/end triggers a
// repaint, and so that two structurally-equal `batches` maps DON'T trigger
// a repaint (avoids wasted paints when the stream re-emits the same value).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

void main() {
  group('_ConveyorPainter.shouldRepaint — batches content equality', () {
    test('repaints when batches["item"] start/end changes', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.3, end: 0.8)},
      );
      expect(
        debugConveyorPainterShouldRepaint(newP, oldP),
        isTrue,
        reason: 'Item-position batch moved from [0.0,0.5] to [0.3,0.8] — '
            'painter must repaint or the animation freezes (production bug).',
      );
    });

    test('repaints when a batch is added to the map', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: <String, Batch>{},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.1, end: 0.3)},
      );
      expect(
        debugConveyorPainterShouldRepaint(newP, oldP),
        isTrue,
        reason: 'Item appeared on the conveyor — painter must repaint.',
      );
    });

    test('repaints when a batch is removed from the map', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.1, end: 0.3)},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: <String, Batch>{},
      );
      expect(
        debugConveyorPainterShouldRepaint(newP, oldP),
        isTrue,
        reason: 'Item left the conveyor — painter must repaint.',
      );
    });

    test('repaints when batch color changes (same start/end)', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5, color: Colors.white)},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5, color: Colors.red)},
      );
      expect(
        debugConveyorPainterShouldRepaint(newP, oldP),
        isTrue,
        reason: 'Batch color changed — painter must repaint.',
      );
    });

    test('does NOT repaint when batches are content-equal (no wasted paint)',
        () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
      );
      expect(
        debugConveyorPainterShouldRepaint(newP, oldP),
        isFalse,
        reason: 'Two distinct maps with identical Batch content — no '
            'visual change, painter must NOT repaint.',
      );
    });

    test('does NOT repaint when both painters are fully identical', () {
      final batches = {'item': Batch(start: 0.2, end: 0.4)};
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.blue,
        batches: batches,
        frequency: 12.5,
        showFrequency: true,
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.blue,
        batches: {'item': Batch(start: 0.2, end: 0.4)},
        frequency: 12.5,
        showFrequency: true,
      );
      expect(
        debugConveyorPainterShouldRepaint(newP, oldP),
        isFalse,
        reason: 'All fields content-equal — no repaint.',
      );
    });

    // Regression guards for the existing shouldRepaint comparisons —
    // ensure we ADDED batches comparison, not REPLACED the others.
    test('still repaints when color changes', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.red,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
      );
      expect(debugConveyorPainterShouldRepaint(newP, oldP), isTrue);
    });

    test('still repaints when frequency changes', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
        frequency: 10.0,
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
        frequency: 15.0,
      );
      expect(debugConveyorPainterShouldRepaint(newP, oldP), isTrue);
    });

    test('still repaints when showExclamation changes', () {
      final oldP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
      );
      final newP = debugBuildConveyorPainterForTest(
        color: Colors.green,
        batches: {'item': Batch(start: 0.0, end: 0.5)},
        showExclamation: true,
      );
      expect(debugConveyorPainterShouldRepaint(newP, oldP), isTrue);
    });
  });
}
