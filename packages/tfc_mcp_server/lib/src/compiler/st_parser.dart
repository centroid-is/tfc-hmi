import 'package:petitparser/petitparser.dart';

import 'st_ast.dart';

/// Parses IEC 61131-3 Structured Text expressions into AST nodes.
///
/// Supports standard IEC, Beckhoff TwinCAT extensions, and Schneider
/// direct-addressing syntax. Keywords are case-insensitive per the spec.
class StParser {
  late final Parser<Expression> _expression;
  late final Parser<Statement> _statement;
  late final Parser<List<Statement>> _statements;

  // Declaration parsers
  late final Parser<VarBlock> _varBlock;
  late final Parser<Pragma> _pragma;
  late final Parser<TypeSpec> _typeSpec;
  late final Parser<TypeDeclaration> _typeDeclaration;
  late final Parser<MethodDeclaration> _methodDeclaration;
  late final Parser<PropertyDeclaration> _propertyDeclaration;
  late final Parser<ActionDeclaration> _actionDeclaration;
  late final Parser<InterfaceDeclaration> _interfaceDeclaration;
  late final Parser<PouDeclaration> _pouDeclaration;
  late final Parser<GlobalVarDeclaration> _globalVarDeclaration;
  late final Parser<Declaration> _declaration;
  late final Parser<CompilationUnit> _compilationUnit;

  StParser() {
    _buildParsers();
    _buildDeclarationParsers();
  }

  // ================================================================
  // Lexer helpers
  // ================================================================

  /// Case-insensitive keyword that must not be followed by a word char.
  Parser<String> _kw(String kw) => string(kw, ignoreCase: true)
      .skip(after: _notWordChar)
      .trim();

  /// Negative lookahead for word characters — ensures keyword boundary.
  Parser<void> get _notWordChar =>
      (letter() | digit() | char('_')).not();

  /// Negative lookahead for statement-boundary keywords.
  /// Prevents keywords like `END_IF`, `THEN`, `ELSE`, etc. from being
  /// consumed as bare expression statements.
  Parser<void> get _notStatementKeyword {
    const keywords = [
      'END_IF', 'END_CASE', 'END_FOR', 'END_WHILE', 'END_REPEAT',
      'END_VAR', 'END_PROGRAM', 'END_FUNCTION_BLOCK', 'END_FUNCTION',
      'END_METHOD', 'END_PROPERTY', 'END_ACTION', 'END_INTERFACE',
      'END_STRUCT', 'END_TYPE', 'END_GET', 'END_SET',
      'THEN', 'ELSE', 'ELSIF', 'DO', 'UNTIL', 'OF',
      'IF', 'CASE', 'FOR', 'WHILE', 'REPEAT',
      'VAR', 'VAR_INPUT', 'VAR_OUTPUT', 'VAR_IN_OUT', 'VAR_GLOBAL',
      'VAR_TEMP', 'VAR_INST', 'VAR_STAT',
      'EXIT', 'RETURN', 'CONTINUE',
    ];
    return keywords
        .map((kw) => (string(kw, ignoreCase: true).skip(after: _notWordChar))
            as Parser)
        .toList()
        .toChoiceParser()
        .not();
  }

  /// Symbol token with surrounding whitespace trimmed.
  Parser<String> _sym(String s) => string(s).trim();

  // ================================================================
  // Literal parsers
  // ================================================================

  /// Time literal: T#... or TIME#...
  Parser<Expression> get _timeLiteral {
    final prefix =
        (string('TIME', ignoreCase: true) | string('T', ignoreCase: true))
            .skip(after: char('#'));

    // Time segments: ms must come before m and s to avoid partial match
    final msSegment = (digit().plus().flatten().map(int.parse))
        .skip(after: string('ms', ignoreCase: true))
        .map((v) => Duration(milliseconds: v));
    final hSegment = (digit().plus().flatten().map(int.parse))
        .skip(after: string('h', ignoreCase: true))
        .map((v) => Duration(hours: v));
    final mSegment = (digit().plus().flatten().map(int.parse))
        .skip(after: string('m', ignoreCase: true))
        .map((v) => Duration(minutes: v));
    final sSegment = (digit().plus().flatten().map(int.parse))
        .skip(after: string('s', ignoreCase: true))
        .map((v) => Duration(seconds: v));

    final segment = msSegment | hSegment | mSegment | sSegment;

    return (prefix & segment.plus())
        .flatten()
        .map((raw) {
      // Re-parse the segments from the raw string
      return _parseTimeLiteralFromRaw(raw);
    });
  }

  TimeLiteral _parseTimeLiteralFromRaw(String raw) {
    // raw is like "T#5s", "TIME#1h30m", "T#2h15m30s500ms"
    final hashIdx = raw.indexOf('#');
    final body = raw.substring(hashIdx + 1).toLowerCase();

    var total = Duration.zero;
    final re = RegExp(r'(\d+)(ms|h|m|s)');
    for (final match in re.allMatches(body)) {
      final value = int.parse(match.group(1)!);
      final unit = match.group(2)!;
      switch (unit) {
        case 'ms':
          total += Duration(milliseconds: value);
        case 'h':
          total += Duration(hours: value);
        case 'm':
          total += Duration(minutes: value);
        case 's':
          total += Duration(seconds: value);
      }
    }
    return TimeLiteral(value: total, raw: raw);
  }

  /// DateTime literal: DT#... or DATE_AND_TIME#...
  /// Must be tried before date literal to avoid D matching DATE_AND_TIME
  Parser<Expression> get _dateTimeLiteral {
    final prefix =
        (string('DATE_AND_TIME', ignoreCase: true) |
            string('DT', ignoreCase: true))
            .skip(after: char('#'));
    final dtBody = pattern('0-9:-').plus().flatten();
    return (prefix.flatten() & dtBody)
        .map((values) => DateTimeLiteral('${values[0]}${values[1]}'));
  }

  /// TimeOfDay literal: TOD#HH:MM:SS or TIME_OF_DAY#HH:MM:SS
  Parser<Expression> get _timeOfDayLiteral {
    final prefix =
        (string('TIME_OF_DAY', ignoreCase: true) |
            string('TOD', ignoreCase: true))
            .skip(after: char('#'));
    final todBody = pattern('0-9:').plus().flatten();
    return (prefix.flatten() & todBody)
        .map((values) => TimeOfDayLiteral('${values[0]}${values[1]}'));
  }

  /// Date literal: D#YYYY-MM-DD or DATE#YYYY-MM-DD
  Parser<Expression> get _dateLiteral {
    final prefix =
        (string('DATE', ignoreCase: true) | string('D', ignoreCase: true))
            .skip(after: char('#'));
    final dateBody = pattern('0-9-').plus().flatten();
    return (prefix.flatten() & dateBody)
        .map((values) => DateLiteral('${values[0]}${values[1]}'));
  }

  /// Typed literal: TYPE#value (INT#42, REAL#3.14, DINT#1000, LREAL#1.0E10)
  Parser<Expression> get _typedLiteral {
    final typeNames = [
      'LREAL', 'REAL', 'LINT', 'DINT', 'SINT', 'USINT', 'UINT',
      'UDINT', 'ULINT', 'INT', 'WORD', 'DWORD', 'LWORD', 'BYTE',
    ].map((t) => string(t, ignoreCase: true) as Parser<String>)
        .toList()
        .toChoiceParser()
        .flatten();

    // Real number with decimal point and optional exponent
    final realNum = (digit().plus() &
        char('.') &
        digit().plus() &
        (pattern('eE') & pattern('+-').optional() & digit().plus()).optional())
        .flatten();

    // Integer number
    final intNum = digit().plus().flatten();

    return (typeNames & char('#') & (realNum | intNum)).map((values) {
      final typeName = (values[0] as String).toUpperCase();
      final numStr = values[2] as String;
      if (numStr.contains('.') ||
          numStr.contains('e') ||
          numStr.contains('E')) {
        return RealLiteral(double.parse(numStr), typePrefix: typeName);
      } else {
        return IntLiteral(int.parse(numStr), typePrefix: typeName);
      }
    });
  }

  /// Base-prefixed integer: 16#FF, 2#1010, 8#77
  Parser<Expression> get _baseLiteral {
    return (digit().plus().flatten() &
        char('#') &
        pattern('0-9a-fA-F').plus().flatten())
        .map((values) {
      final base = int.parse(values[0] as String);
      final digits = values[2] as String;
      return IntLiteral(int.parse(digits, radix: base));
    });
  }

  /// Real literal: digits.digits with optional exponent
  Parser<Expression> get _realLiteral {
    return (digit().plus() &
        char('.') &
        digit().plus() &
        (pattern('eE') & pattern('+-').optional() & digit().plus()).optional())
        .flatten()
        .map((s) => RealLiteral(double.parse(s)));
  }

  /// Integer literal
  Parser<Expression> get _intLiteral {
    return digit().plus().flatten().map((s) => IntLiteral(int.parse(s)));
  }

  /// Boolean literal: TRUE or FALSE (case-insensitive)
  Parser<Expression> get _boolLiteral {
    final trueP = string('TRUE', ignoreCase: true)
        .skip(after: _notWordChar)
        .map((_) => const BoolLiteral(true) as Expression);
    final falseP = string('FALSE', ignoreCase: true)
        .skip(after: _notWordChar)
        .map((_) => const BoolLiteral(false) as Expression);
    return [trueP, falseP].toChoiceParser();
  }

  /// String literal: 'text' with '' for escaped single-quote
  /// Also supports "text" (double-quoted, TwinCAT WSTRING convention).
  Parser<Expression> get _stringLiteral {
    // Single-quoted string: '' maps to a single quote, anything else that's not '
    final escapedQuote = string("''").map((_) => "'");
    final normalChar = any().where((c) => c != "'");
    final stringContent = (escapedQuote | normalChar).star();

    final singleQuoted = (char("'") & stringContent & char("'")).map((values) {
      final chars = values[1] as List;
      return StringLiteral(chars.join());
    });

    // Double-quoted string: "" maps to a single double-quote
    final dblEscapedQuote = string('""').map((_) => '"');
    final dblNormalChar = any().where((c) => c != '"');
    final dblStringContent = (dblEscapedQuote | dblNormalChar).star();

    final doubleQuoted = (char('"') & dblStringContent & char('"')).map((values) {
      final chars = values[1] as List;
      return StringLiteral(chars.join(), isWide: true);
    });

    return [singleQuoted, doubleQuoted]
        .toChoiceParser()
        .map((e) => e as Expression);
  }

  /// Direct address: %MW100, %I0.3.5, %QX0.0, %MD50
  Parser<Expression> get _directAddress {
    return (char('%') &
        pattern('IiQqMmXx') &
        pattern('WwDdFfBbLlXx').optional() &
        pattern('0-9.').plus())
        .flatten()
        .map((s) => DirectAddressExpression(s.toUpperCase()));
  }

  /// Identifier: letter or underscore followed by letters, digits, underscores.
  /// Must not be a reserved keyword.
  Parser<String> get _identifierToken {
    return ((letter() | char('_')) & (letter() | digit() | char('_')).star())
        .flatten()
        .where((name) => !_isKeyword(name),
            message: 'identifier expected (got keyword)');
  }

  static bool _isKeyword(String name) {
    switch (name.toUpperCase()) {
      case 'AND':
      case 'OR':
      case 'XOR':
      case 'NOT':
      case 'MOD':
      case 'TRUE':
      case 'FALSE':
      case 'THIS':
      case 'SUPER':
        return true;
      default:
        return false;
    }
  }

  /// Member name or bit index for member access expressions.
  /// TwinCAT allows `.0` through `.31` for bit-level access on WORD/BYTE types.
  /// Tries identifier first, then falls back to digit sequence for bit access.
  Parser<String> get _memberNameOrBitIndex {
    final bitIndex = digit().plus().flatten() as Parser<String>;
    return [_identifierToken, bitIndex].toChoiceParser();
  }

  // ================================================================
  // Expression parser with ExpressionBuilder
  // ================================================================

  void _buildParsers() {
    // Recursive reference for the expression
    final exprRef = undefined<Expression>();

    // --- Call arguments ---
    // Output capture: name => expr
    final outputArg = (_identifierToken.trim() &
        string('=>').trim() &
        exprRef.trim())
        .map((values) => CallArgument(
        name: values[0] as String,
        value: values[2] as Expression,
        isOutput: true));

    // Named arg: name := expr
    final namedArg = (_identifierToken.trim() &
        string(':=').trim() &
        exprRef.trim())
        .map((values) => CallArgument(
        name: values[0] as String, value: values[2] as Expression));

    // Positional arg
    final positionalArg = exprRef.trim()
        .map((e) => CallArgument(value: e));

    final callArg = [
      outputArg as Parser<CallArgument>,
      namedArg as Parser<CallArgument>,
      positionalArg as Parser<CallArgument>,
    ].toChoiceParser();
    final argList = callArg
        .starSeparated(char(',').trim())
        .map((separated) => separated.elements.cast<CallArgument>().toList());

    // --- Function call: identifier followed by '(' args ')' ---
    final funcCall = (_identifierToken.trim() &
        char('(').trim() &
        argList &
        char(')').trim())
        .map((values) {
      final name = values[0] as String;
      final args = values[2] as List<CallArgument>;
      return FunctionCallExpression(name: name, arguments: args) as Expression;
    });

    // --- Parenthesized expression ---
    final parenExpr = (char('(').trim() & exprRef.trim() & char(')').trim())
        .map((values) => ParenExpression(values[1] as Expression) as Expression);

    // --- THIS / SUPER ---
    final thisExpr = _kw('THIS')
        .map((_) => const ThisExpression() as Expression);
    final superExpr = _kw('SUPER')
        .map((_) => const SuperExpression() as Expression);

    // --- Primary expression (atoms) ---
    // Order: try most specific patterns first
    final primary = [
      // Time/date literals (before typed/base to prevent prefix conflicts)
      _timeLiteral.trim(),
      _dateTimeLiteral.trim(),
      _timeOfDayLiteral.trim(),
      _dateLiteral.trim(),
      // Typed literals: INT#42, REAL#3.14
      _typedLiteral.trim(),
      // Base literals: 16#FF, 2#1010, 8#77
      _baseLiteral.trim(),
      // Bool (before identifier to avoid TRUE/FALSE becoming identifiers)
      _boolLiteral.trim(),
      // String literal
      _stringLiteral.trim(),
      // Real literal (before int to catch decimal point)
      _realLiteral.trim(),
      // Integer literal
      _intLiteral.trim(),
      // Direct address
      _directAddress.trim(),
      // THIS and SUPER
      thisExpr,
      superExpr,
      // Function call (before bare identifier)
      funcCall,
      // Identifier
      _identifierToken.trim().map((name) => IdentifierExpression(name) as Expression),
      // Parenthesized expression
      parenExpr,
    ].toChoiceParser();

    // --- ExpressionBuilder ---
    final builder = ExpressionBuilder<Expression>();
    builder.primitive(primary);

    // Group 1: Parentheses (wrapper)
    builder.group().wrapper(
        char('(').trim(),
        char(')').trim(),
        (l, value, r) => ParenExpression(value));

    // Group 2: Postfix operators (^, .member, [index])
    // All at same precedence, left-to-right
    builder.group()
      ..postfix(
          char('^').trim(),
          (expr, _) => DerefExpression(expr))
      ..postfix(
          (char('.').trim() & _memberNameOrBitIndex.trim())
              .map((values) => values[1] as String),
          (target, member) =>
              MemberAccessExpression(target: target, member: member))
      ..postfix(
          (char('[').trim() &
              exprRef.starSeparated(char(',').trim()).map((s) => s.elements) &
              char(']').trim())
              .map((values) => values[1] as List<Expression>),
          (target, indices) =>
              ArrayAccessExpression(target: target, indices: indices))
      ..postfix(
          (char('(').trim() &
              argList &
              char(')').trim())
              .map((values) => values[1] as List<CallArgument>),
          (target, args) {
        if (target is IdentifierExpression) {
          return FunctionCallExpression(name: target.name, arguments: args);
        }
        // Shouldn't normally happen if funcCall primitive is tried first,
        // but allows chaining like result(...)
        return FunctionCallExpression(name: target.toString(), arguments: args);
      });

    // Group 3: Unary prefix: - (negate) and NOT
    builder.group()
      ..prefix(char('-').trim(),
          (_, operand) =>
              UnaryExpression(operator: UnaryOp.negate, operand: operand))
      ..prefix(_kw('NOT'),
          (_, operand) =>
              UnaryExpression(operator: UnaryOp.not_, operand: operand));

    // Group 4: Power ** (right-associative, Beckhoff)
    builder.group().right(string('**').trim(),
        (left, _, right) =>
            BinaryExpression(left: left, operator: BinaryOp.power, right: right));

    // Group 5: Multiplication level: *, /, MOD
    builder.group()
      ..left(
          // * but not **
          (char('*').skip(after: char('*').not())).trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.multiply, right: right))
      ..left(char('/').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.divide, right: right))
      ..left(_kw('MOD'),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.modulo, right: right));

    // Group 6: Addition level: +, -
    builder.group()
      ..left(char('+').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.add, right: right))
      ..left(char('-').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.subtract, right: right));

    // Group 7: Comparison: =, <>, <, >, <=, >=
    builder.group()
      ..left(string('<>').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.notEqual, right: right))
      ..left(string('<=').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.lessOrEqual, right: right))
      ..left(string('>=').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.greaterOrEqual, right: right))
      ..left(
          // < but not <= or <>
          (char('<').skip(after: anyOf('=>').not())).trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.lessThan, right: right))
      ..left(
          // > but not >=
          (char('>').skip(after: char('=').not())).trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.greaterThan, right: right))
      ..left(
          // = but not => or :=
          char('=').trim(),
          (left, _, right) =>
              BinaryExpression(left: left, operator: BinaryOp.equal, right: right));

    // Group 8: NOT (lower precedence than comparison for boolean context)
    // Note: NOT is already handled as prefix in Group 3 with negate.
    // The IEC precedence has NOT above comparison but below arithmetic.
    // Since we defined it in Group 3 (above power), it naturally has higher
    // precedence than comparisons. This is correct for: NOT a > 0 => NOT(a) > 0
    // But per the tests, NOT a AND b => (NOT a) AND b, which works with NOT
    // having higher precedence than AND.

    // Group 9: AND
    builder.group().left(_kw('AND'),
        (left, _, right) =>
            BinaryExpression(left: left, operator: BinaryOp.and_, right: right));

    // Group 10: XOR
    builder.group().left(_kw('XOR'),
        (left, _, right) =>
            BinaryExpression(left: left, operator: BinaryOp.xor_, right: right));

    // Group 11: OR (lowest precedence)
    builder.group().left(_kw('OR'),
        (left, _, right) =>
            BinaryExpression(left: left, operator: BinaryOp.or_, right: right));

    final built = builder.build();
    exprRef.set(built);
    _expression = built;

    // ==============================================================
    // Statement parsers
    // ==============================================================

    // Recursive reference for nested statement lists
    final stmtRef = undefined<Statement>();
    final stmtsRef = undefined<List<Statement>>();

    final semi = char(';').trim();

    // --- Empty statement: just a semicolon ---
    final emptyStmt = semi
        .map((_) => const EmptyStatement() as Statement);

    // --- EXIT / RETURN / CONTINUE ---
    final exitStmt = (_kw('EXIT') & semi)
        .map((_) => const ExitStatement() as Statement);
    final returnStmt = (_kw('RETURN') & semi)
        .map((_) => const ReturnStatement() as Statement);
    final continueStmt = (_kw('CONTINUE') & semi)
        .map((_) => const ContinueStatement() as Statement);

    // --- IF statement ---
    final elsifClause = (_kw('ELSIF') & _expression.trim() & _kw('THEN') & stmtsRef)
        .map((values) => ElsifClause(
              condition: values[1] as Expression,
              body: values[3] as List<Statement>,
            ));
    final elseClause = (_kw('ELSE') & stmtsRef)
        .map((values) => values[1] as List<Statement>);
    final ifStmt = (_kw('IF') &
            _expression.trim() &
            _kw('THEN') &
            stmtsRef &
            elsifClause.star() &
            elseClause.optional() &
            _kw('END_IF') &
            semi.optional())
        .map((values) => IfStatement(
              condition: values[1] as Expression,
              thenBody: values[3] as List<Statement>,
              elsifClauses: (values[4] as List).cast<ElsifClause>(),
              elseBody: values[5] as List<Statement>?,
            ) as Statement);

    // --- CASE statement ---
    // Case match: value or range (lo..hi)
    // We need a simple expression for case match values — use the full
    // expression parser but then check for range syntax.
    final caseRangeMatch = (_expression.trim() &
            string('..').trim() &
            _expression.trim())
        .map((values) => CaseRangeMatch(
              lower: values[0] as Expression,
              upper: values[2] as Expression,
            ) as CaseMatch);
    final caseValueMatch = _expression.trim()
        .map((e) => CaseValueMatch(e) as CaseMatch);
    final caseMatch = caseRangeMatch | caseValueMatch;
    final caseMatchList = caseMatch
        .plusSeparated(char(',').trim())
        .map((s) => s.elements.cast<CaseMatch>().toList());

    final caseClause = (caseMatchList & char(':').trim() & stmtsRef)
        .map((values) => CaseClause(
              matches: values[0] as List<CaseMatch>,
              body: values[2] as List<Statement>,
            ));
    final caseElse = (_kw('ELSE') & stmtsRef)
        .map((values) => values[1] as List<Statement>);
    final caseStmt = (_kw('CASE') &
            _expression.trim() &
            _kw('OF') &
            caseClause.star() &
            caseElse.optional() &
            _kw('END_CASE') &
            semi.optional())
        .map((values) => CaseStatement(
              expression: values[1] as Expression,
              clauses: (values[3] as List).cast<CaseClause>(),
              elseBody: values[4] as List<Statement>?,
            ) as Statement);

    // --- FOR loop ---
    final byClause = (_kw('BY') & _expression.trim())
        .map((values) => values[1] as Expression);
    final forStmt = (_kw('FOR') &
            _identifierToken.trim() &
            string(':=').trim() &
            _expression.trim() &
            _kw('TO') &
            _expression.trim() &
            byClause.optional() &
            _kw('DO') &
            stmtsRef &
            _kw('END_FOR') &
            semi.optional())
        .map((values) => ForStatement(
              variable: values[1] as String,
              start: values[3] as Expression,
              end: values[5] as Expression,
              step: values[6] as Expression?,
              body: values[8] as List<Statement>,
            ) as Statement);

    // --- WHILE loop ---
    final whileStmt = (_kw('WHILE') &
            _expression.trim() &
            _kw('DO') &
            stmtsRef &
            _kw('END_WHILE') &
            semi.optional())
        .map((values) => WhileStatement(
              condition: values[1] as Expression,
              body: values[3] as List<Statement>,
            ) as Statement);

    // --- REPEAT loop ---
    final repeatStmt = (_kw('REPEAT') &
            stmtsRef &
            _kw('UNTIL') &
            _expression.trim() &
            _kw('END_REPEAT') &
            semi.optional())
        .map((values) => RepeatStatement(
              body: values[1] as List<Statement>,
              condition: values[3] as Expression,
            ) as Statement);

    // --- Target expression (lvalue) parser ---
    // Parses identifier or direct-address with postfix .member and [index]
    // chains, but NOT function call postfix. Used for assignment targets
    // and FB call targets.
    final targetAtom = [
      _directAddress.trim() as Parser<Expression>,
      _identifierToken.trim()
          .map((name) => IdentifierExpression(name) as Expression),
    ].toChoiceParser();

    final memberPostfix = (char('.').trim() & _memberNameOrBitIndex.trim())
        .map((values) => values[1] as String);
    final indexPostfix = (char('[').trim() &
            exprRef.plusSeparated(char(',').trim()).map((s) => s.elements) &
            char(']').trim())
        .map((values) => values[1] as List<Expression>);

    // A single postfix operation — either .member or [index]
    final targetPostfix = [
      memberPostfix.map((m) => _TargetPostfix.member(m)),
      indexPostfix.map((i) => _TargetPostfix.index(i)),
    ].toChoiceParser();

    final targetExpr = (targetAtom & targetPostfix.star()).map((values) {
      var expr = values[0] as Expression;
      final postfixes = values[1] as List;
      for (final p in postfixes) {
        final postfix = p as _TargetPostfix;
        switch (postfix) {
          case _MemberPostfix(:final name):
            expr = MemberAccessExpression(target: expr, member: name);
          case _IndexPostfix(:final indices):
            expr = ArrayAccessExpression(target: expr, indices: indices);
        }
      }
      return expr;
    });

    // --- FB call statement ---
    // target(args);  where target is identifier or member access chain
    final fbOutputArg = (_identifierToken.trim() &
            string('=>').trim() &
            _expression.trim())
        .map((values) => CallArgument(
              name: values[0] as String,
              value: values[2] as Expression,
              isOutput: true,
            ));
    final fbNamedArg = (_identifierToken.trim() &
            string(':=').trim() &
            _expression.trim())
        .map((values) => CallArgument(
              name: values[0] as String,
              value: values[2] as Expression,
            ));
    final fbPositionalArg = _expression.trim()
        .map((e) => CallArgument(value: e));
    final fbArg = [
      fbOutputArg as Parser<CallArgument>,
      fbNamedArg as Parser<CallArgument>,
      fbPositionalArg as Parser<CallArgument>,
    ].toChoiceParser();
    final fbArgList = fbArg
        .starSeparated(char(',').trim())
        .map((s) => s.elements.cast<CallArgument>().toList());

    final fbCallStmt = (targetExpr &
            char('(').trim() &
            fbArgList &
            char(')').trim() &
            semi)
        .map((values) => FbCallStatement(
              target: values[0] as Expression,
              arguments: values[2] as List<CallArgument>,
            ) as Statement);

    // --- Assignment statement ---
    // target := expr; or target S= expr; or target R= expr; or target REF= expr;
    final assignOp = [
      string(':=').trim().map((_) => AssignmentOp.assign),
      string('REF=', ignoreCase: true).trim().map((_) => AssignmentOp.refAssign),
      string('S=').trim().map((_) => AssignmentOp.set_),
      string('R=').trim().map((_) => AssignmentOp.reset),
    ].toChoiceParser();

    final assignStmt = (targetExpr &
            assignOp &
            _expression.trim() &
            semi)
        .map((values) => AssignmentStatement(
              target: values[0] as Expression,
              operator: values[1] as AssignmentOp,
              value: values[2] as Expression,
            ) as Statement);

    // --- Skip inline comment markers injected by _stripComments ---
    final skipCommentMarker = (string('/*COMMENT:') &
            any().starLazy(string('*/')).flatten() & string('*/'))
        .trim()
        .map((_) => const EmptyStatement() as Statement);

    // --- Expression statement ---
    // A bare expression followed by a semicolon (TwinCAT allows this).
    // e.g. `GVL_IO.Input1.q_xState.1;` or `myVar;`
    // Uses targetExpr (identifier/direct-address with postfix chains) rather
    // than the full _expression parser. A negative lookahead rejects
    // statement-boundary keywords (END_IF, THEN, ELSE, etc.) that would
    // otherwise be consumed as bare identifier statements.
    final exprStmt = (_notStatementKeyword & targetExpr & semi)
        .map((values) => ExpressionStatement(values[1] as Expression) as Statement);

    // --- Combined statement parser ---
    // Order matters: try structured statements first (IF, CASE, FOR, etc.),
    // then control flow keywords, then FB call (before assignment since both
    // start with a target expression, and FB call is more specific due to
    // the '(' that follows), then assignment, then expression statement
    // (bare expression with no assignment), then empty.
    final statement = [
      skipCommentMarker,
      ifStmt,
      caseStmt,
      forStmt,
      whileStmt,
      repeatStmt,
      exitStmt,
      returnStmt,
      continueStmt,
      fbCallStmt,
      assignStmt,
      exprStmt,
      emptyStmt,
    ].toChoiceParser();

    stmtRef.set(statement);
    stmtsRef.set(stmtRef.star());
    _statement = statement;
    _statements = stmtsRef;
  }

  /// Parse a standalone expression string and return an AST node.
  ///
  /// Throws [FormatException] on invalid input.
  Expression parseExpression(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw FormatException(
          'Failed to parse expression: empty input', input, 0);
    }
    final result = _expression.end().parse(trimmed);
    if (result is Success<Expression>) return result.value;
    throw FormatException(
        'Failed to parse expression: ${result.message}',
        input,
        result.position);
  }

  /// Parse a single statement string and return an AST node.
  ///
  /// Throws [FormatException] on invalid input.
  Statement parseStatement(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw FormatException(
          'Failed to parse statement: empty input', input, 0);
    }
    final result = _statement.end().parse(trimmed);
    if (result is Success<Statement>) return result.value;
    throw FormatException(
        'Failed to parse statement: ${result.message}',
        input,
        result.position);
  }

  /// Parse multiple statements and return a list of AST nodes.
  ///
  /// Throws [FormatException] on invalid input.
  List<Statement> parseStatements(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return [];
    final result = _statements.end().parse(trimmed);
    if (result is Success<List<Statement>>) return result.value;
    throw FormatException(
        'Failed to parse statements: ${result.message}',
        input,
        result.position);
  }

  /// Parse a single VAR...END_VAR block and return a [VarBlock].
  ///
  /// Throws [FormatException] on invalid input.
  VarBlock parseVarBlock(String input) {
    final cleaned = _stripComments(input).trim();
    if (cleaned.isEmpty) {
      throw FormatException('Failed to parse var block: empty input', input, 0);
    }
    final result = _varBlock.end().parse(cleaned);
    if (result is Success<VarBlock>) return result.value;
    throw FormatException(
        'Failed to parse var block: ${result.message}',
        input,
        result.position);
  }

  /// Parse a complete PROGRAM, FUNCTION_BLOCK, or FUNCTION declaration.
  ///
  /// Throws [FormatException] on invalid input.
  PouDeclaration parsePou(String input) {
    final cleaned = _stripComments(input).trim();
    if (cleaned.isEmpty) {
      throw FormatException('Failed to parse POU: empty input', input, 0);
    }
    final result = _pouDeclaration.end().parse(cleaned);
    if (result is Success<PouDeclaration>) return result.value;
    throw FormatException(
        'Failed to parse POU: ${result.message}',
        input,
        result.position);
  }

  /// Parse a complete ST source file with multiple declarations.
  ///
  /// Returns a [CompilationUnit] containing all declarations found.
  /// Throws [FormatException] on invalid input.
  CompilationUnit parse(String input) {
    final cleaned = _stripComments(input).trim();
    if (cleaned.isEmpty) return const CompilationUnit([]);
    final result = _compilationUnit.end().parse(cleaned);
    if (result is Success<CompilationUnit>) return result.value;
    throw FormatException(
        'Failed to parse compilation unit: ${result.message}',
        input,
        result.position);
  }

  /// Parse a TYPE...END_TYPE declaration.
  ///
  /// Throws [FormatException] on invalid input.
  TypeDeclaration parseTypeDeclaration(String input) {
    final cleaned = _stripComments(input).trim();
    if (cleaned.isEmpty) {
      throw FormatException(
          'Failed to parse type declaration: empty input', input, 0);
    }
    final result = _typeDeclaration.end().parse(cleaned);
    if (result is Success<TypeDeclaration>) return result.value;
    throw FormatException(
        'Failed to parse type declaration: ${result.message}',
        input,
        result.position);
  }

  // ================================================================
  // Comment stripping
  // ================================================================

  String _stripComments(String input) {
    final buf = StringBuffer();
    var i = 0;
    while (i < input.length) {
      if (i + 1 < input.length && input[i] == '(' && input[i + 1] == '*') {
        i += 2;
        while (i + 1 < input.length &&
            !(input[i] == '*' && input[i + 1] == ')')) {
          i++;
        }
        if (i + 1 < input.length) i += 2;
        buf.write(' ');
        continue;
      }
      if (i + 1 < input.length && input[i] == '/' && input[i + 1] == '/') {
        final bufStr = buf.toString();
        final lastNl = bufStr.lastIndexOf('\n');
        final lineStart = lastNl >= 0 ? lastNl + 1 : 0;
        final lineContent = bufStr.substring(lineStart);
        if (lineContent.contains(';')) {
          i += 2;
          if (i < input.length && input[i] == ' ') i++;
          final commentStart = i;
          while (i < input.length && input[i] != '\n') i++;
          final commentText = input.substring(commentStart, i).trimRight();
          buf.write('/*COMMENT:$commentText*/');
        } else {
          i += 2;
          while (i < input.length && input[i] != '\n') i++;
        }
        continue;
      }
      if (input[i] == "'") {
        buf.write(input[i]);
        i++;
        while (i < input.length) {
          if (input[i] == "'" && i + 1 < input.length && input[i + 1] == "'") {
            buf.write("''");
            i += 2;
          } else if (input[i] == "'") {
            buf.write("'");
            i++;
            break;
          } else {
            buf.write(input[i]);
            i++;
          }
        }
        continue;
      }
      // Double-quoted strings (TwinCAT WSTRING convention)
      if (input[i] == '"') {
        buf.write(input[i]);
        i++;
        while (i < input.length) {
          if (input[i] == '"' && i + 1 < input.length && input[i + 1] == '"') {
            buf.write('""');
            i += 2;
          } else if (input[i] == '"') {
            buf.write('"');
            i++;
            break;
          } else {
            buf.write(input[i]);
            i++;
          }
        }
        continue;
      }
      buf.write(input[i]);
      i++;
    }
    return buf.toString();
  }

  // ================================================================
  // Declaration parsers
  // ================================================================

  Parser<String> get _declIdentifier {
    return ((letter() | char('_')) & (letter() | digit() | char('_')).star())
        .flatten()
        .trim();
  }

  static String _normalizeTypeName(String name) {
    final upper = name.toUpperCase();
    const wellKnown = {
      'BOOL', 'BYTE', 'WORD', 'DWORD', 'LWORD',
      'SINT', 'INT', 'DINT', 'LINT',
      'USINT', 'UINT', 'UDINT', 'ULINT',
      'REAL', 'LREAL', 'STRING', 'WSTRING',
      'EBOOL',
    };
    return wellKnown.contains(upper) ? upper : name;
  }

  void _buildDeclarationParsers() {
    // --- Pragmas ---
    // Parse the entire pragma as text between { and }, then extract name/value.
    // This avoids issues with unescaped apostrophes in pragma values
    // (e.g. {attribute 'OPC.UA.DA.Description' := 'Ceiling LED'S'}).
    _pragma = (char('{').trim() &
            any().starLazy(char('}')).flatten() &
            char('}').trim())
        .map((values) {
      final inner = (values[1] as String).trim();
      // Expected format: attribute 'name' [:= 'value']
      // Strip 'attribute' prefix (case-insensitive)
      var text = inner;
      if (text.toLowerCase().startsWith('attribute')) {
        text = text.substring('attribute'.length).trim();
      }
      // Extract name: first quoted string
      String name = text;
      String? value;
      final nameMatch = RegExp(r"'([^']*(?:'{2}[^']*)*)'").firstMatch(text);
      if (nameMatch != null) {
        name = nameMatch.group(1)!;
        final afterName = text.substring(nameMatch.end).trim();
        // Check for := 'value'
        if (afterName.startsWith(':=')) {
          final valueText = afterName.substring(2).trim();
          final valueMatch = RegExp(r"'(.*)'").firstMatch(valueText);
          if (valueMatch != null) {
            value = valueMatch.group(1)!;
          }
        }
      }
      return Pragma(name: name, value: value);
    });

    // --- Type specifications ---
    final typeSpecRef = undefined<TypeSpec>();

    final stringTypeLength = ((char('[').trim() &
                    digit().plus().flatten().map(int.parse) &
                    char(']').trim()) |
                (char('(').trim() &
                    digit().plus().flatten().map(int.parse) &
                    char(')').trim()))
        .map((values) => values[1] as int);

    final stringType = (string('WSTRING', ignoreCase: true)
                .skip(after: _notWordChar).trim().map((_) => true) |
            string('STRING', ignoreCase: true)
                .skip(after: _notWordChar).trim().map((_) => false))
        .seq(stringTypeLength.optional())
        .map((values) => StringType(
              isWide: values[0] as bool,
              maxLength: values[1] as int?) as TypeSpec);

    final arrayRange = (_expression.trim() & string('..').trim() &
            _expression.trim())
        .map((values) => ArrayRange(
              lower: values[0] as Expression,
              upper: values[2] as Expression));
    final arrayRangeList = arrayRange.plusSeparated(char(',').trim())
        .map((s) => s.elements.cast<ArrayRange>().toList());

    final arrayType = (_kw('ARRAY') & char('[').trim() & arrayRangeList &
            char(']').trim() & _kw('OF') & typeSpecRef)
        .map((values) => ArrayType(
              ranges: values[2] as List<ArrayRange>,
              elementType: values[5] as TypeSpec) as TypeSpec);

    final pointerType = (_kw('POINTER') & _kw('TO') & typeSpecRef)
        .map((values) => PointerType(values[2] as TypeSpec) as TypeSpec);

    final referenceType = (_kw('REFERENCE') & _kw('TO') & typeSpecRef)
        .map((values) => ReferenceType(values[2] as TypeSpec) as TypeSpec);

    // Dotted type name: supports Namespace.TypeName (e.g. Centroid_Core.FB_AlarmHandler)
    final dottedTypeName = _declIdentifier
        .plusSeparated(char('.').trim())
        .map((s) => s.elements.cast<String>().join('.'));

    final simpleType = dottedTypeName.map((name) {
      final upper = name.toUpperCase();
      const wellKnown = {
        'BOOL', 'BYTE', 'WORD', 'DWORD', 'LWORD',
        'SINT', 'INT', 'DINT', 'LINT',
        'USINT', 'UINT', 'UDINT', 'ULINT',
        'REAL', 'LREAL', 'TIME', 'DATE', 'TOD', 'DT',
        'STRING', 'WSTRING', 'EBOOL',
        'ANY', 'ANY_INT', 'ANY_REAL', 'ANY_NUM', 'ANY_BIT',
      };
      return SimpleType(wellKnown.contains(upper) ? upper : name) as TypeSpec;
    });

    // --- Inline enum type for VAR declarations ---
    // e.g. state : (IDLE, RUNNING, DONE);
    // e.g. state : (A := 0, B := 1) UINT;
    final inlineEnumValueInit = (string(':=').trim() & _expression.trim())
        .map((values) => values[1] as Expression);
    final inlineEnumValue = (_declIdentifier & inlineEnumValueInit.optional())
        .map((values) => EnumValue(
              name: values[0] as String, value: values[1] as Expression?));
    final inlineEnumValueList = inlineEnumValue.plusSeparated(char(',').trim())
        .map((s) => s.elements.cast<EnumValue>().toList());

    // Optional base type after closing paren (e.g. UINT, INT, DINT)
    final inlineEnumBaseType = _declIdentifier
        .map((name) => _normalizeTypeName(name));

    final inlineEnumType = (char('(').trim() & inlineEnumValueList &
            char(')').trim() & inlineEnumBaseType.optional())
        .map((values) => InlineEnumType(
              values: values[1] as List<EnumValue>,
              baseType: values[3] as String?) as TypeSpec);

    final typeSpec = [stringType, arrayType, pointerType, referenceType,
        inlineEnumType, simpleType].toChoiceParser();
    typeSpecRef.set(typeSpec);
    _typeSpec = typeSpec;

    // --- AT clause ---
    // Supports concrete addresses (%MW100, %I0.3.5) and TwinCAT
    // wildcard auto-link addresses (%I*, %Q*, %IW*, %QW*, etc.)
    final atAddress = (char('%') & pattern('IiQqMmXx') &
            pattern('WwDdFfBbLlXx').optional() &
            (char('*') | pattern('0-9.').plus()))
        .flatten().map((s) => s.toUpperCase()).trim();

    // --- Inline comment marker ---
    final inlineComment = (string('/*COMMENT:') &
            any().starLazy(string('*/')).flatten() & string('*/'))
        .map((values) => values[1] as String).trim();

    // --- Variable declaration ---
    final varDeclNames = _declIdentifier
        .plusSeparated(char(',').trim())
        .map((s) => s.elements.cast<String>().toList());

    final atClause = (_kw('AT') & atAddress)
        .map((values) => values[1] as String);

    // --- Aggregate (struct/FB) initializer: (field := value, ...) ---
    final fieldInit = (_declIdentifier & string(':=').trim() & _expression.trim())
        .map((values) => FieldInit(
              name: values[0] as String,
              value: values[2] as Expression));
    final aggregateInit = (char('(').trim() &
            fieldInit.plusSeparated(char(',').trim())
                .map((s) => s.elements.cast<FieldInit>().toList()) &
            char(')').trim())
        .map((values) =>
            AggregateInitializer(values[1] as List<FieldInit>) as Expression);

    final initClause = (string(':=').trim() &
            (aggregateInit | _expression.trim()))
        .map((values) => values[1] as Expression);

    // --- FB constructor args: Type(arg1, arg2, ...) ---
    // Named arg: name := expr
    final fbCtorNamedArg = (_declIdentifier & string(':=').trim() &
            _expression.trim())
        .map((values) => CallArgument(
              name: values[0] as String,
              value: values[2] as Expression));
    // Positional arg
    final fbCtorPositionalArg = _expression.trim()
        .map((e) => CallArgument(value: e));
    final fbCtorArg = [
      fbCtorNamedArg as Parser<CallArgument>,
      fbCtorPositionalArg as Parser<CallArgument>,
    ].toChoiceParser();
    final fbCtorArgList = fbCtorArg
        .plusSeparated(char(',').trim())
        .map((s) => s.elements.cast<CallArgument>().toList());
    final fbConstructorInit = (char('(').trim() & fbCtorArgList &
            char(')').trim())
        .map((values) =>
            FbConstructorInit(values[1] as List<CallArgument>) as Expression);

    final varDecl = (_pragma.star().trim() & varDeclNames &
            atClause.optional() & char(':').trim() & typeSpec &
            fbConstructorInit.optional() &
            initClause.optional() & char(';').trim() &
            inlineComment.optional())
        .map((values) {
      final pragmas = (values[0] as List).cast<Pragma>();
      final names = values[1] as List<String>;
      final at = values[2] as String?;
      final type = values[4] as TypeSpec;
      final fbCtorInit = values[5] as Expression?;
      final init = values[6] as Expression?;
      final comment = values[8] as String?;
      // FB constructor init takes precedence if both are somehow present;
      // normally only one of fbCtorInit or init will be set.
      final effectiveInit = fbCtorInit ?? init;
      return names.map((name) => VarDeclaration(
            name: name, typeSpec: type, atAddress: at,
            initialValue: effectiveInit, comment: comment, pragmas: pragmas,
          )).toList();
    });

    // --- VAR block ---
    final varSectionKw = [
      _kw('VAR_INPUT').map((_) => VarSection.varInput),
      _kw('VAR_OUTPUT').map((_) => VarSection.varOutput),
      _kw('VAR_IN_OUT').map((_) => VarSection.varInOut),
      _kw('VAR_GLOBAL').map((_) => VarSection.varGlobal),
      _kw('VAR_TEMP').map((_) => VarSection.varTemp),
      _kw('VAR_INST').map((_) => VarSection.varInst),
      _kw('VAR_STAT').map((_) => VarSection.varStat),
      _kw('VAR').map((_) => VarSection.var_),
    ].toChoiceParser();

    final varQualifier = [
      _kw('RETAIN').map((_) => VarQualifier.retain),
      _kw('NON_RETAIN').map((_) => VarQualifier.nonRetain),
      _kw('PERSISTENT').map((_) => VarQualifier.persistent),
      _kw('CONSTANT').map((_) => VarQualifier.constant),
    ].toChoiceParser();

    _varBlock = (varSectionKw & varQualifier.star() & varDecl.star() &
            _kw('END_VAR'))
        .map((values) {
      final section = values[0] as VarSection;
      final qualifiers = (values[1] as List).cast<VarQualifier>();
      final declLists = (values[2] as List).cast<List<VarDeclaration>>();
      return VarBlock(
        section: section, qualifiers: qualifiers,
        declarations: declLists.expand((l) => l).toList());
    });

    // --- Access modifiers ---
    final accessModifier = [
      _kw('PUBLIC').map((_) => AccessModifier.public_),
      _kw('PRIVATE').map((_) => AccessModifier.private_),
      _kw('PROTECTED').map((_) => AccessModifier.protected_),
      _kw('INTERNAL').map((_) => AccessModifier.internal_),
    ].toChoiceParser();

    final abstractKw = _kw('ABSTRACT').map((_) => true);
    final finalKw = _kw('FINAL').map((_) => true);

    // --- Method ---
    final methodReturnType = (char(':').trim() & _declIdentifier)
        .map((values) => _normalizeTypeName(values[1] as String));

    _methodDeclaration = (_kw('METHOD') & accessModifier.optional() &
            abstractKw.optional() & finalKw.optional() &
            _declIdentifier & methodReturnType.optional() &
            _varBlock.star().trim() & _statements.trim() &
            _kw('END_METHOD'))
        .map((values) => MethodDeclaration(
              name: values[4] as String,
              accessModifier: values[1] as AccessModifier?,
              isAbstract: values[2] as bool? ?? false,
              isFinal: values[3] as bool? ?? false,
              returnType: values[5] as String?,
              varBlocks: (values[6] as List).cast<VarBlock>(),
              body: values[7] as List<Statement>));

    // --- Property ---
    final propertyGetter = (_kw('GET') & _varBlock.star().trim() &
            _statements.trim() & _kw('END_GET'))
        .map((values) => PropertyAccessor(
              varBlocks: (values[1] as List).cast<VarBlock>(),
              body: values[2] as List<Statement>));

    final propertySetter = (_kw('SET') & _varBlock.star().trim() &
            _statements.trim() & _kw('END_SET'))
        .map((values) => PropertyAccessor(
              varBlocks: (values[1] as List).cast<VarBlock>(),
              body: values[2] as List<Statement>));

    _propertyDeclaration = (_kw('PROPERTY') & accessModifier.optional() &
            _declIdentifier & char(':').trim() & _declIdentifier &
            propertyGetter.optional() & propertySetter.optional() &
            _kw('END_PROPERTY'))
        .map((values) => PropertyDeclaration(
              name: values[2] as String,
              typeName: _normalizeTypeName(values[4] as String),
              accessModifier: values[1] as AccessModifier?,
              getter: values[5] as PropertyAccessor?,
              setter: values[6] as PropertyAccessor?));

    // --- Action ---
    _actionDeclaration = (_kw('ACTION') & _declIdentifier &
            char(':').optional().trim() & _statements.trim() &
            _kw('END_ACTION'))
        .map((values) => ActionDeclaration(
              name: values[1] as String,
              body: values[3] as List<Statement>));

    // --- Interface ---
    final ifaceExtendsClause = (_kw('EXTENDS') & _declIdentifier)
        .map((values) => values[1] as String);

    final ifaceProperty = (_kw('PROPERTY') & accessModifier.optional() &
            _declIdentifier & char(':').trim() & _declIdentifier &
            propertyGetter.optional() & propertySetter.optional() &
            _kw('END_PROPERTY').optional())
        .map((values) => PropertyDeclaration(
              name: values[2] as String,
              typeName: _normalizeTypeName(values[4] as String),
              accessModifier: values[1] as AccessModifier?,
              getter: values[5] as PropertyAccessor?,
              setter: values[6] as PropertyAccessor?));

    final ifaceMember = [
      _methodDeclaration.map((m) => m as Object),
      ifaceProperty.map((p) => p as Object),
    ].toChoiceParser();

    _interfaceDeclaration = (_kw('INTERFACE') & _declIdentifier &
            ifaceExtendsClause.optional() & ifaceMember.star().trim() &
            _kw('END_INTERFACE'))
        .map((values) {
      final members = values[3] as List;
      return InterfaceDeclaration(
        name: values[1] as String,
        extendsFrom: values[2] as String?,
        methods: members.whereType<MethodDeclaration>().toList(),
        properties: members.whereType<PropertyDeclaration>().toList());
    });

    // --- POU body members ---
    final pouBodyMember = [
      _methodDeclaration.map((m) => m as Object),
      _propertyDeclaration.map((p) => p as Object),
      _actionDeclaration.map((a) => a as Object),
    ].toChoiceParser();

    final pouBodyContent =
        (pouBodyMember | _statement.map((s) => s as Object)).star().trim();

    final extendsClause = (_kw('EXTENDS') & _declIdentifier)
        .map((values) => values[1] as String);
    final implementsClause = (_kw('IMPLEMENTS') &
            _declIdentifier.plusSeparated(char(',').trim())
                .map((s) => s.elements.cast<String>().toList()))
        .map((values) => values[1] as List<String>);

    // --- PROGRAM ---
    // Leading pragmas (e.g. {attribute 'OPC.UA.DA.StructuredType' := '1'}) before POU keyword
    final programDecl = (_pragma.star().trim() &
            _kw('PROGRAM') & _declIdentifier &
            _varBlock.star().trim() & pouBodyContent & _kw('END_PROGRAM'))
        .map((values) {
      final bodyItems = values[4] as List;
      return PouDeclaration(
        pouType: PouType.program, name: values[2] as String,
        varBlocks: (values[3] as List).cast<VarBlock>(),
        body: bodyItems.whereType<Statement>().toList(),
        methods: bodyItems.whereType<MethodDeclaration>().toList(),
        properties: bodyItems.whereType<PropertyDeclaration>().toList(),
        actions: bodyItems.whereType<ActionDeclaration>().toList());
    });

    // --- FUNCTION_BLOCK ---
    final fbDecl = (_pragma.star().trim() &
            _kw('FUNCTION_BLOCK') & accessModifier.optional() &
            abstractKw.optional() & finalKw.optional() &
            _declIdentifier & extendsClause.optional() &
            implementsClause.optional() & _varBlock.star().trim() &
            pouBodyContent & _kw('END_FUNCTION_BLOCK'))
        .map((values) {
      final bodyItems = values[9] as List;
      return PouDeclaration(
        pouType: PouType.functionBlock,
        name: values[5] as String,
        accessModifier: values[2] as AccessModifier?,
        isAbstract: values[3] as bool? ?? false,
        isFinal: values[4] as bool? ?? false,
        extendsFrom: values[6] as String?,
        implementsList: values[7] as List<String>? ?? [],
        varBlocks: (values[8] as List).cast<VarBlock>(),
        body: bodyItems.whereType<Statement>().toList(),
        methods: bodyItems.whereType<MethodDeclaration>().toList(),
        properties: bodyItems.whereType<PropertyDeclaration>().toList(),
        actions: bodyItems.whereType<ActionDeclaration>().toList());
    });

    // --- FUNCTION ---
    final funcReturnType = (char(':').trim() & _declIdentifier)
        .map((values) => _normalizeTypeName(values[1] as String));

    final funcDecl = (_pragma.star().trim() &
            _kw('FUNCTION') & _declIdentifier &
            funcReturnType.optional() & _varBlock.star().trim() &
            pouBodyContent & _kw('END_FUNCTION'))
        .map((values) {
      final bodyItems = values[5] as List;
      return PouDeclaration(
        pouType: PouType.function_, name: values[2] as String,
        returnType: values[3] as String?,
        varBlocks: (values[4] as List).cast<VarBlock>(),
        body: bodyItems.whereType<Statement>().toList());
    });

    _pouDeclaration = [programDecl, fbDecl, funcDecl].toChoiceParser();

    // --- TYPE declarations ---
    final enumValueInit = (string(':=').trim() & _expression.trim())
        .map((values) => values[1] as Expression);
    final enumValue = (_declIdentifier & enumValueInit.optional())
        .map((values) => EnumValue(
              name: values[0] as String, value: values[1] as Expression?));
    final enumValueList = enumValue.plusSeparated(char(',').trim())
        .map((s) => s.elements.cast<EnumValue>().toList());

    // Optional base type after closing paren for TYPE enums
    // e.g. (NORMAL := 0, FORCED_LOW := 1) UINT;
    final enumBaseType = _declIdentifier
        .map((name) => _normalizeTypeName(name));

    final enumDef = (char('(').trim() & enumValueList & char(')').trim() &
            enumBaseType.optional() & char(';').trim())
        .map((values) =>
            EnumDefinition(
              values: values[1] as List<EnumValue>,
              baseType: values[3] as String?,
            ) as TypeDefinition);

    final structField = (_pragma.star().trim() & _declIdentifier &
            char(':').trim() & typeSpec &
            initClause.optional() & char(';').trim())
        .map((values) => FieldDeclaration(
              name: values[1] as String,
              typeSpec: values[3] as TypeSpec,
              initialValue: values[4] as Expression?));

    final structDef = (_kw('STRUCT') & structField.star() & _kw('END_STRUCT'))
        .map((values) => StructDefinition(
              (values[1] as List).cast<FieldDeclaration>()) as TypeDefinition);

    final aliasDef = (typeSpec & char(';').trim())
        .map((values) =>
            AliasDefinition(values[0] as TypeSpec) as TypeDefinition);

    _typeDeclaration = (_pragma.star().trim() & _kw('TYPE') &
            _declIdentifier & char(':').trim() &
            (enumDef | structDef | aliasDef) & _kw('END_TYPE'))
        .map((values) => TypeDeclaration(
              name: values[2] as String,
              definition: values[4] as TypeDefinition));

    // --- Global Variable Declaration ---
    _globalVarDeclaration = (_pragma.star().trim() & _varBlock)
        .where((values) =>
            (values[1] as VarBlock).section == VarSection.varGlobal)
        .map((values) {
      final pragmas = (values[0] as List).cast<Pragma>();
      final block = values[1] as VarBlock;
      return GlobalVarDeclaration(
        qualifiedOnly: pragmas.any((p) => p.name == 'qualified_only'),
        varBlocks: [block]);
    });

    // --- Top-level declaration ---
    _declaration = [
      _interfaceDeclaration.map((d) => d as Declaration),
      _pouDeclaration.map((d) => d as Declaration),
      _typeDeclaration.map((d) => d as Declaration),
      _globalVarDeclaration.map((d) => d as Declaration),
    ].toChoiceParser();

    // --- Compilation unit ---
    _compilationUnit = _declaration.star().trim()
        .map((decls) => CompilationUnit(decls));
  }

  // ================================================================
  // Error-recovery parsing
  // ================================================================

  /// Synchronization keywords for top-level error recovery.
  static final _syncPattern = RegExp(
    r'\b(PROGRAM|FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE|VAR_GLOBAL)\b',
    caseSensitive: false,
  );

  /// Parse a complete ST source file with error recovery.
  ///
  /// Returns a [ParseResult] with the best-effort AST and any errors
  /// encountered. On unrecognized syntax, skips to the next
  /// synchronization point (POU keyword, TYPE, VAR_GLOBAL) and records
  /// the skipped text as an [ErrorNode].
  ///
  /// Never throws — all errors are captured in [ParseResult.errors].
  ParseResult parseResilient(String input) {
    final errors = <ParseError>[];
    final declarations = <Declaration>[];
    var remaining = input;
    var globalOffset = 0;

    remaining = _skipLeadingWhitespace(remaining);
    globalOffset += input.length - remaining.length - (input.length - input.trimLeft().length - (input.length - remaining.length - (input.length - input.length)));
    // Simpler: just track how much we consumed
    globalOffset = input.length - remaining.length;

    while (remaining.trim().isNotEmpty) {
      // Try to parse a declaration using the strict parse path.
      // Since declaration parsers may be stubs, we catch both parse
      // failures and UnimplementedError.
      Declaration? parsed;
      int consumedChars = 0;
      bool parseSucceeded = false;

      try {
        // Try to match a POU-like block by finding its END_ keyword
        final pouMatch = _tryParsePouBlock(remaining);
        if (pouMatch != null) {
          parsed = pouMatch.declaration;
          consumedChars = pouMatch.consumedChars;
          parseSucceeded = true;
        }
      } on UnimplementedError {
        // Declaration parsers are stubs — fall through to error recovery
      } catch (_) {
        // Any other parse error — fall through to error recovery
      }

      if (parseSucceeded && parsed != null) {
        declarations.add(parsed);
        remaining = remaining.substring(consumedChars);
        globalOffset += consumedChars;
        remaining = _skipLeadingWhitespace(remaining);
        globalOffset += (remaining.length - remaining.length); // no-op, trimming below
        final trimmed = _skipLeadingWhitespace(remaining);
        globalOffset += remaining.length - trimmed.length;
        remaining = trimmed;
      } else {
        // Error recovery: find next synchronization point
        final syncPoint = _findNextSyncPoint(remaining);
        final skipped = remaining.substring(0, syncPoint).trim();
        final lineInfo = _calculateLineInfo(input, globalOffset);

        if (skipped.isNotEmpty) {
          final error = ParseError(
            message: 'Unexpected syntax',
            position: globalOffset,
            line: lineInfo.$1,
            column: lineInfo.$2,
            skippedText: skipped,
          );
          errors.add(error);
          declarations.add(ErrorNode(skippedText: skipped, error: error));
        }

        remaining = remaining.substring(syncPoint);
        globalOffset += syncPoint;
        final trimmed = _skipLeadingWhitespace(remaining);
        globalOffset += remaining.length - trimmed.length;
        remaining = trimmed;
      }
    }

    return ParseResult(
      unit: CompilationUnit(declarations),
      errors: errors,
    );
  }

  /// Try to parse a POU block (PROGRAM...END_PROGRAM, etc.) from the
  /// beginning of [text]. Returns null if the text doesn't start with
  /// a recognized POU keyword or if parsing fails.
  _PouParseResult? _tryParsePouBlock(String text) {
    final trimmed = text.trimLeft();
    final upper = trimmed.toUpperCase();

    // Determine POU type and end keyword
    String? startKw;
    String? endKw;
    PouType? pouType;

    if (upper.startsWith('PROGRAM') &&
        _isKeywordBoundary(trimmed, 'PROGRAM'.length)) {
      startKw = 'PROGRAM';
      endKw = 'END_PROGRAM';
      pouType = PouType.program;
    } else if (upper.startsWith('FUNCTION_BLOCK') &&
        _isKeywordBoundary(trimmed, 'FUNCTION_BLOCK'.length)) {
      startKw = 'FUNCTION_BLOCK';
      endKw = 'END_FUNCTION_BLOCK';
      pouType = PouType.functionBlock;
    } else if (upper.startsWith('FUNCTION') &&
        _isKeywordBoundary(trimmed, 'FUNCTION'.length)) {
      startKw = 'FUNCTION';
      endKw = 'END_FUNCTION';
      pouType = PouType.function_;
    } else {
      return null;
    }

    // Find the matching END_ keyword
    final endPattern = RegExp('\\b$endKw\\b', caseSensitive: false);
    final endMatch = endPattern.firstMatch(trimmed);
    if (endMatch == null) return null;

    final blockEnd = endMatch.end;
    final blockText = trimmed.substring(0, blockEnd);

    // Extract the POU name (word after the start keyword)
    final afterKw = trimmed.substring(startKw.length).trimLeft();
    final nameMatch = RegExp(r'^(\w+)').firstMatch(afterKw);
    final name = nameMatch?.group(1) ?? 'unknown';

    // Try to parse VAR blocks and body within the POU
    final varBlocks = <VarBlock>[];
    final bodyStatements = <Statement>[];

    // Extract content between header and END_ keyword
    final headerEnd = trimmed.indexOf(name) + name.length;
    final innerText = trimmed.substring(headerEnd, endMatch.start).trim();

    // Try to parse VAR blocks from inner text
    _parseVarBlocksResilient(innerText, varBlocks);

    // Try to parse body statements (text after last END_VAR or after header)
    final lastEndVar = RegExp(r'\bEND_VAR\b', caseSensitive: false);
    final lastEndVarMatch = lastEndVar.allMatches(innerText).lastOrNull;
    final bodyText = lastEndVarMatch != null
        ? innerText.substring(lastEndVarMatch.end).trim()
        : (varBlocks.isEmpty ? innerText : '');

    if (bodyText.isNotEmpty) {
      _parseStatementsResilient(bodyText, bodyStatements);
    }

    // Calculate how many chars were consumed from the original text
    final leadingWhitespace = text.length - trimmed.length;
    final consumed = leadingWhitespace + blockEnd;

    return _PouParseResult(
      declaration: PouDeclaration(
        pouType: pouType,
        name: name,
        varBlocks: varBlocks,
        body: bodyStatements,
      ),
      consumedChars: consumed,
    );
  }

  /// Try to parse VAR...END_VAR blocks from inner POU text.
  void _parseVarBlocksResilient(String text, List<VarBlock> results) {
    final varPattern = RegExp(
      r'\b(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR_GLOBAL|VAR_TEMP|VAR_INST|VAR_STAT|VAR)\b',
      caseSensitive: false,
    );
    final endVarPattern = RegExp(r'\bEND_VAR\b', caseSensitive: false);

    var remaining = text;
    while (remaining.isNotEmpty) {
      final varMatch = varPattern.firstMatch(remaining);
      if (varMatch == null) break;

      final sectionKw = varMatch.group(1)!.toUpperCase();
      final section = _varSectionFromKeyword(sectionKw);

      final afterVar = remaining.substring(varMatch.end);
      final endVarMatch = endVarPattern.firstMatch(afterVar);
      if (endVarMatch == null) break;

      final declText = afterVar.substring(0, endVarMatch.start).trim();
      final declarations = _parseVarDeclarationsResilient(declText);

      results.add(VarBlock(
        section: section,
        declarations: declarations,
      ));

      remaining = afterVar.substring(endVarMatch.end);
    }
  }

  /// Parse individual variable declarations within a VAR block,
  /// skipping any that fail.
  List<VarDeclaration> _parseVarDeclarationsResilient(String text) {
    final results = <VarDeclaration>[];
    // Split on semicolons and try to parse each declaration
    final parts = text.split(';');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      // Simple pattern: name : TYPE
      final declMatch = RegExp(r'^(\w+)\s*:\s*(\w+(?:\[.*?\])?)').firstMatch(trimmed);
      if (declMatch != null) {
        final name = declMatch.group(1)!;
        final typeName = declMatch.group(2)!;

        // Check for initial value after :=
        Expression? initialValue;
        final initMatch = RegExp(r':=\s*(.+)$').firstMatch(trimmed);
        if (initMatch != null) {
          try {
            initialValue = parseExpression(initMatch.group(1)!.trim());
          } catch (_) {
            // Skip initial value if it can't be parsed
          }
        }

        results.add(VarDeclaration(
          name: name,
          typeSpec: SimpleType(typeName),
          initialValue: initialValue,
        ));
      }
    }
    return results;
  }

  /// Parse statements resiliently — on failure, skip to the next semicolon
  /// and try again.
  void _parseStatementsResilient(String text, List<Statement> results) {
    var remaining = text.trim();
    while (remaining.isNotEmpty) {
      // First, try parsing the full remaining text
      try {
        final stmts = parseStatements(remaining);
        results.addAll(stmts);
        return; // All remaining text parsed successfully
      } catch (_) {
        // Try parsing just the first statement
      }

      // Try to parse a single statement from the start
      final singleResult = _statement.parse(remaining);
      if (singleResult is Success<Statement>) {
        results.add(singleResult.value);
        remaining = remaining.substring(singleResult.position).trimLeft();
        continue;
      }

      // Failed — skip to next semicolon
      final semiIdx = remaining.indexOf(';');
      if (semiIdx == -1) break; // No more semicolons, give up
      remaining = remaining.substring(semiIdx + 1).trimLeft();
    }
  }

  VarSection _varSectionFromKeyword(String kw) {
    switch (kw) {
      case 'VAR_INPUT':
        return VarSection.varInput;
      case 'VAR_OUTPUT':
        return VarSection.varOutput;
      case 'VAR_IN_OUT':
        return VarSection.varInOut;
      case 'VAR_GLOBAL':
        return VarSection.varGlobal;
      case 'VAR_TEMP':
        return VarSection.varTemp;
      case 'VAR_INST':
        return VarSection.varInst;
      case 'VAR_STAT':
        return VarSection.varStat;
      default:
        return VarSection.var_;
    }
  }

  /// Check if position after a keyword is a word boundary.
  bool _isKeywordBoundary(String text, int pos) {
    if (pos >= text.length) return true;
    final ch = text[pos];
    return !RegExp(r'[a-zA-Z0-9_]').hasMatch(ch);
  }

  /// Find the next synchronization point in the text.
  /// Skips at least one character to ensure forward progress.
  int _findNextSyncPoint(String text) {
    if (text.length <= 1) return text.length;
    final match = _syncPattern.firstMatch(text.substring(1));
    return match != null ? match.start + 1 : text.length;
  }

  /// Calculate line and column numbers from a global offset.
  (int line, int column) _calculateLineInfo(String source, int offset) {
    final clamped = offset.clamp(0, source.length);
    final prefix = source.substring(0, clamped);
    final line = '\n'.allMatches(prefix).length + 1;
    final lastNewline = prefix.lastIndexOf('\n');
    final column = lastNewline == -1 ? clamped + 1 : clamped - lastNewline;
    return (line, column);
  }

  /// Strip leading whitespace (including newlines).
  String _skipLeadingWhitespace(String text) => text.trimLeft();
}

/// Helper sealed class for building target expressions with postfix chains.
sealed class _TargetPostfix {
  const _TargetPostfix();
  factory _TargetPostfix.member(String name) = _MemberPostfix;
  factory _TargetPostfix.index(List<Expression> indices) = _IndexPostfix;
}

class _MemberPostfix extends _TargetPostfix {
  final String name;
  const _MemberPostfix(this.name);
}

class _IndexPostfix extends _TargetPostfix {
  final List<Expression> indices;
  const _IndexPostfix(this.indices);
}

/// Result of attempting to parse a POU block.
class _PouParseResult {
  final Declaration declaration;
  final int consumedChars;
  const _PouParseResult({required this.declaration, required this.consumedChars});
}
