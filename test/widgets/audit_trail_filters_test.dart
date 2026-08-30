/// The audit trail filter bar, tested control by control.
///
/// Every test pumps inside a `MaterialApp` built from `muted()` rather than a
/// bare one, for the same reason `audit_trail_row_test.dart` does: a bare
/// `MaterialApp` carries no `HmiStateColors` extension and `HmiStateColors.of`
/// silently falls back to `solarizedLight`, so anything asserted about colour
/// under it is an assertion about a palette this build does not ship.
///
/// The parent owns the filter state, exactly as it does in production, so every
/// test drives a small stateful host that records what the bar emitted and
/// feeds the new value straight back in. Tapping a chip twice against a
/// stateless host would tap it twice against the *same* filters and could never
/// catch a toggle that only worked in one direction.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/audit_trail_store.dart';
import 'package:tfc/theme.dart' show muted;
import 'package:tfc/widgets/audit_trail_filters.dart';
import 'package:tfc_access/tfc_access.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// A stateful stand-in for the page: it holds one [AuditTrailFilters], hands it
/// to [builder], and records every value the widget under test emits before
/// feeding it back.
class _FilterHost extends StatefulWidget {
  const _FilterHost({
    required this.initial,
    required this.log,
    required this.builder,
  });

  final AuditTrailFilters initial;
  final List<AuditTrailFilters> log;
  final Widget Function(
    AuditTrailFilters filters,
    ValueChanged<AuditTrailFilters> onChanged,
  ) builder;

  @override
  State<_FilterHost> createState() => _FilterHostState();
}

class _FilterHostState extends State<_FilterHost> {
  late AuditTrailFilters _filters = widget.initial;

  @override
  Widget build(BuildContext context) => widget.builder(_filters, (next) {
        widget.log.add(next);
        setState(() => _filters = next);
      });
}

/// Pumps [builder] inside the muted theme at [width] logical pixels.
///
/// `Center` + `SizedBox` rather than a `SingleChildScrollView`: a scroll view
/// would give the bar unbounded height and quietly absorb the very overflow the
/// narrow-width test exists to catch.
Future<void> _pumpHost(
  WidgetTester tester, {
  AuditTrailFilters initial = const AuditTrailFilters(),
  required List<AuditTrailFilters> log,
  required Widget Function(
    AuditTrailFilters filters,
    ValueChanged<AuditTrailFilters> onChanged,
  ) builder,
  double width = 800,
}) async {
  final (light, _) = muted();
  await tester.pumpWidget(
    MaterialApp(
      theme: light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: _FilterHost(initial: initial, log: log, builder: builder),
          ),
        ),
      ),
    ),
  );
}

/// The labels of every [FilterChip] on screen, in render order.
List<String> _chipLabels(WidgetTester tester) => tester
    .widgetList<FilterChip>(find.byType(FilterChip))
    .map((chip) => (chip.label as Text).data!)
    .toList();

/// Whether the chip carrying [key] is currently selected.
bool _chipSelected(WidgetTester tester, Key key) =>
    tester.widget<FilterChip>(find.byKey(key)).selected;

void main() {
  // -------------------------------------------------------------------------
  // Task 1 — the group chips, the operate default, and the auth chip
  // -------------------------------------------------------------------------
  group('AuditGroupChips', () {
    testWidgets('renders one chip per AccessGroup in declaration order, '
        'then the auth chip', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      expect(
        _chipLabels(tester),
        [
          for (final group in AccessGroup.values) auditGroupChipLabel(group),
          kAuditTrailAuthChipLabel,
        ],
        reason: 'The chips are built from AccessGroup.values, never from a '
            'hand-typed list, so an eighth group arrives on screen rather '
            'than silently missing. The auth chip is the eighth because auth '
            'rows carry an empty group_required and a bare group filter would '
            'drop every sign-in.',
      );
    });

    testWidgets('under a fresh AuditTrailFilters, operate is the only '
        'deselected chip', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      expect(find.byType(FilterChip), findsNWidgets(AccessGroup.values.length + 1));

      final deselected = <String>[
        for (final group in AccessGroup.values)
          if (!_chipSelected(tester, auditGroupChipKey(group.name)))
            group.name,
        if (!_chipSelected(tester, kAuditTrailAuthChipKey)) 'auth',
      ];
      expect(
        deselected,
        [AccessGroup.operate.name],
        reason: 'The ROADMAP names exactly one default exclusion and no '
            'others. origin: system rows stay visible and denials-only is not '
            'the default.',
      );
    });

    testWidgets('the operate note renders', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      expect(find.text(kAuditTrailOperateNote), findsOneWidget);
    });

    testWidgets('the operate note still renders once operate is selected',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      await tester.tap(find.byKey(auditGroupChipKey(AccessGroup.operate.name)));
      await tester.pumpAndSettle();

      expect(
        find.text(kAuditTrailOperateNote),
        findsOneWidget,
        reason: 'The note explains the default. A note that disappears the '
            'moment you change the thing it explains cannot be read a second '
            'time.',
      );
    });

    testWidgets('tapping operate adds it, and tapping again removes it',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      await tester.tap(find.byKey(auditGroupChipKey(AccessGroup.operate.name)));
      await tester.pumpAndSettle();
      expect(log.last.groupNames, contains(AccessGroup.operate.name));

      await tester.tap(find.byKey(auditGroupChipKey(AccessGroup.operate.name)));
      await tester.pumpAndSettle();
      expect(log.last.groupNames, isNot(contains(AccessGroup.operate.name)));
      expect(log.last.groupNames, kAuditTrailDefaultGroupNames);
    });

    testWidgets('tapping Auth toggles includeAuth and changes nothing else',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      await tester.tap(find.byKey(kAuditTrailAuthChipKey));
      await tester.pumpAndSettle();

      expect(log.single.includeAuth, isFalse);
      expect(log.single.groupNames, kAuditTrailDefaultGroupNames);
      expect(log.single.keyPrefix, isEmpty);
      expect(log.single.who, isNull);
      expect(log.single.outcome, AuditOutcomeFilter.any);
      expect(log.single.range, isNull);
    });

    testWidgets('deselecting every chip is the no-constraint state, not the '
        'nothing state', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      for (final group in AccessGroup.values) {
        if (group == AccessGroup.operate) continue;
        await tester.tap(find.byKey(auditGroupChipKey(group.name)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(kAuditTrailAuthChipKey));
      await tester.pumpAndSettle();

      expect(
        log.last.groupNames,
        isEmpty,
        reason: 'CONTEXT: "empty selection = no constraint. Identical to '
            'AlarmLevelFilterChips." The store omits the group predicate '
            'entirely for that value, so every row matches. The widget must '
            'not block the state or helpfully re-select anything to prevent '
            'it.',
      );
      expect(log.last.includeAuth, isFalse);

      final stillDeselected = <FilterChip>[
        for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip)))
          if (!chip.selected) chip,
      ];
      expect(
        stillDeselected.length,
        AccessGroup.values.length + 1,
        reason: 'Nothing auto-restored.',
      );
    });

    testWidgets('the chips sit in a Wrap so a narrow bar folds them',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        width: 320,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      final wrap = find.descendant(
        of: find.byType(AuditGroupChips),
        matching: find.byType(Wrap),
      );
      expect(wrap, findsOneWidget);
      expect(
        tester.widget<Wrap>(wrap).children.length,
        AccessGroup.values.length + 1,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no chip carries a count', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditGroupChips(filters: filters, onChanged: onChanged),
      );

      for (final label in _chipLabels(tester)) {
        expect(
          label,
          isNot(matches(RegExp(r'\d'))),
          reason: 'All filtering is pushed into SQL, so a chip cannot say how '
              'many rows it would add without a second query per chip. A '
              'count of the loaded window would look authoritative and would '
              'not be.',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Task 2 — the search field, its debounce, the who dropdown, the outcome
  // -------------------------------------------------------------------------
  group('AuditPrefixField', () {
    testWidgets('six keystrokes inside the window emit one filter change '
        'carrying the final text', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditPrefixField(filters: filters, onChanged: onChanged),
      );

      for (final text in ['C', 'CN', 'CN0', 'CN04', 'CN04.', 'CN04.p']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        log,
        isEmpty,
        reason: 'Nothing is emitted while the operator is still typing: every '
            'emission here becomes a query over the whole audit_entry table.',
      );

      await tester.pump(kAuditTrailSearchDebounce);
      expect(log, hasLength(1));
      expect(log.single.keyPrefix, 'CN04.p');

      // No further pump is needed for correctness; this one would fail with a
      // pending-timer error if the debounce were periodic rather than one-shot.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a keystroke after the window emits a second change',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditPrefixField(filters: filters, onChanged: onChanged),
      );

      await tester.enterText(find.byType(TextField), 'CN');
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, hasLength(1));

      await tester.enterText(find.byType(TextField), 'CN04');
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, hasLength(2));
      expect(log.last.keyPrefix, 'CN04');
    });

    testWidgets('dispose cancels a pending debounce', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditPrefixField(filters: filters, onChanged: onChanged),
      );

      await tester.enterText(find.byType(TextField), 'CN');
      await tester.pump(const Duration(milliseconds: 50));

      final (light, _) = muted();
      await tester.pumpWidget(
        MaterialApp(theme: light, home: const Scaffold(body: SizedBox())),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        log,
        isEmpty,
        reason: 'A timer that outlives its widget fires into a dead element '
            'and, in this repo, has broken unrelated widget tests.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('leading and trailing whitespace is trimmed away',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditPrefixField(filters: filters, onChanged: onChanged),
      );

      await tester.enterText(find.byType(TextField), '  CN04  ');
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        log.single.keyPrefix,
        'CN04',
        reason: 'A stray space would otherwise become a LIKE " CN04%" that '
            'matches nothing, and would also flip isSearching, dropping the '
            'seven-day bound for a search that can never hit.',
      );
    });

    testWidgets('the hint names what the field searches', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditPrefixField(filters: filters, onChanged: onChanged),
      );

      expect(find.text(kAuditTrailPrefixHint), findsOneWidget);
    });
  });

  group('AuditWhoDropdown', () {
    testWidgets('the first entry is Anyone, bound to null', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) => AuditWhoDropdown(
          filters: filters,
          options: const ['ada', 'jon'],
          onChanged: onChanged,
        ),
      );

      await tester.tap(find.byKey(kAuditTrailWhoDropdownKey));
      await tester.pumpAndSettle();

      final items = tester
          .widget<DropdownButton<String?>>(find.byKey(kAuditTrailWhoDropdownKey))
          .items!;
      expect(items.first.value, isNull);
      expect((items.first.child as Text).data, kAuditTrailAnyoneLabel);
      expect(items.skip(1).map((item) => item.value), ['ada', 'jon']);
    });

    testWidgets('selecting Anyone clears who', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        initial: const AuditTrailFilters(who: 'jon'),
        log: log,
        builder: (filters, onChanged) => AuditWhoDropdown(
          filters: filters,
          options: const ['ada', 'jon'],
          onChanged: onChanged,
        ),
      );

      await tester.tap(find.byKey(kAuditTrailWhoDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAuditTrailAnyoneLabel).last);
      await tester.pumpAndSettle();

      expect(log.single.who, isNull);
    });

    testWidgets('the options are a parameter, so the bar pumps without a '
        'database or a provider', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) => AuditWhoDropdown(
          filters: filters,
          options: const ['ada', 'jon'],
          onChanged: onChanged,
        ),
      );

      // There is no ProviderScope anywhere above this widget: reading one would
      // have thrown before this line.
      await tester.tap(find.byKey(kAuditTrailWhoDropdownKey));
      await tester.pumpAndSettle();
      expect(find.text('ada'), findsOneWidget);
      expect(find.text('jon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a who absent from the options renders Anyone and does not '
        'throw', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        initial: const AuditTrailFilters(who: 'ghost'),
        log: log,
        builder: (filters, onChanged) => AuditWhoDropdown(
          filters: filters,
          options: const ['jon'],
          onChanged: onChanged,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(kAuditTrailAnyoneLabel),
        findsOneWidget,
        reason: 'The options come from SELECT DISTINCT who over the whole '
            'table, and a filter can outlive the row set that suggested it. '
            'DropdownButton asserts on a value with no matching item, so the '
            'fallback is the difference between a stale filter and a crash.',
      );
      expect(find.text('ghost'), findsNothing);
    });

    testWidgets('choosing a person sets who and changes nothing else',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) => AuditWhoDropdown(
          filters: filters,
          options: const ['ada', 'jon'],
          onChanged: onChanged,
        ),
      );

      await tester.tap(find.byKey(kAuditTrailWhoDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ada').last);
      await tester.pumpAndSettle();

      expect(log.single.who, 'ada');
      expect(log.single.keyPrefix, isEmpty);
      expect(log.single.groupNames, kAuditTrailDefaultGroupNames);
      expect(log.single.outcome, AuditOutcomeFilter.any);
    });
  });

  group('AuditOutcomeSegments', () {
    testWidgets('three labelled segments, no selected icon, any by default',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            AuditOutcomeSegments(filters: filters, onChanged: onChanged),
      );

      final button = tester.widget<SegmentedButton<AuditOutcomeFilter>>(
        find.byKey(kAuditTrailOutcomeKey),
      );
      expect(button.segments.map((segment) => segment.value),
          AuditOutcomeFilter.values);
      expect(button.showSelectedIcon, isFalse);
      expect(button.selected, {AuditOutcomeFilter.any});
      expect(find.text(kAuditTrailOutcomeAnyLabel), findsOneWidget);
      expect(find.text(kAuditTrailOutcomeAllowedLabel), findsOneWidget);
      expect(find.text(kAuditTrailOutcomeDeniedLabel), findsOneWidget);
    });

    testWidgets('selecting Denied emits deniedOnly and changes nothing else',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        initial: const AuditTrailFilters(
          keyPrefix: 'CN04',
          who: 'jon',
          groupNames: ['setpoints'],
        ),
        log: log,
        builder: (filters, onChanged) =>
            AuditOutcomeSegments(filters: filters, onChanged: onChanged),
      );

      await tester.tap(find.text(kAuditTrailOutcomeDeniedLabel));
      await tester.pumpAndSettle();

      expect(log.single.outcome, AuditOutcomeFilter.deniedOnly);
      expect(log.single.keyPrefix, 'CN04');
      expect(log.single.who, 'jon');
      expect(log.single.groupNames, ['setpoints']);
    });
  });

  // -------------------------------------------------------------------------
  // Task 3 — the date-range chip, Clear filters, and the assembled bar
  //
  // Nothing below opens `showSetDatePicker`. It is a third-party modal from
  // `board_datetime_picker`, already in the tree and reused rather than rebuilt;
  // driving it here would be a test of that package's rendering. The bar takes
  // the picker as an injected `AuditRangePicker` that defaults to it, so the
  // conversion from `DateTimeRange` to `AuditWindow` is exercised without the
  // modal ever being built.
  // -------------------------------------------------------------------------
  group('AuditTrailFilterBar', () {
    final start = DateTime(2026, 8, 1, 6);
    final end = DateTime(2026, 8, 30, 18, 30);
    final window = AuditWindow(start: start, end: end);

    Widget bar(
      AuditTrailFilters filters,
      ValueChanged<AuditTrailFilters> onChanged, {
      AuditRangePicker? pickRange,
      VoidCallback? onRefresh,
      String? resultSummary,
    }) =>
        AuditTrailFilterBar(
          filters: filters,
          whoOptions: const ['ada', 'jon'],
          onChanged: onChanged,
          pickRange: pickRange ?? (context, current) async => null,
          onRefresh: onRefresh,
          resultSummary: resultSummary,
        );

    testWidgets('mounts all five controls', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(tester, log: log, builder: bar);

      expect(find.byType(AuditPrefixField), findsOneWidget);
      expect(find.byType(AuditGroupChips), findsOneWidget);
      expect(find.byType(AuditOutcomeSegments), findsOneWidget);
      expect(find.byType(AuditWhoDropdown), findsOneWidget);
      expect(find.byKey(kAuditTrailRangeChipKey), findsOneWidget);
    });

    testWidgets('the range chip reads Last 7 days with a null range',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(tester, log: log, builder: bar);

      expect(find.text(kAuditTrailDefaultRangeLabel), findsOneWidget);
    });

    testWidgets('the range chip reads start → end with a range set',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        initial: AuditTrailFilters(range: window),
        log: log,
        builder: bar,
      );

      expect(find.text(auditRangeLabel(window)), findsOneWidget);
      expect(auditRangeLabel(window), contains('→'));
      expect(find.text(kAuditTrailDefaultRangeLabel), findsNothing);
    });

    testWidgets('a picked range becomes the emitted range, converted at this '
        'boundary', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) => bar(
          filters,
          onChanged,
          pickRange: (context, current) async =>
              DateTimeRange(start: start, end: end),
        ),
      );

      await tester.tap(find.byKey(kAuditTrailRangeChipKey));
      await tester.pumpAndSettle();

      expect(
        log.single.range,
        window,
        reason: 'lib/core/ holds no flutter import, so DateTimeRange stops '
            'here and AuditWindow goes on.',
      );
    });

    testWidgets('a cancelled picker changes nothing', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            bar(filters, onChanged, pickRange: (context, current) async => null),
      );

      await tester.tap(find.byKey(kAuditTrailRangeChipKey));
      await tester.pumpAndSettle();

      expect(log, isEmpty);
    });

    testWidgets('Clear range drops the range and leaves the prefix intact',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        initial: AuditTrailFilters(keyPrefix: 'CN04', range: window),
        log: log,
        builder: bar,
      );

      await tester.tap(find.byKey(kAuditTrailClearRangeKey));
      await tester.pumpAndSettle();

      expect(log.single.range, isNull);
      expect(
        log.single.keyPrefix,
        'CN04',
        reason: 'Returning to the seven-day default must not also throw away '
            'the search that the operator widened the window for.',
      );
    });

    testWidgets('Clear range is absent when there is no range', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(tester, log: log, builder: bar);

      expect(find.byKey(kAuditTrailClearRangeKey), findsNothing);
    });

    testWidgets('Clear filters emits exactly the state a freshly-opened page '
        'holds', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        initial: AuditTrailFilters(
          keyPrefix: 'CN04',
          who: 'jon',
          groupNames: const ['operate'],
          includeAuth: false,
          outcome: AuditOutcomeFilter.deniedOnly,
          range: window,
        ),
        log: log,
        builder: bar,
      );

      await tester.tap(find.byKey(kAuditTrailClearFiltersKey));
      await tester.pumpAndSettle();

      expect(
        log.first,
        const AuditTrailFilters(),
        reason: 'Cleared means the state a freshly-opened page holds, not an '
            'empty filter set: operate stays deselected, because the '
            "ROADMAP's default exclusion is a decision and not an accident of "
            'initialisation. A Clear that brought operate writes back would '
            'quietly disagree with the note two lines above it.',
      );
      expect(log.first.groupNames, isNot(contains(AccessGroup.operate.name)));
      expect(log.first.includeAuth, isTrue);
      expect(log.first.outcome, AuditOutcomeFilter.any);
      expect(log.first.range, isNull);
    });

    testWidgets('Clear filters also empties the search box', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: bar,
      );

      await tester.enterText(find.byType(TextField), 'CN04');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(kAuditTrailClearFiltersKey), findsOneWidget);

      await tester.tap(find.byKey(kAuditTrailClearFiltersKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: 'A box still showing a term that is no longer applied is a bar '
            'that lies about what the list below it holds.',
      );
    });

    testWidgets('Clear filters renders only when the filters are not default',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(tester, log: log, builder: bar);

      expect(
        find.byKey(kAuditTrailClearFiltersKey),
        findsNothing,
        reason: 'With the filters already default there is nothing for this '
            "control to undo, and 05-06's empty body renders its own Clear "
            'filters for that case — so exactly one such control is on screen '
            'in every state, and never two.',
      );

      await tester.pumpWidget(const SizedBox());
      await _pumpHost(
        tester,
        initial: const AuditTrailFilters(who: 'jon'),
        log: log,
        builder: bar,
      );
      expect(find.byKey(kAuditTrailClearFiltersKey), findsOneWidget);
    });

    testWidgets('the refresh affordance invokes its callback once per tap',
        (tester) async {
      final log = <AuditTrailFilters>[];
      var refreshes = 0;
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) =>
            bar(filters, onChanged, onRefresh: () => refreshes++),
      );

      await tester.tap(find.byKey(kAuditTrailRefreshKey));
      await tester.pumpAndSettle();
      expect(refreshes, 1);

      await tester.tap(find.byKey(kAuditTrailRefreshKey));
      await tester.pumpAndSettle();
      expect(
        refreshes,
        2,
        reason: 'CONTEXT: no timer on this page. It refreshes on open and on '
            'this control, so the control has to be the whole mechanism.',
      );
    });

    testWidgets('the result summary renders and names the window it counted '
        'over', (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(
        tester,
        log: log,
        builder: (filters, onChanged) => bar(
          filters,
          onChanged,
          resultSummary: auditTrailResultSummary(
            count: 42,
            filters: filters,
          ),
        ),
      );

      expect(find.byKey(kAuditTrailResultSummaryKey), findsOneWidget);
      expect(find.textContaining('42'), findsOneWidget);
      expect(
        find.textContaining(kAuditTrailDefaultRangeLabel),
        findsWidgets,
        reason: 'A number is never presented without the window that produced '
            'it.',
      );
    });

    testWidgets('at 320 logical pixels the bar folds rather than overflows',
        (tester) async {
      final log = <AuditTrailFilters>[];
      await _pumpHost(tester, log: log, width: 320, builder: bar);

      expect(tester.takeException(), isNull);
    });
  });

  group('auditTrailResultSummary', () {
    test('names the seven-day default when nothing was asked for', () {
      expect(
        auditTrailResultSummary(
            count: 3, filters: const AuditTrailFilters()),
        contains(kAuditTrailDefaultRangeLabel),
      );
    });

    test('names the whole table once a search escapes the window', () {
      expect(
        auditTrailResultSummary(
          count: 3,
          filters: const AuditTrailFilters(keyPrefix: 'CN04'),
        ),
        contains(kAuditTrailWholeTableLabel),
      );
    });

    test('names an explicit range when one is set', () {
      final window = AuditWindow(
        start: DateTime(2026, 8, 1, 6),
        end: DateTime(2026, 8, 30, 18, 30),
      );
      expect(
        auditTrailResultSummary(
          count: 1,
          filters: AuditTrailFilters(range: window),
        ),
        contains(auditRangeLabel(window)),
      );
    });

    test('counts one entry in the singular', () {
      expect(
        auditTrailResultSummary(count: 1, filters: const AuditTrailFilters()),
        startsWith('1 entry '),
      );
    });
  });

  group('the colour convention', () {
    test('the source names no raw palette colour', () {
      final source =
          File('lib/widgets/audit_trail_filters.dart').readAsStringSync();
      expect(
        RegExp(r'\bColors\.').hasMatch(source),
        isFalse,
        reason: 'Every colour comes from the theme — the ColorScheme or '
            'HmiStateColors — and never from the Material palette. The grep '
            'is literal, so the offending spelling must not appear anywhere '
            'in the file, comments included.',
      );
    });
  });

  group('the timer convention', () {
    test('nothing in the file is periodic', () {
      final source =
          File('lib/widgets/audit_trail_filters.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        code.contains('Timer.periodic'),
        isFalse,
        reason: 'CONTEXT: there is no timer on this page — it refreshes on '
            'open and on an explicit action. The one Timer here is a keystroke '
            'debounce, one-shot and cancelled in dispose. An always-on '
            'periodic timer in this repo has broken unrelated widget tests, '
            'and any future live-update work must be listener-gated instead: '
            'started in onListen, stopped in onCancel.',
      );
    });

    test('the debounce is cancelled on replacement and in dispose', () {
      final source =
          File('lib/widgets/audit_trail_filters.dart').readAsStringSync();
      expect(
        '_debounce?.cancel()'.allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason: 'One cancel replaces the previous timer so six keystrokes are '
            'one query; one in dispose so the last one dies with the widget.',
      );
    });
  });
}
