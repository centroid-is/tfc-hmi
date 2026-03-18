/// Web stub for boolean_expression.dart
/// On web, expression evaluation is not performed — types exist for compilation only.

import 'package:tfc_dart/core/dynamic_value.dart';

class Expression {
  final String formula;

  static const operators = <String, String>{
    'AND': 'Logical AND (both sides must be true)',
    'OR': 'Logical OR (either side can be true)',
    '<': 'Less than',
    '<=': 'Less than or equal',
    '>': 'Greater than',
    '>=': 'Greater than or equal',
    '==': 'Equal to',
    '!=': 'Not equal to',
  };

  Expression({required this.formula});

  factory Expression.fromJson(Map<String, dynamic> json) =>
      Expression(formula: json['formula'] as String? ?? '');

  Map<String, dynamic> toJson() => {'formula': formula};

  bool isValid() => false;

  List<String> extractVariables() => [];

  bool evaluate(Map<String, DynamicValue> variables) => false;

  String formatWithValues(Map<String, DynamicValue> variables) => formula;
}

class ExpressionConfig {
  final Expression value;

  ExpressionConfig({required this.value});

  factory ExpressionConfig.fromJson(Map<String, dynamic> json) =>
      ExpressionConfig(value: Expression.fromJson(json['value'] as Map<String, dynamic>? ?? {'formula': ''}));

  Map<String, dynamic> toJson() => {'value': value.toJson()};

  @override
  String toString() => 'ExpressionConfig(value: $value)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExpressionConfig && value.formula == other.value.formula;
  }

  @override
  int get hashCode => value.formula.hashCode;

  static ExpressionConfig from(ExpressionConfig copy) =>
      ExpressionConfig(value: copy.value);
}

class Evaluator {
  final dynamic stateMan;
  final ExpressionConfig expression;

  Evaluator({required this.stateMan, required this.expression});

  Stream<bool> eval() => const Stream.empty();

  Stream<String?> state() => const Stream.empty();

  void cancel() {}
}
