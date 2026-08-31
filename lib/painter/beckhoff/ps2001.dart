/// Beckhoff PS2001-2410 — the 1-phase 24 V DC / 10 A supply that feeds each
/// station's 24 V rail. ST301 alone has seven of them.
///
/// Unlike most of the infrastructure on these pages this one talks: the PLC
/// publishes an `ST_PS2001_2410` per unit (`SVNCoreComponents/ECT/
/// ST_PS2001_2410.TcDUT`) carrying DC OK, warning, error, input undervoltage
/// and the measured output volts and amps. So the face is driven, not drawn.
///
/// Geometry follows the PS2001-2410-1001 documentation, section "Front side
/// and operating elements": a 48 x 124 x 127 mm housing with the mains input
/// (N, L, PE) at the top, the DC output (2 x +, 3 x -) at the bottom, the
/// output-voltage potentiometer and DC-OK LED between them, and the EtherCAT
/// X1 IN / X2 OUT sockets with their LINK/ACT lamps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ek1100.dart' show EthernetPortPainter;
import 'io8.dart' show bodyColor;

/// The front face in mm — the housing is 48 wide by 124 high.
const Size ps2001FaceMm = Size(48, 124);

/// What the supply is doing, worst first. The order is the severity order:
/// [Ps2001FaceState.values] is compared on `index` when something needs the
/// worse of two.
enum Ps2001FaceState {
  /// The unit reports an error — overload hiccup, short circuit, or a
  /// thermal shutdown.
  faulted,

  /// The mains input is below the valid operating range. The output may
  /// still be up, but not for long.
  undervoltage,

  /// A non-critical condition: high temperature or high load. Still
  /// supplying.
  warning,

  /// Output voltage inside tolerance and nothing else flagged.
  healthy,

  /// DC OK is low with no warning or error — the rail is down but the unit
  /// is not complaining, which is what a supply looks like switched off.
  down,

  /// Nothing published yet, or no key configured.
  unknown,
}

class PS2001Painter extends CustomPainter {
  PS2001Painter({
    this.name = 'PS2001',
    this.state = Ps2001FaceState.unknown,
    this.dcOk,
    this.housingColor = bodyColor,
  });

  /// Printed under the wordmark. A page with seven of these wants the tag,
  /// not the model — `ST301.T1`.
  final String name;

  final Ps2001FaceState state;

  /// `p_stat_DC_OK` as the unit last reported it, or null when nothing has
  /// arrived. Carried separately from [state] because the two are genuinely
  /// independent: a supply can be flagging high temperature while its output
  /// is still inside tolerance, and collapsing that into one headline would
  /// put out a lamp that is really lit on the cabinet door.
  final bool? dcOk;

  final Color housingColor;

  @override
  void paint(Canvas canvas, Size size) {
    const design = ps2001FaceMm;
    final scale = math.min(
      size.width / design.width,
      size.height / design.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - design.width * scale) / 2,
      (size.height - design.height * scale) / 2,
    );
    canvas.scale(scale);

    final stroke = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, design.width, design.height),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(body, Paint()..color = housingColor);
    canvas.drawRRect(body, stroke);

    void text(
      String value,
      Offset at, {
      required double fontSize,
      Color color = Colors.black,
      double? width,
      TextAlign align = TextAlign.left,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            // Named, as ek1100.dart names it: a null family renders as the
            // test font's boxes under `flutter test`, and a golden of boxes
            // pins nothing about a label.
            fontFamily: 'Roboto',
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
      tp.paint(canvas, at);
    }

    // One spring-loaded terminal: the square push lever above the round wire
    // hole, the way the EL terminals draw them, with the pole name under it.
    void terminal(Offset at, String label, Color labelColor) {
      const w = 12.0;
      final lever = Rect.fromLTWH(at.dx, at.dy, w, 4);
      canvas.drawRect(lever, Paint()..color = Colors.grey.shade300);
      canvas.drawRect(lever, stroke);
      final hole = Offset(at.dx + w / 2, at.dy + 8.5);
      canvas.drawCircle(hole, 2.4, Paint()..color = Colors.grey.shade300);
      canvas.drawCircle(hole, 2.4, stroke);
      text(
        label,
        Offset(at.dx, at.dy + 11.5),
        fontSize: 3.4,
        color: labelColor,
        width: w,
        align: TextAlign.center,
      );
    }

    // --- (A) Mains input, top: N, L, PE ---
    const inputLabels = ['N', 'L', 'PE'];
    final inputColors = [
      Colors.blue.shade800,
      Colors.brown.shade700,
      Colors.green.shade800,
    ];
    for (int i = 0; i < 3; i++) {
      terminal(Offset(4 + i * 13.5, 4), inputLabels[i], inputColors[i]);
    }

    // --- Wordmark ---
    text('BECKHOFF', const Offset(4, 22),
        fontSize: 5, color: const Color(0xFFE30613));
    text(name, const Offset(4, 29), fontSize: 4);

    // --- (D) DC-OK LED, and the mimic's own fault lamp beside it ---
    void lamp(Offset at, String label, Color color) {
      final rect = Rect.fromLTWH(at.dx, at.dy, 5, 3.2);
      canvas.drawRect(rect, Paint()..color = color);
      canvas.drawRect(rect, stroke);
      text(label, Offset(at.dx + 6.2, at.dy - 0.4), fontSize: 3.2);
    }

    lamp(const Offset(4, 38), 'DC OK', _dcOkColor);
    lamp(const Offset(4, 44), 'FAULT', _faultColor);

    // --- (C) Output voltage potentiometer, factory set to 24.1 V ---
    const potCentre = Offset(38, 41);
    canvas.drawCircle(potCentre, 4.5, Paint()..color = Colors.grey.shade300);
    canvas.drawCircle(potCentre, 4.5, stroke);
    canvas.drawLine(
      potCentre.translate(-2.6, 0),
      potCentre.translate(2.6, 0),
      Paint()
        ..color = Colors.grey.shade800
        ..strokeWidth = 1.0,
    );

    // --- (E)/(F) EtherCAT X1 IN and X2 OUT ---
    void port(Offset at, String label) {
      const socket = 16.0;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.scale(socket / 100.0);
      EthernetPortPainter(strokeColor: Colors.black, strokeWidth: 1.0)
          .paint(canvas, const Size(100, 100));
      canvas.restore();
      text(
        label,
        Offset(at.dx - 2, at.dy + socket),
        fontSize: 3.2,
        width: socket + 4,
        align: TextAlign.center,
      );
    }

    port(const Offset(6, 54), 'X1 IN');
    port(const Offset(26, 54), 'X2 OUT');

    // --- (B) DC output, bottom: two positives and three negatives ---
    // Both poles are internally paralleled, so the drawing shows what an
    // electrician finds on the front rather than one terminal per pole.
    for (int i = 0; i < 2; i++) {
      terminal(Offset(11 + i * 13.5, 82), '+', Colors.red.shade800);
    }
    for (int i = 0; i < 3; i++) {
      terminal(Offset(4 + i * 13.5, 100), '-', Colors.blue.shade800);
    }

    canvas.restore();
  }

  /// The DC-OK lamp is the one an electrician looks at first, so it shows
  /// exactly what the lamp on the housing shows and nothing more: lit while
  /// the output is above the DC OK threshold, dark below it, and a flat grey
  /// while nothing has been published.
  Color get _dcOkColor => switch (dcOk) {
        true => const Color(0xFF6CA545),
        false => const Color(0xFFCCCCCC),
        null => const Color(0xFFE8E8E8),
      };

  /// The mimic's own addition, in the place the real housing puts its
  /// EtherCAT RUN lamp.
  ///
  /// Substituted rather than reproduced because the PLC publishes no EtherCAT
  /// state for this unit, and a lamp captioned RUN that is really showing
  /// something else is worse than no lamp. What the struct does carry is why
  /// an electrician would walk over here: a supply in hiccup mode, running
  /// hot, or fed by a sagging mains.
  /// Dark unless the unit is complaining. A lamp captioned FAULT that glows
  /// green on a healthy supply is the kind of thing an electrician learns to
  /// stop reading; amber for "still supplying but complaining", red for
  /// "stopped", and nothing at all the rest of the time.
  Color get _faultColor => switch (state) {
        Ps2001FaceState.faulted => Colors.red,
        Ps2001FaceState.undervoltage ||
        Ps2001FaceState.warning =>
          const Color(0xFFE0A800),
        Ps2001FaceState.healthy ||
        Ps2001FaceState.down =>
          const Color(0xFFCCCCCC),
        Ps2001FaceState.unknown => const Color(0xFFE8E8E8),
      };

  @override
  bool shouldRepaint(covariant PS2001Painter old) =>
      old.name != name ||
      old.state != state ||
      old.dcOk != dcOk ||
      old.housingColor != housingColor;
}

/// [PS2001Painter] at the housing's own aspect.
class PS2001Widget extends StatelessWidget {
  const PS2001Widget({
    super.key,
    this.name = 'PS2001',
    this.state = Ps2001FaceState.unknown,
    this.dcOk,
    this.height = 300,
  });

  final String name;
  final Ps2001FaceState state;
  final bool? dcOk;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * ps2001FaceMm.width / ps2001FaceMm.height,
      height: height,
      child: CustomPaint(
        painter: PS2001Painter(name: name, state: state, dcOk: dcOk),
      ),
    );
  }
}
