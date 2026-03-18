/// Web stub for alarm.dart
/// On web, alarm management is not performed — types exist for compilation only.

import 'dart:async';

import 'boolean_expression_stub.dart' show ExpressionConfig;

enum AlarmLevel { info, warning, error }

class AlarmRule {
  final AlarmLevel level;
  final ExpressionConfig expression;
  final bool acknowledgeRequired;

  AlarmRule({
    required this.level,
    required this.expression,
    required this.acknowledgeRequired,
  });

  factory AlarmRule.fromJson(Map<String, dynamic> json) => AlarmRule(
        level: AlarmLevel.values.byName(json['level'] as String? ?? 'info'),
        expression:
            ExpressionConfig.fromJson(json['expression'] as Map<String, dynamic>),
        acknowledgeRequired: json['acknowledgeRequired'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'expression': expression.toJson(),
        'acknowledgeRequired': acknowledgeRequired,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlarmRule &&
        level == other.level &&
        expression == other.expression &&
        acknowledgeRequired == other.acknowledgeRequired;
  }

  @override
  int get hashCode => Object.hash(level, expression, acknowledgeRequired);

  static AlarmRule from(AlarmRule copy) => AlarmRule(
        level: copy.level,
        expression: ExpressionConfig(value: copy.expression.value),
        acknowledgeRequired: copy.acknowledgeRequired,
      );
}

class AlarmConfig {
  final String uid;
  final String? key;
  final String title;
  final String description;
  final List<AlarmRule> rules;

  AlarmConfig({
    required this.uid,
    this.key,
    required this.title,
    required this.description,
    required this.rules,
  });

  factory AlarmConfig.fromDb({
    required String uid,
    String? key,
    required String title,
    required String description,
    required String rules,
  }) =>
      AlarmConfig(
        uid: uid,
        key: key,
        title: title,
        description: description,
        rules: [],
      );

  factory AlarmConfig.fromJson(Map<String, dynamic> json) => AlarmConfig(
        uid: json['uid'] as String? ?? '',
        key: json['key'] as String?,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        rules: (json['rules'] as List<dynamic>?)
                ?.map((e) => AlarmRule.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'key': key,
        'title': title,
        'description': description,
        'rules': rules.map((e) => e.toJson()).toList(),
      };

  static AlarmConfig from(AlarmConfig copy) => AlarmConfig(
        uid: copy.uid,
        key: copy.key,
        title: copy.title,
        description: copy.description,
        rules: copy.rules.map((e) => AlarmRule.from(e)).toList(),
      );
}

class AlarmManConfig {
  final List<AlarmConfig> alarms;

  AlarmManConfig({required this.alarms});

  factory AlarmManConfig.fromJson(Map<String, dynamic> json) => AlarmManConfig(
        alarms: (json['alarms'] as List<dynamic>?)
                ?.map((e) => AlarmConfig.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'alarms': alarms.map((e) => e.toJson()).toList(),
      };
}

class AlarmManLocalConfig {
  final bool historyToDb;

  AlarmManLocalConfig({required this.historyToDb});

  factory AlarmManLocalConfig.fromJson(Map<String, dynamic> json) =>
      AlarmManLocalConfig(historyToDb: json['historyToDb'] as bool? ?? false);

  Map<String, dynamic> toJson() => {'historyToDb': historyToDb};
}

class AlarmMan {
  final AlarmManConfig config;
  final Set<Alarm> alarms;

  AlarmMan._({required this.config})
      : alarms = config.alarms.map((e) => Alarm(config: e)).toSet();

  static Future<AlarmMan> create(dynamic preferences, dynamic stateMan,
      {bool historyToDb = false}) async {
    return AlarmMan._(config: AlarmManConfig(alarms: []));
  }

  Stream<Set<AlarmActive>> activeAlarms() => const Stream.empty();

  Stream<List<AlarmActive?>> history() => const Stream.empty();

  void ackAlarm(AlarmActive alarm) {}

  List<AlarmActive> filterAlarms(List<AlarmActive> alarms, String searchQuery) =>
      alarms;

  void addAlarm(AlarmConfig alarm) {}
  void removeAlarm(AlarmConfig alarm) {}
  void updateAlarm(AlarmConfig alarm) {}
}

class Alarm {
  final AlarmConfig config;
  Alarm({required this.config});
}

class AlarmNotification {
  final String uid;
  bool active;
  String? expression;
  final AlarmRule rule;
  final DateTime timestamp;

  AlarmNotification({
    required this.uid,
    required this.active,
    required this.expression,
    required this.rule,
    required this.timestamp,
  });
}

class AlarmActive {
  final Alarm alarm;
  final AlarmNotification notification;
  bool pendingAck;
  DateTime? deactivated;

  AlarmActive({
    required this.alarm,
    required this.notification,
    this.pendingAck = false,
    this.deactivated,
  });
}
