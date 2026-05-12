import 'dart:io' show Platform;

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

  // ── Golden matrix ───────────────────────────────────────────────────────
  // The 8-state colour matrix from `01-UI-SPEC.md` §Test Coverage Contract,
  // plus a 9th stale-state golden (which sits outside the matrix per the
  // spec but lives here for proximity).
  //
  // Canvas: 256×128 — 2:1 ratio matches the red-light pair geometry and
  // gives the optic-field cone enough horizontal room to fan out.
  //
  // Locked colour values across every test (matches `SensorConfig` defaults):
  //   activeColor   = Colors.green
  //   inactiveColor = Colors.grey.shade400
  //
  // Polarity (tests #3, #4) is a pure pre-painter inversion — visually these
  // are identical to tests #1 and #2 respectively, but each has its own
  // golden file so the matrix file-name set is explicit and complete.
  //
  // Skipped on non-macOS to match the existing project convention in
  // `conveyor_gate_golden_test.dart` (Platform.isMacOS guard) — Pitfall 6
  // determinism: goldens are captured on macOS only.
  //
  // Each test inlines its own `SizedBox(width: 256, height: 128)` and a
  // `RepaintBoundary` wrapper so the matched widget is the painter's own
  // pixels (not the surrounding Material chrome). The repeated shape is
  // intentional — it's what the plan calls for ("apply uniformly so future
  // maintainers see one shape").
  const goldenKey = Key('sensor_golden');

  group('Golden matrix',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    // 1. Red light — clear (isActive=false, normal polarity)
    testWidgets('red_light_clear', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: RedLightBeamPainter(
                    isActive: false,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/red_light_clear.png'),
      );
    });

    // 2. Red light — broken (isActive=true, normal polarity)
    testWidgets('red_light_broken', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: RedLightBeamPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/red_light_broken.png'),
      );
    });

    // 3. Red light — clear with polarity inverted (visually identical to #1).
    //    Polarity inversion happens before the painter — `isActive` is the
    //    already-inverted bool. The duplicate golden file exists to lock
    //    the file-name set per the UI-SPEC matrix.
    testWidgets('red_light_clear_inverted', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: RedLightBeamPainter(
                    isActive: false,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/red_light_clear_inverted.png'),
      );
    });

    // 4. Red light — broken with polarity inverted (visually identical to #2)
    testWidgets('red_light_broken_inverted', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: RedLightBeamPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/red_light_broken_inverted.png'),
      );
    });

    // 5. Optic field — inactive
    testWidgets('optic_field_inactive', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: OpticFieldPainter(
                    isActive: false,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/optic_field_inactive.png'),
      );
    });

    // 6. Optic field — active (filled α=0.40 with outline visible)
    testWidgets('optic_field_active', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: OpticFieldPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/optic_field_active.png'),
      );
    });

    // 7. Inductive field — inactive
    testWidgets('inductive_field_inactive', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: InductiveFieldPainter(
                    isActive: false,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/inductive_field_inactive.png'),
      );
    });

    // 8. Inductive field — active (filled α=0.40)
    testWidgets('inductive_field_active', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: InductiveFieldPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/inductive_field_active.png'),
      );
    });

    // 9. Stale — entire glyph rendered grey. Kind irrelevant per UI-SPEC §9;
    //    redLight chosen. `isActive=true` is intentional: proves the stale
    //    flag overrides the active-colour mapping.
    testWidgets('stale', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: RedLightBeamPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                    isStale: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/stale.png'),
      );
    });

    // 10. Red light — broken (active) with a non-empty label.
    //    Verifies the painter's `_paintLabel` helper renders the tag in
    //    inactiveColor (UI-SPEC §Color matrix, label colour rule) below the
    //    glyph, semibold, without overlapping the beam. The label parameter
    //    is the only difference from #2 (red_light_broken).
    testWidgets('red_light_with_label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: RedLightBeamPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                    label: 'PE-101A',
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sensor/red_light_with_label.png'),
      );
    });

    // 11. Inductive field — active with a multi-character label like
    //     "Lock 1". Regression for SENS-17: before the geometry-shrink
    //     fix, the bubble extended to `0.80 * h` and the bottom-aligned
    //     label overlapped the bubble at common canvas sizes. The fix
    //     reserves a bottom band for the label and shrinks the glyph
    //     geometry into the top portion. This golden locks the corrected
    //     layout (label visibly below the bubble).
    testWidgets('inductive_field_active_with_label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: InductiveFieldPainter(
                    isActive: true,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                    label: 'Lock 1',
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/sensor/inductive_field_active_with_label.png'),
      );
    });

    // 12. Inductive field — inactive with a multi-character label.
    //     Same regression class as #11 but for the inactive state (the
    //     outlined bubble) — operators reported the inactive overlap on
    //     a real page (asset named "Lock 1").
    testWidgets('inductive_field_inactive_with_label', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: RepaintBoundary(
              key: goldenKey,
              child: SizedBox(
                width: 256,
                height: 128,
                child: CustomPaint(
                  painter: InductiveFieldPainter(
                    isActive: false,
                    activeColor: Colors.green,
                    inactiveColor: Colors.grey.shade400,
                    label: 'Lock 1',
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/sensor/inductive_field_inactive_with_label.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Sensor label visibility (SENS-13)
  //
  // Caught by Plan 04-02 visual review: the painter painted labels in
  // `inactiveColor`, which defaults to a light grey and therefore blended
  // into the panel background — the operator-facing tag (e.g. 'PE-101A')
  // was effectively invisible. Locked label colour is now `Colors.black87`
  // when not stale, `Colors.grey` when stale. The test assertions exercise
  // the locked formula via `debugLabelColour`, a `@visibleForTesting` hook
  // that mirrors the inlined site in `paint()`.
  // ---------------------------------------------------------------------------
  group('Sensor label visibility (SENS-13)', () {
    test('RedLightBeamPainter label colour is contrasting (not inactiveColor)',
        () {
      const lowContrastInactive = Color(0xFFEEEEEE); // very light grey
      final painter = RedLightBeamPainter(
        isActive: false,
        activeColor: Colors.green,
        inactiveColor: lowContrastInactive,
        label: 'PE-101A',
      );
      expect(painter.debugLabelColour, isNot(equals(lowContrastInactive)),
          reason:
              'Label colour must contrast against the panel — must NOT '
              'inherit the (potentially low-contrast) inactiveColor when '
              'isStale is false (SENS-13 readability lock).');
      expect(painter.debugLabelColour, equals(Colors.black87),
          reason:
              'Locked label colour for non-stale rendering is '
              'Colors.black87 (high contrast against typical light '
              'panel backgrounds).');
    });

    test('OpticFieldPainter label colour is Colors.black87 when not stale',
        () {
      final painter = OpticFieldPainter(
        isActive: false,
        activeColor: Colors.green,
        inactiveColor: const Color(0xFFEEEEEE),
        label: 'OPT-1',
      );
      expect(painter.debugLabelColour, equals(Colors.black87));
    });

    test(
        'InductiveFieldPainter label colour is Colors.black87 when not stale',
        () {
      final painter = InductiveFieldPainter(
        isActive: false,
        activeColor: Colors.green,
        inactiveColor: const Color(0xFFEEEEEE),
        label: 'IND-1',
      );
      expect(painter.debugLabelColour, equals(Colors.black87));
    });

    test('All three painters fall back to Colors.grey when stale', () {
      final r = RedLightBeamPainter(
        isActive: false,
        activeColor: Colors.green,
        inactiveColor: const Color(0xFFBDBDBD),
        label: 'X',
        isStale: true,
      );
      final o = OpticFieldPainter(
        isActive: false,
        activeColor: Colors.green,
        inactiveColor: const Color(0xFFBDBDBD),
        label: 'X',
        isStale: true,
      );
      final i = InductiveFieldPainter(
        isActive: false,
        activeColor: Colors.green,
        inactiveColor: const Color(0xFFBDBDBD),
        label: 'X',
        isStale: true,
      );
      expect(r.debugLabelColour, Colors.grey);
      expect(o.debugLabelColour, Colors.grey);
      expect(i.debugLabelColour, Colors.grey);
    });
  });
}
