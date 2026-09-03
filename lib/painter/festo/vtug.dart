/// Festo VTUG-14 valve terminal with a CTEU-EC bus node on its left end
/// plate — the assembly bolted to the track stations, drawn front-on.
///
/// Left to right, which is the order it is built in: the bus node, the left
/// end plate carrying the supply ports, eight valve positions on a 14 mm
/// grid, and the right end plate. `14` in the part number is that grid
/// dimension, so the slice pitch is not a drawing choice — it is the
/// hardware, and the drawing is built out of it.
///
/// Each position wears its coils' LEDs where the valve wears them: a small
/// yellow lamp per pilot solenoid at the top of the slice, coil 14 on the
/// left and coil 12 on the right. A blanked position has no valve and
/// therefore no lamps, and this draws none — a dark lamp on a position with
/// no coil behind it is a channel that does not exist.
///
/// The bus node's own LEDs are drawn from the same reference: PS, X1 and X2
/// are the CTEU's, RUN, ERROR, L/A1 and L/A2 are EtherCAT's. Nothing on this
/// plant publishes them, so they are lit from the one thing that is known —
/// whether the terminal's process data is arriving. See `CteuLink` in
/// `lib/page_creator/assets/vtug.dart` for what each state means and why the
/// node is never drawn more confident than the data behind it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Valve positions on the manifold — see `vtugPositionCount`.
const int vtugSliceCount = 8;

/// The grid dimension, in mm. `VTUG-14` is named for it.
const double vtugSliceWidthMm = 14;

/// End plate width in mm — the same casting either end.
const double vtugEndPlateWidthMm = 26;

/// The bus node's face, in mm.
const Size cteuFaceMm = Size(52, 78);

/// The whole assembly's face, in mm: node, end plate, eight slices, end
/// plate — 52 + 26 + 8x14 + 26. Spelled out rather than computed because a
/// `const Size` cannot read a field off another one, and the arithmetic is
/// asserted in `vtug_painter_test.dart` so the two cannot drift.
const Size vtugFaceMm = Size(216, 78);

/// Where the manifold starts down the face. The bus node is the tall part of
/// the assembly; the valve block sits below its shoulder.
const double _manifoldTopMm = 14;

/// The anthracite Festo casts the manifold and the node in.
const Color vtugManifoldColor = Color(0xFF3A3D40);

/// The lighter grey of the valve body sitting on the manifold.
const Color vtugValveColor = Color(0xFFBFC3C6);

/// Festo's blue, used the way Festo uses it — as an accent stripe, not a
/// field.
const Color festoBlue = Color(0xFF0091DC);

/// The dark inset the LEDs sit behind on the bus node.
const Color cteuLedPanelColor = Color(0xFF25282A);

/// How a bus-node LED is lit.
///
/// The CTEU's own vocabulary, kept whole rather than collapsed to on/off:
/// RUN slow-flashing means PRE-OPERATIONAL and RUN off means INIT, and an
/// electrician standing at the terminal reads those as different faults.
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

  /// As silkscreened: `PS`, `X1`, `RUN`, `L/A1`.
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
/// [coils] is empty for a blanked position, one long for a single solenoid
/// and two for a double, in coil 14 then coil 12 order. `null` is a coil the
/// terminal has said nothing about.
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
    _paintManifold(canvas);
    if (disconnected) _paintDisconnected(canvas, design);

    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Bus node
  // -------------------------------------------------------------------------

  void _paintBusNode(Canvas canvas) {
    // Square on the right: the node bolts onto the manifold's end plate and
    // there is no seam between them on the hardware. Two rounded edges
    // meeting left a sliver of page showing through the middle of one
    // casting.
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, cteuFaceMm.width, cteuFaceMm.height),
      topLeft: const Radius.circular(2.5),
      bottomLeft: const Radius.circular(2.5),
    );
    canvas.drawRRect(body, Paint()..color = vtugManifoldColor);
    canvas.drawRRect(body, _outline);

    // The LED window. Two columns: the CTEU's own lamps on the left, the
    // EtherCAT ones on the right, which is how the face is laid out — the
    // node is one housing carrying two diagnostics.
    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4, 4, 44, 34),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(panel, Paint()..color = cteuLedPanelColor);

    const rows = 4;
    const colWidth = 22.0;
    const rowHeight = 8.0;
    for (var i = 0; i < leds.length; i++) {
      // An unnamed entry is a hole in the column — the CTEU's own side has
      // three lamps and the EtherCAT side four, so one cell is empty. It
      // has to stay empty: a lamp with no legend beside it is a lamp an
      // electrician goes looking for on the hardware and does not find.
      if (leds[i].label.isEmpty) continue;
      final column = i ~/ rows;
      final row = i % rows;
      final left = 4 + column * colWidth;
      final top = 4 + row * rowHeight + 1;
      _paintCteuLed(canvas, Offset(left + 3, top + 3), leds[i].state);
      _text(
        canvas,
        leds[i].label,
        Offset(left + 7, top - 0.5),
        fontSize: 3.4,
        color: Colors.white70,
        width: colWidth - 8,
        align: TextAlign.left,
      );
    }

    _text(
      canvas,
      'CTEU-EC',
      const Offset(4, 40),
      fontSize: 4.6,
      color: Colors.white,
      width: 44,
    );

    // Festo's blue stripe, under the model name where Festo prints it.
    canvas.drawRect(
      const Rect.fromLTWH(4, 46.5, 44, 1.6),
      Paint()..color = festoBlue,
    );

    // EtherCAT in and out, and the power inlet. Captioned, because three
    // identical M12 rings say nothing about which one is the bus.
    const sockets = [('X1', 12.0), ('X2', 26.0), ('PWR', 40.0)];
    for (final (label, cx) in sockets) {
      canvas.drawCircle(
        Offset(cx, 58),
        4.2,
        Paint()..color = const Color(0xFF2A2D2F),
      );
      canvas.drawCircle(Offset(cx, 58), 4.2, _outline);
      canvas.drawCircle(
        Offset(cx, 58),
        2.4,
        Paint()..color = const Color(0xFF17191A),
      );
      _text(
        canvas,
        label,
        Offset(cx - 7, 64.5),
        fontSize: 3.4,
        color: Colors.white70,
        width: 14,
      );
    }

    _text(
      canvas,
      'FESTO',
      const Offset(4, 70),
      fontSize: 4,
      color: festoBlue,
      width: 44,
    );
  }

  void _paintCteuLed(Canvas canvas, Offset centre, CteuLedState state) {
    // A flashing lamp is drawn as a ring rather than animated: this asset is
    // one of many on a mimic and eight blinking lamps a terminal is a page
    // that nobody can read. The ring says "flashing" and the pane says what
    // the flash means.
    final (fill, ring) = switch (state) {
      CteuLedState.off => (const Color(0xFF3A3D40), false),
      CteuLedState.green => (const Color(0xFF4CAF50), false),
      CteuLedState.greenFlashing => (const Color(0xFF4CAF50), true),
      CteuLedState.red => (const Color(0xFFE53935), false),
      CteuLedState.redFlashing => (const Color(0xFFE53935), true),
      CteuLedState.unknown => (const Color(0xFF55595C), false),
    };
    canvas.drawCircle(centre, 1.6, Paint()..color = fill);
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
  // Manifold
  // -------------------------------------------------------------------------

  void _paintManifold(Canvas canvas) {
    const top = _manifoldTopMm;
    final height = vtugFaceMm.height - top;
    final left = cteuFaceMm.width;
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
    canvas.drawRect(plate, Paint()..color = const Color(0xFF34373A));
    canvas.drawRect(plate, _outline);

    // Supply and exhaust: 1 in, 3 and 5 out, on QS-12 fittings — the fat
    // ones, which is why they are drawn fatter than the working ports.
    final labels = isLeft ? ['1', '3'] : ['', ''];
    for (var i = 0; i < 2; i++) {
      final centre = Offset(left + vtugEndPlateWidthMm / 2, top + 16 + i * 18);
      canvas.drawCircle(centre, 5.4, Paint()..color = const Color(0xFF26282A));
      canvas.drawCircle(centre, 5.4, _outline);
      canvas.drawCircle(centre, 3, Paint()..color = const Color(0xFF141617));
      if (labels[i].isNotEmpty) {
        // Beside the fitting, not above it: the two ports are 18 mm apart
        // and a caption above the lower one sat on the rim of the upper.
        _text(
          canvas,
          labels[i],
          Offset(centre.dx - 11, centre.dy - 2),
          fontSize: 3.6,
          color: Colors.white70,
          width: 5,
          align: TextAlign.right,
        );
      }
    }

    if (!isLeft && name.isNotEmpty) {
      canvas.save();
      canvas.translate(left + vtugEndPlateWidthMm - 3, top + height - 3);
      canvas.rotate(-math.pi / 2);
      _text(
        canvas,
        name,
        Offset.zero,
        fontSize: 4,
        color: Colors.white,
        width: height - 6,
        align: TextAlign.left,
      );
      canvas.restore();
    }
  }

  void _paintSlice(Canvas canvas, double left, double top, int position) {
    const w = vtugSliceWidthMm;
    final slice = slices[position - 1];
    final blank = slice.coils.isEmpty;

    // The valve sitting on the sub-base. A blanked position is a plate, and
    // Festo makes the plate the same anthracite as the manifold, so the eye
    // finds the gap in the row without reading a single number.
    final valve = Rect.fromLTWH(left + 0.6, top + 1.5, w - 1.2, 28);
    canvas.drawRect(
      valve,
      Paint()..color = blank ? const Color(0xFF313437) : vtugValveColor,
    );
    canvas.drawRect(valve, _outline);

    if (!blank) {
      // The coil lamps, at the top of the valve where the real ones are.
      // One coil sits centred; two straddle the centre line.
      final xs = slice.coils.length == 1
          ? [left + w / 2]
          : [left + w / 2 - 3, left + w / 2 + 3];
      for (var i = 0; i < slice.coils.length; i++) {
        final lit = slice.coils[i];
        final lamp = Rect.fromCenter(
          center: Offset(xs[i], top + 5.5),
          width: 3.4,
          height: 3.4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(lamp, const Radius.circular(0.7)),
          Paint()
            ..color = switch (lit) {
              null => const Color(0xFF8E9295),
              true => litColor,
              false => const Color(0xFFE8E8E4),
            },
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(lamp, const Radius.circular(0.7)),
          _outline,
        );
      }

      // The manual override buttons, below the lamps and in the same count —
      // one per coil, which is what makes the pane's push buttons a screen
      // version of something rather than an invention.
      for (var i = 0; i < slice.coils.length; i++) {
        canvas.drawCircle(
          Offset(xs[i], top + 24),
          1.5,
          Paint()..color = const Color(0xFF6E7376),
        );
      }
    }

    // Working ports 2 and 4, stacked on the front of the sub-base — QS-8,
    // so narrower than the supply fittings on the end plate.
    for (var i = 0; i < 2; i++) {
      final centre = Offset(left + w / 2, top + 38 + i * 13);
      canvas.drawCircle(centre, 3.6, Paint()..color = const Color(0xFF26282A));
      canvas.drawCircle(centre, 3.6, _outline);
      canvas.drawCircle(centre, 1.9, Paint()..color = const Color(0xFF141617));
    }

    if (slice.held) {
      canvas.drawRect(
        Rect.fromLTWH(left + 0.6, top + 30.5, w - 1.2, 1.6),
        Paint()..color = Colors.orange,
      );
    }

    _text(
      canvas,
      '$position',
      Offset(left, vtugFaceMm.height - 5),
      fontSize: 3.6,
      color: Colors.white70,
      width: w,
    );
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  Paint get _outline => Paint()
    ..color = Colors.black.withValues(alpha: 0.45)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.3;

  /// The "nothing is arriving" mark.
  ///
  /// Beside the bus node rather than the middle of the manifold, because
  /// that is what it is about: the valves are fine, the terminal is not
  /// talking. A small glyph lost among eight slices — which is where it
  /// started — read as a smudge on a valve.
  ///
  /// In the clear band above the end plate, not on the node's face. Centred
  /// on the node it sat across the L/A2 lamp and the model name, and a fault
  /// badge that hides a diagnostic lamp is a badge that costs more than it
  /// tells.
  void _paintDisconnected(Canvas canvas, Size design) {
    final centre = Offset(cteuFaceMm.width + 10, 8);
    canvas.drawCircle(centre, 7, Paint()..color = const Color(0xFF2A2C2E));
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
          // `DefaultTextStyle`, so a null family falls back to the test
          // font and every caption on this drawing golden-tests as a row of
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
    )..layout(maxWidth: width);
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
