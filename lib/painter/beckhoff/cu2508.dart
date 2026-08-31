/// Beckhoff CU2508 — the real-time Ethernet port multiplier that fans one
/// gigabit uplink out to eight independent 100 Mbit/s EtherCAT segments.
///
/// This plant has three of them (`Box 34/35/44 (CU2508)` in the legacy
/// EtherCAT config), one per network: the cabinet drive master, the Baader
/// network and the roe line.
///
/// The device publishes no process data — nothing in any station's EtherCAT
/// GVL names a CU2508 — so this is a drawing. It is here to be identified and
/// clicked on a topology page, which is the same bargain every passive part
/// on these mimics makes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ek1100.dart' show EthernetPortPainter;
import 'io8.dart' show bodyColor;

/// Front face of the housing in mm, from the CU2508 documentation: the box is
/// 146.5 x 100 x 38 mm, so the face the mimic draws is 146.5 wide by 100 high.
const Size cu2508FaceMm = Size(146.5, 100);

class CU2508Painter extends CustomPainter {
  CU2508Painter({
    this.name = 'CU2508',
    this.housingColor = bodyColor,
  });

  /// Printed top right. Defaults to the model, but a page that has three of
  /// these wants to say which one — `CU2508 roe`, say.
  final String name;

  final Color housingColor;

  /// Downstream ports. The uplink is drawn separately and is not one of them.
  static const int portCount = 8;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is in mm and then scaled once, so the geometry stays
    // readable against the datasheet.
    const design = cu2508FaceMm;
    final scale = math.min(
      size.width / design.width,
      size.height / design.height,
    );
    final dx = (size.width - design.width * scale) / 2;
    final dy = (size.height - design.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final stroke = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, design.width, design.height),
      const Radius.circular(2),
    );
    canvas.drawRRect(body, Paint()..color = housingColor);
    canvas.drawRRect(body, stroke);

    void text(
      String value,
      Offset at, {
      required double fontSize,
      Color color = Colors.black,
      FontWeight weight = FontWeight.bold,
      TextAlign align = TextAlign.left,
      double? width,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
      tp.paint(canvas, at);
    }

    // --- Header: wordmark, model, and the 24 V feed ---
    text('BECKHOFF', const Offset(5, 5),
        fontSize: 7, color: const Color(0xFFE30613));
    text(name, const Offset(5, 13), fontSize: 5);

    // Supply terminal, two poles, top right. The box is fed 24 V DC.
    const supplyLeft = 108.0;
    for (int i = 0; i < 2; i++) {
      final rect = Rect.fromLTWH(supplyLeft + i * 17.0, 5, 14, 12);
      canvas.drawRect(rect, Paint()..color = Colors.grey.shade300);
      canvas.drawRect(rect, stroke);
      canvas.drawCircle(rect.center, 3.2, Paint()..color = Colors.grey.shade400);
      canvas.drawCircle(rect.center, 3.2, stroke);
      text(
        i == 0 ? '24V' : '0V',
        Offset(supplyLeft + i * 17.0, 18),
        fontSize: 3.6,
        color: i == 0 ? Colors.red.shade800 : Colors.blue.shade800,
        width: 14,
        align: TextAlign.center,
      );
    }

    // One RJ45 with its caption underneath, drawn from the top-left of the
    // socket. Kept in one place so the uplink and the eight segments cannot
    // drift apart.
    void port(Offset at, String label) {
      const socket = 18.0;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.scale(socket / 100.0);
      EthernetPortPainter(strokeColor: Colors.black, strokeWidth: 1.0)
          .paint(canvas, const Size(100, 100));
      canvas.restore();

      text(
        label,
        Offset(at.dx - 3, at.dy + socket + 0.5),
        fontSize: 4,
        width: socket + 6,
        align: TextAlign.center,
      );
    }

    // --- Uplink: the gigabit port back to the IPC ---
    port(const Offset(5, 26), 'X1 uplink');

    // --- The eight downstream segments, two rows of four ---
    const columns = 4;
    const firstLeft = 30.0;
    const columnPitch = 29.0;
    const rowTops = [50.0, 74.0];
    for (int i = 0; i < portCount; i++) {
      final row = i ~/ columns;
      final column = i % columns;
      port(
        Offset(firstLeft + column * columnPitch, rowTops[row]),
        '${i + 1}',
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CU2508Painter old) =>
      old.name != name || old.housingColor != housingColor;
}

/// [CU2508Painter] at the housing's own aspect.
class CU2508Widget extends StatelessWidget {
  const CU2508Widget({super.key, this.name = 'CU2508', this.width = 400});

  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * cu2508FaceMm.height / cu2508FaceMm.width,
      child: CustomPaint(painter: CU2508Painter(name: name)),
    );
  }
}
