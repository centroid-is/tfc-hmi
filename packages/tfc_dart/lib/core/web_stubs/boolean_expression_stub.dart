/// Web stub for boolean_expression.dart

class ExpressionConfig {
  final String expression;
  ExpressionConfig({required this.expression});

  Map<String, dynamic> toJson() => {'expression': expression};
  static ExpressionConfig fromJson(Map<String, dynamic> json) =>
      ExpressionConfig(expression: json['expression'] as String? ?? '');
}
