/// `countsAsStop` on [AlarmConfig]: every alarm is downtime unless the
/// definition says otherwise. The default matters most on the wire — every
/// `alarm_man_config` JSON written before the field existed has no key, and
/// each of those alarms must keep counting as a stop.
library;

import 'dart:convert';

import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:test/test.dart';

AlarmConfig config({bool? countsAsStop}) => AlarmConfig(
      uid: 'u1',
      title: 'Jam',
      description: 'Belt jammed',
      countsAsStop: countsAsStop ?? true,
      rules: [
        AlarmRule(
          level: AlarmLevel.error,
          expression: ExpressionConfig(value: Expression(formula: 'x > 1')),
          acknowledgeRequired: false,
        ),
      ],
    );

void main() {
  test('a stored config from before the field counts as a stop', () {
    // Through the encoder, the way alarm_man_config actually stores it —
    // toJson() alone keeps AlarmRule objects and cannot be re-parsed.
    final json = (jsonDecode(jsonEncode(config().toJson()))
        as Map<String, dynamic>)
      ..remove('countsAsStop');
    expect(AlarmConfig.fromJson(json).countsAsStop, isTrue);
  });

  test('false survives the JSON round trip', () {
    final json = jsonDecode(jsonEncode(config(countsAsStop: false).toJson()))
        as Map<String, dynamic>;
    expect(json['countsAsStop'], isFalse);
    expect(AlarmConfig.fromJson(json).countsAsStop, isFalse);
  });

  test('AlarmConfig.from copies the flag', () {
    expect(AlarmConfig.from(config(countsAsStop: false)).countsAsStop, isFalse);
    expect(AlarmConfig.from(config()).countsAsStop, isTrue);
  });
}
