/// The ISO 1219-1 schematic for one VUVG valve — the square-box symbol a
/// pneumatics drawing uses, drawn small enough to live in a side pane.
///
/// A valve terminal's pane can say "port 4" and "centre" all it likes; the
/// symbol is what makes those words mean something. It is also the only
/// thing that shows the difference an operator most needs to see here — a
/// 5/2 bistable and a 5/3 closed centre both have two coils and two lamps,
/// and only the schematic says that one of them has a middle position where
/// both work ports are blocked.
///
/// Conventions, as a fitter would expect them:
///
///  * One box per switching position, side by side, left to right in the
///    order the spool passes through them. Coil 14's position is on the
///    left, coil 12's on the right.
///  * Ports on the *active* box: 4 and 2 on top, 5, 1 and 3 underneath. On
///    a real drawing the symbol slides so the working box lines up with the
///    fixed port lines; here the ports are drawn against whichever box is
///    live, which is the same idea without the animation.
///  * Solenoids are the small flagged rectangles on the outside, labelled
///    with the coil they are — `14` at the left end, `12` at the right.
///  * Springs are the zigzag beside them. A 5/2 monostable has one, at the
///    right; a 5/3 has one at each end, which is what centres it; a
///    bistable has none.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How many switching positions a valve symbol draws, and what happens in
/// each of them.
enum ValveSymbolKind {
  /// 5/2 monostable — two positions, solenoid one end and a spring the
  /// other.
  fiveTwoMono,

  /// 5/2 bistable — two positions, a solenoid at each end, no spring.
  fiveTwoBistable,

  /// 5/3 closed centre — three positions, a solenoid and a centring spring
  /// at each end, and a middle in which all five ports are blocked.
  fiveThreeClosed;

  /// Boxes drawn side by side.
  int get positions => this == ValveSymbolKind.fiveThreeClosed ? 3 : 2;

  bool get hasSpringLeft => this == ValveSymbolKind.fiveThreeClosed;

  bool get hasSpringRight => this != ValveSymbolKind.fiveTwoBistable;

  /// Whether the middle box blocks every port. Only a 5/3 has a middle at
  /// all, and the `C` in `P53C` is what makes it the closed one.
  bool get blocksCentre => this == ValveSymbolKind.fiveThreeClosed;
}

/// Which box is live — 0 is coil 14's position, and the last index is coil
/// 12's.
///
/// Null when nothing is known: the terminal has said nothing, so no box is
/// claimed and the ports hang off the symbol's rest position instead.
typedef ValveSymbolPosition = int?;

/// The symbol's drawing size for [kind], in its own units. Height is fixed
/// so a row of mixed valves lines up; width follows the position count.
///
/// The boxes are deliberately most of the height. A first pass gave the port
/// stubs and their numbers as much room as the boxes, and at the size this
/// renders in a 380 px pane the flow arrows inside came out as a smudge —
/// which is the one part of the symbol that has to be readable.
Size valveSymbolSize(ValveSymbolKind kind) =>
    Size(24 + kind.positions * _ValveSymbolMetrics.boxW, 58);

/// Shared geometry, so [valveSymbolSize] and the painter cannot disagree.
abstract final class _ValveSymbolMetrics {
  static const double boxW = 30;
  static const double boxH = 30;
  static const double actuatorW = 12;
  static const double top = 13;
  static const double portStub = 8;
}

class ValveSymbolPainter extends CustomPainter {
  ValveSymbolPainter({
    required this.kind,
    required this.active,
    required this.lineColor,
    required this.activeColor,
    this.mutedColor,
  });

  final ValveSymbolKind kind;

  /// Index of the live box, or null when nothing is known.
  final ValveSymbolPosition active;

  /// The schematic's own ink.
  final Color lineColor;

  /// Wash behind the live box, and the colour of the flow arrows inside it.
  final Color activeColor;

  /// Ink for the boxes that are not live. Defaults to [lineColor] at half
  /// strength, which is what keeps the live box the thing the eye lands on.
  final Color? mutedColor;

  static const double _boxW = _ValveSymbolMetrics.boxW;
  static const double _boxH = _ValveSymbolMetrics.boxH;
  static const double _actuatorW = _ValveSymbolMetrics.actuatorW;

  Color get _muted =>
      mutedColor ?? lineColor.withValues(alpha: 0.45);

  @override
  void paint(Canvas canvas, Size size) {
    final design = valveSymbolSize(kind);
    final scale = math.min(size.width / design.width, size.height / design.height);
    canvas.save();
    canvas.translate(
      (size.width - design.width * scale) / 2,
      (size.height - design.height * scale) / 2,
    );
    canvas.scale(scale);

    // The boxes sit between the two actuators, and the port lines need room
    // above and below.
    const top = _ValveSymbolMetrics.top;
    const left = _actuatorW;

    for (var i = 0; i < kind.positions; i++) {
      _paintBox(canvas, Offset(left + i * _boxW, top), i);
    }

    _paintActuators(canvas, left, top);
    if (active != null) {
      _paintPorts(canvas, Offset(left + active! * _boxW, top));
    } else {
      // Nothing known: hang the ports off the position the valve rests in,
      // so the symbol is still a complete schematic rather than a row of
      // boxes floating unconnected.
      _paintPorts(canvas, Offset(left + _restIndex * _boxW, top));
    }

    canvas.restore();
  }

  /// The box a de-energised valve sits in — the spring end on a monostable,
  /// the centre on a 5/3. A bistable has no rest position; its left box is
  /// as good a place to hang the ports as any.
  int get _restIndex => switch (kind) {
        ValveSymbolKind.fiveTwoMono => 1,
        ValveSymbolKind.fiveThreeClosed => 1,
        ValveSymbolKind.fiveTwoBistable => 0,
      };

  Paint _stroke(Color color, [double width = 1.1]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  void _paintBox(Canvas canvas, Offset at, int index) {
    final live = active == index;
    final rect = Rect.fromLTWH(at.dx, at.dy, _boxW, _boxH);

    if (live) {
      canvas.drawRect(
        rect,
        Paint()..color = activeColor.withValues(alpha: 0.3),
      );
    }
    canvas.drawRect(rect, _stroke(live ? lineColor : _muted, live ? 1.4 : 1.0));

    // The flow lines are drawn in ink, not in the accent, and the wash
    // behind the box is what says which position is live. Colouring the
    // arrows instead put the one thing that has to stay readable — where
    // the air is going — into a low-contrast accent on a cream page.
    final ink = live ? lineColor : _muted;
    final isCentre = kind.positions == 3 && index == 1;

    if (isCentre && kind.blocksCentre) {
      _paintBlocked(canvas, rect, ink);
      return;
    }

    // Which way the spool routes in this box. Index 0 is coil 14's
    // position: pressure to port 4, port 2 exhausting to 3. The last box is
    // coil 12's: pressure to port 2, port 4 exhausting to 5.
    final toPort4 = index == 0;
    _paintFlow(canvas, rect, ink, toPort4: toPort4);
  }

  /// All five ports stopped — the `C` of a closed centre. Each port is a
  /// stub ending in a crossbar, which is how a drawing says "blocked" as
  /// opposed to "not connected".
  void _paintBlocked(Canvas canvas, Rect rect, Color ink) {
    final paint = _stroke(ink);
    void stub(Offset from, Offset to) {
      canvas.drawLine(from, to, paint);
      // The bar across the end.
      final dx = to.dy == from.dy ? 0.0 : 3.0;
      final dy = to.dy == from.dy ? 3.0 : 0.0;
      canvas.drawLine(
        Offset(to.dx - dx, to.dy - dy),
        Offset(to.dx + dx, to.dy + dy),
        paint,
      );
    }

    for (final x in _topPortXs(rect)) {
      stub(Offset(x, rect.top), Offset(x, rect.top + 8));
    }
    for (final x in _bottomPortXs(rect)) {
      stub(Offset(x, rect.bottom), Offset(x, rect.bottom - 8));
    }
  }

  /// The two diagonals that carry pressure one way and exhaust the other.
  void _paintFlow(
    Canvas canvas,
    Rect rect,
    Color ink, {
    required bool toPort4,
  }) {
    final paint = _stroke(ink);
    final top = _topPortXs(rect);
    final bottom = _bottomPortXs(rect);
    final supply = Offset(bottom[1], rect.bottom);

    if (toPort4) {
      // 1 → 4, and 2 → 3.
      _arrow(canvas, supply, Offset(top[0], rect.top), paint);
      _arrow(canvas, Offset(top[1], rect.top), Offset(bottom[2], rect.bottom),
          paint);
    } else {
      // 1 → 2, and 4 → 5.
      _arrow(canvas, supply, Offset(top[1], rect.top), paint);
      _arrow(canvas, Offset(top[0], rect.top), Offset(bottom[0], rect.bottom),
          paint);
    }
  }

  /// Ports 4 and 2, in that order.
  List<double> _topPortXs(Rect rect) =>
      [rect.left + _boxW * 0.3, rect.left + _boxW * 0.7];

  /// Ports 5, 1 and 3, in that order.
  List<double> _bottomPortXs(Rect rect) => [
        rect.left + _boxW * 0.18,
        rect.left + _boxW * 0.5,
        rect.left + _boxW * 0.82,
      ];

  void _arrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from, to, paint);
    // A head short of the tip rather than on it: at this size a head on the
    // box edge merges into the edge and the line reads undirected. It has to
    // be big, too — the first pass drew a 3.6-unit head in a 30-unit box and
    // an operator could not tell which way the air was going, which is the
    // one thing the symbol exists to say.
    final at = Offset.lerp(from, to, 0.72)!;
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const len = 6.5;
    const spread = 0.42;
    canvas.drawLine(
      at,
      at - Offset(math.cos(angle - spread) * len, math.sin(angle - spread) * len),
      paint,
    );
    canvas.drawLine(
      at,
      at - Offset(math.cos(angle + spread) * len, math.sin(angle + spread) * len),
      paint,
    );
  }

  /// The port lines hanging off the live box, with their numbers.
  void _paintPorts(Canvas canvas, Offset at) {
    final rect = Rect.fromLTWH(at.dx, at.dy, _boxW, _boxH);
    final paint = _stroke(lineColor);

    const topLabels = ['4', '2'];
    final topXs = _topPortXs(rect);
    for (var i = 0; i < topXs.length; i++) {
      canvas.drawLine(
        Offset(topXs[i], rect.top),
        Offset(topXs[i], rect.top - _ValveSymbolMetrics.portStub),
        paint,
      );
      _text(canvas, topLabels[i], Offset(topXs[i] - 5, rect.top - 17));
    }

    const bottomLabels = ['5', '1', '3'];
    final bottomXs = _bottomPortXs(rect);
    for (var i = 0; i < bottomXs.length; i++) {
      canvas.drawLine(
        Offset(bottomXs[i], rect.bottom),
        Offset(bottomXs[i], rect.bottom + _ValveSymbolMetrics.portStub),
        paint,
      );
      _text(canvas, bottomLabels[i], Offset(bottomXs[i] - 5, rect.bottom + 9));
    }
  }

  /// Solenoids and springs, outside the block at each end.
  void _paintActuators(Canvas canvas, double left, double top) {
    final right = left + kind.positions * _boxW;
    final paint = _stroke(lineColor);

    _solenoid(canvas, Rect.fromLTWH(left - _actuatorW, top, _actuatorW, _boxH),
        paint, flipped: false);
    _text(canvas, '14', Offset(left - _actuatorW - 1, top + _boxH + 2));

    if (kind.positions == 2 && kind == ValveSymbolKind.fiveTwoMono) {
      _spring(canvas, Rect.fromLTWH(right, top, _actuatorW, _boxH), paint);
    } else {
      _solenoid(canvas, Rect.fromLTWH(right, top, _actuatorW, _boxH), paint,
          flipped: true);
      // Clear of the port numbers: at `right - 1` this label overlapped the
      // `3` under the last box whenever that box was the live one, and the
      // two ran together into an unreadable smear.
      _text(canvas, '12', Offset(right + 2, top + _boxH + 2));
    }

    // A 5/3's centring springs sit inboard of its solenoids; there is no
    // room to draw them separately at this size, so they are the small
    // zigzag drawn over the actuator's inner edge.
    if (kind.hasSpringLeft) {
      _springTick(canvas, Offset(left - 2, top + _boxH / 2), paint);
    }
    if (kind.hasSpringRight && kind != ValveSymbolKind.fiveTwoMono) {
      _springTick(canvas, Offset(right + 2, top + _boxH / 2), paint);
    }
  }

  /// The flagged rectangle a drawing uses for a solenoid pilot.
  void _solenoid(Canvas canvas, Rect rect, Paint paint,
      {required bool flipped}) {
    canvas.drawRect(rect, paint);
    // The diagonal, running out of the end away from the boxes.
    final a = flipped
        ? Offset(rect.right - 1.5, rect.top + 2)
        : Offset(rect.left + 1.5, rect.top + 2);
    final b = flipped
        ? Offset(rect.left + 1.5, rect.bottom - 2)
        : Offset(rect.right - 1.5, rect.bottom - 2);
    canvas.drawLine(a, b, paint);
  }

  /// The zigzag a drawing uses for a return spring.
  void _spring(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..moveTo(rect.left, rect.center.dy);
    const steps = 4;
    for (var i = 0; i < steps; i++) {
      final x = rect.left + rect.width * (i + 0.5) / steps;
      path.lineTo(x, rect.center.dy + (i.isEven ? -4 : 4));
    }
    path.lineTo(rect.right, rect.center.dy);
    canvas.drawPath(path, paint);
  }

  /// A short spring, for the centring springs of a 5/3 where a full zigzag
  /// will not fit.
  void _springTick(Canvas canvas, Offset at, Paint paint) {
    final path = Path()..moveTo(at.dx, at.dy - 4);
    path.lineTo(at.dx + 2, at.dy - 1.3);
    path.lineTo(at.dx - 2, at.dy + 1.3);
    path.lineTo(at.dx, at.dy + 4);
    canvas.drawPath(path, paint);
  }

  void _text(Canvas canvas, String value, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: lineColor,
          fontSize: 8,
          height: 1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 10, maxWidth: 10);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(ValveSymbolPainter old) =>
      old.kind != kind ||
      old.active != active ||
      old.lineColor != lineColor ||
      old.activeColor != activeColor ||
      old.mutedColor != mutedColor;
}

/// The symbol at its natural size, scaled to [height].
class ValveSymbol extends StatelessWidget {
  const ValveSymbol({
    super.key,
    required this.kind,
    required this.active,
    this.height = 72,
  });

  final ValveSymbolKind kind;
  final ValveSymbolPosition active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final design = valveSymbolSize(kind);
    final width = height * design.width / design.height;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: ValveSymbolPainter(
          kind: kind,
          active: active,
          // Derived from the body colour rather than `colorScheme.outline`,
          // which neither Solarized scheme sets — a schematic drawn in it
          // disappears on a dark station.
          lineColor: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          activeColor: theme.colorScheme.primary,
          mutedColor: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
