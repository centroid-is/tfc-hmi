import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'state_man.dart';

part 'boolean_expression.g.dart';

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

  static ExpressionConfig from(ExpressionConfig copy) {
    return ExpressionConfig(value: copy.value);
  }
}

class Evaluator {
  final StateMan stateMan;
  final ExpressionConfig expression;
  StreamSubscription? subscription;
  StreamController<String?> streamController =
      StreamController<String?>.broadcast();

  Evaluator({required this.stateMan, required this.expression});

  Stream<String?> state() {
    streamController.onListen = () async {
      final variables = expression.value.extractVariables();
      final streams = await Future.wait(variables.map((variable) async {
        final stream = await stateMan.subscribe(variable);
        return stream;
      }));

      subscription = CombineLatestStream.list<DynamicValue>(streams).listen(
        (values) {
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
        },
        onError: (error, stack) {
          streamController.addError(error, stack);
        },
      );
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
      } else if (token.value != null || token.literal != null) {
        if (!expectOperand) return false;
        expectOperand = false;
      }
    }

    if (parenCount != 0 || expectOperand) return false;
    return true;
  }

  /// Parses the expression and returns a list of variable names used in the expression
  List<String> extractVariables() {
    final tokens = _parseExpression();
    return tokens
        .where((token) => token.value != null)
        .map((token) => token.value!)
        .toList();
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
        if (parseLiteral(beforeOp) != null) {
          tokens.add(_Token(literal: beforeOp));
        } else {
          tokens.add(_Token(value: beforeOp));
        }
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
      if (parseLiteral(remaining) != null) {
        tokens.add(_Token(literal: remaining));
      } else {
        tokens.add(_Token(value: remaining));
      }
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
      } else if (token.literal != null) {
        // Literal
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
          {
            if (lhs.isString && rhs.isString) {
              return DynamicValue(value: lhs.asString == rhs.asString);
            }
            if (lhs.isBoolean && rhs.isBoolean) {
              return DynamicValue(value: lhs.asBool == rhs.asBool);
            }
            return DynamicValue(value: lhs.asDouble == rhs.asDouble);
          }
        case '!=':
          {
            if (lhs.isString && rhs.isString) {
              return DynamicValue(value: lhs.asString != rhs.asString);
            }
            if (lhs.isBoolean && rhs.isBoolean) {
              return DynamicValue(value: lhs.asBool != rhs.asBool);
            }
            return DynamicValue(value: lhs.asDouble != rhs.asDouble);
          }
        default:
          throw ArgumentError('Invalid operator $op');
      }
    }

    for (final tok in outputQueue) {
      if (tok.value != null) {
        final name = tok.value!;
        var val = variables[name];
        if (val == null) {
          throw ArgumentError('Variable $name not found');
        }
        evalStack.add(val);
      } else if (tok.literal != null) {
        evalStack.add(parseLiteral(tok.literal!)!);
      } else if (tok.operator != null) {
        if (evalStack.length < 2) {
          throw ArgumentError('Invalid expression');
        }
        final rhs = evalStack.removeLast();
        final lhs = evalStack.removeLast();
        final evaluation = evaluateOp(lhs, tok.operator!, rhs);
        evalStack.add(evaluation);
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
        final value = variables[token.value!];
        result.write('${token.value}{${value.toString().trim()}}');
      } else if (token.operator != null) {
        // For operators, add spaces around them
        result.write(' ${token.operator} ');
      } else if (token.parenthesis != null) {
        // For parentheses, add them as is
        result.write(token.parenthesis);
      } else if (token.literal != null) {
        // For literals, add them as is
        result.write('${token.literal}');
      }
    }

    return result.toString().trim();
  }

  DynamicValue? parseLiteral(String value) {
    // Handle boolean literals
    if (value.toLowerCase() == 'true') {
      return DynamicValue(value: true);
    }
    if (value.toLowerCase() == 'false') {
      return DynamicValue(value: false);
    }

    // Handle numeric literals
    final numValue = double.tryParse(value);
    if (numValue != null) {
      return DynamicValue(value: numValue);
    }

    // Handle string literals (quoted)
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return DynamicValue(value: value.substring(1, value.length - 1));
    }
    return null;
  }
}

class _Token {
  final String? value;
  final String? operator;
  final String? parenthesis;
  final String? literal;

  _Token({this.value, this.operator, this.parenthesis, this.literal});
}
