/// The audit trail list item, tested the way an engineer reads it.
///
/// Every test pumps inside a `MaterialApp` built from `muted()` rather than a
/// bare one. `HmiStateColors.of` falls back to `solarizedLight` when the theme
/// carries no extension (`lib/theme.dart:134-138`), so a colour assertion made
/// under a bare `MaterialApp` would be an assertion about the wrong palette —
/// it would pass, and it would be checking nothing this build ships.
///
/// Colours are compared against `HmiStateColors.of(context)` read from the very
/// element under test, never against a hex literal. A hex literal here would
/// have to be re-typed the day `MutedColors.alarmRed` moves, and a test that has
/// to be edited when a token changes is a test that pins the token instead of
/// the rule.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/theme.dart' show HmiStateColors, muted;
import 'package:tfc/widgets/audit_trail_row.dart';
import 'package:tfc_dart/core/database_drift.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The moment every row in this file happened, so `formatTimestamp`'s output is
/// a constant a test can name rather than something the clock decides.
final DateTime _at = DateTime(2026, 8, 30, 14, 5, 9);

/// A 32-hex-character correlation id, the shape `newActionId()` produces.
const String _actionId = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// One audit row, with every column defaulted to the ordinary case so a test
/// names only the column it is about.
AuditEntryData _row({
  int id = 1,
  DateTime? at,
  String who = 'jon',
  String station = 'ST101',
  String roleName = 'engineer',
  String surface = 'tag',
  String itemKey = 'ST101.CN04.p_cfg',
  String? member,
  String? oldValue = '20',
  String? newValue = '35',
  String groupRequired = 'setpoints',
  bool allowed = true,
  String origin = 'operator',
  String actionId = _actionId,
  String? reason,
}) =>
    AuditEntryData(
      id: id,
      at: at ?? _at,
      who: who,
      station: station,
      roleName: roleName,
      surface: surface,
      itemKey: itemKey,
      member: member,
      oldValue: oldValue,
      newValue: newValue,
      groupRequired: groupRequired,
      allowed: allowed,
      origin: origin,
      actionId: actionId,
      reason: reason,
    );

/// Pumps [child] under the muted light theme at a width a 1080p panel would
/// give it, so an ellipsis in a test means the widget clipped rather than that
/// the 800px default test surface did.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: muted().$1,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 760, child: child),
        ),
      ),
    ),
  );
}

/// The state colours the widget under test would resolve, read from its own
/// element so the palette is the one that rendered.
HmiStateColors _colours(WidgetTester tester) =>
    HmiStateColors.of(tester.element(find.byType(AuditEntryLine).first));

/// Every colour the subtree under [root] actually paints.
///
/// Deliberately not `tester.allWidgets`: the `MaterialApp` and `Scaffold` above
/// the row carry the scheme's own error colour in places, and a walker that saw
/// them would report red on a row that paints none.
Iterable<Color> _coloursIn(WidgetTester tester, Finder root) sync* {
  final widgets = tester.widgetList(
    find.descendant(
      of: root,
      matching: find.byWidgetPredicate((_) => true),
      matchRoot: true,
    ),
  );
  for (final widget in widgets) {
    if (widget is ColoredBox) yield widget.color;
    if (widget is Icon && widget.color != null) yield widget.color!;
    if (widget is Text && widget.style?.color != null) {
      yield widget.style!.color!;
    }
    if (widget is Container) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        yield decoration.color!;
      }
    }
    if (widget is DecoratedBox) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        yield decoration.color!;
      }
    }
    if (widget is Material && widget.color != null) yield widget.color!;
    if (widget is Card && widget.color != null) yield widget.color!;
  }
}

/// Every string the rendered tree puts in front of a reader.
Iterable<String> _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? '')
    .where((data) => data.isNotEmpty);

void main() {
  // -------------------------------------------------------------------------
  // The collapsed line
  // -------------------------------------------------------------------------

  group('AuditEntryLine, the collapsed line', () {
    testWidgets('carries the timestamp, who, the role, the key and the '
        'transition — the line an engineer reads without opening anything',
        (tester) async {
      await _pump(tester, AuditEntryLine(row: _row()));

      expect(find.text('30-08-2026 14:05:09'), findsOneWidget);
      expect(find.textContaining('jon'), findsWidgets);
      expect(find.textContaining('engineer'), findsWidgets);
      expect(find.text('ST101.CN04.p_cfg'), findsOneWidget);
      expect(find.text('20 $kAuditTransitionArrow 35'), findsOneWidget);
    });

    testWidgets('renders the item key and its member as one string, so a '
        'struct member row is readable without the parent', (tester) async {
      await _pump(
        tester,
        AuditEntryLine(row: _row(itemKey: 'ST101.CN04', member: 'p_cfg.Freq')),
      );

      expect(find.text('ST101.CN04.p_cfg.Freq'), findsOneWidget);
    });

    testWidgets('renders an em dash for a null oldValue, and the word null '
        'appears nowhere in the tree', (tester) async {
      await _pump(tester, AuditEntryLine(row: _row(oldValue: null)));

      expect(
        find.text('$kAuditValueMissing $kAuditTransitionArrow 35'),
        findsOneWidget,
      );
      expect(
        _renderedText(tester).where((text) => text.contains('null')),
        isEmpty,
        reason: 'a literal null on screen is a value an operator will try to '
            'interpret; the trail has to be readable at a glance',
      );
    });

    testWidgets('renders an em dash for a null newValue too', (tester) async {
      await _pump(tester, AuditEntryLine(row: _row(newValue: null)));

      expect(
        find.text('20 $kAuditTransitionArrow $kAuditValueMissing'),
        findsOneWidget,
      );
      expect(
        _renderedText(tester).where((text) => text.contains('null')),
        isEmpty,
      );
    });
  });

  // -------------------------------------------------------------------------
  // The mark slot: red means refused, and nothing else is coloured
  // -------------------------------------------------------------------------

  group('AuditEntryLine, the allow/deny mark', () {
    testWidgets('a denied row carries a leading mark in HmiStateColors.red',
        (tester) async {
      await _pump(tester, AuditEntryLine(row: _row(allowed: false)));

      expect(find.byKey(kAuditDenialMarkKey), findsOneWidget);
      final mark = tester.widget<ColoredBox>(find.byKey(kAuditDenialMarkKey));
      expect(mark.color, _colours(tester).red);
    });

    testWidgets('an allowed row carries no colour at all', (tester) async {
      await _pump(tester, AuditEntryLine(row: _row()));

      expect(find.byKey(kAuditDenialMarkKey), findsNothing);
      expect(
        _coloursIn(tester, find.byType(AuditEntryLine)),
        isNot(contains(_colours(tester).red)),
        reason: 'only fault red may be saturated, and a fully coloured list '
            'stops distinguishing anything — a page of allowed writes must '
            'have exactly as much red in it as it has denials',
      );
    });

    testWidgets('an allowed row holds an equally sized placeholder, so the '
        'columns of an allowed and a denied row line up', (tester) async {
      await _pump(tester, AuditEntryLine(row: _row()));
      final allowedMark = tester.getSize(find.byKey(kAuditMarkPlaceholderKey));

      await _pump(tester, AuditEntryLine(row: _row(allowed: false)));
      final deniedMark = tester.getSize(find.byKey(kAuditDenialMarkKey));

      expect(allowedMark.width, deniedMark.width);
    });
  });

  // -------------------------------------------------------------------------
  // The open vocabulary
  // -------------------------------------------------------------------------

  group('AuditEntryLine, the open surface vocabulary', () {
    testWidgets(
        'a surface this build has never heard of renders the generic write '
        'shape', (tester) async {
      await _pump(
        tester,
        AuditEntryLine(
          row: _row(
            surface: 'admin',
            itemKey: 'role.update',
            groupRequired: 'users',
            oldValue: 'operate, users',
            newValue: 'operate',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('role.update'), findsOneWidget);
      expect(
        find.text('operate, users $kAuditTransitionArrow operate'),
        findsOneWidget,
        reason: "Phase 6's admin surface must need no change to this widget: "
            'the writer puts a human-readable summary in oldValue and '
            'newValue, and this widget renders whatever is there',
      );
      expect(
        find.descendant(
          of: find.byType(AuditEntryLine),
          matching: find.byType(Text),
        ),
        findsWidgets,
        reason: 'the rendered tree must not be empty; refusing to draw a row '
            'is how a page goes blank the day somebody upgrades one panel',
      );
    });

    testWidgets('an unknown surface is not treated as an auth row',
        (tester) async {
      await _pump(
        tester,
        AuditEntryLine(
          row: _row(surface: 'admin', itemKey: 'user.create'),
        ),
      );

      expect(find.textContaining(kAuditTransitionArrow), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Overflow
  // -------------------------------------------------------------------------

  group('AuditEntryLine, long strings', () {
    testWidgets('a long key and a long value ellipsise rather than change the '
        'height of the row', (tester) async {
      await _pump(tester, AuditEntryLine(row: _row()));
      final short = tester.getSize(find.byType(AuditEntryLine));

      await _pump(
        tester,
        AuditEntryLine(
          row: _row(
            itemKey: 'ST101.${'CN04.' * 40}p_cfg',
            oldValue: 'x' * 2000,
            newValue: 'y' * 2000,
          ),
        ),
      );
      final long = tester.getSize(find.byType(AuditEntryLine));

      expect(tester.takeException(), isNull);
      expect(long.height, short.height);
    });
  });

  // -------------------------------------------------------------------------
  // The colour convention, asserted on the source
  // -------------------------------------------------------------------------

  group('the colour convention', () {
    test('lib/widgets/audit_trail_row.dart names no raw Colors.* literal', () {
      final source =
          File('lib/widgets/audit_trail_row.dart').readAsStringSync();
      final offenders = RegExp(r'\bColors\.').allMatches(source);

      expect(
        offenders,
        isEmpty,
        reason: 'every colour comes from HmiStateColors, which is themed; '
            'lib/pages/key_repository.dart uses Colors.red directly and is a '
            'known violation that predates the convention',
      );
    });

    test('and it reaches for HmiStateColors.of instead', () {
      final source =
          File('lib/widgets/audit_trail_row.dart').readAsStringSync();

      expect(source, contains('HmiStateColors.of('));
    });
  });
}
