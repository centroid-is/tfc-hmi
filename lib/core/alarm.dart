import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:shared_preferences/shared_preferences.dart';

import 'preferences.dart';
import 'database.dart';
import 'state_man.dart';
import 'ring_buffer.dart';
import 'boolean_expression.dart';

part 'alarm.g.dart';

@JsonEnum()
enum AlarmLevel {
  info,
  warning,
  error,
}

@JsonSerializable()
class AlarmRule {
  final AlarmLevel level;
  final ExpressionConfig expression;
  final bool acknowledgeRequired;

  AlarmRule({
    required this.level,
    required this.expression,
    required this.acknowledgeRequired,
  });

  @override
  String toString() {
    return 'AlarmRule(level: $level, expression: $expression, acknowledgeRequired: $acknowledgeRequired)';
  }

  factory AlarmRule.fromJson(Map<String, dynamic> json) =>
      _$AlarmRuleFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmRuleToJson(this);

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

  static AlarmRule from(AlarmRule copy) {
    return AlarmRule(
      level: copy.level,
      expression: ExpressionConfig.from(copy.expression),
      acknowledgeRequired: copy.acknowledgeRequired,
    );
  }
}

@JsonSerializable()
class AlarmConfig {
  final String uid;
  // todo I would like this to fetch title and description from opcua alarm
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

  @override
  String toString() {
    return 'AlarmConfig(uid: $uid, key: $key, title: $title, description: $description, rules: $rules)';
  }

  factory AlarmConfig.fromJson(Map<String, dynamic> json) =>
      _$AlarmConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmConfigToJson(this);

  static AlarmConfig from(AlarmConfig copy) {
    return AlarmConfig(
      uid: copy.uid,
      key: copy.key,
      title: copy.title,
      description: copy.description,
      rules: copy.rules.map((e) => AlarmRule.from(e)).toList(),
    );
  }
}

@JsonSerializable()
class AlarmManConfig {
  final List<AlarmConfig> alarms;

  AlarmManConfig({required this.alarms});

  factory AlarmManConfig.fromJson(Map<String, dynamic> json) =>
      _$AlarmManConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmManConfigToJson(this);
}

@JsonSerializable()
class AlarmManLocalConfig {
  final bool historyToDb;

  AlarmManLocalConfig({required this.historyToDb});

  factory AlarmManLocalConfig.fromJson(Map<String, dynamic> json) =>
      _$AlarmManLocalConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmManLocalConfigToJson(this);
}

class AlarmMan {
  final AlarmManConfig config;
  final AlarmManLocalConfig localConfig;
  final Preferences preferences;
  final StateMan stateMan;
  final Set<Alarm> alarms;
  final Set<AlarmActive> _activeAlarms;
  final StreamController<Set<AlarmActive>> _activeAlarmsController;
  final RingBuffer<AlarmActive> _history;
  final StreamController<List<AlarmActive?>> _historyController;
  AlarmMan._(
      {required this.config,
      required this.preferences,
      required this.stateMan,
      required this.localConfig})
      : alarms = config.alarms.map((e) => Alarm(config: e)).toSet(),
        _activeAlarms = {},
        _activeAlarmsController = BehaviorSubject<Set<AlarmActive>>.seeded({}),
        _history = RingBuffer<AlarmActive>(1000),
        _historyController = BehaviorSubject<List<AlarmActive?>>.seeded([]) {
    _activeAlarmsController.onListen = () async {
      for (final alarm in alarms) {
        final stream = alarm.onChange(stateMan);
        stream.listen((alarmNotification) {
          final existing = _activeAlarms.firstWhereOrNull((e) =>
              // the uid must match, we are in correct closure
              e.alarm.config.uid == alarm.config.uid &&
              // the rule must match
              e.notification.rule == alarmNotification.rule);

          if (alarmNotification.active) {
            if (existing != null) {
              _removeActiveAlarm(existing);
            }
            _activeAlarms.add(
                AlarmActive(alarm: alarm, notification: alarmNotification));
          } else if (!alarmNotification.rule.acknowledgeRequired) {
            if (existing != null) {
              _removeActiveAlarm(existing);
            } else {
              stderr.writeln(
                  'Did not find existing active alarm for alarmNotification: $alarmNotification');
            }
          } else {
            for (final e in _activeAlarms) {
              if (e.alarm.config.uid == alarm.config.uid &&
                  e.notification.rule == alarmNotification.rule) {
                e.pendingAck = true;
                e.notification.active = false;
                break;
              }
            }
          }
          _activeAlarmsController.add(_activeAlarms);
        }, onError: (error, stack) {
          stderr.writeln('Alarm stream error: $error');
        });
      }
    };
    _activeAlarmsController.onCancel = () async {};
  }

  static Future<AlarmMan> create(
      Preferences preferences, StateMan stateMan) async {
    final sharedPreferences = SharedPreferencesAsync();
    var localConfigJson =
        await sharedPreferences.getString('alarm_man_local_config');
    if (localConfigJson == null) {
      await sharedPreferences.setString('alarm_man_local_config',
          jsonEncode(AlarmManLocalConfig(historyToDb: false).toJson()));
      localConfigJson =
          await sharedPreferences.getString('alarm_man_local_config');
    }
    final localConfig =
        AlarmManLocalConfig.fromJson(jsonDecode(localConfigJson!));

    var configJson = await preferences.getString('alarm_man_config');
    if (configJson == null) {
      configJson = await preferences.getString('alarm_man_config');
      if (configJson == null) {
        await preferences.setString(
            'alarm_man_config', jsonEncode(AlarmManConfig(alarms: [])));
        configJson = await preferences.getString('alarm_man_config');
      }
    }
    final config = AlarmManConfig.fromJson(jsonDecode(configJson!));
    final alarmMan = AlarmMan._(
        config: config,
        preferences: preferences,
        stateMan: stateMan,
        localConfig: localConfig);
    try {
      await alarmMan._ensureTable();
      alarmMan._history.addAll(await alarmMan.getRecentAlarms());
      alarmMan._historyController.add(alarmMan._history.buffer);
    } catch (e) {
      stderr.writeln('Error loading history: $e');
    }
    return alarmMan;
  }

  Stream<Set<AlarmActive>> activeAlarms() {
    return _activeAlarmsController.stream;
  }

  Stream<List<AlarmActive?>> history() {
    return _historyController.stream;
  }

  void ackAlarm(AlarmActive alarm) {
    _removeActiveAlarm(alarm);
    _activeAlarmsController.add(_activeAlarms);
  }

  void addAlarm(AlarmConfig alarm) {
    config.alarms.add(alarm);
    _saveConfig();
    alarms.add(Alarm(config: alarm));
  }

  void removeAlarm(AlarmConfig alarm) {
    config.alarms.removeWhere((e) => e.uid == alarm.uid);
    _saveConfig();
    alarms.removeWhere((e) => e.config.uid == alarm.uid);
  }

  void updateAlarm(AlarmConfig alarm) {
    config.alarms.removeWhere((e) => e.uid == alarm.uid);
    config.alarms.add(alarm);
    _saveConfig();
    alarms.removeWhere((e) => e.config.uid == alarm.uid);
    alarms.add(Alarm(config: alarm));
  }

  List<AlarmActive> filterAlarms(List<AlarmActive> alarms, String searchQuery) {
    // Group alarms by uid and keep only the highest priority one for each
    final Map<String, AlarmActive> highestPriorityAlarms = {};
    for (final alarm in alarms) {
      final existing = highestPriorityAlarms[alarm.alarm.config.uid];
      if (existing == null ||
          alarm.notification.rule.level.index >
              existing.notification.rule.level.index) {
        highestPriorityAlarms[alarm.alarm.config.uid] = alarm;
      }
    }

    var filteredAlarms = highestPriorityAlarms.values.toList()
      ..sort((a, b) {
        // First sort by priority (error > warning > info)
        final priorityCompare = b.notification.rule.level.index
            .compareTo(a.notification.rule.level.index);
        if (priorityCompare != 0) return priorityCompare;

        // If same priority, sort by most recent timestamp
        return b.notification.timestamp.compareTo(a.notification.timestamp);
      });

    // Filter alarms based on search query
    if (searchQuery.isNotEmpty) {
      filteredAlarms = filteredAlarms.where((alarm) {
        final title = alarm.alarm.config.title.toLowerCase();
        final description = alarm.alarm.config.description.toLowerCase();
        final query = searchQuery.toLowerCase();
        return title.contains(query) || description.contains(query);
      }).toList();
    }

    return filteredAlarms;
  }

  void _saveConfig() async {
    await preferences.setString(
        'alarm_man_config', jsonEncode(config.toJson()));
  }

  void _removeActiveAlarm(AlarmActive alarm) {
    alarm.notification.active = false;
    alarm.deactivated = DateTime.now();
    _history.add(alarm);
    _activeAlarms.remove(alarm);
    _historyController.add(_history.buffer);
    if (localConfig.historyToDb) {
      _addToDb(alarm);
    }
  }

  Future<void> _addToDb(AlarmActive alarm) async {
    if (preferences.database == null) return;
    await preferences.database!.query(
      '''
        INSERT INTO alarm_history (
          alarm_uid, alarm_title, alarm_description, alarm_level,
          expression, active, pending_ack, created_at, deactivated_at
        ) VALUES (
          @uid, @title, @description, @level,
          @expression, @active, @pending_ack, @created_at, @deactivated_at
        )
      ''',
      parameters: {
        'uid': alarm.alarm.config.uid,
        'title': alarm.alarm.config.title,
        'description': alarm.alarm.config.description,
        'level': alarm.notification.rule.level.name,
        'expression': alarm.notification.expression,
        'active': alarm.notification.active,
        'pending_ack': alarm.pendingAck,
        'created_at': alarm.notification.timestamp,
        'deactivated_at': alarm.deactivated,
      },
    );
  }

  Future<void> _ensureTable() async {
    if (preferences.database == null) return;
    await preferences.database!.query('''
      CREATE TABLE IF NOT EXISTS alarm_history (
        id SERIAL PRIMARY KEY,
        alarm_uid TEXT NOT NULL,
        alarm_title TEXT NOT NULL,
        alarm_description TEXT NOT NULL,
        alarm_level TEXT NOT NULL,
        expression TEXT,
        active BOOLEAN NOT NULL,
        pending_ack BOOLEAN NOT NULL,
        created_at TIMESTAMP NOT NULL,
        deactivated_at TIMESTAMP,
        acknowledged_at TIMESTAMP
      )
    ''');
  }

  Future<List<AlarmActive>> getRecentAlarms({int limit = 1000}) async {
    if (preferences.database == null) return [];

    final result = await preferences.database!.query(
      '''
        SELECT * FROM alarm_history 
        ORDER BY created_at DESC 
        LIMIT @limit
      ''',
      parameters: {'limit': limit},
    );

    return result
        .map((row) {
          // Find the corresponding alarm config from our current alarms
          final alarmConfig = alarms.firstWhereOrNull(
            (a) => a.config.uid == row[1] as String, // alarm_uid is at index 1
          );

          // Skip this alarm if config is not found
          if (alarmConfig == null) {
            return null;
          }

          // Create AlarmRule from stored data
          final rule = AlarmRule(
            level: AlarmLevel.values.firstWhere(
              (l) => l.name == row[4] as String, // alarm_level is at index 4
            ),
            expression: ExpressionConfig(
              value: Expression(
                  formula: row[5] as String? ?? ''), // expression is at index 5
            ),
            acknowledgeRequired: false, // We don't store this in history
          );

          // Create AlarmNotification
          final notification = AlarmNotification(
            uid: row[1] as String, // alarm_uid
            active: row[6] as bool, // active
            expression: row[5] as String?, // expression
            rule: rule,
            timestamp: row[8] as DateTime, // created_at
          );

          // Create and return AlarmActive
          return AlarmActive(
            alarm: alarmConfig,
            notification: notification,
            pendingAck: row[7] as bool, // pending_ack
            deactivated: row[9] as DateTime?, // deactivated_at
          );
        })
        .whereType<AlarmActive>()
        .toList();
  }
}

class Alarm {
  final AlarmConfig config;
  final List<String?> _lastEvaluations;

  Alarm({required this.config})
      : _lastEvaluations = List.filled(config.rules.length, null);

  Stream<AlarmNotification> onChange(StateMan stateMan) {
    final streamController = StreamController<AlarmNotification>.broadcast();
    final evaluators = <Evaluator>[];

    streamController.onListen = () async {
      for (var i = 0; i < config.rules.length; i++) {
        final rule = config.rules[i];
        final evaluator =
            Evaluator(stateMan: stateMan, expression: rule.expression);
        evaluators.add(evaluator);
        evaluator.state().listen((state) {
          // Only emit if state has changed for this rule
          if (state != _lastEvaluations[i]) {
            _lastEvaluations[i] = state;
            // If this rule is true, the alarm is active
            final alarmState = state != null;
            streamController.add(AlarmNotification(
                uid: config.uid,
                active: alarmState,
                expression: _lastEvaluations[i],
                rule: rule,
                timestamp: DateTime.now()));
          }
        }, onError: (error, stack) {
          streamController.addError(error, stack);
        });
      }
    };

    streamController.onCancel = () async {
      for (final evaluator in evaluators) {
        evaluator.cancel();
      }
    };

    return streamController.stream;
  }
}

class AlarmNotification {
  final String uid;
  bool active;
  String? expression;
  final AlarmRule rule;
  final DateTime timestamp;

  AlarmNotification(
      {required this.uid,
      required this.active,
      required this.expression,
      required this.rule,
      required this.timestamp});

  @override
  String toString() {
    return 'AlarmNotification(uid: $uid, active: $active, expression: $expression, rule: $rule, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlarmNotification &&
        uid == other.uid &&
        active == other.active &&
        expression == other.expression &&
        rule == other.rule;
  }

  @override
  int get hashCode => Object.hash(uid, active, expression, rule);

  /// Returns the background and text colors for this alarm level
  (Color, Color) getColors(BuildContext context) {
    switch (rule.level) {
      case AlarmLevel.info:
        return (
          Theme.of(context).colorScheme.primaryContainer,
          Theme.of(context).colorScheme.onPrimaryContainer
        );
      case AlarmLevel.warning:
        return (
          Theme.of(context).colorScheme.tertiaryContainer,
          Theme.of(context).colorScheme.onTertiaryContainer
        );
      case AlarmLevel.error:
        return (
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer
        );
    }
  }
}

class AlarmActive {
  final Alarm alarm;
  final AlarmNotification notification;
  bool pendingAck;
  DateTime? deactivated;

  @override
  String toString() {
    return 'AlarmActive(alarm: $alarm, notification: $notification, deactivated: $deactivated)';
  }

  AlarmActive({
    required this.alarm,
    required this.notification,
    this.pendingAck = false,
    this.deactivated,
  });
}
