/// FFI-free boolean expression validator for MCP server.
///
/// Ported from `tfc_dart`'s `Expression` class but replaces the
/// `DynamicValue` FFI dependency with plain Dart type checks.
/// Provides validation, parsing, serialization, and variable extraction
/// for boolean expressions used in alarm formulas.
///
/// Example expressions:
/// - `pump3.current > 15`
/// - `pump3.current > 15 AND pump3.temp < 80`
/// - `(a > 1) OR (b < 2)`
class ExpressionValidator {
  /// Operators recognized in expressions.
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

  /// Regex that splits expressions into tokens (operators and parentheses).
  ///
  /// Copied verbatim from tfc_dart's Expression class.
  static final expressionRegex = RegExp(r'(AND|OR|<=|>=|==|!=|<|>|\(|\))');

  /// Validates whether [formula] is a syntactically valid boolean expression.
  ///
  /// Returns `true` if the expression has balanced parentheses, alternating
  /// operands and operators, and no trailing operators or empty segments.
  bool isValid(String formula) {
    late List<ExpressionToken> tokens;
    try {
      tokens = _parseExpression(formula);
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
      } else if (token.variable != null || token.literal != null) {
        if (!expectOperand) return false;
        expectOperand = false;
      }
    }

    if (parenCount != 0 || expectOperand) return false;
    return true;
  }

  /// Parses [formula] into a list of [ExpressionToken]s.
  ///
  /// Throws [ArgumentError] if variable names contain whitespace.
  List<ExpressionToken> parse(String formula) => _parseExpression(formula);

  /// Serializes a list of [ExpressionToken]s back into a formula string.
  ///
  /// Variables and literals are emitted without surrounding spaces.
  /// Operators are emitted with spaces around them.
  /// Parentheses are emitted as-is (no extra spaces).
  String serialize(List<ExpressionToken> tokens) {
    final buffer = StringBuffer();

    for (final token in tokens) {
      if (token.variable != null) {
        buffer.write(token.variable);
      } else if (token.literal != null) {
        buffer.write(token.literal);
      } else if (token.operator != null) {
        buffer.write(' ${token.operator} ');
      } else if (token.parenthesis != null) {
        buffer.write(token.parenthesis);
      }
    }

    return buffer.toString().trim();
  }

  /// Extracts variable names from [formula], excluding literals and operators.
  List<String> extractVariables(String formula) {
    final tokens = _parseExpression(formula);
    return tokens
        .where((token) => token.variable != null)
        .map((token) => token.variable!)
        .toList();
  }

  /// Checks whether [value] is a literal (number, boolean, or quoted string).
  ///
  /// Replaces tfc_dart's `parseLiteral()` which returned `DynamicValue`.
  bool _isLiteral(String value) {
    // Boolean literals
    if (value.toLowerCase() == 'true' || value.toLowerCase() == 'false') {
      return true;
    }

    // Numeric literals
    if (double.tryParse(value) != null) {
      return true;
    }

    // Quoted string literals
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return true;
    }

    return false;
  }

  /// Internal parser that splits a formula into tokens.
  ///
  /// Logic ported from tfc_dart's `Expression._parseExpression()` with
  /// `parseLiteral()` replaced by `_isLiteral()`.
  List<ExpressionToken> _parseExpression(String formula) {
    if (formula.isEmpty) return [];

    final matches = expressionRegex.allMatches(formula);
    final tokens = <ExpressionToken>[];
    var lastEnd = 0;

    for (final match in matches) {
      // Add the text before the operator (if any)
      final beforeOp = formula.substring(lastEnd, match.start).trim();
      if (beforeOp.isNotEmpty) {
        if (beforeOp.contains(' ') || beforeOp.contains('\t')) {
          throw ArgumentError('Variable name: "$beforeOp" contains whitespace');
        }
        if (_isLiteral(beforeOp)) {
          tokens.add(ExpressionToken(literal: beforeOp));
        } else {
          tokens.add(ExpressionToken(variable: beforeOp));
        }
      }

      // Add the operator or parenthesis
      final op = match.group(0);
      if (op != null) {
        if (op == '(' || op == ')') {
          tokens.add(ExpressionToken(parenthesis: op));
        } else {
          tokens.add(ExpressionToken(operator: op));
        }
      }
      lastEnd = match.end;
    }

    // Add any remaining text after the last operator
    final remaining = formula.substring(lastEnd).trim();
    if (remaining.isNotEmpty) {
      if (remaining.contains(' ') || remaining.contains('\t')) {
        throw ArgumentError(
            'Variable name: "$remaining" contains whitespace');
      }
      if (_isLiteral(remaining)) {
        tokens.add(ExpressionToken(literal: remaining));
      } else {
        tokens.add(ExpressionToken(variable: remaining));
      }
    }

    if (tokens.isEmpty) return [];
    return tokens;
  }
}

/// A token in a parsed boolean expression.
///
/// Exactly one of [variable], [operator], [parenthesis], or [literal]
/// will be non-null.
class ExpressionToken {
  /// A variable name (e.g., `pump3.current`).
  final String? variable;

  /// An operator (e.g., `AND`, `>`, `==`).
  final String? operator;

  /// A parenthesis character (`(` or `)`).
  final String? parenthesis;

  /// A literal value (e.g., `15`, `true`, `"running"`).
  final String? literal;

  ExpressionToken({this.variable, this.operator, this.parenthesis, this.literal});

  @override
  String toString() {
    if (variable != null) return 'Token(var: $variable)';
    if (operator != null) return 'Token(op: $operator)';
    if (parenthesis != null) return 'Token(paren: $parenthesis)';
    if (literal != null) return 'Token(lit: $literal)';
    return 'Token(empty)';
  }
}
