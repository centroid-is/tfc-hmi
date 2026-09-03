/// Festo VTUG-14 valve terminal with a CTEU-EC bus node — the assembly
/// bolted to the track stations, drawn front-on.
///
/// Left to right, which is the order it is built in: the bus node, the
/// electrical interface, the left end plate carrying the supply, eight valve
/// positions on a 14 mm grid, and the right end plate. `14` in the part
/// number is that grid dimension, so the slice pitch is not a drawing
/// choice — it is the hardware, and the drawing is built out of it.
///
/// ## Drawn from photographs, and where that changed things
///
/// Festo blocks their own catalogue, so a first pass of this was built from
/// dimensions and the CTEU-EC installation instructions. Photographs of the
/// actual parts corrected three things, and every one of them mattered:
///
///  * **The hardware is white.** VUVG valves, the VAEM interface and the
///    CTEU housing are all a pale grey-white with a dark solenoid block, not
///    the anthracite the first pass assumed. A mimic that gets a device's
///    colour wrong is a mimic nobody matches to the cabinet in front of them.
///  * **The manual overrides are blue.** They are the one saturated thing on
///    the valve and the first thing a fitter's eye goes to, so they are the
///    one saturated thing here.
///  * **The node has six lamps, in one column, and no `ERROR`.** The
///    silkscreen reads `PS`, `X1`, `X2`, `Run`, `L/A2`, `L/A1`. The
///    instructions describe an EtherCAT error indicator, the first pass drew
///    one in a second column, and it is not on the housing. See [CteuLink]
///    for why an invented diagnostic lamp is worse than a missing one.
///
/// Each valve wears its coils' LEDs where the real one does: small clear
/// lenses at the top of the coil end, under the `14` and `12` moulded into
/// the body. A blanked position has no valve and therefore no lamps, and
/// this draws none — a dark lamp on a position with no coil behind it is a
/// channel that does not exist.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Valve positions on the manifold — see `vtugPositionCount`.
const int vtugSliceCount = 8;

/// The grid dimension, in mm. `VTUG-14` is named for it.
const double vtugSliceWidthMm = 14;

/// End plate width in mm — the same casting either end.
const double vtugEndPlateWidthMm = 24;

/// The bus node's face, in mm. Taller than the manifold, which is why it
/// sets the height of the whole drawing.
const Size cteuFaceMm = Size(54, 80);

/// The `VAEM-L1-S-8-PT` electrical interface between the node and the
/// valves — a flat plate with one M12 on it.
const double vaemWidthMm = 18;

/// The whole assembly's face, in mm: node, interface, end plate, eight
/// slices, end plate — 54 + 18 + 24 + 8x14 + 24. Spelled out rather than
/// computed because a `const Size` cannot read a field off another one, and
/// the arithmetic is asserted in `vtug_test.dart` so the two cannot drift.
const Size vtugFaceMm = Size(232, 80);

/// Where the manifold starts down the face. The bus node is the tall part of
/// the assembly; the valve block sits below its shoulder.
const double _manifoldTopMm = 16;

/// The pale grey-white Festo moulds the VUVG bodies, the VAEM interface and
/// the CTEU housing in.
const Color festoWhite = Color(0xFFECECEA);

/// A half-tone of it, for the sub-base the valves sit on — enough to read as
/// a separate casting without turning the terminal into two colours.
const Color vtugManifoldColor = Color(0xFFD5D6D4);

/// The dark block over the pilot solenoids, which is the strongest shape on
/// a VUVG and the thing that makes a row of them read as valves.
const Color vuvgSolenoidColor = Color(0xFF3B3B3D);

/// Festo's blue. On the hardware it is the logo and the manual override
/// caps, and it is used for exactly those two things here.
const Color festoBlue = Color(0xFF0091DC);

/// The dark inset the LEDs sit behind on the bus node.
const Color cteuLedPanelColor = Color(0xFF2B2E30);

/// How a bus-node LED is lit.
///
/// The CTEU's own vocabulary, kept whole rather than collapsed to on/off:
/// `Run` slow-flashing means PRE-OPERATIONAL and `Run` off means INIT, and
/// an electrician standing at the terminal reads those as different faults.
enum CteuLedState {
  off,
  green,
  greenFlashing,
  red,
  redFlashing,

  /// Nothing is known about this LED. Drawn as an unlit lamp with no
  /// colour — distinct from [off], which is a state the node reports.
  unknown,
}

/// One lamp on the bus node's face.
@immutable
class CteuLed {
  const CteuLed(this.label, this.state);

  /// As silkscreened: `PS`, `X1`, `X2`, `Run`, `L/A2`, `L/A1`.
  final String label;

  final CteuLedState state;

  @override
  bool operator ==(Object other) =>
      other is CteuLed && other.label == label && other.state == state;

  @override
  int get hashCode => Object.hash(label, state);
}

/// One valve position as the drawing needs it: how many lamps, and whether
/// each is lit.
///
/// [coils] is empty for a blanked position, one long for a monostable and
/// two for a 5/2 bistable or a 5/3, in coil 14 then coil 12 order. `null` is
/// a coil the terminal has said nothing about.
@immutable
class VtugSliceView {
  const VtugSliceView({required this.coils, this.held = false});

  final List<bool?> coils;

  /// True when an operator is holding this position by hand. Drawn as an
  /// orange bar under the slice — forced is orange everywhere in this repo,
  /// and a held valve is the one thing on this drawing somebody has to
  /// remember to give back.
  final bool held;

  @override
  bool operator ==(Object other) =>
      other is VtugSliceView &&
      listEquals(other.coils, coils) &&
      other.held == held;

  @override
  int get hashCode => Object.hash(Object.hashAll(coils), held);
}

class VtugPainter extends CustomPainter {
  VtugPainter({
    required this.slices,
    required this.leds,
    required this.litColor,
    this.name = '',
    this.disconnected = false,
  }) : assert(slices.length == vtugSliceCount);

  /// Position 1 first.
  final List<VtugSliceView> slices;

  /// The bus node's lamps, in face order.
  final List<CteuLed> leds;

  /// What an energised coil is drawn in. Passed rather than baked so the
  /// lamps take the theme's yellow — the same yellow the conveyors use for
  /// commanded state — instead of a raw colour the theme cannot reach.
  final Color litColor;

  /// The plant's tag for the terminal, printed on the end plate.
  final String name;

  /// Draws the "nothing is arriving" mark.
  final bool disconnected;

  @override
  void paint(Canvas canvas, Size size) {
    const design = vtugFaceMm;
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

    _paintBusNode(canvas);
    _paintInterface(canvas);
    _paintManifold(canvas);
    if (disconnected) _paintDisconnected(canvas, design);

    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Bus node
  // -------------------------------------------------------------------------

  void _paintBusNode(Canvas canvas) {
    // Square on the right: the node bolts to the interface plate and there
    // is no seam between them on the hardware. Two rounded edges meeting
    // left a sliver of page showing through the middle of one casting.
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, cteuFaceMm.width, cteuFaceMm.height),
      topLeft: const Radius.circular(2),
      bottomLeft: const Radius.circular(2),
    );
    canvas.drawRRect(body, Paint()..color = festoWhite);
    canvas.drawRRect(body, _outline);

    // The lamps: one column down the left, labels outboard of the dots,
    // exactly as the housing is silkscreened. No panel behind them — the
    // real ones are bare lenses in the white moulding.
    const ledTop = 8.0;
    const ledPitch = 7.4;
    for (var i = 0; i < leds.length; i++) {
      final y = ledTop + i * ledPitch;
      _text(
        canvas,
        leds[i].label,
        Offset(3, y - 1.6),
        fontSize: 3.2,
        color: const Color(0xFF55585A),
        width: 11,
        align: TextAlign.right,
      );
      _paintCteuLed(canvas, Offset(17, y), leds[i].state);
    }

    // The service window — the clear cover over the address switches, and
    // the most recognisable thing on the face after the lamps.
    final window = RRect.fromRectAndRadius(
      const Rect.fromLTWH(24, 8, 26, 13),
      const Radius.circular(1),
    );
    canvas.drawRRect(window, Paint()..color = cteuLedPanelColor.withValues(alpha: 0.25));
    canvas.drawRRect(window, _outline);

    // Power in on top, then the two bus sockets. `In 1` and `Out 2` are
    // moulded beside them, and they are what `L/A1` and `L/A2` report on —
    // three identical rings say nothing about which one is the bus.
    _connector(canvas, const Offset(31, 32), male: true);
    _text(canvas, 'PWR', const Offset(24, 39), fontSize: 3, color: const Color(0xFF55585A), width: 14);

    _connector(canvas, const Offset(24, 52), male: false);
    _text(canvas, 'In 1', const Offset(17, 59), fontSize: 3, color: const Color(0xFF55585A), width: 14);

    _connector(canvas, const Offset(43, 52), male: false);
    _text(canvas, 'Out 2', const Offset(36, 59), fontSize: 3, color: const Color(0xFF55585A), width: 14);

    _text(
      canvas,
      'CTEU-EC',
      const Offset(3, 70),
      fontSize: 4,
      color: const Color(0xFF44474A),
      width: 30,
      align: TextAlign.left,
    );
  }

  /// An M12. Male shows pins, female shows the socket ring.
  void _connector(Canvas canvas, Offset centre, {required bool male}) {
    canvas.drawCircle(centre, 5, Paint()..color = const Color(0xFFB9BCBE));
    canvas.drawCircle(centre, 5, _outline);
    canvas.drawCircle(centre, 3.2, Paint()..color = const Color(0xFF3A3D3F));
    if (male) {
      canvas.drawCircle(centre, 1.1, Paint()..color = const Color(0xFFD8D9D6));
    } else {
      canvas.drawCircle(
        centre,
        1.7,
        Paint()
          ..color = const Color(0xFF17191A)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _paintCteuLed(Canvas canvas, Offset centre, CteuLedState state) {
    // A flashing lamp is drawn as a ring rather than animated: this asset is
    // one of many on a mimic, and six blinking lamps a terminal is a page
    // nobody can read. The ring says "flashing" and the pane says what the
    // flash means.
    final (fill, ring) = switch (state) {
      CteuLedState.off => (const Color(0xFFCBCCC9), false),
      CteuLedState.green => (const Color(0xFF43A047), false),
      CteuLedState.greenFlashing => (const Color(0xFF43A047), true),
      CteuLedState.red => (const Color(0xFFE53935), false),
      CteuLedState.redFlashing => (const Color(0xFFE53935), true),
      CteuLedState.unknown => (const Color(0xFFA8ABAD), false),
    };
    canvas.drawCircle(centre, 1.5, Paint()..color = fill);
    canvas.drawCircle(centre, 1.5, _outline);
    if (ring) {
      canvas.drawCircle(
        centre,
        2.5,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Electrical interface
  // -------------------------------------------------------------------------

  /// `VAEM-L1-S-8-PT` — the flat plate between the node and the valves. One
  /// M12 on top and a Festo logo, and that is genuinely all there is on it.
  void _paintInterface(Canvas canvas) {
    final rect = Rect.fromLTWH(
      cteuFaceMm.width,
      _manifoldTopMm - 4,
      vaemWidthMm,
      vtugFaceMm.height - (_manifoldTopMm - 4),
    );
    canvas.drawRect(rect, Paint()..color = festoWhite);
    canvas.drawRect(rect, _outline);

    _connector(canvas, Offset(rect.center.dx, rect.top + 10), male: true);
    _text(
      canvas,
      'FESTO',
      Offset(rect.left + 1, rect.top + 22),
      fontSize: 3.2,
      color: festoBlue,
      width: vaemWidthMm - 2,
    );
    _text(
      canvas,
      'VAEM',
      Offset(rect.left + 1, rect.bottom - 6),
      fontSize: 3,
      color: const Color(0xFF6E7274),
      width: vaemWidthMm - 2,
    );
  }

  // -------------------------------------------------------------------------
  // Manifold
  // -------------------------------------------------------------------------

  void _paintManifold(Canvas canvas) {
    const top = _manifoldTopMm;
    final height = vtugFaceMm.height - top;
    final left = cteuFaceMm.width + vaemWidthMm;
    final width = vtugFaceMm.width - left;

    final block = RRect.fromRectAndCorners(
      Rect.fromLTWH(left, top, width, height),
      topRight: const Radius.circular(1.5),
      bottomRight: const Radius.circular(1.5),
    );
    canvas.drawRRect(block, Paint()..color = vtugManifoldColor);
    canvas.drawRRect(block, _outline);

    _paintEndPlate(canvas, left, top, height, isLeft: true);
    _paintEndPlate(
      canvas,
      vtugFaceMm.width - vtugEndPlateWidthMm,
      top,
      height,
      isLeft: false,
    );

    final slicesLeft = left + vtugEndPlateWidthMm;
    for (var i = 0; i < slices.length; i++) {
      _paintSlice(canvas, slicesLeft + i * vtugSliceWidthMm, top, i + 1);
    }
  }

  void _paintEndPlate(
    Canvas canvas,
    double left,
    double top,
    double height, {
    required bool isLeft,
  }) {
    final plate = Rect.fromLTWH(left, top, vtugEndPlateWidthMm, height);
    canvas.drawRect(plate, Paint()..color = festoWhite);
    canvas.drawRect(plate, _outline);

    if (isLeft) {
      // Supply on a QS-12 fitting, and the exhaust under a `U-1/4`
      // silencer — the fat white cap in the parts list, drawn as a cap
      // rather than a fitting because that is what tells them apart on the
      // hardware.
      _fitting(canvas, Offset(left + vtugEndPlateWidthMm / 2, top + 16),
          radius: 5);
      _text(canvas, '1', Offset(left + 2, top + 14), fontSize: 3.4,
          color: const Color(0xFF6E7274), width: 5, align: TextAlign.right);

      final silencer = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(left + vtugEndPlateWidthMm / 2, top + 36),
          width: 13,
          height: 9,
        ),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(silencer, Paint()..color = const Color(0xFFDEDFDC));
      canvas.drawRRect(silencer, _outline);
      for (var i = 0; i < 4; i++) {
        final x = silencer.left + 2.5 + i * 2.6;
        canvas.drawLine(
          Offset(x, silencer.top + 1.6),
          Offset(x, silencer.bottom - 1.6),
          Paint()
            ..color = const Color(0xFF9DA0A2)
            ..strokeWidth = 0.5,
        );
      }
      _text(canvas, '3/5', Offset(left + 1, top + 34), fontSize: 3,
          color: const Color(0xFF6E7274), width: 6, align: TextAlign.right);
    } else if (name.isNotEmpty) {
      canvas.save();
      canvas.translate(left + vtugEndPlateWidthMm - 4, top + height - 3);
      canvas.rotate(-math.pi / 2);
      _text(
        canvas,
        name,
        Offset.zero,
        fontSize: 4,
        color: const Color(0xFF44474A),
        width: height - 6,
        align: TextAlign.left,
      );
      canvas.restore();
    }
  }

  /// A QS push-in fitting: the collet ring with the tube bore in the middle.
  void _fitting(Canvas canvas, Offset centre, {required double radius}) {
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFFDEDFDC));
    canvas.drawCircle(centre, radius, _outline);
    canvas.drawCircle(
        centre, radius * 0.62, Paint()..color = const Color(0xFFB6B9BB));
    canvas.drawCircle(
        centre, radius * 0.34, Paint()..color = const Color(0xFF4A4D4F));
  }

  void _paintSlice(Canvas canvas, double left, double top, int position) {
    const w = vtugSliceWidthMm;
    final slice = slices[position - 1];
    final blank = slice.coils.isEmpty;

    // A blanked position carries a plate rather than a valve. Festo makes it
    // in the same white, so the gap in the row is read off the missing
    // solenoid block and the missing lamps, not off a colour change.
    final valve = Rect.fromLTWH(left + 0.5, top + 1, w - 1, 30);
    canvas.drawRect(valve, Paint()..color = festoWhite);
    canvas.drawRect(valve, _outline);

    if (blank) {
      // The plate's one feature: a shallow recess where the valve body
      // would be.
      canvas.drawRect(
        Rect.fromLTWH(left + 2.5, top + 6, w - 5, 18),
        Paint()..color = const Color(0xFFDCDDDA),
      );
    } else {
      // The dark solenoid block. One coil takes half the width, two take
      // the lot — which is the fastest read on the whole drawing for how
      // many coils a position has, before anyone counts lamps.
      final coils = slice.coils.length;
      final blockWidth = coils == 1 ? (w - 3) * 0.55 : w - 3;
      canvas.drawRect(
        Rect.fromLTWH(left + 1.5, top + 12, blockWidth, 13),
        Paint()..color = vuvgSolenoidColor,
      );

      // The lamps, at the top of the coil end where the real lenses are,
      // with `14` and `12` moulded above them.
      final xs = coils == 1
          ? [left + w / 2]
          : [left + w / 2 - 3.2, left + w / 2 + 3.2];
      const labels = ['14', '12'];
      for (var i = 0; i < coils; i++) {
        final lamp = Rect.fromCenter(
          center: Offset(xs[i], top + 8),
          width: 3.2,
          height: 3.2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(lamp, const Radius.circular(0.6)),
          Paint()
            ..color = switch (slice.coils[i]) {
              null => const Color(0xFFA8ABAD),
              true => litColor,
              false => const Color(0xFFF6F6F2),
            },
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(lamp, const Radius.circular(0.6)),
          _outline,
        );
        _text(
          canvas,
          labels[i],
          Offset(xs[i] - 2.5, top + 2.6),
          fontSize: 2.6,
          color: const Color(0xFF6E7274),
          width: 5,
        );
      }

      // The blue manual overrides, one per coil, on the solenoid block. The
      // only saturated colour on the hardware and the only one here.
      for (var i = 0; i < coils; i++) {
        canvas.drawCircle(Offset(xs[i], top + 18.5), 1.5,
            Paint()..color = festoBlue);
        canvas.drawCircle(Offset(xs[i], top + 18.5), 1.5, _outline);
      }
    }

    // Working ports 2 and 4, stacked on the front of the sub-base — QS-8,
    // so narrower than the supply fitting on the end plate.
    const portLabels = ['4', '2'];
    for (var i = 0; i < 2; i++) {
      final centre = Offset(left + w / 2, top + 40 + i * 13);
      _fitting(canvas, centre, radius: 3.6);
      _text(
        canvas,
        portLabels[i],
        Offset(left + 0.5, centre.dy - 1.4),
        fontSize: 2.8,
        color: const Color(0xFF6E7274),
        width: 3,
        align: TextAlign.right,
      );
    }

    if (slice.held) {
      canvas.drawRect(
        Rect.fromLTWH(left + 0.5, top + 32, w - 1, 1.8),
        Paint()..color = Colors.orange,
      );
    }

    _text(
      canvas,
      '$position',
      Offset(left, vtugFaceMm.height - 5),
      fontSize: 3.4,
      color: const Color(0xFF6E7274),
      width: w,
    );
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  Paint get _outline => Paint()
    ..color = const Color(0xFF8E9294)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.3;

  /// The "nothing is arriving" mark.
  ///
  /// Beside the bus node rather than the middle of the manifold, because
  /// that is what it is about: the valves are fine, the terminal is not
  /// talking. A small glyph lost among eight slices — which is where it
  /// started — read as a smudge on a valve.
  ///
  /// In the clear band above the interface plate, not on the node's face.
  /// Centred on the node it sat across a diagnostic lamp, and a fault badge
  /// that hides a diagnostic lamp costs more than it tells.
  void _paintDisconnected(Canvas canvas, Size design) {
    final centre = Offset(cteuFaceMm.width + vaemWidthMm / 2, 8);
    canvas.drawCircle(centre, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      centre,
      7,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _text(
      canvas,
      '!',
      Offset(centre.dx - 5, centre.dy - 5),
      fontSize: 10,
      color: Colors.red,
      width: 10,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    required double fontSize,
    required Color color,
    required double width,
    TextAlign align = TextAlign.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          // Named, not inherited: a painter draws outside any
          // `DefaultTextStyle`, so a null family falls back to the test font
          // and every caption on this drawing golden-tests as a row of
          // boxes. The other device painters in this repo name 'Roboto' for
          // the same reason.
          fontFamily: 'Roboto',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(VtugPainter old) =>
      !listEquals(old.slices, slices) ||
      !listEquals(old.leds, leds) ||
      old.litColor != litColor ||
      old.name != name ||
      old.disconnected != disconnected;
}

/// The assembly at its native aspect, sized by [height].
class VtugWidget extends StatelessWidget {
  const VtugWidget({
    super.key,
    required this.slices,
    required this.leds,
    required this.litColor,
    this.name = '',
    this.disconnected = false,
    this.height = 120,
  });

  final List<VtugSliceView> slices;
  final List<CteuLed> leds;
  final Color litColor;
  final String name;
  final bool disconnected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final width = height * vtugFaceMm.width / vtugFaceMm.height;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: VtugPainter(
          slices: slices,
          leds: leds,
          litColor: litColor,
          name: name,
          disconnected: disconnected,
        ),
      ),
    );
  }
}
