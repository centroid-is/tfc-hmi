import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// A turn's `position` is where the operator points at the bend — and the
/// visible bend is the arc, so `position` must land on the *center of the
/// corner arc*, measured along the belt. It used to seed the corner of the
/// straight-line skeleton instead, so the run into a bend and the arc's own
/// length pushed the visible corner away from the number on the slider —
/// most visibly near the ends: a turn "at 1%" showed up several percent in.
///
/// When the radius physically cannot hug an end (the arc needs half its own
/// length of belt before its center), the bend clamps as close as the
/// geometry allows instead of collapsing the radius.
///
/// The arcs are found by sampling the fitted path's heading and looking for
/// stretches of sustained curvature.

class _Arc {
  final double startFraction;
  final double endFraction;
  _Arc(this.startFraction, this.endFraction);
  double get centerFraction => (startFraction + endFraction) / 2;
  double get lengthFraction => endFraction - startFraction;
}

List<_Arc> _arcs(ConveyorPathGeometry g, {int samples = 2000}) {
  final headings = <double>[];
  for (var i = 0; i <= samples; i++) {
    final t = g.tangentAt(i / samples);
    var a = atan2(t.vector.dy, t.vector.dx);
    if (headings.isNotEmpty) {
      while (a - headings.last > pi) {
        a -= 2 * pi;
      }
      while (headings.last - a > pi) {
        a += 2 * pi;
      }
    }
    headings.add(a);
  }
  final arcs = <_Arc>[];
  int? start;
  for (var i = 0; i < samples; i++) {
    // Radians of heading change per sample; straight runs are ~0.
    final turning = (headings[i + 1] - headings[i]).abs() > 1e-4;
    if (turning && start == null) start = i;
    if (!turning && start != null) {
      arcs.add(_Arc(start / samples, i / samples));
      start = null;
    }
  }
  if (start != null) arcs.add(_Arc(start / samples, 1.0));
  return arcs;
}

void main() {
  test('paired turns center their arcs on the configured positions', () {
    // Positions can only be honoured where the box leaves a choice: a
    // single turn's two runs are pinned by the box (one must span its
    // width, the other its height), but as soon as runs share a heading
    // their proportions are free — and those proportions are exactly what
    // the position sliders express. An S keeps its entry and exit heading,
    // so the two bends can sit anywhere along the belt.
    final g = ConveyorPathGeometry.build(
      [
        ConveyorTurnEntry(position: 0.3, angle: 60, radius: 1.5),
        ConveyorTurnEntry(position: 0.65, angle: -60, radius: 1.5),
      ],
      const Size(600, 200),
      thicknessFactor: 0.15,
    )!;
    final arcs = _arcs(g);
    expect(arcs, hasLength(2));
    expect(arcs[0].centerFraction, closeTo(0.3, 0.05),
        reason: 'the first bend should sit where its slider says');
    expect(arcs[1].centerFraction, closeTo(0.65, 0.05),
        reason: 'the second bend should sit where its slider says');
  });

  test('symmetric positions produce mirror-image arc centers', () {
    final g = ConveyorPathGeometry.build(
      [
        ConveyorTurnEntry(position: 0.25, angle: 45, radius: 1.5),
        ConveyorTurnEntry(position: 0.75, angle: -45, radius: 1.5),
      ],
      const Size(600, 200),
      thicknessFactor: 0.15,
    )!;
    final arcs = _arcs(g);
    expect(arcs, hasLength(2));
    expect(arcs[0].centerFraction + arcs[1].centerFraction, closeTo(1.0, 0.02),
        reason: 'mirrored sliders must give a mirrored belt');
  });

  test(
      'a turn pushed to the very start hugs the start at full radius '
      'instead of collapsing or drifting in', () {
    // The reported S-conveyor: down 40 and back up 40, first bend at 1%.
    const beltFraction = 0.2;
    final g = ConveyorPathGeometry.build(
      [
        ConveyorTurnEntry(position: 0.01, angle: 40, radius: 1.5),
        ConveyorTurnEntry(position: 0.5, angle: -40, radius: 1.5),
      ],
      const Size(600, 200),
      thicknessFactor: beltFraction,
    )!;
    final arcs = _arcs(g);
    expect(arcs, hasLength(2));
    final first = arcs.first;

    // Full radius: the arc's on-screen length must be what a 40 degree
    // fillet of the configured radius measures, not a pinched remnant.
    // Radius and belt width scale together with the fit.
    final expectedArcLen = (1.5 * g.beltWidth * g.scale) * (40 * pi / 180);
    expect(first.lengthFraction * g.length, closeTo(expectedArcLen, expectedArcLen * 0.15),
        reason: 'the bend radius must not be sacrificed to reach the slider '
            'position');

    // As close to the requested 1% as the radius physically allows: the
    // arc center cannot come closer to the end than half the arc itself.
    final minimumCenter = first.lengthFraction / 2;
    expect(first.centerFraction, lessThanOrEqualTo(minimumCenter + 0.02),
        reason: 'a bend asked to sit at the start should hug the start');
  });
}
