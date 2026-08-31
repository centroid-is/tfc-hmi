/// Beckhoff EtherCAT Box — the IP67 modules that live out on the machines
/// rather than in a cabinet.
///
/// Two of them are on this plant and they share this drawing because they
/// share a housing: 126 x 30 x 26.5 mm, EtherCAT in and out on M8 at the top,
/// eight signal sockets down the middle, power in and out at the foot.
///
///  * **EP2338-1002** — 8-channel digital combi, each socket usable as an
///    input or an output. The PLC publishes it as an `ST_EP2338_0002`
///    (`I0..I7`, `O0..O7`), so its sockets are lit from live data.
///  * **EP1918-0002** — TwinSAFE, 8 safe digital inputs. Yellow housing, and
///    no process data at all: the safety inputs are consumed by TwinSAFE
///    logic, and no station's EtherCAT GVL names one. Its sockets stay dark.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'io8.dart' show IOState, bodyColor;

/// The front face in mm — the housing is 30 wide by 126 high.
const Size epBoxFaceMm = Size(30, 126);

/// Signal sockets on the front of an EtherCAT Box.
const int epBoxChannelCount = 8;

class EPBoxPainter extends CustomPainter {
  EPBoxPainter({
    required this.model,
    required this.name,
    this.channels = const [
      IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
    ],
    this.disconnected = false,
    this.housingColor = bodyColor,
  }) : assert(channels.length == epBoxChannelCount);

  /// Printed on the housing, e.g. `EP2338`.
  final String model;

  /// The tag under the model — `ST301.RM05`, the box erector's box.
  final String name;

  /// One entry per socket, socket 1 first.
  final List<IOState> channels;

  /// Draws the "nothing is arriving" mark, the same one [IO8Painter] uses.
  final bool disconnected;

  final Color housingColor;

  @override
  void paint(Canvas canvas, Size size) {
    const design = epBoxFaceMm;
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
      const Radius.circular(3),
    );
    canvas.drawRRect(body, Paint()..color = housingColor);
    canvas.drawRRect(body, stroke);

    void text(
      String value,
      Offset at, {
      required double fontSize,
      Color color = Colors.black,
      double? width,
      TextAlign align = TextAlign.center,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
      tp.paint(canvas, at);
    }

    // A round connector: the knurled ring with the keyway notch that makes an
    // M8/M12 socket recognisable at mimic scale.
    void socket(Offset centre, double radius) {
      canvas.drawCircle(centre, radius, Paint()..color = Colors.grey.shade400);
      canvas.drawCircle(centre, radius, stroke);
      canvas.drawCircle(
        centre,
        radius * 0.58,
        Paint()..color = Colors.grey.shade700,
      );
      canvas.drawCircle(centre, radius * 0.58, stroke);
      canvas.drawRect(
        Rect.fromCenter(
          center: centre.translate(0, -radius * 0.78),
          width: radius * 0.34,
          height: radius * 0.44,
        ),
        Paint()..color = Colors.grey.shade300,
      );
    }

    // --- EtherCAT in and out, M8, at the top ---
    socket(const Offset(9, 10), 5);
    socket(const Offset(21, 10), 5);
    text('IN', const Offset(3, 16), fontSize: 2.6, width: 12);
    text('OUT', const Offset(15, 16), fontSize: 2.6, width: 12);

    // --- Wordmark ---
    text('BECKHOFF', const Offset(0, 21),
        fontSize: 3.4, color: const Color(0xFFE30613), width: design.width);
    text(model, const Offset(0, 25.5), fontSize: 3.0, width: design.width);
    if (name.isNotEmpty) {
      text(name, const Offset(0, 29.5), fontSize: 2.6, width: design.width);
    }

    // --- The eight signal sockets, two columns of four ---
    const firstTop = 36.0;
    const rowPitch = 17.5;
    for (int i = 0; i < epBoxChannelCount; i++) {
      final row = i ~/ 2;
      final column = i % 2;
      final centre = Offset(9.0 + column * 12.0, firstTop + row * rowPitch);
      socket(centre, 5);

      // The channel lamp sits beside its socket, inboard, where the real box
      // puts the per-channel LED.
      final lamp = Rect.fromCenter(
        center: centre.translate(column == 0 ? -6.5 : 6.5, 0),
        width: 2.2,
        height: 2.2,
      );
      canvas.drawRect(lamp, Paint()..color = _lampColor(channels[i]));
      canvas.drawRect(lamp, stroke);

      text(
        '${i + 1}',
        Offset(centre.dx - 6, centre.dy + 5.4),
        fontSize: 2.6,
        width: 12,
      );
    }

    // --- Power in and out at the foot ---
    socket(const Offset(9, 114), 5.5);
    socket(const Offset(21, 114), 5.5);
    text('IN', const Offset(3, 120.5), fontSize: 2.6, width: 12);
    text('OUT', const Offset(15, 120.5), fontSize: 2.6, width: 12);

    // --- "Nothing is arriving" ---
    if (disconnected) {
      final mark = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(design.width / 2 - 0.9, 105.0, 1.8, 4.5),
        mark,
      );
      canvas.drawCircle(Offset(design.width / 2, 111.0), 0.9, mark);
    }

    canvas.restore();
  }

  Color _lampColor(IOState state) => switch (state) {
        IOState.high || IOState.forcedHigh => const Color(0xFF6CA545),
        IOState.error => Colors.red,
        IOState.low || IOState.forcedLow => const Color(0xFFE0E0E0),
      };

  @override
  bool shouldRepaint(covariant EPBoxPainter old) =>
      old.model != model ||
      old.name != name ||
      old.disconnected != disconnected ||
      old.housingColor != housingColor ||
      !listEquals(old.channels, channels);
}

/// [EPBoxPainter] at the housing's own aspect.
class EPBoxWidget extends StatelessWidget {
  const EPBoxWidget({
    super.key,
    required this.model,
    required this.name,
    required this.channels,
    this.disconnected = false,
    this.housingColor = bodyColor,
    this.height = 300,
  });

  final String model;
  final String name;
  final List<IOState> channels;
  final bool disconnected;
  final Color housingColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * epBoxFaceMm.width / epBoxFaceMm.height,
      height: height,
      child: CustomPaint(
        painter: EPBoxPainter(
          model: model,
          name: name,
          channels: channels,
          disconnected: disconnected,
          housingColor: housingColor,
        ),
      ),
    );
  }
}
