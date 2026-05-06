import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/elevator_painter.dart';

void main() {
  group('ElevatorPainter shouldRepaint contract', () {
    test('same inputs → shouldRepaint=false', () {
      final notifier = ValueNotifier<double>(0.5);
      final a = ElevatorPainter(progress: notifier, isStale: false);
      final b = ElevatorPainter(progress: notifier, isStale: false);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('different progress notifier → shouldRepaint=true', () {
      final n1 = ValueNotifier<double>(0.5);
      final n2 = ValueNotifier<double>(0.5); // distinct instance, same value
      final a = ElevatorPainter(progress: n1, isStale: false);
      final b = ElevatorPainter(progress: n2, isStale: false);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different isStale → shouldRepaint=true', () {
      final n = ValueNotifier<double>(0.5);
      final a = ElevatorPainter(progress: n, isStale: false);
      final b = ElevatorPainter(progress: n, isStale: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('cross-runtimeType → shouldRepaint=true (Pitfall 3 guard)', () {
      final n = ValueNotifier<double>(0.5);
      final elevator = ElevatorPainter(progress: n, isStale: false);
      final other = _DummyPainter();
      // shouldRepaint accepts a covariant CustomPainter; the cross-runtimeType
      // guard inside ElevatorPainter.shouldRepaint must short-circuit to true.
      expect(elevator.shouldRepaint(other), isTrue);
    });
  });
}

class _DummyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
