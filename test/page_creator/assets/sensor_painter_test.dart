import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/sensor_painter.dart';

/// Tests for the three sensor `CustomPainter` subclasses defined in
/// `lib/page_creator/assets/sensor_painter.dart`.
///
/// Two test groups:
///   - `shouldRepaint contract` — pure unit tests covering the cross-kind
///     guard (Pitfall 3) plus per-field equality. No goldens, no canvas.
///   - `Golden matrix` — added in Task 3; the 8-state colour matrix from
///     UI-SPEC §Test Coverage Contract plus a 9th stale-state golden.
void main() {
  group('shouldRepaint contract', () {
    // ── Cross-kind safety (Pitfall 3) ────────────────────────────────────
    // A painter swap across kinds (e.g. SensorKind.redLight →
    // SensorKind.opticField) must trigger a repaint, otherwise the canvas
    // keeps drawing the old kind's geometry. The runtimeType guard inside
    // shouldRepaint is what enforces this.

    test(
        'RedLightBeamPainter.shouldRepaint(OpticFieldPainter) returns true (cross-runtimeType — Pitfall 3)',
        () {
      // Single-line cross-kind expectations for grep matching.
      expect(RedLightBeamPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey).shouldRepaint(OpticFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey)), isTrue);
      expect(OpticFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey).shouldRepaint(RedLightBeamPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey)), isTrue);
    });

    test(
        'InductiveFieldPainter.shouldRepaint(RedLightBeamPainter) returns true (cross-runtimeType — Pitfall 3)',
        () {
      expect(InductiveFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey).shouldRepaint(RedLightBeamPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey)), isTrue);
      expect(RedLightBeamPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey).shouldRepaint(InductiveFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey)), isTrue);
    });

    test(
        'OpticFieldPainter.shouldRepaint(InductiveFieldPainter) returns true (cross-runtimeType — Pitfall 3)',
        () {
      expect(OpticFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey).shouldRepaint(InductiveFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey)), isTrue);
      expect(InductiveFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey).shouldRepaint(OpticFieldPainter(isActive: true, activeColor: Colors.green, inactiveColor: Colors.grey)), isTrue);
    });

    // ── Per-field equality: RedLightBeamPainter ──────────────────────────

    test('RedLightBeamPainter shouldRepaint TRUE when isActive flips', () {
      final a = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = RedLightBeamPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('RedLightBeamPainter shouldRepaint TRUE when activeColor changes',
        () {
      final a = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.red,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('RedLightBeamPainter shouldRepaint TRUE when inactiveColor changes',
        () {
      final a = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.black);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('RedLightBeamPainter shouldRepaint TRUE when label changes', () {
      final a = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PE-101A');
      final b = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PE-101B');
      expect(a.shouldRepaint(b), isTrue);
    });

    test('RedLightBeamPainter shouldRepaint TRUE when isStale changes', () {
      final a = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          isStale: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test(
        'RedLightBeamPainter shouldRepaint FALSE when all inputs identical (deterministic)',
        () {
      final a = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PE-101A');
      final b = RedLightBeamPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PE-101A');
      expect(a.shouldRepaint(b), isFalse);
    });

    // ── Per-field equality: OpticFieldPainter ────────────────────────────

    test('OpticFieldPainter shouldRepaint TRUE when isActive flips', () {
      final a = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = OpticFieldPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('OpticFieldPainter shouldRepaint TRUE when activeColor changes', () {
      final a = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.red,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('OpticFieldPainter shouldRepaint TRUE when inactiveColor changes',
        () {
      final a = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.black);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('OpticFieldPainter shouldRepaint TRUE when label changes', () {
      final a = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PE-101A');
      final b = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PE-101B');
      expect(a.shouldRepaint(b), isTrue);
    });

    test('OpticFieldPainter shouldRepaint TRUE when isStale changes', () {
      final a = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = OpticFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          isStale: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test(
        'OpticFieldPainter shouldRepaint FALSE when all inputs identical (deterministic)',
        () {
      final a = OpticFieldPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = OpticFieldPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isFalse);
    });

    // ── Per-field equality: InductiveFieldPainter ────────────────────────

    test('InductiveFieldPainter shouldRepaint TRUE when isActive flips', () {
      final a = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = InductiveFieldPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('InductiveFieldPainter shouldRepaint TRUE when activeColor changes',
        () {
      final a = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.red,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isTrue);
    });

    test(
        'InductiveFieldPainter shouldRepaint TRUE when inactiveColor changes',
        () {
      final a = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.black);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('InductiveFieldPainter shouldRepaint TRUE when label changes', () {
      final a = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PR-202A');
      final b = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          label: 'PR-202B');
      expect(a.shouldRepaint(b), isTrue);
    });

    test('InductiveFieldPainter shouldRepaint TRUE when isStale changes', () {
      final a = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = InductiveFieldPainter(
          isActive: true,
          activeColor: Colors.green,
          inactiveColor: Colors.grey,
          isStale: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test(
        'InductiveFieldPainter shouldRepaint FALSE when all inputs identical (deterministic)',
        () {
      final a = InductiveFieldPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      final b = InductiveFieldPainter(
          isActive: false,
          activeColor: Colors.green,
          inactiveColor: Colors.grey);
      expect(a.shouldRepaint(b), isFalse);
    });
  });
}
