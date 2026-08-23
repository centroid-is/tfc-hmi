/// The retention field in the key-mapping editor.
///
/// This is the control whose only job is to delete data, and it used to be a
/// bare [TextField]: `keyboardType: TextInputType.number` and nothing else. No
/// input formatter, no clamp, no objection to 0 or to a negative number.
///
/// Two values did real damage:
///
///   * 3651 — one day past ten years — was stored as 5_257_440 minutes, which
///     was one minute-count past the tolerant converter's cutoff and came back
///     as 5.25744 *seconds*. Timescale was then told to drop every chunk older
///     than five seconds. It read back in this field as 0 days, which looks
///     plausible, so nothing about the UI said anything was wrong.
///   * 0 — a retention that drops everything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/key_mapping_sections.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';

void main() {
  /// Pumps the section and returns a sink for whatever it reports.
  Future<List<CollectEntry>> pump(WidgetTester tester,
      {int? initialDays}) async {
    final changes = <CollectEntry>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CollectionConfigSection(
            enabled: true,
            keyName: 'cn01.motor.speed',
            collect: CollectEntry(
              key: 'cn01.motor.speed',
              retention: RetentionPolicy(
                  dropAfter: Duration(days: initialDays ?? 365)),
            ),
            onToggle: (_) {},
            onChanged: changes.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changes;
  }

  Finder retentionField() => find.ancestor(
        of: find.text('Retention (days)'),
        matching: find.byType(TextField),
      );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(retentionField(), text);
    await tester.pumpAndSettle();
  }

  group('what the field will let an operator produce', () {
    testWidgets('a minus sign cannot be typed at all', (tester) async {
      final changes = await pump(tester);
      await type(tester, '-5');
      // digitsOnly strips the sign as it is typed.
      expect(tester.widget<TextField>(retentionField()).controller!.text, '5');
      expect(changes.last.retention.dropAfter, const Duration(days: 5));
    });

    testWidgets('0 is not accepted as a retention', (tester) async {
      final changes = await pump(tester);
      await type(tester, '0');
      expect(changes.last.retention.dropAfter,
          greaterThanOrEqualTo(const Duration(days: 1)),
          reason: 'A dropAfter of zero tells Timescale to drop every chunk.');
      expect(find.textContaining('at least 1 day'), findsOneWidget,
          reason: 'And the operator has to be told, not silently corrected.');
    });

    testWidgets('one day past the maximum is clamped, not reinterpreted',
        (tester) async {
      final changes = await pump(tester);
      await type(tester, '3651');
      expect(changes.last.retention.dropAfter,
          const Duration(days: kMaxRetentionDays));
      expect(find.textContaining('Maximum retention'), findsOneWidget);
    });

    testWidgets('a value far past the maximum is clamped too', (tester) async {
      final changes = await pump(tester);
      await type(tester, '4000');
      expect(changes.last.retention.dropAfter,
          const Duration(days: kMaxRetentionDays));
    });

    testWidgets('the maximum itself is accepted without complaint',
        (tester) async {
      final changes = await pump(tester);
      await type(tester, '3650');
      expect(changes.last.retention.dropAfter,
          const Duration(days: kMaxRetentionDays));
      expect(find.textContaining('Maximum retention'), findsNothing);
    });

    testWidgets('an ordinary value is passed through untouched',
        (tester) async {
      final changes = await pump(tester);
      await type(tester, '90');
      expect(changes.last.retention.dropAfter, const Duration(days: 90));
      expect(find.textContaining('Maximum retention'), findsNothing);
      expect(find.textContaining('at least 1 day'), findsNothing);
    });
  });

  group('what the field says for itself', () {
    testWidgets('the supported range is stated before anything is typed',
        (tester) async {
      await pump(tester);
      expect(find.text('1 to $kMaxRetentionDays days'), findsOneWidget,
          reason: 'A limit an operator only discovers by exceeding it is not a '
              'limit, it is a trap.');
    });
  });

  group('the round trip that caused the damage', () {
    testWidgets('what the field produces survives being saved and reloaded',
        (tester) async {
      final changes = await pump(tester);
      await type(tester, '3651');
      final produced = changes.last.retention;

      // Exactly what a config file does between two runs of the application.
      final reloaded = RetentionPolicy.fromJson(produced.toJson());

      expect(reloaded.dropAfter, produced.dropAfter,
          reason: 'This is the whole defect in one line: the value the UI '
              'produced came back as something else entirely.');
      expect(reloaded.dropAfter.inDays, kMaxRetentionDays);
      expect(reloaded.isUsable, isTrue);
    });

    testWidgets('every day count the field permits survives the round trip',
        (tester) async {
      final changes = await pump(tester);
      for (final days in ['1', '30', '365', '3649', '3650', '3651', '9999']) {
        await type(tester, days);
        final produced = changes.last.retention;
        final reloaded = RetentionPolicy.fromJson(produced.toJson());
        expect(reloaded.dropAfter, produced.dropAfter,
            reason: 'Typing $days did not survive the round trip.');
        expect(reloaded.isUsable, isTrue,
            reason: 'Typing $days produced a policy that deletes history.');
      }
    });
  });
}
