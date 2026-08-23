import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/alarm_view.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

AlarmActive active(String uid, AlarmLevel level, DateTime at) {
  final rule = AlarmRule(
    level: level,
    expression: ExpressionConfig(value: Expression(formula: 'x')),
    acknowledgeRequired: false,
  );
  return AlarmActive(
    alarm: Alarm(
      config: AlarmConfig(
          uid: uid, title: uid, description: '', rules: [rule]),
    ),
    notification: AlarmNotification(
      uid: uid,
      active: true,
      expression: 'x',
      rule: rule,
      timestamp: at,
    ),
  );
}

void main() {
  group('mostCriticalAlarm', () {
    test('nothing active, nothing chosen', () {
      expect(mostCriticalAlarm([]), isNull);
    });

    test('the highest level wins regardless of list order', () {
      final t = DateTime(2026, 8, 23, 12);
      final picked = mostCriticalAlarm([
        active('info-new', AlarmLevel.info, t.add(const Duration(hours: 1))),
        active('warn', AlarmLevel.warning, t),
        active('err-old', AlarmLevel.error, t.subtract(const Duration(days: 1))),
      ]);
      expect(picked!.notification.uid, 'err-old',
          reason: 'an error beats a newer warning or info');
    });

    test('within a level the newest wins', () {
      final t = DateTime(2026, 8, 23, 12);
      final picked = mostCriticalAlarm([
        active('err-old', AlarmLevel.error, t),
        active('err-new', AlarmLevel.error, t.add(const Duration(minutes: 5))),
      ]);
      expect(picked!.notification.uid, 'err-new');
    });
  });
}
