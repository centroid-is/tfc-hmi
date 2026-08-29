/// History has to include the alarms that have not ended yet.
///
/// [AlarmMan] only files an alarm into its history buffer when it deactivates,
/// so the History list showed everything except the thing the operator is
/// standing in front of. Asking "when did this start?" of a running alarm sent
/// them back to the Active list, which does not answer it either.
///
/// A standing alarm now appears in History with no deactivation time — the
/// row says "Still active" rather than leaving the line blank — and sorts
/// above the ended ones.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/alarm.dart';

import 'alarm_fixture.dart';

void main() {
  group('alarmHistoryEntries', () {
    test('a standing alarm is in the list with no deactivation time', () {
      final live = alarm('running', at: DateTime(2026, 8, 29, 8));

      final entries = alarmHistoryEntries(const [], [live]);

      expect(entries, hasLength(1));
      expect(entries.single.$1, same(live));
      expect(entries.single.$2, isNull,
          reason: 'it has not ended, so there is no time to show');
    });

    test('the standing alarms come first, then the ended ones', () {
      final oldLive = alarm('live-old', at: DateTime(2026, 8, 29, 6));
      final newLive = alarm('live-new', at: DateTime(2026, 8, 29, 9));
      final endedEarly = alarm('ended-early',
          at: DateTime(2026, 8, 29, 5), ended: DateTime(2026, 8, 29, 7));
      final endedLate = alarm('ended-late',
          at: DateTime(2026, 8, 29, 4), ended: DateTime(2026, 8, 29, 10));

      final entries = alarmHistoryEntries(
        [endedEarly, endedLate],
        [oldLive, newLive],
      );

      expect([for (final e in entries) e.$1.notification.uid],
          ['live-new', 'live-old', 'ended-late', 'ended-early'],
          reason: 'live newest-first, then ended newest-deactivation-first');
    });

    test('the buffer\'s empty slots are skipped', () {
      final ended = alarm('ended',
          at: DateTime(2026, 8, 29, 4), ended: DateTime(2026, 8, 29, 5));

      final entries = alarmHistoryEntries([null, ended, null], const []);

      expect(entries, hasLength(1));
      expect(entries.single.$1, same(ended));
    });

    test('an alarm in both streams is listed once, as the live one', () {
      // AlarmMan moves the same instance from the active set into the history
      // buffer, so for a frame after it clears both streams can carry it.
      final both = alarm('both', at: DateTime(2026, 8, 29, 8));

      final entries = alarmHistoryEntries([both], [both]);

      expect(entries, hasLength(1));
      expect(entries.single.$2, isNull);
    });

    test('an alarm that ran, cleared and came back is two entries', () {
      final first = alarm('boiler',
          at: DateTime(2026, 8, 29, 4), ended: DateTime(2026, 8, 29, 5));
      final again = alarm('boiler', at: DateTime(2026, 8, 29, 9));

      final entries = alarmHistoryEntries([first], [again]);

      expect(entries, hasLength(2), reason: 'two events, two rows');
    });
  });

  group('the History list', () {
    testWidgets('shows a standing alarm and says it has not ended',
        (tester) async {
      await pumpAlarmList(
        tester,
        AlarmFixture(
          active: {alarm('Freezer door', at: DateTime(2026, 8, 29, 8, 15))},
          past: [
            alarm('Line stopped',
                at: DateTime(2026, 8, 29, 6),
                ended: DateTime(2026, 8, 29, 6, 30)),
          ],
        ),
      );
      await showHistory(tester);

      expect(find.text('Freezer door'), findsOneWidget);
      expect(find.text('Still active'), findsOneWidget);
      expect(find.text('Activated: 29-08-2026 08:15:00'), findsOneWidget);
      expect(find.text('Deactivated: 29-08-2026 06:30:00'), findsOneWidget,
          reason: 'the ended alarm keeps its deactivation time');
    });

    testWidgets('the Active list is unchanged — no "Still active" row there',
        (tester) async {
      await pumpAlarmList(
        tester,
        AlarmFixture(
          active: {alarm('Freezer door', at: DateTime(2026, 8, 29, 8, 15))},
        ),
      );

      expect(find.text('Freezer door'), findsOneWidget);
      expect(find.text('Still active'), findsNothing,
          reason: 'everything in the Active list is active; saying so is '
              'noise');
    });
  });
}
