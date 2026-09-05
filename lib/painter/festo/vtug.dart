/// Festo VTUG-14 valve terminal with a CTEU-EC bus node — the assembly
/// bolted to the track stations, drawn from above.
///
/// ## Why the top view
///
/// Because that is where the lamps are. Every LED this asset exists to show
/// — the coil lamps on each valve and the status column on the bus node —
/// sits on the upper face of the hardware. An elevation shows the row of
/// valves end-on with their lamps hidden behind the moulding, which is a
/// drawing of the right object answering the wrong question.
///
/// ## Where the geometry comes from
///
/// Every dimension below is off the Festo catalogue's dimension drawing for
/// a size-14 VABM manifold rail with an I-Port interface, cross-checked
/// against the individual part datasheets. It is not estimated:
///
/// | | |
/// |---|---|
/// | Terminal, 8 positions | 192 x 110 mm (L1 x B1) |
/// | Valve grid | **16 mm** (L4) |
/// | Valve body | 14.7 mm wide (VUVG-B14 B1) |
/// | Electrical section | 60.6 mm (L5) |
/// | Span, first to last valve centre | 112 mm (L3) |
/// | CTEU-EC | 40 x 91 x 50 mm |
///
/// Two of those corrected a drawing built from guesswork. The grid is
/// **16 mm and not 14** — 14 is the *valve size*, the VUVG-B14 designation,
/// and a size-14 manifold rail carries it on a 16 mm pitch. And the bus node
/// is a little over half the height of the valve block rather than taller
/// than it, which is the proportion that made the first drawing read wrong
/// to anyone who has stood in front of one.
///
/// ## What is drawn, and what is honest about being approximate
///
/// The outer envelope, the grid, the electrical section's width and the
/// node's footprint are exact. The arrangement of features *within* a valve
/// strip — where on the top face the coil lamps and the manual overrides
/// sit — is not dimensioned anywhere I can reach, so it is drawn where the
/// hardware photographs put it: at the solenoid end, under the `14` and `12`
/// moulded into the body. A blanked position has no solenoid cap, no lamps
/// and no overrides, because it has no valve.
///
/// One thing the photographs do *not* license: the dark solenoid housing on
/// a VUVG is dark on the valve's **side**, and a top view never sees it.
/// Nothing here is filled black. The only saturated colour on the drawing is
/// the blue of the manual overrides, which is the only saturated colour on
/// the hardware.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Valve positions on the manifold — see `vtugPositionCount`.
const int vtugSliceCount = 8;

/// The manifold rail's grid, in mm — catalogue dimension `L4` for a size-14
/// VABM.
///
/// Not 14. `VTUG-14` and `VUVG-B14` name the *valve size*; the rail that
/// carries them is on a 16 mm pitch, and the 1.3 mm of daylight between one
/// 14.7 mm valve body and the next is visible on the hardware.
const double vtugGridMm = 16;

/// The valve body itself — catalogue dimension `B1` for a `VUVG-B14`.
const double vtugValveBodyMm = 14.7;

/// The bus node's footprint in mm, from the CTEU-EC datasheet: 40 mm across
/// the row by 91 mm deep.
const Size cteuFaceMm = Size(40, 91);

/// The whole electrical end — node, interface and supply plate — catalogue
/// dimension `L5`.
const double vtugElectricalWidthMm = 60.6;

/// What is left past the last valve, so the parts sum to [vtugFaceMm].
const double vtugRightEndMm = 3.4;

/// The assembly seen from above, in mm: catalogue `L1` x `B1` for eight
/// positions.
const Size vtugFaceMm = Size(192, 110);

/// Depth at which the body starts and ends, leaving room for the H-rail
/// mounting feet.
const double _bodyTop = 5;
const double _bodyBottom = 96;

/// Festo's pale grey-white — the VUVG bodies, the VAEM plate and the CTEU
/// housing are all this colour.
const Color festoWhite = Color(0xFFECECEA);

/// A half-tone of it for the manifold rail the valves stand on.
const Color vtugManifoldColor = Color(0xFFDBDCDA);

/// Festo's blue. On the hardware it is the logo and the manual override
/// caps, and it is used for exactly those two things here.
const Color festoBlue = Color(0xFF0091DC);

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

/// One valve position as the drawing needs it.
///
/// [coils] is empty for a blanked position, one long for a monostable and
/// two for a 5/2 bistable or a 5/3, in coil 14 then coil 12 order. `null` is
/// a coil the terminal has said nothing about.
@immutable
class VtugSliceView {
  const VtugSliceView({required this.coils, this.held = false});

  final List<bool?> coils;

  /// True when an operator is holding this position by hand. Drawn as an
  /// orange bar down the slice — forced is orange everywhere in this repo,
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

  /// Position 1 first, which is the position nearest the bus node.
  final List<VtugSliceView> slices;

  /// The bus node's lamps, in the order they are silkscreened down its face.
  final List<CteuLed> leds;

  /// What an energised coil is drawn in. Passed rather than baked so the
  /// lamps take the theme's yellow — the same yellow the conveyors use for
  /// commanded state — instead of a raw colour the theme cannot reach.
  final Color litColor;

  /// The plant's tag for the terminal.
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

    _paintRail(canvas);
    _paintBusNode(canvas);
    _paintInterface(canvas);
    for (var i = 0; i < slices.length; i++) {
      _paintSlice(canvas, vtugElectricalWidthMm + i * vtugGridMm, i + 1);
    }
    _paintEndMarkings(canvas);
    if (disconnected) _paintDisconnected(canvas);

    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Rail and feet
  // -------------------------------------------------------------------------

  void _paintRail(Canvas canvas) {
    // The H-rail mounting feet, at each end and under the body.
    for (final x in [12.0, vtugFaceMm.width - 22]) {
      final foot = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, _bodyBottom - 2, 10, 12),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(foot, Paint()..color = vtugManifoldColor);
      canvas.drawRRect(foot, _outline);
    }

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, _bodyTop, vtugFaceMm.width, _bodyBottom - _bodyTop),
      const Radius.circular(1.2),
    );
    canvas.drawRRect(body, Paint()..color = vtugManifoldColor);
    canvas.drawRRect(body, _outline);
  }

  // -------------------------------------------------------------------------
  // Bus node
  // -------------------------------------------------------------------------

  void _paintBusNode(Canvas canvas) {
    // 40 x 91, sat 5 mm in from the left end — the catalogue's L7.
    final rect = Rect.fromLTWH(5, _bodyTop + 3, cteuFaceMm.width, 87);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      Paint()..color = festoWhite,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      _outline,
    );

    _screw(canvas, Offset(rect.right - 4, rect.top + 4));
    _screw(canvas, Offset(rect.right - 4, rect.bottom - 4));

    // The lamp column down the left, labels outboard of the dots, exactly as
    // the housing is silkscreened. No panel behind them — the real ones are
    // bare lenses in the white moulding.
    const top = 15.0;
    const pitch = 6.4;
    for (var i = 0; i < leds.length; i++) {
      final y = top + i * pitch;
      _text(
        canvas,
        leds[i].label,
        Offset(rect.left + 0.5, y - 1.5),
        fontSize: 3,
        color: const Color(0xFF55585A),
        width: 9.5,
        align: TextAlign.right,
      );
      _paintCteuLed(canvas, Offset(rect.left + 12.5, y), leds[i].state);
    }

    // Three M12s, not one: the power inlet and both ends of the bus.
    //
    // `In 1` and `Out 2` are what `L/A1` and `L/A2` in the lamp column
    // report on, so drawing a single connector left two of the six lamps
    // with nothing on the housing to belong to. Power is the male one —
    // pins, not sockets — which is how you tell it from the bus pair
    // without reading the moulding, and so it is drawn that way here.
    const sockets = [
      ('PWR', 16.0, true),
      ('In 1', 31.0, false),
      ('Out 2', 46.0, false),
    ];
    for (final (label, y, male) in sockets) {
      _text(
        canvas,
        label,
        Offset(rect.left + 15, y - 1.4),
        fontSize: 2.8,
        color: const Color(0xFF55585A),
        // The node's 40 mm is four columns: lamp legends, lamps, these
        // legends, connectors. Narrower than 12 and 'Out 2' ellipsises,
        // which on a two-port bus node is the one legend that has to read.
        width: 12,
        align: TextAlign.right,
      );
      _connector(canvas, Offset(rect.left + 33, y), male: male);
    }

    final window = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left + 5, 57, 30, 27),
      const Radius.circular(0.8),
    );
    canvas.drawRRect(window, Paint()..color = const Color(0xFFF7F7F5));
    canvas.drawRRect(window, _outline);
    _text(
      canvas,
      'CTEU-EC',
      Offset(rect.left + 5, 65),
      fontSize: 4,
      color: const Color(0xFF44474A),
      width: 30,
    );
    _text(
      canvas,
      'FESTO',
      Offset(rect.left + 5, 73),
      fontSize: 3.4,
      color: festoBlue,
      width: 30,
    );
  }

  void _paintCteuLed(Canvas canvas, Offset centre, CteuLedState state) {
    // A flashing lamp is drawn as a ring rather than animated: this asset is
    // one of many on a mimic, and six blinking lamps a terminal is a page
    // nobody can read. The ring says "flashing" and the pane says what the
    // flash means.
    final (fill, ring) = switch (state) {
      CteuLedState.off => (const Color(0xFFCFD0CD), false),
      CteuLedState.green => (const Color(0xFF43A047), false),
      CteuLedState.greenFlashing => (const Color(0xFF43A047), true),
      CteuLedState.red => (const Color(0xFFE53935), false),
      CteuLedState.redFlashing => (const Color(0xFFE53935), true),
      CteuLedState.unknown => (const Color(0xFFA8ABAD), false),
    };
    canvas.drawCircle(centre, 1.4, Paint()..color = fill);
    canvas.drawCircle(centre, 1.4, _outline);
    if (ring) {
      canvas.drawCircle(
        centre,
        2.4,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4,
      );
    }
  }

  /// An M12. Male shows pins — the power inlet — female the socket bore,
  /// which is both EtherCAT ports.
  void _connector(Canvas canvas, Offset centre, {required bool male}) {
    canvas.drawCircle(centre, 4.6, Paint()..color = const Color(0xFFC3C6C8));
    canvas.drawCircle(centre, 4.6, _outline);
    canvas.drawCircle(centre, 3.1, Paint()..color = const Color(0xFF44484A));
    if (male) {
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + math.pi / 4;
        canvas.drawCircle(
          centre + Offset(math.cos(a), math.sin(a)) * 1.6,
          0.5,
          Paint()..color = const Color(0xFFDDDEDB),
        );
      }
    } else {
      canvas.drawCircle(centre, 1.5, Paint()..color = const Color(0xFF17191A));
    }
  }

  // -------------------------------------------------------------------------
  // Electrical interface
  // -------------------------------------------------------------------------

  /// `VAEM-L1-S-8-PT` and the supply plate — the strip between the node and
  /// the first valve. On the hardware it is a field of small contacts and
  /// two rows of fixings, and at this scale that is what it reads as.
  void _paintInterface(Canvas canvas) {
    final left = 5 + cteuFaceMm.width;
    final rect = Rect.fromLTWH(
      left,
      _bodyTop + 3,
      vtugElectricalWidthMm - left,
      87,
    );
    canvas.drawRect(rect, Paint()..color = festoWhite);
    canvas.drawRect(rect, _outline);

    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawCircle(
          Offset(rect.left + 4.5 + col * 6, 22 + row * 11),
          2,
          Paint()..color = const Color(0xFFCACCCE),
        );
        canvas.drawCircle(
          Offset(rect.left + 4.5 + col * 6, 22 + row * 11),
          2,
          _outline,
        );
      }
    }
    _text(
      canvas,
      'VAEM',
      Offset(rect.left, rect.bottom - 5),
      fontSize: 2.8,
      color: const Color(0xFF6E7274),
      width: rect.width,
    );
  }

  // -------------------------------------------------------------------------
  // Valve positions
  // -------------------------------------------------------------------------

  void _paintSlice(Canvas canvas, double gridLeft, int position) {
    final slice = slices[position - 1];
    final blank = slice.coils.isEmpty;
    final coils = slice.coils.length;

    // The body is narrower than the grid — 14.7 in 16 — and the daylight
    // between one valve and the next is on the hardware, not a drawing
    // convention.
    final left = gridLeft + (vtugGridMm - vtugValveBodyMm) / 2;
    const w = vtugValveBodyMm;
    final body = Rect.fromLTWH(left, _bodyTop + 3, w, 87);
    canvas.drawRect(body, Paint()..color = festoWhite);
    canvas.drawRect(body, _outline);

    if (!blank) {
      // The ribbed cap over the pilot solenoids, at the far end of the
      // valve. One coil takes a little over half of it, two take the lot —
      // a second, redundant read on how many coils a position has, before
      // anyone counts lamps.
      //
      // Ribs on white, not a filled block. The solenoid housing on a VUVG
      // genuinely is dark, and an earlier pass drew it that way — but it is
      // dark on the valve's *side*, which a top view never sees. Fill it in
      // from above and you get a black rectangle that is on no face of the
      // hardware, sized differently per position for a reason the drawing
      // never explains. The catalogue's own top view draws this as hatching
      // in outline, and it is right to.
      final capW = coils == 1 ? w * 0.56 : w;
      final cap = Rect.fromLTWH(left, _bodyTop + 3, capW, 9);
      canvas.drawRect(cap, Paint()..color = const Color(0xFFDFE0DD));
      canvas.drawRect(cap, _outline);
      final ribs = Paint()
        ..color = const Color(0xFF9DA0A2)
        ..strokeWidth = 0.45;
      for (var i = 1; i < 6; i++) {
        final x = cap.left + cap.width * i / 6;
        canvas.drawLine(
          Offset(x, cap.top + 1.2),
          Offset(x, cap.bottom - 1.2),
          ribs,
        );
      }

      // The coil lamps and, under them, the blue manual overrides. Not
      // dimensioned anywhere reachable; drawn at the solenoid end, under
      // the 14 and 12 moulded into the body, which is where the hardware
      // photographs put them.
      final xs = coils == 1
          ? [left + w / 2]
          : [left + w * 0.3, left + w * 0.7];
      const labels = ['14', '12'];
      for (var i = 0; i < coils; i++) {
        // Below the ribbed cap, not on it: the cap runs to y=17 and this
        // was landing inside it.
        _text(
          canvas,
          labels[i],
          Offset(xs[i] - 2.5, 17.8),
          fontSize: 2.6,
          color: const Color(0xFF6E7274),
          width: 5,
        );
        final lamp = Rect.fromCenter(
          center: Offset(xs[i], 23.6),
          width: 3.4,
          height: 3.4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(lamp, const Radius.circular(0.6)),
          Paint()
            ..color = switch (slice.coils[i]) {
              null => const Color(0xFFA8ABAD),
              true => litColor,
              false => const Color(0xFFF8F8F4),
            },
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(lamp, const Radius.circular(0.6)),
          _outline,
        );

        canvas.drawCircle(
            Offset(xs[i], 29.5), 1.3, Paint()..color = festoBlue);
        canvas.drawCircle(Offset(xs[i], 29.5), 1.3, _outline);
      }
    } else {
      _text(
        canvas,
        'BLANK',
        Offset(left, 22),
        fontSize: 2.4,
        color: const Color(0xFF9DA0A2),
        width: w,
      );
    }

    // Working ports 4 and 2 on QS push-in fittings, then the mounting screw
    // at each end of the body — the arrangement the catalogue's top view
    // shows for every position, blank ones included.
    _fitting(canvas, Offset(left + w / 2, 40), radius: 4.4);
    _text(canvas, '4', Offset(left + 0.4, 38.5), fontSize: 2.6,
        color: const Color(0xFF6E7274), width: 3, align: TextAlign.right);
    _fitting(canvas, Offset(left + w / 2, 55), radius: 4.4);
    _text(canvas, '2', Offset(left + 0.4, 53.5), fontSize: 2.6,
        color: const Color(0xFF6E7274), width: 3, align: TextAlign.right);

    _screw(canvas, Offset(left + w / 2, 66));
    _screw(canvas, Offset(left + w / 2, 88));

    if (slice.held) {
      canvas.drawRect(
        Rect.fromLTWH(left, 70, w, 2),
        Paint()..color = Colors.orange,
      );
    }

    _text(
      canvas,
      '$position',
      Offset(gridLeft, 78),
      fontSize: 4,
      color: const Color(0xFF55585A),
      width: vtugGridMm,
    );
  }

  /// A QS push-in fitting: the collet ring with the tube bore in the middle.
  void _fitting(Canvas canvas, Offset centre, {required double radius}) {
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFFE3E4E1));
    canvas.drawCircle(centre, radius, _outline);
    canvas.drawCircle(
        centre, radius * 0.66, Paint()..color = const Color(0xFFC0C3C5));
    canvas.drawCircle(
        centre, radius * 0.34, Paint()..color = const Color(0xFF54585A));
  }

  void _screw(Canvas canvas, Offset centre) {
    canvas.drawCircle(centre, 2, Paint()..color = const Color(0xFFD4D6D3));
    canvas.drawCircle(centre, 2, _outline);
    canvas.drawLine(
      centre - const Offset(1.3, 0),
      centre + const Offset(1.3, 0),
      Paint()
        ..color = const Color(0xFF83878A)
        ..strokeWidth = 0.5,
    );
  }

  /// The terminal's tag.
  ///
  /// The end plates also carry the supply and pilot port markings — `14`,
  /// `84`, `5`, `1`, `3` down each outer edge — and this deliberately does
  /// not draw them. On the hardware they are read with the terminal in front
  /// of you and a spanner in your hand; on a mimic at this scale they are
  /// five characters of noise down both sides of the outermost box, and they
  /// answer a question nobody asks a screen.
  ///
  /// The port numbers that *do* earn their place are the ones on each valve
  /// position, because those are the ports the pane's controls act on.
  void _paintEndMarkings(Canvas canvas) {
    if (name.isNotEmpty) {
      _text(
        canvas,
        name,
        const Offset(5, _bodyBottom - 6),
        fontSize: 4,
        color: const Color(0xFF44474A),
        width: cteuFaceMm.width,
        align: TextAlign.left,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  Paint get _outline => Paint()
    ..color = const Color(0xFF8A8E90)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.3;

  /// The "nothing is arriving" mark.
  ///
  /// Over the bus node's corner, because that is what it is about: the
  /// valves are fine, the terminal is not talking. Clear of the lamp column,
  /// because a fault badge that hides a diagnostic lamp costs more than it
  /// tells.
  void _paintDisconnected(Canvas canvas) {
    const centre = Offset(38, 8);
    canvas.drawCircle(centre, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      centre,
      6,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );
    _text(
      canvas,
      '!',
      centre - const Offset(4.5, 4.5),
      fontSize: 9,
      color: Colors.red,
      width: 9,
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
          // and every caption golden-tests as a row of boxes.
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
