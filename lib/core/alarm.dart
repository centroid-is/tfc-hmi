import 'dart:async';
import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'preferences.dart';
import 'state_man.dart';

part 'alarm.g.dart';

@JsonSerializable()
class ExpressionConfig {
  final Expression value;

  ExpressionConfig({required this.value});

  factory ExpressionConfig.fromJson(Map<String, dynamic> json) =>
      _$ExpressionConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ExpressionConfigToJson(this);
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

  factory AlarmRule.fromJson(Map<String, dynamic> json) =>
      _$AlarmRuleFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmRuleToJson(this);
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
  final List<Alarm> alarms;

  AlarmMan._({required this.config, required this.preferences})
      : alarms = config.alarms.map((e) => Alarm(config: e)).toList();

  static Future<AlarmMan> create(Preferences preferences) async {
    final configJson = await preferences.getString('alarm_man_config');
    if (configJson == null) {
      final config = AlarmManConfig(alarms: []);
      await preferences.setString(
          'alarm_man_config', jsonEncode(config.toJson()));
      return AlarmMan._(config: config, preferences: preferences);
    }
    final config = AlarmManConfig.fromJson(jsonDecode(configJson));
    return AlarmMan._(config: config, preferences: preferences);
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
}

class Alarm {
  final AlarmConfig config;
  final List<bool> _lastStates; // Track state for each rule

  Alarm({required this.config})
      : _lastStates = List.filled(config.rules.length, false);

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
          if (state != _lastStates[i]) {
            _lastStates[i] = state;
            // If any rule is true, the alarm is active
            final alarmState = _lastStates.any((state) => state);
            streamController.add(AlarmNotification(
                uid: config.uid, active: alarmState, rule: rule));
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
  final bool active;
  final AlarmRule rule;

  AlarmNotification(
      {required this.uid, required this.active, required this.rule});
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
  static final operatorRegex = RegExp(r'(AND|OR|<=|>=|==|!=|<|>)');

  Expression({required this.formula});

  /// Creates an Expression from JSON
  factory Expression.fromJson(Map<String, dynamic> json) {
    return Expression(formula: json['formula'] as String);
  }

  /// Converts the Expression to JSON
  Map<String, dynamic> toJson() => {'formula': formula};

  /// Validates if the expression looks like a valid boolean expression
  bool isValid() {
    // todo boolean DynamicValue

    return _looksBoolean(formula);
  }

  /// Basic validation that the expression contains at least one operator
  bool _looksBoolean(String expr) {
    return operatorRegex.hasMatch(expr);
  }

  /// Parses the expression and returns a list of variable names used in the expression
  List<String> extractVariables() {
    // Remove operators and split by spaces to get potential variables
    final withoutOperators = formula
        .replaceAll(operatorRegex, ' ')
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
    final matches = operatorRegex.allMatches(formula);
    final tokens = <_Token>[];
    var lastEnd = 0;

    for (final match in matches) {
      // Add the text before the operator (if any)
      final beforeOp = formula.substring(lastEnd, match.start).trim();
      if (beforeOp.isNotEmpty) {
        tokens.add(_Token(value: beforeOp, isOperator: false));
      }

      // Add the operator
      tokens.add(_Token(value: match.group(0)!, isOperator: true));
      lastEnd = match.end;
    }

    // Add any remaining text after the last operator
    final remaining = formula.substring(lastEnd).trim();
    if (remaining.isNotEmpty) {
      tokens.add(_Token(value: remaining, isOperator: false));
    }

    // Validate that we have a valid pattern of variables and operators
    if (tokens.isEmpty) return [];

    return tokens;
  }

  /// Evaluates the expression with given variable values
  bool evaluate(Map<String, DynamicValue> variables) {
    final tokens = _parseExpression();
    if (tokens.isEmpty) return false;

    // Helper function to evaluate a single operation
    DynamicValue evaluateOperation(
        DynamicValue lhs, String op, DynamicValue rhs) {
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

    // Define operator precedence (higher number = higher precedence)
    final precedence = {
      'AND': 2,
      'OR': 1,
      '<': 3,
      '<=': 3,
      '>': 3,
      '>=': 3,
      '==': 3,
      '!=': 3,
    };

    // Convert tokens to a list of values and operators
    var values = <DynamicValue>[];
    var operators = <String>[];

    for (var token in tokens) {
      if (token.isOperator) {
        while (operators.isNotEmpty &&
            precedence[operators.last]! >= precedence[token.value]!) {
          final op = operators.removeLast();
          final rhs = values.removeLast();
          final lhs = values.removeLast();
          values.add(evaluateOperation(lhs, op, rhs));
        }
        operators.add(token.value);
      } else {
        final value = variables[token.value];
        if (value == null) {
          throw ArgumentError('Variable ${token.value} not found');
        }
        values.add(value);
      }
    }

    // Process remaining operators
    while (operators.isNotEmpty) {
      final op = operators.removeLast();
      final rhs = values.removeLast();
      final lhs = values.removeLast();
      values.add(evaluateOperation(lhs, op, rhs));
    }

    // Final result should be a single value
    if (values.length != 1) {
      throw ArgumentError('Invalid expression');
    }

    return values.first.asBool;
  }
}

class _Evaluator {
  final StateMan stateMan;
  final ExpressionConfig expression;
  StreamSubscription? subscription;
  StreamController<bool> streamController = StreamController<bool>.broadcast();

  _Evaluator({required this.stateMan, required this.expression});

  Stream<bool> state() {
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
        streamController.add(result);
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
  final String value;
  final bool isOperator;

  _Token({required this.value, required this.isOperator});
}
