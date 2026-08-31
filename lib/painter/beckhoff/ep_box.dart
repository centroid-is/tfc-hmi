/// Beckhoff EtherCAT Box — the IP67 modules that live out on the machines
/// rather than in a cabinet.
///
/// Two of them are on this plant and they share this drawing because they
/// share a housing: 126 x 30 x 26.5 mm, EtherCAT in and out on M8 at the top,
/// four M12 signal plugs down the middle, power in and out at the foot. Both
/// end pairs are captioned — two identical rings of round connectors with
/// 'IN / OUT' under each says nothing about which pair is the bus.
///
/// Each signal plug carries two channels, A on pin 4 and B on pin 2, with a
/// lamp for each. That is why eight channels are drawn on four sockets.
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

/// Signal channels an EtherCAT Box carries.
const int epBoxChannelCount = 8;

/// Signal plugs on the front — half the channel count.
///
/// The M12 connectors carry two channels each, A on pin 4 and B on pin 2, so
/// the eight channels of an EP2338 land on four plugs. Drawing eight sockets
/// would send an electrician to a plug that is not on the box.
const int epBoxSocketCount = epBoxChannelCount ~/ 2;

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
    // Captioned, because the box has two identical-looking pairs of round
    // connectors and 'IN / OUT' twice over says nothing about which is the
    // bus and which is the 24 V. Getting that wrong at the cabinet is a
    // wasted trip at best.
    text('ETHERCAT', const Offset(0, 2), fontSize: 2.6, width: design.width);
    socket(const Offset(9, 11), 5);
    socket(const Offset(21, 11), 5);
    text('IN', const Offset(3, 17), fontSize: 2.6, width: 12);
    text('OUT', const Offset(15, 17), fontSize: 2.6, width: 12);

    // --- Wordmark ---
    text('BECKHOFF', const Offset(0, 22),
        fontSize: 3.4, color: const Color(0xFFE30613), width: design.width);
    text(model, const Offset(0, 26.5), fontSize: 3.0, width: design.width);
    if (name.isNotEmpty) {
      text(name, const Offset(0, 30.5), fontSize: 2.6, width: design.width);
    }

    // --- The four signal plugs, one column, two channels each ---
    // A lamp either side of every plug: A (pin 4) to the left, B (pin 2) to
    // the right, in [channels] order. The first plug clears the tag above it
    // — a socket at 43 with a 6 mm radius starts at 37, and the tag's last
    // line ends around 34.
    const firstPlug = 44.0;
    const plugPitch = 16.5;
    for (int plug = 0; plug < epBoxSocketCount; plug++) {
      final centre = Offset(design.width / 2, firstPlug + plug * plugPitch);
      socket(centre, 6);

      // The lamp captions carry the plug number as well as the side — '1A',
      // '1B'. A bare number under each socket sat exactly between its own
      // plug and the next one's lamps, close enough to either to be read as
      // belonging to the wrong one.
      for (int side = 0; side < 2; side++) {
        final lampX = side == 0 ? 5.0 : 25.0;
        final lamp = Rect.fromCenter(
          center: Offset(lampX, centre.dy - 2.5),
          width: 3,
          height: 3,
        );
        canvas.drawRect(
          lamp,
          Paint()..color = _lampColor(channels[plug * 2 + side]),
        );
        canvas.drawRect(lamp, stroke);
        text(
          '${plug + 1}${side == 0 ? 'A' : 'B'}',
          Offset(lampX - 3.5, centre.dy + 0.5),
          fontSize: 2.8,
          width: 7,
        );
      }
    }

    // --- Power in and out at the foot, captioned for the same reason ---
    text('POWER', const Offset(0, 102), fontSize: 2.6, width: design.width);
    socket(const Offset(9, 113), 5.5);
    socket(const Offset(21, 113), 5.5);
    text('IN', const Offset(3, 119), fontSize: 2.6, width: 12);
    text('OUT', const Offset(15, 119), fontSize: 2.6, width: 12);

    // --- "Nothing is arriving" ---
    // Beside the identity block rather than at the foot: the foot now
    // carries the POWER caption, and the mark belongs next to the tag it is
    // talking about anyway.
    if (disconnected) {
      final mark = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(25.1, 23.0, 1.8, 4.5), mark);
      canvas.drawCircle(const Offset(26.0, 29.0), 0.9, mark);
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
