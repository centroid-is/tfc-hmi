/// The outline of what actually takes a tap.
///
/// Every other way of drawing a boundary around an asset re-derives it: the
/// editor's selection border is the asset's `w×h` box turned by its angle,
/// the AI proposal outline is the same box dashed. That is a second opinion
/// about the asset's shape, and second opinions drift — a conveyor turn is an
/// arc across a box it fills maybe a third of, a straight belt with an
/// explicit width is a band down the middle, and a rectangle around either
/// claims far more than the operator can actually hit
/// (`ConveyorPainter.hitTest` takes only the painted belt).
///
/// So the asset says so instead. An asset whose hit test is a path publishes
/// that same path — the object its `hitTest` consults, not a copy of it —
/// with [AssetHitShape]. The plant view flattens it ([flattenPath]), stands
/// it off ([offsetContour]) and draws it: exact, analytic, and costing one
/// path per pane rather than the ten thousand hit tests it took to discover
/// the same shape by interrogation. An asset that publishes nothing takes
/// taps on its whole face, and its face is what gets marked, which for most
/// of them is the truth rather than an approximation of it.
///
/// What stops a published path from quietly becoming a third opinion is
/// `hit_boundary_drift_test`, which probes the real hit test the expensive
/// way and holds it against the published one. That is a CI cost, not an
/// operator's.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart' show HmiColorRole;

/// Moves every point of [ring] [distance] away from the region it encloses.
///
/// Along each point's own normal, so the clearance is the same the whole way
/// round whatever the shape does — the mark stands off a belt's long edges
/// and its rounded ends by the same 4px.
///
/// Which way is out is settled by asking [inside] rather than by the ring's
/// winding, so the boundary of a hole moves into the hole — also away from
/// the material, which is what the eye expects.
List<Offset> offsetContour(
  List<Offset> ring,
  double distance, {
  required bool Function(Offset point) inside,
}) {
  if (ring.length < 3 || distance == 0) return ring;

  final normals = <Offset>[
    for (var i = 0; i < ring.length; i++)
      () {
        final before = ring[(i - 1 + ring.length) % ring.length];
        final after = ring[(i + 1) % ring.length];
        final tangent = after - before;
        final length = tangent.distance;
        return length == 0
            ? Offset.zero
            : Offset(tangent.dy / length, -tangent.dx / length);
      }(),
  ];

  // One probe settles the whole ring: the normals are consistent along it, so
  // the side that is outside at one point is outside at all of them.
  var sign = 1.0;
  for (var i = 0; i < ring.length; i++) {
    final normal = normals[i];
    if (normal == Offset.zero) continue;
    final ahead = inside(ring[i] + normal * 1.5);
    final behind = inside(ring[i] - normal * 1.5);
    if (ahead == behind) continue; // Grazing the edge here; try another point.
    sign = ahead ? -1.0 : 1.0;
    break;
  }

  return [
    for (var i = 0; i < ring.length; i++) ring[i] + normals[i] * distance * sign,
  ];
}

/// Publishes the shape this subtree takes taps on.
///
/// Wrap the widget whose box the shape is measured in — the `CustomPaint`
/// whose painter hit-tests against it — and hand over **the path the hit test
/// itself consults**. Handing over a second path drawn to look right would
/// put the mark back where it started: a picture of where an asset is
/// supposed to be tappable, which is not evidence of anything and is exactly
/// what drifts.
///
/// Assets that take taps on their whole face publish nothing. A box is the
/// truth for them, and the plant view draws one.
///
/// Not an [InheritedWidget]: nothing below this needs to read it. The plant
/// view finds it by walking down into the asset, the same way it finds the
/// box to measure, so the shape can be published from wherever the geometry
/// already exists rather than plumbed up to the asset's config.
class AssetHitShape extends StatelessWidget {
  /// The tappable shape, in the coordinates of [child]'s render box.
  ///
  /// A callback, not a path: the shape is wanted about once a minute, when an
  /// operator opens a pane, and this is built on every frame the asset
  /// rebuilds on. Resolving a turned belt's outline eagerly measured 145µs
  /// per build, on top of the 123µs its geometry already costs — doubling the
  /// price of a belt to publish something almost nobody asks for. The painter
  /// keeps the path once it has built it, so the mark and `hitTest` still get
  /// the same object.
  final ValueGetter<Path> shape;

  final Widget child;

  const AssetHitShape({super.key, required this.shape, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Walks [path] into rings of points, one per closed subpath.
///
/// [step] is the spacing along the path; the curve is already smooth, so this
/// only has to be fine enough that a straight line between neighbours is
/// indistinguishable from the arc it replaces.
List<List<Offset>> flattenPath(Path path, {double step = 2}) {
  final rings = <List<Offset>>[];
  for (final metric in path.computeMetrics()) {
    final ring = <Offset>[];
    for (var distance = 0.0; distance < metric.length; distance += step) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) ring.add(tangent.position);
    }
    if (ring.length > 2) rings.add(ring);
  }
  return rings;
}

/// Cuts [ring] into the painted runs of a dash pattern.
///
/// [phase] slides the pattern along the ring, in the same units as [dash] and
/// [gap]; advancing it by `dash + gap` puts every dash exactly where its
/// neighbour was, which is what makes the ants march without the ring ever
/// looking like it moved.
///
/// The ring is closed — the segment from its last point back to its first is
/// walked like any other — so a pattern that fits it a whole number of times
/// (see [fitDashes]) comes back round onto itself with no seam.
List<List<Offset>> dashRing(
  List<Offset> ring, {
  required double dash,
  required double gap,
  double phase = 0,
}) {
  if (ring.length < 2 || dash <= 0) return const [];
  final period = dash + gap;
  if (gap <= 0) return [ring.toList()..add(ring.first)];

  // Arc length at each point, with the closing segment on the end, so a
  // distance can be turned into a position by one walk rather than by
  // re-measuring the ring for every dash.
  final marks = <double>[0];
  for (var i = 1; i <= ring.length; i++) {
    final to = ring[i % ring.length];
    marks.add(marks[i - 1] + (to - ring[i - 1]).distance);
  }
  final perimeter = marks.last;
  if (perimeter == 0) return const [];

  Offset at(double distance, int index) {
    final span = marks[index + 1] - marks[index];
    final t = span == 0 ? 0.0 : (distance - marks[index]) / span;
    return Offset.lerp(ring[index], ring[(index + 1) % ring.length], t)!;
  }

  final runs = <List<Offset>>[];
  // Back far enough that the dash straddling the ring's start is drawn whole
  // rather than clipped to it.
  for (var start = -(phase % period) - period;
      start < perimeter;
      start += period) {
    final from = math.max(start, 0.0);
    final to = math.min(start + dash, perimeter);
    if (to <= from) continue;

    final run = <Offset>[];
    for (var i = 0; i < ring.length; i++) {
      if (marks[i + 1] < from || marks[i] > to) continue;
      if (run.isEmpty) run.add(at(from, i));
      run.add(marks[i + 1] <= to ? ring[(i + 1) % ring.length] : at(to, i));
    }
    if (run.length > 1) runs.add(run);
  }
  return runs;
}

/// Scales a wanted dash pattern so a whole number of it fits [perimeter].
///
/// Both lengths move by the same factor, so the pattern keeps its proportions
/// and only its size gives — by at most half a dash on a ring long enough to
/// carry several. Without this the ring closes onto a runt dash that never
/// matches its neighbours and sits still while the rest of them march past
/// it, which is the one thing that gives a marching outline away as a drawing.
({double dash, double gap}) fitDashes(
  double perimeter, {
  required double dash,
  required double gap,
}) {
  final period = dash + gap;
  if (perimeter <= 0 || period <= 0) return (dash: dash, gap: gap);
  final repeats = math.max(1, (perimeter / period).round());
  final scale = perimeter / (repeats * period);
  return (dash: dash * scale, gap: gap * scale);
}

/// The opacity multiplier for a ring that breathes, at [phase] of one cycle.
///
/// Full at phase 0, faintest at half way, back to full at 1, so it closes onto
/// itself and can be looped.
///
/// Not a plain raised cosine, which is what this was first: that spends as
/// long dim as it does bright, and a mark whose job is to say "this one" then
/// reads as mostly absent with brief appearances rather than present with a
/// pulse in it. Cubing the swing pushes the dwell to the bright end — the ring
/// sits at better than 80% of full for well over half the cycle and passes
/// through the trough rather than resting in it — while leaving the shape
/// smooth and the two endpoints exactly equal.
///
/// [pulse] is how far it falls at the trough, so the ring never goes below
/// `1 - pulse` of full. It is not meant to reach zero: an outline that
/// disappears entirely stops marking anything for as long as it is gone, and
/// on a page an operator glances at, that is a mark that is simply not there
/// when they look.
double breathAt(double phase, double pulse) {
  if (pulse <= 0) return 1;
  final swing = 0.5 - 0.5 * math.cos(2 * math.pi * phase);
  return 1 - pulse * swing * swing * swing;
}

/// How the mark is drawn and how it moves.
///
/// Presets rather than a free-for-all: the ring is one thing on one page, and
/// the choice between these is a design decision taken once. [selection] is
/// the one in use; the others are kept so the decision can be re-taken by
/// looking at them side by side rather than by re-deriving the numbers.
@immutable
class HitBoundaryStyle {
  /// The painted run, before [fitDashes] scales it to the ring.
  final double dash;

  /// The unpainted run between them.
  final double gap;

  final double strokeWidth;

  /// How far off the asset the ring stands, in logical pixels.
  ///
  /// The lever that decides whether this reads as a mark at all. Drawn tight
  /// to the shape it is a border the asset appears to have grown, and an
  /// operator has no reason to read a border as "selected"; given room it is
  /// plainly a separate ring around the machine, which is the whole message.
  final double standoff;

  /// How long the pattern takes to travel one whole `dash + gap`. One full
  /// turn of the animation, and the length of a loop that closes seamlessly.
  final Duration period;

  /// How far the line's opacity falls at the trough of its breath, 0..1.
  ///
  /// Zero holds it steady. The presets keep well clear of one: see [breathAt]
  /// for why a ring that goes all the way out is a worse mark than one that
  /// only ever dims.
  final double pulse;

  /// The scheme colour to draw the dashes in, or null for
  /// [HitBoundaryPainter.defaultInk].
  ///
  /// A role rather than a `Color` so the ring follows a scheme switch the way
  /// every asset does, and so no raw `Colors.*` gets into the mimic. Resolved
  /// by the widget that owns the ring — a painter has no `BuildContext`.
  ///
  /// Spending a hue on this cuts against the reasoning on
  /// [HitBoundaryPainter]: on a plant page green is running, yellow manual,
  /// blue cleaning, grey stopped, red faulted, violet unreadable and orange
  /// forced, so a ring in any of them is a colour the operator has already
  /// been taught to read as an equipment state. Blue in particular is what a
  /// belt in cleaning looks like. That is the trade being made, not an
  /// oversight.
  final HmiColorRole? inkRole;

  /// Whether the dashes travel round the ring.
  ///
  /// Off with a [pulse] on, the ring is a fixed dashed outline that fades in
  /// and out — the motion is the breath rather than the crawl. Off with no
  /// pulse it is a still dashed outline, which says nothing a border does not.
  final bool crawl;

  /// Paint the gaps in the light tone instead of leaving them empty.
  ///
  /// This is where the old halo's contrast guarantee goes when the halo is
  /// dropped: a light run and a dark run alternate along the same line, so
  /// every stretch of background still has one of the two tones across it
  /// (see the note on [HitBoundaryPainter]). Off, the ring is one dark ink
  /// and disappears where it crosses a dark asset.
  final bool twoTone;

  const HitBoundaryStyle({
    this.dash = 8,
    this.gap = 5,
    this.strokeWidth = 2.4,
    this.standoff = 7,
    this.period = const Duration(milliseconds: 1200),
    this.pulse = 0,
    this.crawl = true,
    this.twoTone = false,
    this.inkRole,
  });

  /// Dashes crawling at a walk. Calm enough to sit on a mimic all shift.
  static const march = HitBoundaryStyle();

  /// The same ring at twice the pace.
  static const brisk =
      HitBoundaryStyle(period: Duration(milliseconds: 600));

  /// Crawling, and breathing while it crawls.
  static const breathing = HitBoundaryStyle(pulse: 0.35);

  /// Crawling, with the gaps carrying the light tone — the arrangement image
  /// editors use, and the one that keeps the ring readable over a dark belt.
  static const twoToneMarch = HitBoundaryStyle(twoTone: true);

  /// Still dashes, breathing. The ring is where it was; what moves is how
  /// present it is. Slower than the crawling styles — a breath at walking
  /// pace reads as panting.
  ///
  /// It dips to half and no further. The ring is legible at every point of
  /// the cycle, which is the whole difference between a mark that breathes
  /// and one that blinks.
  static const pulsing = HitBoundaryStyle(
    pulse: 0.5,
    crawl: false,
    period: Duration(milliseconds: 1800),
  );

  /// Both at once. The fade is shallower than [pulsing]'s because the crawl
  /// is already carrying half the work.
  static const marchAndFade = HitBoundaryStyle(
    pulse: 0.45,
    period: Duration(milliseconds: 1800),
  );

  /// [pulsing] in the scheme's blue — the colour selection wears nearly
  /// everywhere else. Same geometry and same breath; only the ink differs.
  /// See [inkRole] for what that costs on a plant page.
  static const blueFade = HitBoundaryStyle(
    pulse: 0.5,
    crawl: false,
    period: Duration(milliseconds: 1800),
    inkRole: HmiColorRole.blue,
  );

  /// [pulsing] with more of everything that makes a ring visible: a heavier
  /// stroke, longer dashes, and more air between it and the machine. For
  /// deciding how much presence the mark should have, not a different idea
  /// about what it does.
  static const pulsingBold = HitBoundaryStyle(
    dash: 11,
    gap: 7,
    strokeWidth: 3.4,
    standoff: 9,
    pulse: 0.5,
    crawl: false,
    period: Duration(milliseconds: 1800),
  );

  /// [blueFade] at [pulsingBold]'s weight.
  static const blueFadeBold = HitBoundaryStyle(
    dash: 11,
    gap: 7,
    strokeWidth: 3.4,
    standoff: 9,
    pulse: 0.5,
    crawl: false,
    period: Duration(milliseconds: 1800),
    inkRole: HmiColorRole.blue,
  );

  /// The style the plant view actually marks with.
  static const selection = march;

  HitBoundaryStyle copyWith({
    double? dash,
    double? gap,
    double? strokeWidth,
    double? standoff,
    Duration? period,
    double? pulse,
    bool? crawl,
    bool? twoTone,
    HmiColorRole? inkRole,
  }) =>
      HitBoundaryStyle(
        dash: dash ?? this.dash,
        gap: gap ?? this.gap,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        standoff: standoff ?? this.standoff,
        period: period ?? this.period,
        pulse: pulse ?? this.pulse,
        crawl: crawl ?? this.crawl,
        twoTone: twoTone ?? this.twoTone,
        inkRole: inkRole ?? this.inkRole,
      );

  @override
  bool operator ==(Object other) =>
      other is HitBoundaryStyle &&
      other.dash == dash &&
      other.gap == gap &&
      other.strokeWidth == strokeWidth &&
      other.standoff == standoff &&
      other.period == period &&
      other.pulse == pulse &&
      other.crawl == crawl &&
      other.twoTone == twoTone &&
      other.inkRole == inkRole;

  @override
  int get hashCode => Object.hash(dash, gap, strokeWidth, standoff, period,
      pulse, crawl, twoTone, inkRole);
}

/// Draws [contours] as a ring of dashes that crawl around the shape.
///
/// Neither tone here is a hue. Every colour on a plant page is spoken for —
/// green running, yellow manual, blue cleaning, grey stopped, red faulted,
/// violet unreadable, orange forced — and ISA-101 practice is to spend colour
/// on abnormal conditions and nothing else, so a mark in any of them would
/// read as a seventh state. Cyan is the one hue left in the palette, and at
/// glyph size it is a coin-flip against cleaning blue.
///
/// So the ring says "selected" by shape and motion instead. Dashes that crawl
/// are the mark image editors and CAD marquees have used forever, and they
/// carry the meaning on their own: nothing else on a mimic moves along a
/// contour, so no still state can be mistaken for one.
///
/// This used to be a fine dark line laid on a wider light band, and the band
/// showing either side of it was the contrast guarantee — W3C technique C40:
/// two colours far enough apart in luminance (~17:1 here) mean at least one of
/// them clears 3:1 against whatever solid colour they land on, which matters
/// for a ring drawn half over the page and half over an asset whose fill is a
/// state colour. Read as a mark it was a white outline around the asset, and
/// that is what it looked like, so it is gone. [HitBoundaryStyle.twoTone] is
/// where the guarantee can be had back without it: the light tone goes in the
/// gaps between the dark dashes rather than around them, alternating along one
/// line instead of fringing it.
///
/// Deliberately strokes rather than a [BoxDecoration] with a `boxShadow` —
/// that shadow is a filled, blurred copy of the shape, and with nothing
/// filling the shape on top of it the asset ends up under a grey wash. These
/// are strokes, so the middle is left alone: an asset's colour is its
/// equipment state and has to come through untouched.
class HitBoundaryPainter extends CustomPainter {
  /// The dashes.
  static const Color defaultInk = Color(0xD11A1D1F);

  /// How solid the dashes are, whatever colour they are drawn in. A role
  /// colour resolves fully opaque, and at full opacity the ring stops being a
  /// mark laid over the page and starts being part of the machine.
  static const double inkOpacity = 0xD1 / 0xFF;

  /// The tone the gaps carry under [HitBoundaryStyle.twoTone].
  static const Color defaultHalo = Color(0xD1F2F4F5);

  /// The rings, already in this painter's coordinates.
  final List<List<Offset>> contours;

  final Color ink;
  final Color halo;
  final HitBoundaryStyle style;

  /// Where the pattern has got to, 0..1 of one `dash + gap`. Wraps, so 0 and
  /// 1 are the same picture.
  final double phase;

  const HitBoundaryPainter({
    required this.contours,
    this.ink = defaultInk,
    this.halo = defaultHalo,
    this.style = HitBoundaryStyle.selection,
    this.phase = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;

    // Faintest half way through the pattern, so the ring dips once per turn
    // rather than twice.
    final breath = breathAt(phase, style.pulse);

    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: color.a * breath);

    void draw(List<List<Offset>> runs, Paint paint) {
      if (runs.isEmpty) return;
      final path = Path();
      for (final run in runs) {
        path.moveTo(run.first.dx, run.first.dy);
        for (final point in run.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    for (final ring in contours) {
      if (ring.length < 2) continue;
      var perimeter = 0.0;
      for (var i = 0; i < ring.length; i++) {
        perimeter += (ring[(i + 1) % ring.length] - ring[i]).distance;
      }
      final fitted =
          fitDashes(perimeter, dash: style.dash, gap: style.gap);
      final period = fitted.dash + fitted.gap;
      // A ring that only breathes keeps its dashes where they are; the phase
      // is still what drives the breath.
      final travelled = style.crawl ? phase * period : 0.0;

      draw(
        dashRing(ring,
            dash: fitted.dash, gap: fitted.gap, phase: travelled),
        stroke(ink),
      );
      if (style.twoTone) {
        // The complement: the same pattern slid on by one dash, so the light
        // runs land in the gaps the dark ones left.
        draw(
          dashRing(ring,
              dash: fitted.gap,
              gap: fitted.dash,
              phase: travelled - fitted.dash),
          stroke(halo),
        );
      }
    }
  }

  @override
  bool shouldRepaint(HitBoundaryPainter oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.halo != halo ||
      oldDelegate.style != style ||
      oldDelegate.phase != phase ||
      !identical(oldDelegate.contours, contours);
}
