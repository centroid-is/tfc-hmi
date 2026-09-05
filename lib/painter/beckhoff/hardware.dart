/// The material vocabulary the Beckhoff drawings are built from.
///
/// Every device on these pages used to be flat fills and hairlines, which is
/// fine as a schematic and poor as a mimic: a rack of eight EL terminals read
/// as eight identical rectangles, and the terminal points — dark holes in a
/// cream moulding on the real part — were drawn *lighter* than the housing,
/// so the one feature an electrician actually aims at looked like a sticker
/// rather than a hole.
///
/// This library holds the pieces that fix that, once, for every device:
///
///  * [housingPaint] / [paintHousing] — the moulded plastic shell, lit from
///    the left as a cabinet is, so adjacent terminals show a seam.
///  * [paintRecess], [paintContactHole], [paintActuationSlot] — openings,
///    which are dark and beveled rather than light and outlined.
///  * [paintLed] — a lens rather than a filled rectangle, with a glow when
///    it is lit so a live channel is findable across a room.
///  * [paintRj45], [paintUsbA], [paintM12] — the connectors, which appear on
///    six different drawings and were six different wireframes.
///  * [paintFinnedHeatsink] — the CX heat sink, which was drawn as
///    alternating black bars and read as a barcode.
///
/// Everything here paints into the caller's current coordinate space and
/// takes its geometry in that space, so a device keeps working in whatever
/// design units it already used (mm for the boxes, fractions of the widget
/// for the terminals).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Beckhoff red, off the wordmark.
const beckhoffRed = Color(0xFFE30613);

/// The dark grey the mouldings are outlined in. Not black: a rack of
/// black-outlined terminals is a grid of hard lines, and the real seams
/// between adjacent housings are a shadow, not a rule.
final housingOutline = Colors.grey.shade700;

/// Nudge a colour's lightness, desaturating as it darkens.
///
/// Lightness alone is not enough on the cream the terminals are moulded in:
/// dropping the lightness of a pale yellow while holding its saturation
/// walks it towards khaki, and a housing shaded that way looks dirty rather
/// than rounded. Pulling saturation down with it keeps the shaded side the
/// same cream, just in shadow.
Color shiftLightness(Color base, double delta) {
  final hsl = HSLColor.fromColor(base);
  final saturation = delta < 0
      ? (hsl.saturation * (1.0 + delta * 1.6)).clamp(0.0, 1.0)
      : hsl.saturation;
  return hsl
      .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
      .withSaturation(saturation)
      .toColor();
}

/// The moulded-plastic fill for a housing of [rect].
///
/// Lit from the left, which is the convention the rest of the drawings on
/// these pages already follow, and the one that makes a row of terminals
/// show a seam at each join instead of merging into one cream slab.
Paint housingPaint(Rect rect, Color base) {
  return Paint()
    ..shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        shiftLightness(base, 0.030),
        base,
        shiftLightness(base, -0.050),
      ],
      stops: const [0.0, 0.40, 1.0],
    ).createShader(rect);
}

/// Fills and outlines a housing shell, with a highlight along its top edge.
///
/// [strokeWidth] is in the caller's units; pass what the device already used
/// for its outline so nothing changes weight.
void paintHousing(
  Canvas canvas,
  RRect shell, {
  required Color color,
  required double strokeWidth,
  Color? outline,
}) {
  final rect = shell.outerRect;
  canvas.drawRRect(shell, housingPaint(rect, color));

  // The top face of the moulding catches the light. One hairline, inset, so
  // it reads as a chamfer and not as a second border.
  canvas.drawLine(
    Offset(rect.left + rect.width * 0.08, rect.top + strokeWidth),
    Offset(rect.right - rect.width * 0.08, rect.top + strokeWidth),
    Paint()
      ..color = shiftLightness(color, 0.10)
      ..strokeWidth = strokeWidth * 0.9,
  );

  canvas.drawRRect(
    shell,
    Paint()
      ..color = outline ?? housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}

/// A recessed field — an LED window, a connector well, a label pocket.
///
/// Dark at the top-left where the wall shades it, lighter at the bottom-right
/// where the far wall catches light. That pair of edges is the whole cue; the
/// fill can stay close to the housing colour and the recess still reads.
void paintRecess(
  Canvas canvas,
  RRect well, {
  required Color face,
  required double strokeWidth,
}) {
  final rect = well.outerRect;
  canvas.drawRRect(
    well,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [shiftLightness(face, -0.10), face],
      ).createShader(rect),
  );

  // Shaded near wall, lit far wall.
  canvas.save();
  canvas.clipRRect(well);
  canvas.drawLine(
    Offset(rect.left, rect.top + strokeWidth * 0.5),
    Offset(rect.right, rect.top + strokeWidth * 0.5),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = strokeWidth,
  );
  canvas.drawLine(
    Offset(rect.left, rect.bottom - strokeWidth * 0.5),
    Offset(rect.right, rect.bottom - strokeWidth * 0.5),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..strokeWidth = strokeWidth,
  );
  canvas.restore();

  canvas.drawRRect(
    well,
    Paint()
      ..color = housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}

/// The round conductor entry of a spring terminal — a hole, not a disc.
///
/// Dark in the middle and darkest at the top where the bore is deepest, with
/// a lit lower rim. This is the feature an electrician aims a ferrule at, so
/// it is the one that most needs to look like an opening.
void paintContactHole(
  Canvas canvas,
  Offset centre,
  double radius, {
  required double strokeWidth,
}) {
  final bounds = Rect.fromCircle(center: centre, radius: radius);
  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.15, 0.5),
        radius: 1.0,
        colors: const [
          Color(0xFF4A4A4A),
          Color(0xFF5E5E5E),
          Color(0xFF9A9A9A),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(bounds),
  );

  // Lit rim along the bottom of the bore.
  canvas.drawArc(
    Rect.fromCircle(center: centre, radius: radius - strokeWidth * 0.4),
    math.pi * 0.15,
    math.pi * 0.7,
    false,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );

  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..color = housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}

/// The square screwdriver opening above each contact — the spring actuator.
///
/// Same treatment as [paintContactHole] so the pair reads as two openings in
/// one moulding rather than a square sticker over a round one.
void paintActuationSlot(
  Canvas canvas,
  Rect slot, {
  required double strokeWidth,
}) {
  canvas.drawRect(
    slot,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF585858), Color(0xFF8C8C8C)],
      ).createShader(slot),
  );

  // The blade slot itself: a lighter bar across the middle, which is what
  // catches the eye on the real part.
  canvas.drawRect(
    Rect.fromCenter(
      center: slot.center,
      width: slot.width * 0.62,
      height: slot.height * 0.2,
    ),
    Paint()..color = const Color(0xFF8C8C8C),
  );

  canvas.drawLine(
    Offset(slot.left, slot.bottom - strokeWidth * 0.5),
    Offset(slot.right, slot.bottom - strokeWidth * 0.5),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = strokeWidth,
  );

  canvas.drawRect(
    slot,
    Paint()
      ..color = housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}

/// An indicator lamp with a lens.
///
/// [color] is the lamp's face colour; [lit] decides whether it gets the bloom
/// that makes a live channel findable in a rack of forty. Unlit lamps keep
/// the dome shading, because a dark LED on the real hardware is still a
/// glossy dome and not a grey square.
void paintLed(
  Canvas canvas,
  RRect lens, {
  required Color color,
  required bool lit,
  required double strokeWidth,
  Paint? border,
}) {
  final rect = lens.outerRect;

  if (lit) {
    // A halo just outside the lens. Cheap — a radial gradient rather than a
    // blur — because a rack can carry sixty of these on a station PC.
    final halo = rect.inflate(math.min(rect.width, rect.height) * 0.35);
    canvas.drawRect(
      halo,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.0)],
          stops: const [0.35, 1.0],
        ).createShader(halo),
    );
  }

  canvas.drawRRect(
    lens,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [shiftLightness(color, 0.12), color, shiftLightness(color, -0.12)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect),
  );

  // Specular blob, upper left, where a cabinet light would sit.
  final gloss = Rect.fromLTWH(
    rect.left + rect.width * 0.12,
    rect.top + rect.height * 0.10,
    rect.width * 0.48,
    rect.height * 0.36,
  );
  canvas.drawOval(
    gloss,
    Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: lit ? 0.50 : 0.40),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(gloss),
  );

  canvas.drawRRect(
    lens,
    border ??
        (Paint()
          ..color = housingOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth),
  );
}

/// An RJ45 socket, viewed from the front, latch slot to the left.
///
/// The Beckhoff parts that carry one — EK1100, EK1110, CX, PS2001, CU2508 —
/// mount the jack turned a quarter so the cable leaves sideways out of a
/// 20 mm-wide face, which is why the keyway is on the left rather than the
/// bottom. Two link lamps sit in the bezel beside it, as they do on the part.
///
/// Fits itself inside [bounds] at the jack's own 0.83 aspect, so a caller
/// that hands it a square gets a centred socket rather than a stretched one.
void paintRj45(
  Canvas canvas,
  Rect bounds, {
  Color outline = Colors.black,
  double strokeScale = 1.0,
}) {
  const aspect = 53.48 / 64.63; // width / height, off the original drawing
  var w = bounds.width;
  var h = w / aspect;
  if (h > bounds.height) {
    h = bounds.height;
    w = h * aspect;
  }
  final r = Rect.fromCenter(center: bounds.center, width: w, height: h);
  final stroke = math.max(w * 0.018, 0.35) * strokeScale;

  // Bezel: the shielded shroud, dark plastic over metal.
  final bezel = RRect.fromRectAndRadius(r, Radius.circular(w * 0.06));
  canvas.drawRRect(
    bezel,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xFF6E7276), Color(0xFF3C4044)],
      ).createShader(r),
  );

  // Link lamps in the bezel, amber above and green below — the pair a
  // Beckhoff RJ45 wears, and the two little tabs the original wireframe had
  // on this edge without saying what they were.
  const lampColors = [Color(0xFFE8A317), Color(0xFF62B32E)];
  for (int i = 0; i < 2; i++) {
    final lamp = Rect.fromCenter(
      center: Offset(r.left + w * 0.12, r.top + h * (i == 0 ? 0.11 : 0.89)),
      width: w * 0.14,
      height: h * 0.11,
    );
    canvas.drawRect(lamp, Paint()..color = lampColors[i]);
    canvas.drawRect(
      lamp,
      Paint()
        ..color = const Color(0xFF2A2C2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  // The opening: a rectangle with the latch keyway notched out of its left
  // side. Built as one path so the cavity shading crosses both.
  final wellLeft = r.left + w * 0.26;
  final wellRight = r.right - w * 0.10;
  final wellTop = r.top + h * 0.10;
  final wellBottom = r.bottom - h * 0.10;
  final notchTop = r.top + h * 0.38;
  final notchBottom = r.top + h * 0.62;
  final notchLeft = wellLeft - w * 0.14;

  final well = Path()
    ..moveTo(wellLeft, wellTop)
    ..lineTo(wellRight, wellTop)
    ..lineTo(wellRight, wellBottom)
    ..lineTo(wellLeft, wellBottom)
    ..lineTo(wellLeft, notchBottom)
    ..lineTo(notchLeft, notchBottom)
    ..lineTo(notchLeft, notchTop)
    ..lineTo(wellLeft, notchTop)
    ..close();

  final wellBounds = Rect.fromLTRB(notchLeft, wellTop, wellRight, wellBottom);
  canvas.drawPath(
    well,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [Color(0xFF0E1012), Color(0xFF232729)],
      ).createShader(wellBounds),
  );

  // The eight contacts, gold, on the wall opposite the latch.
  final contactLeft = wellLeft + (wellRight - wellLeft) * 0.46;
  final pitch = (wellBottom - wellTop) / 9.0;
  final contactPaint = Paint()
    ..color = const Color(0xFFC8A23C)
    ..strokeWidth = math.max(pitch * 0.32, stroke)
    ..strokeCap = StrokeCap.round;
  for (int i = 1; i <= 8; i++) {
    final y = wellTop + pitch * i;
    canvas.drawLine(
      Offset(contactLeft, y),
      Offset(wellRight - w * 0.05, y),
      contactPaint,
    );
  }

  canvas.drawPath(
    well,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke,
  );
  canvas.drawRRect(
    bezel,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke,
  );
}

/// A USB-A socket, viewed from the front, turned a quarter like the RJ45s
/// beside it on a CX front panel.
///
/// A metal shroud, a dark well, and the insulator tongue with its contacts
/// down one side — the only detail that tells a USB port apart from any other
/// rectangular hole at mimic scale. Blue, because the CX fronts on this plant
/// carry USB 3.0 and the blue insulator is how you know that at a glance.
void paintUsbA(
  Canvas canvas,
  Rect bounds, {
  Color outline = Colors.black,
}) {
  final stroke = math.max(bounds.width * 0.05, 0.3);

  final shroud = RRect.fromRectAndRadius(
    bounds,
    Radius.circular(bounds.width * 0.08),
  );
  canvas.drawRRect(
    shroud,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xFFC9CDD2), Color(0xFF8A9095)],
      ).createShader(bounds),
  );

  final well = bounds.deflate(bounds.width * 0.16);
  canvas.drawRect(well, Paint()..color = const Color(0xFF17191B));

  // Insulator tongue against the left wall, four contacts along it.
  final tongue = Rect.fromLTWH(
    well.left,
    well.top + well.height * 0.06,
    well.width * 0.42,
    well.height * 0.88,
  );
  canvas.drawRect(tongue, Paint()..color = const Color(0xFF2B62B5));
  final pitch = tongue.height / 5.0;
  for (int i = 1; i <= 4; i++) {
    canvas.drawRect(
      Rect.fromLTWH(
        tongue.left + tongue.width * 0.2,
        tongue.top + pitch * i - pitch * 0.14,
        tongue.width * 0.62,
        pitch * 0.28,
      ),
      Paint()..color = const Color(0xFFC8A23C),
    );
  }

  canvas.drawRRect(
    shroud,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke,
  );
}

/// An M8 or M12 circular connector, as the EtherCAT Boxes wear.
///
/// The knurled coupling nut is what makes one recognisable at a glance —
/// without the knurl a round connector is just a washer — so the ring gets
/// its grip flutes and the well gets its keyway and pins.
void paintM12(
  Canvas canvas,
  Offset centre,
  double radius, {
  required double strokeWidth,
  int pins = 4,
  int flutes = 20,
  Color well = const Color(0xFF20242A),
}) {
  final ringBounds = Rect.fromCircle(center: centre, radius: radius);

  // Coupling nut, lit from the upper left like everything else here.
  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xFFDCDCDC), Color(0xFF8E8E8E)],
      ).createShader(ringBounds),
  );

  // Grip flutes around the nut.
  final flute = Paint()
    ..color = Colors.black.withValues(alpha: 0.35)
    ..strokeWidth = strokeWidth * 0.8;
  for (int i = 0; i < flutes; i++) {
    final a = i * 2 * math.pi / flutes;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
      centre + dir * (radius * 0.78),
      centre + dir * (radius * 0.98),
      flute,
    );
  }
  canvas.drawCircle(
    centre,
    radius,
    Paint()
      ..color = housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );

  // The well, and the moulded insert with its pins.
  final wellR = radius * 0.62;
  final wellBounds = Rect.fromCircle(center: centre, radius: wellR);
  canvas.drawCircle(
    centre,
    wellR,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.2, 0.4),
        colors: [well, shiftLightness(well, 0.12)],
      ).createShader(wellBounds),
  );
  canvas.drawCircle(
    centre,
    wellR,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );

  final pinR = math.max(wellR * 0.15, strokeWidth * 0.6);
  final pinPaint = Paint()..color = const Color(0xFFD8B252);
  for (int i = 0; i < pins; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / pins;
    final at = centre + Offset(math.cos(a), math.sin(a)) * (wellR * 0.48);
    canvas.drawCircle(at, pinR, pinPaint);
  }

  // Keyway notch at the top of the nut, the orientation mark.
  canvas.drawRect(
    Rect.fromCenter(
      center: centre.translate(0, -radius * 0.86),
      width: radius * 0.30,
      height: radius * 0.30,
    ),
    Paint()..color = const Color(0xFF5C5C5C),
  );
}

/// The cooling vents down the side of a CX embedded PC.
///
/// Photographs of a CX5340 settle what these are: dark slots cut into the
/// light housing, seen edge-on, not bright aluminium fins. So the ground
/// stays the housing colour and each pitch gets a dark slot with a lit lip
/// under it — which is the original drawing's alternating bars, given the
/// depth they were missing.
void paintFinnedHeatsink(
  Canvas canvas,
  Rect bounds, {
  required int fins,
  required Color housing,
  required double strokeWidth,
}) {
  canvas.drawRect(bounds, housingPaint(bounds, housing));

  final pitch = bounds.height / fins;
  final slotHeight = pitch * 0.55;
  for (int i = 0; i < fins; i++) {
    final y = bounds.top + i * pitch + (pitch - slotHeight) / 2;
    final slot = Rect.fromLTWH(bounds.left, y, bounds.width, slotHeight);
    canvas.drawRect(
      slot,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF101214), Color(0xFF32373B)],
        ).createShader(slot),
    );
    // The lip below each slot catches the light.
    canvas.drawLine(
      Offset(bounds.left, slot.bottom + strokeWidth * 0.5),
      Offset(bounds.right, slot.bottom + strokeWidth * 0.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = strokeWidth,
    );
  }

  canvas.drawRect(
    bounds,
    Paint()
      ..color = housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
}

/// Where a name or id may be broken across two lines: after a space, and
/// after a separator. Never inside a token.
///
/// The positions are indices into [label] at which a second line may start.
List<int> markerBreakPoints(String label) {
  final out = <int>[];
  for (var i = 0; i < label.length - 1; i++) {
    if (label[i] == ' ' || '._-/:'.contains(label[i])) out.add(i + 1);
  }
  return out;
}

/// The operator's own tag on a terminal — the configured name or id, printed
/// on the marker band where the 07/08 terminal markers go.
///
/// The hard part is that the band is only as wide as a 12 mm terminal and a
/// plant id is a dozen characters. Shrinking one line to fit put
/// `ST101.A1.03` on the housing at a third the height of its band, and
/// ellipsizing is worse than shrinking: these ids are told apart by their
/// *tail*, and an ellipsis eats exactly that.
///
/// So the tag may take two lines — but only broken where a person would
/// break it. Handing the job to the `TextPainter` is not enough: with no
/// space to break at it wraps mid-token, which turned `LICENCE` into
/// `LICE`/`NCE` and `ST301 A1` into `ST30`/`1 A1`. The split is therefore
/// chosen here, from [markerBreakPoints], at whichever legal point leaves
/// the two halves most even, and the line ending is explicit.
///
/// Two lines are used only when they buy a materially bigger face than one
/// line would; a name that fits comfortably on one keeps it.
void paintMarkerTag(
  Canvas canvas,
  Rect band,
  String label, {
  required Color color,
  required double strokeWidth,
  required double minFontSize,
  String fontFamily = 'Roboto',
}) {
  canvas.drawRect(band, Paint()..color = color);
  canvas.drawRect(
    band,
    Paint()
      ..color = housingOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );

  final inner = band.deflate(strokeWidth * 1.5);

  TextPainter layoutAt(String text, double fontSize, int maxLines) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.05,
            // Named, as ek1100.dart names it: a null family renders as the
            // test font's boxes under `flutter test`, and a golden of boxes
            // pins nothing about a label.
            fontFamily: fontFamily,
          ),
        ),
        maxLines: maxLines,
        ellipsis: '…',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: inner.width, maxWidth: inner.width);

  final maxFontSize = band.height * 0.62;
  const steps = 28;
  double stepFontSize(int i) =>
      maxFontSize - (maxFontSize - minFontSize) * i / steps;

  /// The largest size at which [text] fits without the painter having to
  /// wrap or ellipsize it, or null when even the floor does not fit.
  ({double fontSize, TextPainter painter})? largestFit(
      String text, int maxLines) {
    for (var i = 0; i <= steps; i++) {
      final fontSize = stepFontSize(i);
      final tp = layoutAt(text, fontSize, maxLines);
      if (!tp.didExceedMaxLines && tp.height <= inner.height) {
        return (fontSize: fontSize, painter: tp);
      }
    }
    return null;
  }

  final single = largestFit(label, 1);

  // The most even legal split, if there is one.
  ({double fontSize, TextPainter painter})? double_;
  final breaks = markerBreakPoints(label);
  if (breaks.isNotEmpty) {
    var best = breaks.first;
    for (final at in breaks) {
      if ((label.length - at - at).abs() < (label.length - best - best).abs()) {
        best = at;
      }
    }
    final wrapped =
        '${label.substring(0, best).trimRight()}\n${label.substring(best)}';
    double_ = largestFit(wrapped, 2);
  }

  // One line unless two buy a materially bigger face — wrapping a name that
  // already fits is churn, not legibility.
  final chosen = switch ((single, double_)) {
    // Nothing fits: one ellipsized line, never two, because a second line in
    // a band sized for one would paint over the LED block below it.
    (null, null) => layoutAt(label, minFontSize, 1),
    (final s?, null) => s.painter,
    (null, final d?) => d.painter,
    (final s?, final d?) =>
      d.fontSize > s.fontSize * 1.15 ? d.painter : s.painter,
  };

  chosen.paint(
    canvas,
    Offset(inner.left, inner.top + (inner.height - chosen.height) / 2),
  );
}
