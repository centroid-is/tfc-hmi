import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:tfc/widgets/panes/standard_dialog.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/providers/collector.dart';
import 'dart:math';
import 'package:tfc/widgets/number_slider.dart';
import 'common.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import '../../widgets/graph.dart';
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'auger_conveyor_painter.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/collector.dart';
import '../page.dart';
import 'conveyor_gate.dart';

part 'conveyor.g.dart';

/// Deserialize gates list with backward compatibility for old format.
///
/// Old format: gate config at root level with "asset_name" key.
/// New format: ChildGateEntry with "position", "side", and "gate" sub-object.
List<ChildGateEntry> _gatesFromJson(List<dynamic>? json) {
  if (json == null) return [];
  return json.map((item) {
    final map = item as Map<String, dynamic>;
    // Old format: gate config at root level with "asset_name" key
    if (map.containsKey('asset_name') && !map.containsKey('gate')) {
      final position = (map['position'] as num?)?.toDouble() ?? 0.5;
      final side = map['side'] != null
          ? GateSide.values.firstWhere(
              (e) => e.name == map['side'],
              orElse: () => GateSide.left,
            )
          : GateSide.left;
      return ChildGateEntry(
        position: position,
        side: side,
        gate: ConveyorGateConfig.fromJson(map),
      );
    }
    // New format: ChildGateEntry with "gate" sub-object
    return ChildGateEntry.fromJson(map);
  }).toList();
}

List<Map<String, dynamic>> _gatesToJson(List<ChildGateEntry> gates) =>
    gates.map((e) => e.toJson()).toList();

/// A bend in the conveyor belt.
///
/// The belt runs straight until [position] (fraction of the configured belt
/// length), then follows a circular arc of [radius] belt-widths sweeping
/// [angle] degrees, and continues straight in the new direction. Positive
/// angles turn towards the bottom of the screen, negative towards the top
/// (before the asset's own rotation is applied).
@JsonSerializable()
class ConveyorTurnEntry {
  /// Fractional position along the belt where the turn starts (0.0 = start).
  double position;

  /// Sweep of the turn in degrees. Positive = down/clockwise on screen.
  double angle;

  /// Turn radius expressed in belt widths (the conveyor's cross dimension).
  double radius;

  ConveyorTurnEntry({
    this.position = 0.5,
    this.angle = 45,
    this.radius = 1.5,
  });

  /// Where a freshly added turn should sit: the middle of the widest stretch
  /// of belt no turn occupies yet.
  ///
  /// Every new turn used to land on 0.5. A second one therefore shared the
  /// first one's corner, where each fillet is clamped to the zero-length
  /// straight between them and both bends paint as a single sharp corner —
  /// so adding a turn looked like nothing happened, and deleting either of
  /// them looked like the wrong one went.
  static double freePosition(List<ConveyorTurnEntry> existing) {
    if (existing.isEmpty) return 0.5;
    final taken = existing.map((t) => t.position.clamp(0.0, 1.0)).toList()
      ..sort();
    var widest = -1.0;
    var pick = 0.5;
    for (var i = 0; i <= taken.length; i++) {
      final lo = i == 0 ? 0.0 : taken[i - 1];
      final hi = i == taken.length ? 1.0 : taken[i];
      if (hi - lo > widest) {
        widest = hi - lo;
        pick = (lo + hi) / 2;
      }
    }
    return pick;
  }

  factory ConveyorTurnEntry.fromJson(Map<String, dynamic> json) =>
      _$ConveyorTurnEntryFromJson(json);
  Map<String, dynamic> toJson() => _$ConveyorTurnEntryToJson(this);
}

/// Centerline geometry of a conveyor with one or more [ConveyorTurnEntry]
/// bends, fitted into the asset's bounding box.
///
/// The centerline is built in "natural" units where the belt length equals the
/// box width and the belt width equals the box height (matching the straight
/// rendering), then uniformly scaled and centered so the whole belt stays
/// inside the box. Fractional belt positions (batches, gates) map onto the
/// path through its [PathMetric].
class ConveyorPathGeometry {
  final Path path;
  final double beltWidth;
  final double scale;
  final PathMetric _metric;

  ConveyorPathGeometry._(this.path, this.beltWidth, this.scale, this._metric);

  double get length => _metric.length;

  Tangent tangentAt(double fraction) =>
      _metric.getTangentForOffset(fraction.clamp(0.0, 1.0) * length) ??
      Tangent(Offset.zero, const Offset(1, 0));

  Path extractFraction(double from, double to) => _metric.extractPath(
      from.clamp(0.0, 1.0) * length, to.clamp(0.0, 1.0) * length);

  /// Outline of a band running along [from]..[to] of the belt: a rectangle
  /// [width] across with its four corners rounded by [radius], bent to follow
  /// the centerline.
  ///
  /// This is the shape a straight belt draws with a single `RRect` — for the
  /// belt itself and for every batch on it. Stroking the centerline instead
  /// cannot produce it: a stroke's cap is a half circle, and squaring one off
  /// against a bend leaves a wedge where the cap and the body meet at
  /// different angles.
  ///
  /// Null when the band is wider than its own bend can carry — the inner edge
  /// would reach past the centre of curvature and fold the outline into a bow
  /// tie. Callers fall back to stroking the centerline there, which is
  /// meaningless geometry either way but at least stays solid.
  Path? bandOutline(double from, double to,
      {required double width, required double radius}) {
    final start = from.clamp(0.0, 1.0) * length;
    final span = to.clamp(0.0, 1.0) * length - start;
    if (span <= 0 || width <= 0) return Path();
    final half = width / 2;
    // Same clamping an RRect applies when the radii do not fit the rect.
    final r = max(min(min(radius, half), span / 2), 0.0);

    /// Half-width of a rounded rectangle [d] along from its nearer flat end.
    double halfWidthAt(double d) {
      if (r <= 0 || d >= r) return half;
      final k = r - d;
      return (half - r) + sqrt(max(r * r - k * k, 0));
    }

    // Dense through the two corners, every few pixels along the middle.
    const cornerSteps = 12;
    final middleSteps = max((span / 4).ceil(), 2);
    final offsets = <double>{0, span};
    for (var i = 0; i <= cornerSteps; i++) {
      offsets.add(r * i / cornerSteps);
      offsets.add(span - r * i / cornerSteps);
    }
    for (var i = 0; i <= middleSteps; i++) {
      offsets.add(span * i / middleSteps);
    }

    final ordered = offsets.toList()..sort();
    final samples = <double>[];
    final tangents = <Tangent>[];
    for (final d in ordered) {
      final t = _metric.getTangentForOffset(start + d);
      if (t == null) continue;
      samples.add(d);
      tangents.add(t);
    }
    if (samples.length < 2) return Path();

    // Heading along the run, unwrapped so a bend does not read as a jump.
    final heading = <double>[];
    for (var i = 0; i < tangents.length; i++) {
      var a = atan2(tangents[i].vector.dy, tangents[i].vector.dx);
      if (i > 0) {
        while (a - heading[i - 1] > pi) {
          a -= 2 * pi;
        }
        while (heading[i - 1] - a > pi) {
          a += 2 * pi;
        }
      }
      heading.add(a);
    }

    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < samples.length; i++) {
      final t = tangents[i];
      final normal = Offset(-t.vector.dy, t.vector.dx);
      final h = halfWidthAt(min(samples[i], span - samples[i]));
      // On the inside of a bend the edge cannot reach past the centre of
      // curvature without crossing the centerline, which folds the outline
      // into a bow tie. There is no honest band to draw at that point.
      final lo = max(i - 1, 0), hi = min(i + 1, samples.length - 1);
      final ds = samples[hi] - samples[lo];
      final curvature = ds > 1e-9 ? (heading[hi] - heading[lo]) / ds : 0.0;
      // With a little margin: an edge that merely grazes the centre of
      // curvature already leaves a cusp the border traces as a stray hair.
      if (curvature.abs() > 1e-9 && h > 0.9 / curvature.abs()) return null;
      left.add(t.position + normal * h);
      right.add(t.position - normal * h);
    }

    final outline = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      outline.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      outline.lineTo(p.dx, p.dy);
    }
    return outline..close();
  }

  /// Whether a fill solve still resembles the configured belt.
  ///
  /// Stretching runs is the point of the solve, but a run crushed to nothing
  /// while its neighbours grow is the belt being folded into a different
  /// shape. A run may shrink, but not more than a factor of four below the
  /// uniform rescale.
  static bool _keepsProportions(List<double> before, List<double> after) {
    final totalBefore = before.fold<double>(0, (a, b) => a + b);
    final totalAfter = after.fold<double>(0, (a, b) => a + b);
    if (totalBefore <= 0 || totalAfter <= 0) return false;
    final g = totalAfter / totalBefore;
    for (var i = 0; i < before.length; i++) {
      if (before[i] <= 1e-9) continue; // was zero, allowed to stay zero
      if (after[i] < before[i] * g / 4) return false;
    }
    return true;
  }

  /// Whether stroking [path] at [beltWidth] would paint the belt over
  /// itself — two stretches far apart along the belt but closer across it
  /// than the belt is wide.
  ///
  /// A solve is free to move the runs, and nothing in the extents stops it
  /// from parking the exit run of a U-turn on top of its entry run: both
  /// bounds still match the box. Overlap is what makes that wrong, so test
  /// for it directly. Belts *configured* to self-overlap look the same
  /// before and after the solve and are the fallback's problem either way.
  static bool _selfOverlaps(Path path, double beltWidth) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return false;
    final metric = metrics.first;
    const samples = 64;
    final pts = <Offset>[];
    for (var i = 0; i <= samples; i++) {
      final t = metric.getTangentForOffset(metric.length * i / samples);
      if (t == null) return false;
      pts.add(t.position);
    }
    final step = metric.length / samples;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        // Neighbours along the belt are close by construction; only count
        // stretches separated by enough arc length to be different runs.
        if ((j - i) * step <= 2 * beltWidth) continue;
        if ((pts[i] - pts[j]).distance < beltWidth * 0.9) return true;
      }
    }
    return false;
  }

  static ConveyorPathGeometry? build(
    List<ConveyorTurnEntry> turns,
    Size size, {
    double thicknessFactor = 1.0,
    double? beltWidthOverride,
  }) {
    if (turns.isEmpty || size.width <= 0 || size.height <= 0) return null;
    // Belt thickness relative to the box height. A bend needs a taller box to
    // fit, which would otherwise force a fat belt — the factor lets e.g. an
    // L-shaped conveyor in a square box keep a thin belt.
    //
    // A turned belt curves in both axes, so a thickness taken from the height
    // can exceed the *width* in a tall narrow box and spill out sideways no
    // matter how the centerline is fitted. Cap it against the short side so
    // the box invariant always holds; for the usual wide box this is a no-op.
    const margin = 2.0;
    final containable = max(size.shortestSide - 2 * margin, 1.0);
    // An explicit belt width is given in screen units, so the same number has
    // to mean the same belt everywhere — resizing the box must not silently
    // change it. Only the box-relative thickness is, by definition, bounded
    // by the box.
    final double beltWidth;
    final double fitWidth;
    if (beltWidthOverride != null) {
      beltWidth = beltWidthOverride;
      // The fit insets the box by half the belt width so the belt lands
      // inside it. Once the belt is wider than the box that is unreachable,
      // and insetting anyway squeezes the centerline into a sliver — the
      // bend collapses into a blob. So hand the inset back as the overflow
      // grows: at the limit it is still the full belt (no jump), and by
      // twice the limit the bare centerline is fitted and the belt simply
      // spills over the box.
      final overflow = max(beltWidthOverride - containable, 0.0);
      fitWidth = max(min(beltWidthOverride, containable) - overflow, 0.0);
    } else {
      beltWidth =
          min(size.height * thicknessFactor.clamp(0.05, 1.0), containable);
      fitWidth = beltWidth;
    }
    final sorted = List<ConveyorTurnEntry>.of(turns)
      ..sort((a, b) => a.position.compareTo(b.position));

    // Turns are CAD fillets on a skeleton of straight runs: each keeps its
    // configured sweep, and its radius is truly `radius * beltWidth` on
    // screen. The straights are what flexes — they stretch or shrink so the
    // belt fills the bounding box, the way a conveyor is actually drawn into
    // a floor plan: the bend is fixed geometry, the runs absorb the space.
    //
    // The arc must not consume the positional budget. When it did, every
    // straight after a turn was only whatever was left over, so a symmetric
    // set of positions produced an asymmetric belt — the run into the first
    // turn kept its full length while the run out of the last one got the
    // remainder — and a large radius silently deleted straights entirely.
    final active = sorted.where((t) => t.angle != 0).toList();
    final sweeps = [
      for (final t in active)
        // tan blows up at a half turn, so stop just short of it.
        (t.angle.clamp(-179.5, 179.5)) * pi / 180
    ];
    final n = active.length;
    // Capped: a fillet radii beyond any box (hand-edited JSON, slider abuse)
    // only gets uniformly scaled down again, and taken literally it
    // overflows the seeding arithmetic into non-finite geometry.
    final radii = [
      for (final t in active)
        min(max(t.radius, 0.1) * beltWidth, size.longestSide * 1e3)
    ];

    final inset = fitWidth / 2 + margin;
    final inner = Size(
        max(size.width - 2 * inset, 1.0), max(size.height - 2 * inset, 1.0));

    // Straight runs between consecutive corners: seg[0] leads into the first
    // corner, seg[n] leaves the last one. Positions seed their proportions;
    // the fill solve rescales them per axis afterwards.
    //
    // A position points at the *center of the corner arc*, measured along
    // the belt — the arc is the bend the operator sees, so it is what the
    // slider must move. Seeded on the skeleton's corner points instead, the
    // run into a bend and the arc's own length pushed the visible corner
    // away from the configured number. The skeleton distances are the path
    // lengths with each fillet's tangent runs added back: a fillet replaces
    // 2*tangent of skeleton with its arc of belt.
    //
    // A radius can make a position physically unreachable — the arc's
    // center needs half the arc of belt before it, and neighbouring
    // fillets need their tangent runs — so such positions clamp to the
    // closest spot the fillet still fits at full radius, rather than
    // pinching the bend to honour a number nobody can see honoured.
    final naturalLength = inner.width;
    final tangentLen = [
      for (var i = 0; i < n; i++) radii[i] * tan(sweeps[i].abs() / 2)
    ];
    final arcLen = [for (var i = 0; i < n; i++) radii[i] * sweeps[i].abs()];
    // Each run's ideal skeleton length: the belt distance between the arc
    // centers it connects (box start and end count as centers of nothing),
    // with each adjacent fillet's tangent run added back and half its arc
    // taken out — a fillet replaces 2*tangent of skeleton with its arc of
    // belt. Written as differences of neighbouring positions, not a running
    // sum, so a clamp on one run cannot leak asymmetry into the others.
    final seg = <double>[];
    for (var i = 0; i <= n; i++) {
      final prevCenter = i == 0
          ? 0.0
          : active[i - 1].position.clamp(0.0, 1.0) * naturalLength;
      final nextCenter = i == n
          ? naturalLength
          : active[i].position.clamp(0.0, 1.0) * naturalLength;
      var ideal = nextCenter - prevCenter;
      if (i > 0) ideal += tangentLen[i - 1] - arcLen[i - 1] / 2;
      if (i < n) ideal += tangentLen[i] - arcLen[i] / 2;
      final minimum = (i > 0 ? tangentLen[i - 1] : 0.0) +
          (i < n ? tangentLen[i] : 0.0);
      seg.add(max(ideal, minimum));
    }

    var fillClamped = false;
    Path buildPath(List<double> seg) {
      fillClamped = false;
      // Tangent length each fillet eats out of the straights beside it —
      // shrink fillets that do not fit rather than dropping the straight:
      // first against each neighbouring run, then the pair sharing a run.
      final tangent = <double>[];
      for (var i = 0; i < n; i++) {
        tangent.add(radii[i] * tan(sweeps[i].abs() / 2));
      }
      final wanted = List<double>.of(tangent);
      for (var i = 0; i < n; i++) {
        tangent[i] = min(tangent[i], seg[i]);
        tangent[i] = min(tangent[i], seg[i + 1]);
      }
      for (var i = 1; i < n; i++) {
        final pair = tangent[i - 1] + tangent[i];
        if (pair > seg[i] && pair > 0) {
          final scale = seg[i] / pair;
          tangent[i - 1] *= scale;
          tangent[i] *= scale;
        }
      }
      for (var i = 0; i < n; i++) {
        if (tangent[i] < wanted[i] - 1e-6) fillClamped = true;
      }

      final path = Path()..moveTo(0, 0);
      var corner = Offset.zero;
      var heading = 0.0;
      for (var i = 0; i < n; i++) {
        final inDir = Offset(cos(heading), sin(heading));
        final c = corner + inDir * seg[i];
        final arcStart = c - inDir * tangent[i];
        path.lineTo(arcStart.dx, arcStart.dy);
        heading += sweeps[i];
        final outDir = Offset(cos(heading), sin(heading));
        final arcEnd = c + outDir * tangent[i];
        final effectiveRadius = tangent[i] / tan(sweeps[i].abs() / 2);
        if (tangent[i] > 0 && effectiveRadius.isFinite && effectiveRadius > 0) {
          path.arcToPoint(
            arcEnd,
            radius: Radius.circular(effectiveRadius),
            clockwise: sweeps[i] > 0,
          );
        } else {
          // No room to round the corner — keep it sharp rather than skip it.
          path.lineTo(arcEnd.dx, arcEnd.dy);
        }
        corner = c;
      }
      final tail = corner + Offset(cos(heading), sin(heading)) * seg[n];
      path.lineTo(tail.dx, tail.dy);
      return path;
    }

    // Fill solve: nudge each straight until the centerline's bounds match the
    // inner box on both axes. A run contributes to each axis by its heading,
    // so a horizontal run absorbs width, a vertical one height, a diagonal a
    // blend — and runs sharing a heading keep their relative proportions,
    // which is what the position sliders express. The arcs are fixed
    // geometry; when they alone exceed an axis no seg change can fix it, the
    // residual stays, and the uniform-fit fallback below takes over.
    Path? solved;
    if (n > 0) {
      // Work on a copy: if the box cannot be filled, the fallback must fit
      // the position-faithful skeleton, not whatever the failed solve left.
      final trial = List<double>.of(seg);
      final headings = <double>[0.0];
      for (final sweep in sweeps) {
        headings.add(headings.last + sweep);
      }
      var path = buildPath(trial);
      for (var iter = 0; iter < 40; iter++) {
        final b = path.getBounds();
        // A fill only counts when every fillet kept its true radius. The
        // solve can always "fill" a too-small box by pinching corners sharp
        // and amputating runs — a belt that fits the box by no longer being
        // the belt that was configured. That case belongs to the fallback.
        if (!fillClamped &&
            (b.width - inner.width).abs() < 0.5 &&
            (b.height - inner.height).abs() < 0.5 &&
            _keepsProportions(seg, trial) &&
            !_selfOverlaps(path, beltWidth)) {
          solved = path;
          break;
        }
        final fx = b.width > 1e-6 ? inner.width / b.width : 1.0;
        final fy = b.height > 1e-6 ? inner.height / b.height : 1.0;
        for (var i = 0; i <= n; i++) {
          final wx = cos(headings[i]).abs();
          final wy = sin(headings[i]).abs();
          final f = (fx * wx + fy * wy) / (wx + wy);
          trial[i] = max(trial[i] * f, 0.0);
        }
        path = buildPath(trial);
      }
    }

    final Path fitted;
    final double fit;
    if (solved != null) {
      // Solved: the belt fills the box at true scale. The residual is under
      // half a pixel; squeeze it out rather than let the paint cross the box.
      final bounds = solved.getBounds();
      final clamp = min(
          1.0,
          min(bounds.width > 1e-6 ? inner.width / bounds.width : 1.0,
              bounds.height > 1e-6 ? inner.height / bounds.height : 1.0));
      fit = clamp;
      // Centre on the box, not on the inset origin: a box thinner than the
      // belt clamps `inner` to a floor, and anchoring to the inset would
      // push the centerline off-centre and the paint over the box edge.
      final dx = size.width / 2 - bounds.center.dx * clamp;
      final dy = size.height / 2 - bounds.center.dy * clamp;
      fitted = solved.transform(Matrix4(
        clamp, 0, 0, 0, //
        0, clamp, 0, 0, //
        0, 0, 1, 0, //
        dx, dy, 0, 1,
      ).storage);
    } else {
      // Unfillable box (arcs alone overrun an axis, or a straight belt):
      // uniform fit inside, centred — bends shrink below true radius, which
      // is the least-wrong rendering left.
      final path = buildPath(seg);
      final bounds = path.getBounds();
      final sx =
          bounds.width > 1e-6 ? inner.width / bounds.width : double.infinity;
      final sy =
          bounds.height > 1e-6 ? inner.height / bounds.height : double.infinity;
      var f = min(sx, sy);
      if (!f.isFinite || f <= 0) f = 1.0;
      fit = f;
      final dx = size.width / 2 - bounds.center.dx * fit;
      final dy = size.height / 2 - bounds.center.dy * fit;
      final matrix = Matrix4(
        fit, 0, 0, 0, //
        0, fit, 0, 0, //
        0, 0, 1, 0, //
        dx, dy, 0, 1,
      );
      fitted = path.transform(matrix.storage);
    }
    final metrics = fitted.computeMetrics().toList();
    if (metrics.isEmpty) return null;
    final geometry =
        ConveyorPathGeometry._(fitted, beltWidth, fit, metrics.first);

    // Center the ink, not the centerline. The band extends beltWidth/2 past
    // the centerline on the outer side of every run but ends in a flat cap,
    // so around an L the ink is lopsided against the centerline's bounds —
    // centered on those, the belt visibly hugs one corner of its box. The
    // shift is at most beltWidth/4 per axis, which the fit's own inset
    // (beltWidth/2 + margin per side) always has room for.
    final ink = geometry
            .bandOutline(0, 1,
                width: beltWidth,
                radius: beltWidth * ConveyorPainter._endRadiusFactor)
            ?.getBounds() ??
        // Over-wide belt: the painter falls back to a round-capped stroke,
        // whose ink is the centerline inflated evenly — nothing to correct.
        fitted.getBounds().inflate(beltWidth / 2);
    // Per axis, and only while the ink fits: an over-wide belt spills over
    // the box by design, and dragging its centerline around to center the
    // spill would break the skeleton's own containment.
    final shift = Offset(
      ink.width <= size.width ? size.width / 2 - ink.center.dx : 0.0,
      ink.height <= size.height ? size.height / 2 - ink.center.dy : 0.0,
    );
    // Hostile configs (hand-edited JSON) can degenerate into non-finite
    // bounds; Path.shift asserts on NaN, and there is nothing to center.
    if (!shift.dx.isFinite || !shift.dy.isFinite) return geometry;
    if (shift.distance < 0.01) return geometry;
    final moved = fitted.shift(shift);
    final movedMetrics = moved.computeMetrics().toList();
    if (movedMetrics.isEmpty) return geometry;
    return ConveyorPathGeometry._(moved, beltWidth, fit, movedMetrics.first);
  }
}

@JsonSerializable(explicitToJson: true)
class ConveyorColorPaletteConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor Palette';
  @override
  String get category => 'Visualization';

  ConveyorColorPaletteConfig();
  bool? preview = false;

  @override
  Widget build(BuildContext context) => ConveyorColorPalette(config: this);

  @override
  Widget configure(BuildContext context) {
    return Column(
      children: [
        SizeField(
          initialValue: size,
          onChanged: (size) => this.size = size,
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: coordinates,
          onChanged: (coordinates) => this.coordinates = coordinates,
          enableAngle: true,
        ),
      ],
    );
  }

  ConveyorColorPaletteConfig.preview() : preview = true;

  factory ConveyorColorPaletteConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorColorPaletteConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ConveyorColorPaletteConfigToJson(this);
}

class ConveyorColorPalette extends StatelessWidget {
  final ConveyorColorPaletteConfig config;
  const ConveyorColorPalette({required this.config});

  @override
  Widget build(BuildContext context) {
    // First, compute the exact width/height we want from config.size:
    final size = config.size.toSize(MediaQuery.of(context).size);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          // ─── Top "title" row ───
          const Expanded(
            flex: 1,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Conveyor colors',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildColorRow(Colors.green, 'Auto', textColor: Colors.white),
                _buildColorRow(Colors.blue, 'Clean', textColor: Colors.white),
                _buildColorRow(Colors.yellow, 'Manual',
                    textColor: Colors.blueGrey),
                _buildColorRow(Colors.grey, 'Stopped', textColor: Colors.white),
                _buildColorRow(Colors.red, 'Fault', textColor: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper that returns an Expanded widget wrapping a padded Container of a given color,
  /// with text that always fills/shrinks to fit that container.
  Widget _buildColorRow(Color background, String label,
      {required Color textColor}) {
    return Expanded(
      flex: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ConveyorConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor';
  @override
  String get category => 'Visualization';

  String? key;
  String? batchesKey;
  String? frequencyKey;
  String? tripKey;
  bool? simulateBatches;
  bool? bidirectional;
  bool? reverseDirection;
  bool? showFrequency;
  bool? showAuger;
  String? augerRpmKey;
  AugerOpenEnd? augerOpenEnd;

  @JsonKey(fromJson: _gatesFromJson, toJson: _gatesToJson)
  List<ChildGateEntry> gates;

  /// Bends along the belt; empty means a straight conveyor.
  List<ConveyorTurnEntry> turns;

  /// Belt thickness as a fraction of the box height (turned conveyors only).
  ///
  /// A bend needs a taller bounding box, which with the straight convention
  /// (belt thickness = box height) would force a fat belt.
  double? beltThickness;

  /// Thickness actually used for rendering.
  ///
  /// A straight belt keeps the old convention of filling the box height. A
  /// turned belt cannot: the bend needs vertical room *on top of* the belt
  /// thickness, and at 1.0 there is none left, so the belt degenerates into a
  /// blob. Defaulting turned belts to a fraction of the box keeps a freshly
  /// added turn usable without touching a second setting.
  double get effectiveBeltThickness =>
      beltThickness ?? (turns.isEmpty ? 1.0 : _defaultTurnedThickness);

  static const _defaultTurnedThickness = 0.4;

  /// Belt width as a fraction of the screen height — the same units as
  /// [size], so a straight belt set to 4% and a turned belt set to 4% paint
  /// the same width and line up on a page.
  ///
  /// Applies with or without turns. Null falls back to [beltThickness] /
  /// [effectiveBeltThickness], which are relative to the box instead.
  double? beltWidthRelative;

  /// Requested belt width in logical pixels, or null when the box-relative
  /// thickness should be used instead.
  double? requestedBeltWidth(Size screen) =>
      beltWidthRelative == null ? null : beltWidthRelative! * screen.height;

  /// The widest belt this asset's box can hold. A belt is a band across the
  /// box, and a turned belt curves in both axes, so a bend is bounded by the
  /// short side rather than the height.
  double maxBeltWidth(Size screen) {
    final box = size.toSize(screen);
    return max((turns.isEmpty ? box.height : box.shortestSide) - 4, 1.0);
  }

  /// Whether the requested belt width is wider than its box, so the belt
  /// paints over the box edge and the editor should say so.
  ///
  /// The width itself is still honoured — it is set in screen units, and a
  /// setting that quietly changed whenever the box was resized would not be
  /// worth having. Only selection and hit-testing stay on the box.
  bool beltWidthOverflows(Size screen) {
    final requested = requestedBeltWidth(screen);
    return requested != null && requested > maxBeltWidth(screen);
  }

  ConveyorConfig(
      {this.key,
      this.batchesKey,
      this.frequencyKey,
      this.tripKey,
      this.simulateBatches,
      this.bidirectional,
      this.reverseDirection,
      this.showFrequency,
      this.showAuger,
      this.augerRpmKey,
      this.augerOpenEnd,
      this.beltThickness,
      List<ChildGateEntry>? gates,
      List<ConveyorTurnEntry>? turns})
      : gates = gates != null ? List<ChildGateEntry>.of(gates) : [],
        turns = turns != null ? List<ConveyorTurnEntry>.of(turns) : [];

  static const previewStr = 'Conveyor Preview';

  ConveyorConfig.preview()
      : gates = [],
        turns = [],
        key = previewStr;

  @override
  Widget build(BuildContext context) => Conveyor(this);

  @override
  Widget configure(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: _ConveyorConfigContent(config: this),
      ),
    );
  }

  factory ConveyorConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ConveyorConfigToJson(this);
}

class _ConveyorConfigContent extends StatefulWidget {
  final ConveyorConfig config;
  const _ConveyorConfigContent({required this.config});

  @override
  State<_ConveyorConfigContent> createState() => _ConveyorConfigContentState();
}

class _ConveyorConfigContentState extends State<_ConveyorConfigContent> {
  @override
  void initState() {
    super.initState();
    // Pages saved before turns were kept in belt order.
    _sortTurns();
    _pinBeltWidth();
  }

  /// Makes the belt width of a turned belt an explicit number.
  ///
  /// A turned belt has exactly one width knob — the screen-relative field.
  /// Configs from before that field existed carry a box-relative thickness
  /// instead, whose meaning shifts every time the box is resized; freeze
  /// what it currently resolves to so the panel always shows one number and
  /// the render never moves behind the user's back.
  void _pinBeltWidth() {
    if (widget.config.turns.isEmpty) return;
    widget.config.beltWidthRelative ??=
        widget.config.effectiveBeltThickness * widget.config.size.height;
  }

  /// Keeps [ConveyorConfig.turns] in the order the belt actually bends.
  ///
  /// [ConveyorPathGeometry.build] sorts by position, so the belt's first bend
  /// is the lowest position. The panel listed insertion order and numbered
  /// the cards from it, and "Add Turn" appends — so as soon as a turn was
  /// added after an earlier one had been dragged along the belt, "Turn 1" in
  /// the panel was some other bend, and its delete button took out a turn the
  /// user was not looking at.
  ///
  /// Sorting the list itself rather than a display copy keeps the card order
  /// stable while a position slider is being dragged; the reorder happens
  /// once the drag ends.
  void _sortTurns() {
    widget.config.turns.sort((a, b) => a.position.compareTo(b.position));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyField(
          initialValue: widget.config.key,
          onChanged: (val) => setState(() => widget.config.key = val),
          label: 'Main key (optional)',
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.batchesKey,
          onChanged: (val) => setState(() => widget.config.batchesKey = val),
          label: 'Batches key',
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.frequencyKey,
          onChanged: (val) => setState(() => widget.config.frequencyKey = val),
          label: 'Frequency key',
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.tripKey,
          onChanged: (val) => setState(() => widget.config.tripKey = val),
          label: 'Trip key',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Simulate batches:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.simulateBatches ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.simulateBatches = val)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Bidirectional:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.bidirectional ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.bidirectional = val)),
          ],
        ),
        if (widget.config.bidirectional ?? false) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Reverse direction:'),
              const SizedBox(width: 8),
              Checkbox(
                  value: widget.config.reverseDirection ?? false,
                  onChanged: (val) =>
                      setState(() => widget.config.reverseDirection = val)),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Show frequency:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.showFrequency ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.showFrequency = val)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Auger conveyor:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.showAuger ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.showAuger = val)),
          ],
        ),
        if (widget.config.showAuger ?? false) ...[
          const SizedBox(height: 8),
          KeyField(
            initialValue: widget.config.augerRpmKey,
            onChanged: (val) => setState(() => widget.config.augerRpmKey = val),
            label: 'Output shaft RPM key',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Open end:'),
              const SizedBox(width: 8),
              DropdownButton<AugerOpenEnd?>(
                value: widget.config.augerOpenEnd,
                onChanged: (val) =>
                    setState(() => widget.config.augerOpenEnd = val),
                items: const [
                  DropdownMenuItem(
                      value: AugerOpenEnd.right, child: Text('Right')),
                  DropdownMenuItem(
                      value: AugerOpenEnd.left, child: Text('Left')),
                  DropdownMenuItem(value: null, child: Text('None')),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        SizeField(
          initialValue: widget.config.size,
          onChanged: (size) => setState(() => widget.config.size = size),
          // The box runs along the belt, so its width is how long the
          // conveyor is and its height is how wide the belt sits.
          widthLabel: 'Length %',
          heightLabel: 'Width %',
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (c) => setState(() => widget.config.coordinates = c),
          enableAngle: true,
        ),
        const SizedBox(height: 16),
        const Divider(),
        Text('Gates', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              widget.config.gates
                  .add(ChildGateEntry(gate: ConveyorGateConfig()));
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Gate'),
        ),
        const SizedBox(height: 8),
        if (widget.config.gates.isEmpty)
          Text('No gates configured',
              style: Theme.of(context).textTheme.bodyMedium)
        else
          ...widget.config.gates.asMap().entries.map((mapEntry) {
            final entry = mapEntry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: variant name + edit/delete
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.gate.gateVariant.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Edit gate',
                          onPressed: () => showStandardDialog<void>(
                            context: context,
                            title: 'Edit gate',
                            icon: Icons.swap_horiz,
                            width: 360,
                            closeLabel: 'Done',
                            builder: (context) => SizedBox(
                              width: 300,
                              child: entry.gate.configure(context),
                            ),
                          ).then((_) => setState(() {})),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          tooltip: 'Remove gate',
                          onPressed: () => setState(() {
                            widget.config.gates.removeAt(
                              widget.config.gates.indexOf(entry),
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Side toggle: Top (left) / Bottom (right)
                    Text('Conveyor Side',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    SegmentedButton<GateSide>(
                      segments: const [
                        ButtonSegment(value: GateSide.left, label: Text('Top')),
                        ButtonSegment(
                            value: GateSide.right, label: Text('Bottom')),
                      ],
                      selected: {entry.side},
                      onSelectionChanged: (selection) {
                        setState(() => entry.side = selection.first);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Position slider
                    NumberSlider(
                      labelAbove: true,
                      label: 'Belt Position',
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                      displayScale: 100,
                      suffix: '%',
                      value: entry.position,
                      onChanged: (v) => setState(() => entry.position = v),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        const Divider(),
        Text('Turns', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              widget.config.turns.add(ConveyorTurnEntry(
                position: ConveyorTurnEntry.freePosition(widget.config.turns),
              ));
              _sortTurns();
              _pinBeltWidth();
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Turn'),
        ),
        const SizedBox(height: 8),
        _beltWidthField(context),
        const SizedBox(height: 8),
        if (widget.config.turns.isEmpty)
          Text('No turns configured — belt is straight',
              style: Theme.of(context).textTheme.bodyMedium)
        else ...[
          if (widget.config.showAuger ?? false)
            Text('Turns are ignored while "Auger conveyor" is enabled',
                style: Theme.of(context).textTheme.bodySmall),
          ...widget.config.turns.asMap().entries.map((mapEntry) {
            final entry = mapEntry.value;
            return Card(
              // Identity, not index: ending a position drag can reorder the
              // cards, and the element state has to follow its own turn.
              key: ObjectKey(entry),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Turn ${mapEntry.key + 1}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          tooltip: 'Remove turn',
                          onPressed: () => setState(() {
                            widget.config.turns.remove(entry);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _turnValue(
                      context,
                      label: 'Belt position',
                      suffix: '%',
                      value: entry.position.clamp(0.0, 1.0) * 100,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      decimals: 0,
                      onChanged: (v) =>
                          setState(() => entry.position = v / 100),
                      // Dragging a turn past a neighbour changes which bend
                      // it is; renumber once the drag is over rather than
                      // shuffling cards under the pointer.
                      onSettled: () => setState(_sortTurns),
                    ),
                    _turnValue(
                      context,
                      label: 'Angle (${entry.angle >= 0 ? 'down' : 'up'})',
                      suffix: '°',
                      value: entry.angle.clamp(-180.0, 180.0),
                      min: -180,
                      max: 180,
                      divisions: 72,
                      decimals: 0,
                      onChanged: (v) => setState(() => entry.angle = v),
                    ),
                    _turnValue(
                      context,
                      label: 'Radius (× belt width)',
                      suffix: '×',
                      value: entry.radius.clamp(0.5, 5.0),
                      min: 0.5,
                      max: 5.0,
                      divisions: 45,
                      decimals: 1,
                      onChanged: (v) => setState(() => entry.radius = v),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  /// One turn setting: a label, a box you can type an exact value into, and a
  /// slider for the same number.
  ///
  /// The slider alone could not express a value between its divisions, and
  /// reading a turn back off a slider is guesswork — the box is the one that
  /// says what the turn actually is.
  Widget _turnValue(
    BuildContext context, {
    required String label,
    required String suffix,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required int decimals,
    required ValueChanged<double> onChanged,
    VoidCallback? onSettled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 78,
              child: _NumberBox(
                value: value,
                min: min,
                max: max,
                decimals: decimals,
                suffix: suffix,
                onChanged: onChanged,
                onSettled: onSettled,
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          label: value.toStringAsFixed(decimals),
          onChanged: onChanged,
          onChangeEnd: onSettled == null ? null : (_) => onSettled(),
        ),
      ],
    );
  }

  /// Belt width in the same screen-relative percent as the Size fields, so a
  /// straight belt and a turned belt set to the same number match on a page.
  /// Empty falls back to the box-relative thickness.
  Widget _beltWidthField(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final overflows = widget.config.beltWidthOverflows(screen);
    final maxPercent = widget.config.maxBeltWidth(screen) / screen.height * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: widget.config.beltWidthRelative == null
              ? ''
              : (widget.config.beltWidthRelative! * 100).toStringAsFixed(2),
          decoration: InputDecoration(
            labelText: 'Belt width (% of screen height)',
            hintText: 'Empty — belt fills the box',
            suffixText: '%',
            errorText: overflows
                ? 'Wider than the box (fits ${maxPercent.toStringAsFixed(2)}%) '
                    '— the belt is painted at the width you set and spills '
                    'over the box, which still owns selection and clicks.'
                : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() {
            final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
            widget.config.beltWidthRelative =
                parsed == null || parsed <= 0 ? null : parsed / 100;
          }),
        ),
      ],
    );
  }
}

/// A compact number box that stays in step with the slider beside it.
///
/// The value is pushed in from outside only while the box is not being
/// edited, so a keystroke is never overwritten mid-word, and what is typed is
/// clamped into the same range the slider covers.
class _NumberBox extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int decimals;
  final String suffix;
  final ValueChanged<double> onChanged;
  final VoidCallback? onSettled;

  const _NumberBox({
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.suffix,
    required this.onChanged,
    this.onSettled,
  });

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  String _format(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(_NumberBox old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _format(widget.value) != _controller.text) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    // Leaving the box tidies whatever was typed back into range, and settles
    // the value the same way letting go of the slider does.
    _controller.text = _format(widget.value);
    widget.onSettled?.call();
  }

  void _submit(String raw) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed == null) return;
    widget.onChanged(parsed.clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.numberWithOptions(
          decimal: widget.decimals > 0, signed: widget.min < 0),
      onChanged: _submit,
      onSubmitted: (v) {
        _submit(v);
        widget.onSettled?.call();
      },
    );
  }
}

class Conveyor extends ConsumerStatefulWidget {
  final ConveyorConfig config;
  const Conveyor(this.config, {Key? key}) : super(key: key);

  @override
  ConsumerState<Conveyor> createState() => _ConveyorState();
}

class _ConveyorState extends ConsumerState<Conveyor>
    with TickerProviderStateMixin {
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 2,
      lineLength: 80,
      colors: true,
      printEmojis: false,
    ),
  );
  final Map<String, Batch> _batches = {};
  // periodic timer for batches
  Timer? _simulateBatchesTimer;

  // Auger animation — ValueNotifier repaints only the CustomPaint, no setState
  final ValueNotifier<double> _augerPhase = ValueNotifier(0.0);
  Timer? _augerAnimationTimer;
  double _augerRpm = 0.0;

  void _updateAugerAnimation(double rpm) {
    _augerRpm = rpm;
    if (rpm != 0 && _augerAnimationTimer == null) {
      _augerAnimationTimer =
          Timer.periodic(const Duration(milliseconds: 32), (_) {
        if (!mounted) {
          _augerAnimationTimer?.cancel();
          _augerAnimationTimer = null;
          return;
        }
        var phase = _augerPhase.value + _augerRpm / 60.0 * 2 * pi * 0.032;
        if (phase > 2 * pi) phase -= 2 * pi;
        if (phase < -2 * pi) phase += 2 * pi;
        _augerPhase.value = phase;
      });
    } else if (rpm == 0 && _augerAnimationTimer != null) {
      _augerAnimationTimer?.cancel();
      _augerAnimationTimer = null;
    }
  }

  @override
  void dispose() {
    // A docked pane outlives the route that opened it, so a page change must
    // not leave this conveyor's pane behind.
    closeSidePane(id: _paneId);
    _augerAnimationTimer?.cancel();
    _augerPhase.dispose();
    _simulateBatchesTimer?.cancel();
    super.dispose();
  }

  void _startSimulateBatchesTimer() {
    _simulateBatchesTimer ??=
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (_batches.isNotEmpty) {
        final batch = _batches.values.first;
        batch.start += 0.01;
        batch.end += 0.01;
        if (batch.start >= 1) {
          _batches.clear();
        }
      } else {
        // length 10 % of conveyor
        _batches['0'] = Batch(start: -0.1, end: 0, color: Colors.yellow);
      }
      if (mounted) {
        setState(() {});
      } else {
        _simulateBatchesTimer?.cancel();
      }
    });
  }

  void _stopSimulateBatchesTimer() {
    _simulateBatchesTimer?.cancel();
  }

  Color _getConveyorColor(
      {DynamicValue? driveValue,
      DynamicValue? frequencyValue,
      DynamicValue? tripValue}) {
    try {
      // Check trip condition first if trip key is provided
      if (tripValue != null) {
        try {
          final isTripped = tripValue.asBool;
          if (isTripped) {
            return Colors.red; // Trip condition overrides everything
          }
        } catch (_) {
          // If trip value can't be read as bool, continue with normal logic
        }
      }

      // If we have drive value, use the original logic
      if (driveValue != null) {
        final state = driveValue['p_stat_RunMode'].asInt;
        final fields = driveValue['p_stat_RunMode'].enumFields;
        final name = fields?[state]?.name;
        if (name == 'fault') {
          return Colors.red;
        } else if (name == 'stopped') {
          return Colors.grey;
        } else if (name == 'auto') {
          return Colors.green;
        } else if (name == 'manual') {
          return Colors.yellow;
        } else if (name == 'clean') {
          return Colors.blue;
        }
        return Colors.pink;
      }

      // If we only have frequency and trip, use frequency-based logic
      if (frequencyValue != null) {
        try {
          final frequency = frequencyValue.asDouble;
          if (frequency != 0) {
            return Colors.green; // Running
          } else {
            return Colors.grey; // Stopped
          }
        } catch (_) {
          return Colors.purple; // Error reading frequency
        }
      }

      return Colors.grey; // Default fallback
    } catch (_) {
      return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.key == ConveyorConfig.previewStr) {
      return _buildConveyorVisual(context, Colors.grey);
    }

    // The "Simulate batches" toggle is independent of any PLC stream — it
    // must drive the timer even when no keys are configured and even before
    // the first stream tick arrives. Evaluate it here, outside StreamBuilder.
    if (widget.config.simulateBatches ?? false) {
      _startSimulateBatchesTimer();
    } else {
      _stopSimulateBatchesTimer();
    }

    // Determine which streams to subscribe to
    final streams = <Stream<DynamicValue>>[];
    final streamLabels = <String>[];

    if (widget.config.key != null && widget.config.key!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.key!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('drive');
    }

    if (widget.config.batchesKey != null &&
        widget.config.batchesKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.batchesKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('batches');
    }

    if (widget.config.frequencyKey != null &&
        widget.config.frequencyKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.frequencyKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('frequency');
    }

    if (widget.config.tripKey != null && widget.config.tripKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.tripKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('trip');
    }

    if (widget.config.augerRpmKey != null &&
        widget.config.augerRpmKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.augerRpmKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('augerRpm');
    }

    // If no streams are configured, show error state
    if (streams.isEmpty) {
      return _buildConveyorVisual(context, Colors.grey, true);
    }

    return StreamBuilder<Map<String, DynamicValue>>(
      stream: CombineLatestStream(
        streams,
        (List<DynamicValue> values) {
          final result = <String, DynamicValue>{};
          for (int i = 0; i < streamLabels.length; i++) {
            result[streamLabels[i]] = values[i];
          }
          return result;
        },
      ),
      builder: (context, snapshot) {
        if (widget.config.key == null || widget.config.key == '') {
          // print('no key');
        }
        if (snapshot.hasError) {
          _log.e(
            'Error fetching dynamic values, error: ${snapshot.error}',
          );
          return _buildConveyorVisual(context, Colors.grey, true);
        }
        if (!snapshot.hasData) {
          return _buildConveyorVisual(context, Colors.grey, true);
        }

        final dynValue = snapshot.data!;
        final color = _getConveyorColor(
          driveValue: dynValue['drive'],
          frequencyValue: dynValue['frequency'],
          tripValue: dynValue['trip'],
        );

        double? freq;
        // Try dedicated frequency key first
        if (dynValue['frequency'] != null) {
          try {
            freq = dynValue['frequency']!.asDouble;
          } catch (_) {}
        }
        // Fall back to p_stat_Frequency inside the main drive value
        if (freq == null && dynValue['drive'] != null) {
          try {
            freq = dynValue['drive']!['p_stat_Frequency'].asDouble;
          } catch (_) {}
        }

        // Update auger animation from RPM key, frequency, or default
        if (dynValue['augerRpm'] != null) {
          try {
            _updateAugerAnimation(dynValue['augerRpm']!.asDouble);
          } catch (_) {
            _updateAugerAnimation(0);
          }
        } else if (freq != null && freq != 0) {
          _updateAugerAnimation(freq);
        } else {
          _updateAugerAnimation(0);
        }

        // simulateBatches handled at top of build() — independent of streams.
        // When simulation is on, the periodic timer owns `_batches`. Skipping
        // _updateBatches here prevents an incoming snapshot (e.g. a configured
        // batchesKey emitting unoccupied slots) from clobbering the simulator
        // on every stream tick.
        if (!(widget.config.simulateBatches ?? false) &&
            dynValue['batches'] != null) {
          _updateBatches(dynValue['batches']!);
        }

        final hasMainKey =
            widget.config.key != null && widget.config.key!.isNotEmpty;
        if (hasMainKey) {
          return GestureDetector(
            onTap: () => _showDetailsPane(context),
            child: _buildConveyorVisual(context, color, null, freq),
          );
        }
        return _buildConveyorVisual(context, color, null, freq);
      },
    );
  }

  void _updateBatches(DynamicValue dynConveyor) {
    final conveyorLength = dynConveyor['p_stat_Length'].asDouble;
    const batchLength = 500; // todo variable mm
    var idx = 0;
    final batches = dynConveyor['p_stat_Batches'].asArray;
    for (final batchInfo in batches) {
      final occupied = batchInfo['xOccupied'].asBool;
      final backendOfBatch = batchInfo['position'].asDouble;
      final relativeStart = backendOfBatch / conveyorLength;
      final relativeEnd = (backendOfBatch + batchLength) / conveyorLength;
      if (occupied) {
        _batches[idx.toString()] =
            Batch(start: relativeStart, end: relativeEnd);
      } else {
        _batches.remove(idx.toString());
      }
      idx++;
    }
    if (mounted) {
      // setState(() {});
    }
  }

  Widget _buildConveyorVisual(
    BuildContext context,
    Color color, [
    bool? showExclamation,
    double? frequency,
  ]) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildConveyorVisualSized(context, constraints, color,
              showExclamation, frequency),
    );
  }

  Widget _buildConveyorVisualSized(
    BuildContext context,
    BoxConstraints constraints,
    Color color,
    bool? showExclamation,
    double? frequency,
  ) {
    // The geometry must be built for the box the belt is actually painted
    // into. `AssetStack` lays assets out with tight constraints from the page
    // canvas — the same rectangle the editor draws the selection box from —
    // and the canvas is never the window: the editor keeps panes and headers
    // around it, and every monitor slices it differently. A window-derived
    // size therefore painted the belt offset and rescaled against its own
    // box. The config-derived size only decides anything in unconstrained
    // hosts (previews, palettes), where it is what the CustomPaint below
    // would measure anyway — `constrain` reproduces that layout exactly.
    final requestedSize =
        widget.config.size.toSize(MediaQuery.of(context).size);
    final paintSize = constraints.constrain(requestedSize);

    if (widget.config.showAuger ?? false) {
      return LayoutRotatedBox(
        angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
        child: CustomPaint(
          size: paintSize,
          painter: AugerConveyorPainter(
            stateColor: color,
            phaseNotifier: _augerPhase,
            showAuger: !(showExclamation ?? false),
            openEnd: widget.config.augerOpenEnd,
          ),
        ),
      );
    }

    // An explicit canvas-relative belt width wins over the box-relative
    // thickness, and applies whether or not the belt turns. The canvas the
    // fraction refers to is the one the asset's own `size` fractions are
    // resolved against; it is not in scope here, but the box is `size` times
    // the canvas by construction, so it is recovered from the box — using the
    // window instead made the belt fatten and thin as the window changed
    // while everything around it stayed put.
    final canvasHeight = widget.config.size.height > 1e-6
        ? paintSize.height / widget.config.size.height
        : MediaQuery.of(context).size.height;
    final beltWidth = widget.config.beltWidthRelative == null
        ? null
        : widget.config.beltWidthRelative! * canvasHeight;
    final geometry = ConveyorPathGeometry.build(
      widget.config.turns,
      paintSize,
      thicknessFactor: widget.config.effectiveBeltThickness,
      beltWidthOverride: beltWidth,
    );

    final conveyorPaint = CustomPaint(
      size: paintSize,
      painter: ConveyorPainter(
        color: color,
        showExclamation: showExclamation ?? false,
        bidirectional: widget.config.bidirectional ?? false,
        reverseDirection: widget.config.reverseDirection ?? false,
        showFrequency: widget.config.showFrequency ?? false,
        frequency: frequency,
        batches: _batches,
        angle: widget.config.coordinates.angle ?? 0.0,
        geometry: geometry,
        straightBeltWidth: beltWidth,
        paintSize: paintSize,
      ),
    );

    final gateEntries = widget.config.gates;

    final Widget content;
    if (gateEntries.isEmpty) {
      content = conveyorPaint;
    } else {
      content = SizedBox(
        width: paintSize.width,
        height: paintSize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            conveyorPaint,
            for (final entry in gateEntries)
              _positionedChildGate(entry, paintSize, geometry,
                  straightBeltWidth: beltWidth),
          ],
        ),
      );
    }

    return LayoutRotatedBox(
      angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
      child: content,
    );
  }

  Widget _positionedChildGate(
      ChildGateEntry entry, Size conveyorSize, ConveyorPathGeometry? geometry,
      {double? straightBeltWidth}) {
    // Cross-belt dimension: the turned belt carries its own width, a straight
    // belt is either an explicit band or the full box height.
    final beltHeight =
        geometry?.beltWidth ?? straightBeltWidth ?? conveyorSize.height;
    // A straight band is centred in the box, so gates hang off the band edge
    // rather than the box edge.
    final bandInset =
        geometry == null ? (conveyorSize.height - beltHeight) / 2 : 0.0;
    final gateSize = beltHeight; // square so flap spans belt width
    final xCenter = entry.position * conveyorSize.width;

    // Overhang: how far the gate extends outside the conveyor border.
    // Pusher uses pi/2 rotation so content spans full height — less overhang
    // keeps the actuator closer to the edge. Slider/pneumatic have centered
    // elements and need more overhang.
    final outsideOverhang = switch (entry.gate.gateVariant) {
      GateVariant.pusher => gateSize * 0.4,
      GateVariant.slider => gateSize * 0.57,
      GateVariant.pneumatic => gateSize * 0.6,
    };

    // Same rotation for both sides; bottom gates are mirrored, not rotated 180°.
    final rotation = switch (entry.gate.gateVariant) {
      GateVariant.slider => pi,
      GateVariant.pneumatic => entry.side == GateSide.left ? 0.0 : pi,
      GateVariant.pusher => pi / 2,
    };

    final isBottom = entry.side == GateSide.right;

    final child = SizedBox(
      width: gateSize,
      height: gateSize,
      child: Transform.flip(
        flipX: false,
        flipY: isBottom && entry.gate.gateVariant != GateVariant.pneumatic,
        child: Transform.rotate(
          angle: rotation,
          child: ConveyorGate(config: entry.gate),
        ),
      ),
    );

    if (geometry != null) {
      // Curved belt: place the gate along the centerline path, offset
      // perpendicular to the travel direction and rotated to follow it.
      final tangent = geometry.tangentAt(entry.position);
      final v = tangent.vector; // unit vector along travel, screen coords
      final leftNormal = Offset(v.dy, -v.dx); // "top" side of the belt
      final distFromCenter = beltHeight / 2 + outsideOverhang - gateSize / 2;
      final center = entry.side == GateSide.left
          ? tangent.position + leftNormal * distFromCenter
          : tangent.position - leftNormal * distFromCenter;
      return Positioned(
        left: center.dx - gateSize / 2,
        top: center.dy - gateSize / 2,
        width: gateSize,
        height: gateSize,
        child: Transform.rotate(
          angle: atan2(v.dy, v.dx),
          child: child,
        ),
      );
    }

    if (entry.side == GateSide.left) {
      return Positioned(
        left: xCenter - gateSize / 2,
        top: bandInset - outsideOverhang,
        width: gateSize,
        height: gateSize,
        child: child,
      );
    } else {
      return Positioned(
        left: xCenter - gateSize / 2,
        bottom: bandInset - outsideOverhang,
        width: gateSize,
        height: gateSize,
        child: child,
      );
    }
  }

  /// Identity of this conveyor's docked pane. Tapping the same conveyor
  /// twice toggles it; tapping another device replaces it.
  String get _paneId => 'conveyor:${identityHashCode(widget.config)}';

  /// Opens the operator pane for this conveyor.
  ///
  /// Since Plan 260811 this is a non-modal [SidePane] rather than an
  /// `AlertDialog`. It matters more here than anywhere else: jogging a belt
  /// is a hand-on-button, eyes-on-the-belt operation, and the old dialog put
  /// a barrier over the very mimic the operator was watching.
  ///
  /// The layout follows the house rule — headline numbers as tiles, commands
  /// pinned in the footer, and the stats trend behind a [PaneGraphTile] so
  /// the pane itself stays inside one screen. Tapping the trend opens it in a
  /// free-floating dialog the operator can drag onto the plant view.
  ///
  /// The subscription lives in a `StreamBuilder` inside the pane body, so it
  /// is released when the pane closes — same lifetime contract as the dialog
  /// it replaces.
  void _showDetailsPane(BuildContext context) {
    showSidePane(
      context: context,
      id: _paneId,
      builder: (paneContext) => Consumer(
        builder: (paneContext, ref, _) =>
            StreamBuilder<(StateMan, DynamicValue)>(
          stream: ref.watch(stateManProvider.future).asStream().switchMap(
                (stateMan) => stateMan
                    .subscribe(widget.config.key!)
                    .asStream()
                    .map(
                      (stream) => Rx.combineLatest2(
                        Stream.value(stateMan),
                        stream,
                        (stateMan, value) => (stateMan, value),
                      ),
                    )
                    .switchMap((stream) => stream),
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SidePane(
                title: widget.config.key!,
                subtitle: 'Conveyor',
                icon: Icons.conveyor_belt,
                status: const PaneStatus.unknown('Connecting'),
                child: const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (snapshot.hasError) {
              return SidePane(
                title: widget.config.key!,
                subtitle: 'Conveyor',
                icon: Icons.conveyor_belt,
                status: const PaneStatus.fault('Error'),
                child: PaneSection(
                  title: 'Subscription failed',
                  child: SelectableText(snapshot.error.toString()),
                ),
              );
            }

            final (stateMan, dynValue) = snapshot.data!;

            /// Copy-on-write helper — every command follows the same shape:
            /// clone the current value, set one field, write the whole thing
            /// back. Preserved verbatim from the dialog this replaced.
            void write(String field, Object? value) {
              final newValue = DynamicValue.from(dynValue);
              newValue[field] = value;
              stateMan.write(widget.config.key!, newValue);
            }

            final jogFwd = dynValue['p_stat_JogFwd'].asBool;
            final jogBwd = dynValue['p_stat_JogBwd'].asBool;
            final stopOnRelease = dynValue['p_stat_ManualStopOnRelease'].asBool;
            final frequency = dynValue['p_stat_Frequency'].asDouble;
            final runMinutes = dynValue['p_stat_RunMinutes'].asInt;

            return SidePane(
              title: widget.config.key!,
              subtitle: 'Conveyor',
              icon: Icons.conveyor_belt,
              status: (jogFwd || jogBwd)
                  ? const PaneStatus.running('Jogging')
                  : frequency.abs() > 0.01
                      ? const PaneStatus.running()
                      : const PaneStatus.stopped(),
              // One command in the footer: three buttons wrap onto two rows
              // in a 380px pane and the pinned bar stops reading as a bar.
              // 'Reset run hours' sits on the Status section instead, next to
              // the number it resets.
              actions: [
                PaneAction.destructive(
                  label: 'Fault reset',
                  icon: Icons.restart_alt,
                  onPressed: () => write('p_cmd_FaultReset', true),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Jog -------------------------------------------------
                  //
                  // `p_stat_ManualStopOnRelease` decides the gesture: when
                  // set, the belt runs only while the button is held (the
                  // press/release callbacks write true/false); when clear, a
                  // tap latches it. Both paths are unchanged from the dialog.
                  PaneSection(
                    title: 'Jog',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _JogButton(
                              icon: Icons.arrow_back,
                              label: 'Reverse',
                              active: jogBwd,
                              stopOnRelease: stopOnRelease,
                              onCommand: (v) => write('p_cmd_JogBwd', v),
                            ),
                            _JogButton(
                              icon: Icons.arrow_forward,
                              label: 'Forward',
                              active: jogFwd,
                              stopOnRelease: stopOnRelease,
                              onCommand: (v) => write('p_cmd_JogFwd', v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Compact row rather than a SwitchListTile: the pane
                        // has one screen of height and this is a mode flag,
                        // not a headline. On = a tap latches the belt and it
                        // keeps running; off = it runs only while held —
                        // so the switch reads as the opposite of the PLC's
                        // stop-on-release flag.
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Jog continuous',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Switch(
                              value: !stopOnRelease,
                              onChanged: (_) =>
                                  write('p_cmd_ManualStopOnRelease', true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // The speed those buttons jog at — full width, under
                        // the controls it belongs to.
                        _FrequencyField(
                          fieldKey: 'manual_freq_field',
                          label: 'Manual frequency',
                          value: dynValue['p_cfg_ManualFreq'],
                          onSubmitted: (v) => write('p_cfg_ManualFreq', v),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Live numbers ----------------------------------------
                  PaneSection(
                    title: 'Status',
                    trailing: TextButton(
                      onPressed: () => write('p_cmd_ResetRunHours', true),
                      child: const Text('Reset hours'),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PaneTileRow(
                          children: [
                            PaneMetricTile(
                              label: 'Frequency',
                              value: frequency.toStringAsFixed(2),
                              unit: 'Hz',
                              icon: Icons.speed,
                            ),
                            PaneMetricTile(
                              label: 'Current',
                              value: dynValue['p_stat_Current']
                                  .asDouble
                                  .toStringAsFixed(2),
                              unit: 'A',
                              icon: Icons.bolt,
                            ),
                            PaneMetricTile(
                              label: 'Run hours',
                              value:
                                  '${runMinutes ~/ 60}:${(runMinutes % 60).toString().padLeft(2, '0')}',
                              unit: 'h:m',
                              icon: Icons.schedule,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        PaneDetailRow(
                          label: 'HMIS',
                          value: dynValue['p_stat_State'].toString(),
                        ),
                        PaneDetailRow(
                          label: 'Last fault',
                          value: dynValue['p_stat_LastFault'].toString(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Trend ------------------------------------------------
                  //
                  // A preview in the pane, the real chart in a floating
                  // dialog the operator can park next to the mimic.
                  PaneSection(
                    title: 'Trend',
                    child: PaneGraphTile(
                      // Tall enough for a two-axis line chart to be readable
                      // rather than decorative, and no taller — the setpoint
                      // fields below it have to fit on the same screen.
                      height: 100,
                      preview: _ConveyorStatsGraphLoader(
                        keyName: widget.config.key!,
                        showButtons: false,
                        compact: true,
                        xSpan: const Duration(minutes: 5),
                      ),
                      expandedTitle: '${widget.config.key!} — trend',
                      expandedSize: const Size(820, 520),
                      expandedBuilder: (context) => _ConveyorStatsGraphLoader(
                        keyName: widget.config.key!,
                        xSpan: const Duration(minutes: 30),
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Setpoints --------------------------------------------
                  //
                  // Inline, not behind a dialog: there are only two of them
                  // and an operator changing a frequency wants to see the
                  // belt while doing it. Manual frequency is not here — it
                  // belongs to jogging, so it sits beside the jog toggle.
                  //
                  // Committed on submit (Enter / focus-out), never per
                  // keystroke — a half-typed frequency must not reach the
                  // drive. Keys embed the current value so a field resets when
                  // the PLC reports a different one.
                  PaneSection(
                    title: 'Setpoints',
                    // Side by side — two short numbers read better as a pair
                    // than as a stack, and it costs one row instead of two.
                    child: Row(
                      // Top-aligned: a field showing a validation or helper
                      // line below it must not shove its neighbour down.
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _FrequencyField(
                            fieldKey: 'auto_freq_field',
                            label: 'Auto',
                            value: dynValue['p_cfg_AutoFreq'],
                            onSubmitted: (v) => write('p_cfg_AutoFreq', v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FrequencyField(
                            fieldKey: 'cleaning_freq_field',
                            label: 'Cleaning',
                            value: dynValue['p_cfg_CleaningFreq'],
                            onSubmitted: (v) => write('p_cfg_CleaningFreq', v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One jog button — a large touch target with a label underneath.
///
/// [stopOnRelease] mirrors `p_stat_ManualStopOnRelease`: when true the
/// command follows the press state (true on press, false on release); when
/// false a tap writes a single latching `true`.
class _JogButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool stopOnRelease;
  final void Function(bool value) onCommand;

  const _JogButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.stopOnRelease,
    required this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green : Theme.of(context).disabledColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RawMaterialButton(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onHighlightChanged: (isPressed) {
            if (stopOnRelease) onCommand(isPressed);
          },
          onPressed: () {
            if (!stopOnRelease) onCommand(true);
          },
          child: Icon(icon, color: color, size: 36),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// A frequency setpoint field. Submits on Enter/focus-out only.
class _FrequencyField extends StatelessWidget {
  final String fieldKey;
  final String label;
  final DynamicValue value;
  final void Function(double value) onSubmitted;

  const _FrequencyField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: Key('$fieldKey-${value.asString}'),
      initialValue: value.asDouble.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'Hz',
        isDense: true,
      ),
      onFieldSubmitted: (text) {
        if (text.isEmpty) return;
        final parsed = double.tryParse(text);
        if (parsed == null) return;
        onSubmitted(parsed);
      },
    );
  }
}

/// Resolves the [Collector] and hands it to [ConveyorStatsGraph].
///
/// Used for both the pane preview and the expanded floating chart, so the
/// two can never drift apart.
class _ConveyorStatsGraphLoader extends ConsumerWidget {
  final String keyName;
  final bool showButtons;
  final Duration xSpan;
  final bool compact;

  const _ConveyorStatsGraphLoader({
    required this.keyName,
    this.showButtons = true,
    this.xSpan = const Duration(minutes: 5),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Collector?>(
      future: ref.watch(collectorProvider.future),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ConveyorStatsGraph(
          collector: snapshot.data,
          keyName: keyName,
          showButtons: showButtons,
          xSpan: xSpan,
          compact: compact,
        );
      },
    );
  }
}

class Batch {
  double start; // 0…1 (can be <0 while entering)
  double end; // 0…1 (can be >1 while exiting)
  Color color;

  Batch({required this.start, required this.end, this.color = Colors.white});
}

class ConveyorPainter extends CustomPainter {
  final Map<String, Batch> batches;
  final Color color;
  final bool showExclamation;
  final bool bidirectional;
  final bool reverseDirection;
  final bool showFrequency;
  final double? frequency;
  final double angle;
  final ConveyorPathGeometry? geometry;

  /// Explicit belt width for a *straight* belt, in logical pixels.
  ///
  /// Null keeps the original convention of filling the box height. Turned
  /// belts carry their width on [geometry] instead.
  final double? straightBeltWidth;

  /// The box the painter is laid out at. [hitTest] needs it to place the
  /// straight band inside the box; null keeps the whole box tappable.
  final Size? paintSize;

  ConveyorPainter(
      {required this.color,
      this.showExclamation = false,
      this.bidirectional = false,
      this.reverseDirection = false,
      this.showFrequency = false,
      this.frequency,
      required this.batches,
      required this.angle,
      this.geometry,
      this.straightBeltWidth,
      this.paintSize});

  /// Belt outline used by [hitTest], resolved once per painter instance —
  /// hit tests run on every pointer event, the outline never changes.
  Path? _hitOutline;
  bool _hitOutlineResolved = false;

  /// Claim only the painted belt, not the whole box.
  ///
  /// A turned belt occupies a fraction of its bounding box, and a straight
  /// belt with an explicit width is a band centred in it. Taps on the empty
  /// remainder used to open the details pane anyway; letting them fall
  /// through keeps the dead space inert and lets assets behind it stay
  /// reachable.
  @override
  bool hitTest(Offset position) {
    final g = geometry;
    if (g == null) {
      final band = straightBeltWidth;
      final size = paintSize;
      // No explicit band: the belt fills the box, so the box is the belt.
      if (band == null || size == null) return true;
      final rect =
          Rect.fromLTWH(0, (size.height - band) / 2, size.width, band);
      return RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide * _endRadiusFactor),
      ).contains(position);
    }
    if (!_hitOutlineResolved) {
      _hitOutlineResolved = true;
      _hitOutline = g.bandOutline(0, 1,
          width: g.beltWidth, radius: g.beltWidth * _endRadiusFactor);
    }
    final outline = _hitOutline;
    if (outline != null) return outline.contains(position);
    // Over-wide belt: painted as a fat stroke of the centerline, so accept
    // anything within half the belt width (plus border) of it.
    const samples = 64;
    final reach = g.beltWidth / 2 + 2;
    for (var i = 0; i <= samples; i++) {
      if ((g.tangentAt(i / samples).position - position).distance <= reach) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry != null) {
      _paintTurnedBelt(canvas, size);
      return;
    }
    // An explicit belt width paints the belt as a band centred in the box
    // rather than filling it, so a straight belt can be set to the same width
    // as a turned one. Everything below is box-relative, so resizing the box
    // we hand it is enough — batches, arrows and text all follow. A band
    // wider than the box paints over the box edge rather than being trimmed
    // back to it: the width is set in screen units and must not move when the
    // box does.
    final band = straightBeltWidth;
    if (band != null) {
      canvas.save();
      canvas.translate(0, (size.height - band) / 2);
      _paintStraightBelt(canvas, Size(size.width, band));
      canvas.restore();
      return;
    }
    _paintStraightBelt(canvas, size);
  }

  /// Rounding of the belt's two ends, as a fraction of the belt width.
  ///
  /// Shared by both renderers so a belt keeps the same silhouette when a turn
  /// is added: the turned belt used to end in a stroke cap, which is a half
  /// circle — 0.5 of the belt width — and looked far blobbier than the
  /// straight belt beside it at the same width.
  static const _endRadiusFactor = 0.2;

  void _paintStraightBelt(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final borderRadius = Radius.circular(size.shortestSide * _endRadiusFactor);
    final rrect = RRect.fromRectAndRadius(rect, borderRadius);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, paint);

    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, border);

    // Draw exclamation mark if needed
    if (showExclamation) {
      _drawExclamation(canvas, size);
      return;
    }
    // 2) draw each batch segment as a plain box
    final paintBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final batchHeight = size.height * 0.8;
    final batchRadius =
        Radius.circular(batchHeight * 0.2); // 20% of batch height

    for (final batch in batches.values) {
      final paintBatch = Paint()..color = batch.color;
      // clamp into [0..1] then to pixels
      final x0 = (batch.start.clamp(0.0, 1.0)) * size.width;
      final x1 = (batch.end.clamp(0.0, 1.0)) * size.width;
      final w = x1 - x0;
      if (w <= 0) continue; // not yet visible / already off

      final rect = Rect.fromLTWH(
        x0,
        (size.height - batchHeight) / 2,
        w,
        batchHeight,
      );
      final rrect = RRect.fromRectAndRadius(rect, batchRadius);

      // fill
      canvas.drawRRect(rrect, paintBatch);
      // border (optional)
      canvas.drawRRect(rrect, paintBorder);
    }

    _drawDirectionArrow(canvas, size);
    _drawFrequency(canvas, size);
  }

  /// Fills a band along the centerline and outlines it with [border].
  ///
  /// A band too wide for its own bend has no outline to draw, so it falls
  /// back to stroking the centerline — the shape is meaningless at that point
  /// either way, but a solid blob reads as an over-wide belt where a folded
  /// outline reads as a rendering bug.
  void _paintBand(Canvas canvas, ConveyorPathGeometry g, double from, double to,
      {required double width,
      required double radius,
      required Color fill,
      required Paint border}) {
    final outline = g.bandOutline(from, to, width: width, radius: radius);
    if (outline != null) {
      canvas.drawPath(outline, Paint()..color = fill);
      canvas.drawPath(outline, border);
      return;
    }
    final centerline = g.extractFraction(from, to);
    canvas.drawPath(
      centerline,
      Paint()
        ..color = border.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 2 * border.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      centerline,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Path-based rendering used when the conveyor has turns configured.
  ///
  /// Belt and batches are both bands along the centerline, filled and then
  /// outlined — the same recipe [_paintStraightBelt] runs with an `RRect`,
  /// so a belt keeps its silhouette when a turn is added under it.
  void _paintTurnedBelt(Canvas canvas, Size size) {
    final g = geometry!;

    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    _paintBand(canvas, g, 0, 1,
        width: g.beltWidth,
        radius: g.beltWidth * _endRadiusFactor,
        fill: color,
        border: border);

    if (showExclamation) {
      _drawExclamation(canvas, size);
      return;
    }

    final batchWidth = g.beltWidth * 0.8;
    final batchRadius = batchWidth * _endRadiusFactor;
    final batchBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final batch in batches.values) {
      final start = batch.start.clamp(0.0, 1.0);
      final end = batch.end.clamp(0.0, 1.0);
      if (end <= start) continue; // not yet visible / already off
      _paintBand(canvas, g, start, end,
          width: batchWidth,
          radius: batchRadius,
          fill: batch.color,
          border: batchBorder);
    }

    _drawDirectionArrow(canvas, size);
    _drawFrequency(canvas, size);
  }

  /// Reference dimension for centered text: the belt width. For straight
  /// conveyors that is the box's short side; for turned conveyors the box is
  /// taller than the belt, so use the fitted belt width instead.
  double _textBasis(Size size) => geometry?.beltWidth ?? size.shortestSide;

  /// Anchor for centered overlays: box center for straight belts, the
  /// centerline midpoint for turned belts (the box center can be off-belt).
  Offset _overlayCenter(Size size) =>
      geometry?.tangentAt(0.5).position ??
      Offset(size.width / 2, size.height / 2);

  void _drawExclamation(Canvas canvas, Size size) {
    canvas.save();
    // Move origin to center of conveyor
    final center = _overlayCenter(size);
    canvas.translate(center.dx, center.dy);
    // Counter-rotate
    canvas.rotate(-angle * pi / 180);
    // Draw exclamation mark centered at (0,0)
    final textPainter = TextPainter(
      text: TextSpan(
        text: '!',
        style: TextStyle(
          color: Colors.white,
          fontSize: _textBasis(size) * 0.7,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final offset = Offset(
      -textPainter.width / 2,
      -textPainter.height / 2,
    );
    textPainter.paint(canvas, offset);
    canvas.restore();
  }

  void _drawDirectionArrow(Canvas canvas, Size size) {
    // Draw direction arrow for bidirectional conveyors
    if (!bidirectional || frequency == null || frequency == 0) return;
    canvas.save();
    final center = _overlayCenter(size);
    canvas.translate(center.dx, center.dy);

    final arrowLength = size.width * 0.4;
    final arrowSize = _textBasis(size) * 0.25;
    final arrowPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Determine direction: positive frequency = right, unless reversed
    final pointsRight = (frequency! > 0) ^ reverseDirection;

    // Shaft
    canvas.drawLine(
      Offset(-arrowLength / 2, 0),
      Offset(arrowLength / 2, 0),
      arrowPaint,
    );

    // Single arrowhead in the running direction
    if (pointsRight) {
      final head = Path()
        ..moveTo(arrowLength / 2 - arrowSize, -arrowSize * 0.5)
        ..lineTo(arrowLength / 2, 0)
        ..lineTo(arrowLength / 2 - arrowSize, arrowSize * 0.5);
      canvas.drawPath(head, arrowPaint);
    } else {
      final head = Path()
        ..moveTo(-arrowLength / 2 + arrowSize, -arrowSize * 0.5)
        ..lineTo(-arrowLength / 2, 0)
        ..lineTo(-arrowLength / 2 + arrowSize, arrowSize * 0.5);
      canvas.drawPath(head, arrowPaint);
    }

    canvas.restore();
  }

  void _drawFrequency(Canvas canvas, Size size) {
    // Draw frequency number in center
    if (!showFrequency || frequency == null) return;
    canvas.save();
    final center = _overlayCenter(size);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-angle * pi / 180);
    final textPainter = TextPainter(
      text: TextSpan(
        text: frequency!.toStringAsFixed(1),
        style: TextStyle(
          color: Colors.white,
          fontSize: _textBasis(size) * 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConveyorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.showExclamation != showExclamation ||
      oldDelegate.bidirectional != bidirectional ||
      oldDelegate.showFrequency != showFrequency ||
      oldDelegate.frequency != frequency ||
      oldDelegate.straightBeltWidth != straightBeltWidth ||
      // Geometry is rebuilt each frame when turns are configured, so curved
      // conveyors repaint on every rebuild (needed for batch animation).
      !identical(oldDelegate.geometry, geometry);
}

/// Series colours for the conveyor trend, fixed so the small preview in the
/// pane and the full chart in the floating dialog read as the same chart.
/// The legend carries the units, so the tile needs no caption repeating them.
const String kConveyorFreqSeries = 'Frequency (Hz)';
const String kConveyorCurrentSeries = 'Current (A)';

const Map<String, Color> conveyorTrendColors = {
  kConveyorFreqSeries: Colors.blue,
  kConveyorCurrentSeries: Colors.orange,
};

class ConveyorStatsGraph extends ConsumerStatefulWidget {
  final Collector? collector;
  final String keyName;

  /// Pan/zoom/now buttons. Off in the pane preview, on in the floating chart.
  final bool showButtons;

  /// Visible window. The preview shows a short span so the line has shape;
  /// the expanded chart shows more history.
  final Duration xSpan;

  /// Drops the units from the tick labels. In the pane preview there is only
  /// ~20px of gutter, so "48.20 Hz" wraps to four lines and eats the plot —
  /// the tile caption names the units instead.
  final bool compact;

  const ConveyorStatsGraph({
    required this.collector,
    required this.keyName,
    this.showButtons = true,
    this.xSpan = const Duration(minutes: 5),
    this.compact = false,
    super.key,
  });

  @override
  ConsumerState<ConveyorStatsGraph> createState() => _ConveyorStatsGraphState();
}

class _ConveyorStatsGraphState extends ConsumerState<ConveyorStatsGraph> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TimeseriesData<dynamic>>>(
      stream: widget.collector
          ?.collectStream(widget.keyName, since: const Duration(hours: 2)),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No data'));
        }

        final samples = snapshot.data!;
        final currentData = <List<double>>[];
        final freqData = <List<double>>[];

        double minFreq = 1000;
        double maxFreq = 0;
        double minCurrent = 1000;
        double maxCurrent = 0;

        for (final sample in samples) {
          final v = sample.value;
          final current = v['p_stat_Current'] ?? 0.0;
          final freq = v['p_stat_Frequency'] ?? 0.0;
          final time = sample.time.millisecondsSinceEpoch.toDouble();

          currentData.add([time, current]);
          freqData.add([time, freq]);

          if (freq < minFreq) minFreq = freq;
          if (freq > maxFreq) maxFreq = freq;
          if (current < minCurrent) minCurrent = current;
          if (current > maxCurrent) maxCurrent = current;
        }
        if (minCurrent == maxCurrent) {
          maxCurrent++;
        }
        if (minFreq == maxFreq) {
          maxFreq++;
        }

        // Headroom above and below the data.
        //
        // Scaling each axis to the exact extremes pins the traces to the top
        // and bottom edges of the plot, where they run into the tick labels —
        // the top reading and the top of the line end up drawn on each other.
        // A 10% margin keeps the line inside the frame and the labels clear
        // of it, on both axes.
        (double, double) withHeadroom(double min, double max) {
          final margin = (max - min) * 0.1;
          return (min - margin, max + margin);
        }

        (minFreq, maxFreq) = withHeadroom(minFreq, maxFreq);
        (_, maxCurrent) = withHeadroom(minCurrent, maxCurrent);
        // Current is framed from zero, not from its own minimum. Load tracks
        // speed, so scaling both axes to their own extremes maps the two
        // traces onto the same shape and the second one drawn simply hides
        // the first. Anchoring current at zero separates them — and zero is
        // the meaningful floor for a current reading anyway.
        minCurrent = 0;

        // Time along the bottom, frequency on the LEFT axis and current on
        // the RIGHT — frequency is what an operator reads first, so it gets
        // the axis the eye lands on.
        final graphConfig = GraphConfig(
          type: GraphType.timeseries,
          xAxis: GraphAxisConfig(unit: widget.compact ? '' : 'Time'),
          yAxis: GraphAxisConfig(
            unit: widget.compact ? '' : 'Hz',
            min: minFreq,
            max: maxFreq,
          ),
          yAxis2: GraphAxisConfig(
            unit: widget.compact ? '' : 'A',
            min: minCurrent,
            max: maxCurrent,
          ),
          xSpan: widget.xSpan,
        );

        final List<Map<String, dynamic>> data = [];
        data.addAll(freqData
            .map((e) => {'x': e[0], 'y': e[1], 's': kConveyorFreqSeries}));
        data.addAll(currentData
            .map((e) => {'x': e[0], 'y2': e[1], 's': kConveyorCurrentSeries}));

        // The compact preview needs its own gutters: at 130px tall the
        // default padding lets tick labels print over the tile caption and
        // the time row. Same theme otherwise, so both charts still match.
        final theme = widget.compact
            ? (Theme.of(context).brightness == Brightness.dark
                ? darkChartTheme(padding: kCompactChartPadding)
                : lightChartTheme(padding: kCompactChartPadding))
            : ref.watch(chartThemeNotifierProvider);

        return Graph(
          config: graphConfig,
          data: data,
          showButtons: widget.showButtons,
          categoryColors: conveyorTrendColors,
          chartTheme: theme,
          redraw: () {},
        ).build(context);
      },
    );
  }
}
