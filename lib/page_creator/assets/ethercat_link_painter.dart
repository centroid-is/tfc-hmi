/// Painting one EtherCAT cable.
///
/// The ink is deliberately plain: a run of cable is context for the equipment
/// around it, not the subject of the page, and a mimic full of cables drawn as
/// loudly as the machines would be unreadable. What the colour has to carry is
/// one question — is this cable a problem — and the answer has three useful
/// values, not two. See [LinkHealth].
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart' show HmiStateColors;
import 'link_geometry.dart';

/// What a cable is doing, in the terms the colour has to say it.
///
/// The middle value is the whole reason this is not a boolean. A marginal
/// cable — bent past its radius, a connector taking spray, a screen not
/// landed — carries traffic and reports its link UP while quietly retrying,
/// and a green/red lamp shows it as healthy right up to the day it drops the
/// line. [degraded] is what makes it visible before then.
enum LinkHealth {
  /// Link up, errors not accumulating.
  healthy,

  /// Link up, but errors above the configured rate. Working, and on its way
  /// out.
  degraded,

  /// No link.
  down,

  /// Nothing is subscribed — the asset has no key yet.
  idle,

  /// Subscribed, but the value could not be read or decoded.
  unknown,
}

/// The state colour for [health], from the page's scheme.
///
/// Follows the repo's vocabulary: green runs, red faults, violet means the
/// value could not be read, grey means nothing is watching. Yellow carries
/// [LinkHealth.degraded] — the one borrowed meaning, since a cable has no
/// manual mode for it to be confused with.
Color linkHealthColor(HmiStateColors states, LinkHealth health) =>
    switch (health) {
      LinkHealth.healthy => states.green,
      LinkHealth.degraded => states.yellow,
      LinkHealth.down => states.red,
      LinkHealth.idle => states.grey,
      LinkHealth.unknown => states.violet,
    };

/// Draws a resolved run, and answers taps against the cable rather than its
/// box.
class EtherCatLinkPainter extends CustomPainter {
  EtherCatLinkPainter({
    required this.link,
    required this.color,
    required this.strokeWidth,
    this.showCasing = true,
    this.selected = false,
  });

  /// The run, already resolved into the coordinates this painter draws in.
  final ResolvedLink link;
  final Color color;
  final double strokeWidth;

  /// The darker sheath under the conductor. Off for a very thin cable, where
  /// two strokes would just muddy each other.
  final bool showCasing;

  /// Editor selection. Drawn as a halo rather than a box, because the box is
  /// most of the page and outlining it says nothing about which cable is
  /// selected.
  final bool selected;

  /// Built once and kept: `AssetHitShape` asks for the tap shape roughly once
  /// a minute, and this runs on every frame the asset repaints on. The mark
  /// and [hitTest] have to be handed the same object or the ring the plant
  /// view draws stops being evidence of anything.
  ui.Path? _outline;

  /// The tappable shape, in this painter's coordinates.
  ///
  /// Wider than the ink. A cable painted six pixels across is not something a
  /// gloved finger finds on a panel, and the run is the thinnest thing on the
  /// page by a wide margin.
  ui.Path outline() => _outline ??= link.outline(width: hitWidth);

  double get hitWidth => strokeWidth < 18 ? 18 : strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = link.centreline;

    if (selected) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.28),
      );
    }

    if (showCasing) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF000000).withValues(alpha: 0.18),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  /// Taps land on the cable, not on the rectangle that contains it.
  ///
  /// A run from one corner of a page to the other has a bounding box covering
  /// most of it. The default `CustomPainter.hitTest` answers true for that
  /// whole box, which would put an invisible sheet over the equipment the
  /// cable runs past — the same defect a turned conveyor had, for the same
  /// reason.
  @override
  bool hitTest(Offset position) => link.distanceTo(position) <= hitWidth / 2;

  @override
  bool shouldRepaint(EtherCatLinkPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.selected != selected ||
      old.showCasing != showCasing ||
      !_samePoints(old.link.points, link.points) ||
      old.link.radius != link.radius;

  static bool _samePoints(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
