import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';

import 'preferences.dart';
import 'state_man.dart';
import 'ring_buffer.dart';
part 'alarm.g.dart';

@JsonSerializable()
class ExpressionConfig {
  final Expression value;

  ExpressionConfig({required this.value});

  factory ExpressionConfig.fromJson(Map<String, dynamic> json) =>
      _$ExpressionConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ExpressionConfigToJson(this);

  @override
  String toString() {
    return 'ExpressionConfig(value: $value)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExpressionConfig && value.formula == other.value.formula;
  }

  @override
  int get hashCode => value.formula.hashCode;
}

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
}

@JsonSerializable()
class AlarmManConfig {
  final List<AlarmConfig> alarms;

  AlarmManConfig({required this.alarms});

  factory AlarmManConfig.fromJson(Map<String, dynamic> json) =>
      _$AlarmManConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmManConfigToJson(this);
}

class AlarmMan {
  final AlarmManConfig config;
  final Preferences preferences;
  final StateMan stateMan;
  final Set<Alarm> alarms;
  final Set<AlarmActive> _activeAlarms;
  final StreamController<Set<AlarmActive>> _activeAlarmsController;
  final RingBuffer<AlarmActive> _history;
  final StreamController<List<AlarmActive?>> _historyController;
  AlarmMan._(
      {required this.config, required this.preferences, required this.stateMan})
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
        });
      }
    };
    _activeAlarmsController.onCancel = () async {};
  }

  static Future<AlarmMan> create(
      Preferences preferences, StateMan stateMan) async {
    final configJson = await preferences.getString('alarm_man_config');
    if (configJson == null) {
      final config = AlarmManConfig(alarms: []);
      await preferences.setString(
          'alarm_man_config', jsonEncode(config.toJson()));
      return AlarmMan._(
          config: config, preferences: preferences, stateMan: stateMan);
    }
    final config = AlarmManConfig.fromJson(jsonDecode(configJson));
    return AlarmMan._(
        config: config, preferences: preferences, stateMan: stateMan);
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
  }
}

class Alarm {
  final AlarmConfig config;
  final List<String?> _lastEvaluations;

  Alarm({required this.config})
      : _lastEvaluations = List.filled(config.rules.length, null);

  Stream<AlarmNotification> onChange(StateMan stateMan) {
    final streamController = StreamController<AlarmNotification>.broadcast();
    final evaluators = <_Evaluator>[];

    streamController.onListen = () async {
      for (var i = 0; i < config.rules.length; i++) {
        final rule = config.rules[i];
        final evaluator =
            _Evaluator(stateMan: stateMan, expression: rule.expression);
        evaluators.add(evaluator);
        evaluator.state().listen((state) {
          // Only emit if state has changed for this rule
          if (state != _lastEvaluations[i]) {
            _lastEvaluations[i] = state;
            // If any rule is true, the alarm is active
            final alarmState = _lastEvaluations.any((state) => state != null);
            streamController.add(AlarmNotification(
                uid: config.uid,
                active: alarmState,
                expression: _lastEvaluations[i],
                rule: rule,
                timestamp: DateTime.now()));
          }
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

class Expression {
  final String formula;

  // Define operators as static constants
  static const operators = {
    'AND': 'Logical AND (both sides must be true)',
    'OR': 'Logical OR (either side can be true)',
    '<': 'Less than',
    '<=': 'Less than or equal',
    '>': 'Greater than',
    '>=': 'Greater than or equal',
    '==': 'Equal to',
    '!=': 'Not equal to',
  };
  static final expressionRegex = RegExp(r'(AND|OR|<=|>=|==|!=|<|>|\(|\))');

  Expression({required this.formula});

  /// Creates an Expression from JSON
  factory Expression.fromJson(Map<String, dynamic> json) {
    return Expression(formula: json['formula'] as String);
  }

  /// Converts the Expression to JSON
  Map<String, dynamic> toJson() => {'formula': formula};

  /// Validates if the expression looks like a valid boolean expression
  bool isValid() {
    late List<_Token> tokens;
    try {
      tokens = _parseExpression();
    } catch (_) {
      return false;
    }
    if (tokens.isEmpty) return false;

    int parenCount = 0;
    bool expectOperand = true;

    for (final token in tokens) {
      if (token.parenthesis == '(') {
        if (!expectOperand) return false;
        parenCount++;
        expectOperand = true;
      } else if (token.parenthesis == ')') {
        parenCount--;
        if (parenCount < 0 || expectOperand) return false;
        expectOperand = false;
      } else if (token.operator != null) {
        if (expectOperand) return false;
        expectOperand = true;
      } else if (token.value != null) {
        if (!expectOperand) return false;
        expectOperand = false;
      }
    }

    if (parenCount != 0 || expectOperand) return false;
    return true;
  }

  /// Parses the expression and returns a list of variable names used in the expression
  List<String> extractVariables() {
    // Remove operators and split by spaces to get potential variables
    final withoutOperators = formula
        .replaceAll(expressionRegex, ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();

    // Filter out numeric literals and quoted strings
    return withoutOperators.where((s) {
      if (double.tryParse(s) != null) return false;
      if (s.startsWith('"') && s.endsWith('"')) return false;
      if (s.startsWith("'") && s.endsWith("'")) return false;
      return true;
    }).toList();
  }

  // List of (variable, operator, variable, operator, variable, ...)
  List<_Token> _parseExpression() {
    if (formula.isEmpty) return [];

    // Get all matches (both operators and the text between them)
    final matches = expressionRegex.allMatches(formula);
    final tokens = <_Token>[];
    var lastEnd = 0;

    for (final match in matches) {
      // Add the text before the operator (if any)
      final beforeOp = formula.substring(lastEnd, match.start).trim();
      if (beforeOp.isNotEmpty) {
        if (beforeOp.contains(' ') || beforeOp.contains('\t')) {
          throw ArgumentError('Variable name: "$beforeOp" contains whitespace');
        }
        tokens.add(_Token(value: beforeOp));
      }

      // Add the operator
      final operator = match.group(0);
      if (operator != null) {
        if (operator == '(' || operator == ')') {
          tokens.add(_Token(parenthesis: operator));
        } else {
          tokens.add(_Token(operator: operator));
        }
      }
      lastEnd = match.end;
    }

    // Add any remaining text after the last operator
    final remaining = formula.substring(lastEnd).trim();
    if (remaining.isNotEmpty) {
      if (remaining.contains(' ') || remaining.contains('\t')) {
        throw ArgumentError('Variable name: $remaining contains whitespace');
      }
      tokens.add(_Token(value: remaining));
    }

    // Validate that we have a valid pattern of variables and operators
    if (tokens.isEmpty) return [];

    return tokens;
  }

  DynamicValue _evaluate(
      List<_Token> tokens, Map<String, DynamicValue> variables) {
    // Define operator precedence
    final precedence = {
      'OR': 1,
      'AND': 2,
      '==': 3,
      '!=': 3,
      '<': 3,
      '<=': 3,
      '>': 3,
      '>=': 3,
    };

    // Convert infix tokens to RPN using the Shunting-yard algorithm
    final outputQueue = <_Token>[];
    final operatorStack = <_Token>[];

    for (final token in tokens) {
      if (token.value != null) {
        // Variable or literal
        outputQueue.add(token);
      } else if (token.operator != null) {
        // Operator
        while (operatorStack.isNotEmpty &&
            operatorStack.last.operator != null &&
            precedence[operatorStack.last.operator]! >=
                precedence[token.operator]!) {
          outputQueue.add(operatorStack.removeLast());
        }
        operatorStack.add(token);
      } else if (token.parenthesis == '(') {
        operatorStack.add(token);
      } else if (token.parenthesis == ')') {
        while (
            operatorStack.isNotEmpty && operatorStack.last.parenthesis != '(') {
          outputQueue.add(operatorStack.removeLast());
        }
        if (operatorStack.isNotEmpty && operatorStack.last.parenthesis == '(') {
          operatorStack.removeLast();
        } else {
          throw ArgumentError('Mismatched parentheses');
        }
      }
    }

    // Drain remaining operators
    while (operatorStack.isNotEmpty) {
      final top = operatorStack.removeLast();
      if (top.parenthesis != null) {
        throw ArgumentError('Mismatched parentheses');
      }
      outputQueue.add(top);
    }

    // Evaluate the RPN expression
    final evalStack = <DynamicValue>[];

    DynamicValue evaluateOp(DynamicValue lhs, String op, DynamicValue rhs) {
      switch (op) {
        case 'AND':
          return DynamicValue(value: lhs.asBool && rhs.asBool);
        case 'OR':
          return DynamicValue(value: lhs.asBool || rhs.asBool);
        case '<':
          return DynamicValue(value: lhs.asDouble < rhs.asDouble);
        case '<=':
          return DynamicValue(value: lhs.asDouble <= rhs.asDouble);
        case '>':
          return DynamicValue(value: lhs.asDouble > rhs.asDouble);
        case '>=':
          return DynamicValue(value: lhs.asDouble >= rhs.asDouble);
        case '==':
          return DynamicValue(value: lhs.asString == rhs.asString);
        case '!=':
          return DynamicValue(value: lhs.asString != rhs.asString);
        default:
          throw ArgumentError('Invalid operator $op');
      }
    }

    for (final tok in outputQueue) {
      if (tok.value != null) {
        final name = tok.value!;
        final val = variables[name];
        if (val == null) {
          throw ArgumentError('Variable $name not found');
        }
        evalStack.add(val);
      } else if (tok.operator != null) {
        if (evalStack.length < 2) {
          throw ArgumentError('Invalid expression');
        }
        final rhs = evalStack.removeLast();
        final lhs = evalStack.removeLast();
        evalStack.add(evaluateOp(lhs, tok.operator!, rhs));
      }
    }

    if (evalStack.length != 1) {
      throw ArgumentError('Invalid expression');
    }
    return evalStack.first;
  }

  /// Evaluates the expression with given variable values
  bool evaluate(Map<String, DynamicValue> variables) {
    final tokens = _parseExpression();
    if (tokens.isEmpty) return false;
    final result = _evaluate(tokens, variables);
    return result.asBool;
  }

  /// Formats the expression with given variable values
  /// Example:
  /// formula: "A AND B"
  /// variables: {"A": true, "B": false}
  /// result: "A{true} AND B{false}"
  String formatWithValues(Map<String, DynamicValue> variables) {
    // Split the formula into tokens
    final tokens = _parseExpression();
    final result = StringBuffer();

    for (final token in tokens) {
      if (token.value != null) {
        // For variables, append the value in curly braces
        final value = variables[token.value!];
        if (value == null) {
          throw ArgumentError('Variable ${token.value} not found in variables');
        }
        result.write('${token.value}{${value.asString}}');
      } else if (token.operator != null) {
        // For operators, add spaces around them
        result.write(' ${token.operator} ');
      } else if (token.parenthesis != null) {
        // For parentheses, add them as is
        result.write(token.parenthesis);
      }
    }

    return result.toString().trim();
  }
}

class _Evaluator {
  final StateMan stateMan;
  final ExpressionConfig expression;
  StreamSubscription? subscription;
  StreamController<String?> streamController =
      StreamController<String?>.broadcast();

  _Evaluator({required this.stateMan, required this.expression});

  Stream<String?> state() {
    streamController.onListen = () async {
      final variables = expression.value.extractVariables();
      final streams = await Future.wait(variables.map((variable) async {
        final stream = await stateMan.subscribe(variable);
        return stream;
      }));

      subscription =
          CombineLatestStream.list<DynamicValue>(streams).listen((values) {
        final map = Map.fromEntries(variables
            .asMap()
            .entries
            .map((e) => MapEntry(e.value, values[e.key])));
        final result = expression.value.evaluate(map);
        if (result) {
          streamController.add(expression.value.formatWithValues(map));
        } else {
          streamController.add(null);
        }
      });
    };

    streamController.onCancel = () async {
      await subscription?.cancel();
      streamController.close();
    };

    return streamController.stream;
  }

  void cancel() {
    subscription?.cancel();
    streamController.close();
  }
}

class _Token {
  final String? value;
  final String? operator;
  final String? parenthesis;

  _Token({this.value, this.operator, this.parenthesis});
}
