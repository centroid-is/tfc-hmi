import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/ethercat_link_painter.dart';
import 'package:tfc/page_creator/assets/link_geometry.dart';
import 'package:tfc/theme.dart' show HmiStateColors;

void main() {
  const canvas = Size(600, 400);
  const states = HmiStateColors.solarizedLight;

  EtherCatLinkPainter painterFor(LinkRun run, {double stroke = 5}) =>
      EtherCatLinkPainter(
        link: run.resolve(canvas, LinkAnchors.none),
        color: linkHealthColor(states, LinkHealth.healthy),
        strokeWidth: stroke,
      );

  /// A run corner to corner, whose bounding box is very nearly the whole page.
  LinkRun diagonal() => LinkRun(
        from: LinkEnd(x: 0.05, y: 0.05),
        to: LinkEnd(x: 0.95, y: 0.95),
      );

  group('hit testing', () {
    test('a tap on the cable lands', () {
      final p = painterFor(diagonal());
      expect(p.hitTest(const Offset(300, 200)), isTrue);
    });

    test('a tap in the empty corner of the box does not', () {
      // The whole point. A diagonal run's box covers most of the page, and the
      // default CustomPainter.hitTest would answer true for all of it -- an
      // invisible sheet over every device the cable runs past.
      final p = painterFor(diagonal());
      expect(p.hitTest(const Offset(560, 40)), isFalse);
      expect(p.hitTest(const Offset(40, 360)), isFalse);
    });

    test('a thin cable is still tappable off its ink', () {
      // 2px of ink is not a target on a panel touched with a glove. The hit
      // width has a floor independent of the stroke.
      final p = painterFor(diagonal(), stroke: 2);
      expect(p.hitWidth, greaterThanOrEqualTo(18));
      // ~7px off the centreline, well outside 2px of paint.
      expect(p.hitTest(const Offset(305, 195)), isTrue);
    });

    test('the target follows a bend rather than the straight line', () {
      final bent = LinkRun(
        from: LinkEnd(x: 0.05, y: 0.5),
        to: LinkEnd(x: 0.95, y: 0.5),
        waypoints: [LinkWaypoint.onRun(0.5, -0.35)],
      );
      final p = painterFor(bent);
      final corner = bent.resolve(canvas, LinkAnchors.none).points[1];
      expect(p.hitTest(corner), isTrue);
      // The chord between the two ends is not where the cable is.
      expect(p.hitTest(const Offset(300, 200)), isFalse);
    });
  });

  group('outline', () {
    test('is closed, so AssetHitShape finds a ring to trace', () {
      // AssetHitShape walks a path into closed rings and ignores anything with
      // fewer than three points; a bare centreline has none, and the plant
      // view would draw no mark at all.
      final outline = painterFor(diagonal()).outline();
      final metrics = outline.computeMetrics().toList();
      expect(metrics, isNotEmpty);
      expect(metrics.first.isClosed, isTrue);
    });

    test('is the same object on repeat calls', () {
      // The mark and the hit test have to be handed one shape or the ring
      // stops being evidence of where taps actually land -- and this is built
      // on every frame the asset repaints on.
      final p = painterFor(diagonal());
      expect(identical(p.outline(), p.outline()), isTrue);
    });
  });

  group('health colours', () {
    test('each state is distinct', () {
      final seen = {
        for (final h in LinkHealth.values) linkHealthColor(states, h)
      };
      expect(seen, hasLength(LinkHealth.values.length));
    });

    test('down is the fault red and idle is the idle grey', () {
      expect(linkHealthColor(states, LinkHealth.down), states.red);
      expect(linkHealthColor(states, LinkHealth.idle), states.grey);
      // Unreadable is violet by the repo's vocabulary, not red: "we cannot
      // tell" is a different thing from "it is broken".
      expect(linkHealthColor(states, LinkHealth.unknown), states.violet);
    });

    test('degraded is not the same as healthy', () {
      // The whole reason health is not a boolean: a marginal cable carries
      // traffic and reports its link up.
      expect(linkHealthColor(states, LinkHealth.degraded),
          isNot(linkHealthColor(states, LinkHealth.healthy)));
    });
  });

  group('repaint', () {
    test('does not repaint when nothing moved', () {
      final run = diagonal();
      final a = painterFor(run);
      final b = painterFor(run);
      expect(b.shouldRepaint(a), isFalse);
    });

    test('repaints when a corner moves', () {
      final a = painterFor(diagonal());
      final moved = diagonal()..waypoints.add(LinkWaypoint.onRun(0.5, 0.2));
      expect(painterFor(moved).shouldRepaint(a), isTrue);
    });

    test('repaints when the health colour changes', () {
      final run = diagonal();
      final a = painterFor(run);
      final b = EtherCatLinkPainter(
        link: run.resolve(canvas, LinkAnchors.none),
        color: linkHealthColor(states, LinkHealth.down),
        strokeWidth: 5,
      );
      expect(b.shouldRepaint(a), isTrue);
    });
  });
}
