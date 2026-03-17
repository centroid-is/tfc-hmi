/// Web stub for boolean_expression.dart

class Expression {
  final String formula;

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

  factory Expression.fromJson(Map<String, dynamic> json) =>
      Expression(formula: json['formula'] as String);

  Map<String, dynamic> toJson() => {'formula': formula};

  bool isValid() => formula.isNotEmpty;

  List<String> extractVariables() => [];

  bool evaluate(Map<String, dynamic> variables) => false;

  String formatWithValues(Map<String, dynamic> variables) => formula;
}

class ExpressionConfig {
  final Expression value;
  ExpressionConfig({required this.value});

  factory ExpressionConfig.fromJson(Map<String, dynamic> json) {
    final expr = json['value'] != null
        ? Expression.fromJson(json['value'] as Map<String, dynamic>)
        : Expression(formula: json['expression'] as String? ?? '');
    return ExpressionConfig(value: expr);
  }

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

  static ExpressionConfig from(ExpressionConfig copy) {
    return ExpressionConfig(value: copy.value);
  }
}

class Evaluator {
  Evaluator({required dynamic stateMan, required ExpressionConfig expression});

  Stream<bool> eval() => const Stream.empty();

  void cancel() {}
}
