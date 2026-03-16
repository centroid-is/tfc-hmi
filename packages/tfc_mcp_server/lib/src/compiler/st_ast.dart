/// IEC 61131-3 Structured Text AST
///
/// Supports standard IEC, Beckhoff TwinCAT extensions, and Schneider extensions.
/// Uses Dart 3 sealed classes for exhaustive pattern matching.
library;

// ============================================================
// === Top Level ===
// ============================================================

/// Base class for all AST nodes. Sealed for exhaustive matching at the
/// top level; concrete subtypes are further sealed where appropriate.
sealed class StNode {
  const StNode();
}

/// A compilation unit contains one or more POU declarations and type
/// declarations.
class CompilationUnit extends StNode {
  final List<Declaration> declarations;
  const CompilationUnit(this.declarations);

  @override
  String toString() => 'CompilationUnit(${declarations.length} declarations)';
}

// ============================================================
// === Declarations ===
// ============================================================

sealed class Declaration extends StNode {
  const Declaration();
}

/// PROGRAM, FUNCTION_BLOCK, or FUNCTION
class PouDeclaration extends Declaration {
  final PouType pouType;
  final String name;
  final String? returnType; // FUNCTION only
  final String? extendsFrom; // Beckhoff EXTENDS
  final List<String> implementsList; // Beckhoff IMPLEMENTS
  final AccessModifier? accessModifier; // Beckhoff PUBLIC/PRIVATE/etc
  final bool isAbstract; // Beckhoff ABSTRACT
  final bool isFinal; // Beckhoff FINAL
  final List<VarBlock> varBlocks;
  final List<Statement> body;
  final List<MethodDeclaration> methods; // Beckhoff
  final List<PropertyDeclaration> properties; // Beckhoff
  final List<ActionDeclaration> actions;

  const PouDeclaration({
    required this.pouType,
    required this.name,
    this.returnType,
    this.extendsFrom,
    this.implementsList = const [],
    this.accessModifier,
    this.isAbstract = false,
    this.isFinal = false,
    this.varBlocks = const [],
    this.body = const [],
    this.methods = const [],
    this.properties = const [],
    this.actions = const [],
  });

  @override
  String toString() => 'PouDeclaration(${pouType.name} $name)';
}

enum PouType { program, functionBlock, function_ }

enum AccessModifier { public_, private_, protected_, internal_ }

/// Beckhoff METHOD
class MethodDeclaration extends Declaration {
  final String name;
  final String? returnType;
  final AccessModifier? accessModifier;
  final bool isAbstract;
  final bool isFinal;
  final List<VarBlock> varBlocks;
  final List<Statement> body;

  const MethodDeclaration({
    required this.name,
    this.returnType,
    this.accessModifier,
    this.isAbstract = false,
    this.isFinal = false,
    this.varBlocks = const [],
    this.body = const [],
  });

  @override
  String toString() => 'MethodDeclaration($name)';
}

/// Beckhoff PROPERTY with GET/SET
class PropertyDeclaration extends Declaration {
  final String name;
  final String typeName;
  final AccessModifier? accessModifier;
  final PropertyAccessor? getter;
  final PropertyAccessor? setter;

  const PropertyDeclaration({
    required this.name,
    required this.typeName,
    this.accessModifier,
    this.getter,
    this.setter,
  });

  @override
  String toString() => 'PropertyDeclaration($name : $typeName)';
}

class PropertyAccessor extends StNode {
  final List<VarBlock> varBlocks;
  final List<Statement> body;
  const PropertyAccessor({this.varBlocks = const [], this.body = const []});
}

/// ACTION block
class ActionDeclaration extends Declaration {
  final String name;
  final List<Statement> body;
  const ActionDeclaration({required this.name, this.body = const []});

  @override
  String toString() => 'ActionDeclaration($name)';
}

/// Beckhoff INTERFACE
class InterfaceDeclaration extends Declaration {
  final String name;
  final String? extendsFrom;
  final List<MethodDeclaration> methods;
  final List<PropertyDeclaration> properties;

  const InterfaceDeclaration({
    required this.name,
    this.extendsFrom,
    this.methods = const [],
    this.properties = const [],
  });

  @override
  String toString() => 'InterfaceDeclaration($name)';
}

/// TYPE ... END_TYPE (STRUCT, ENUM, or alias)
class TypeDeclaration extends Declaration {
  final String name;
  final TypeDefinition definition;
  const TypeDeclaration({required this.name, required this.definition});

  @override
  String toString() => 'TypeDeclaration($name)';
}

sealed class TypeDefinition extends StNode {
  const TypeDefinition();
}

class StructDefinition extends TypeDefinition {
  final List<FieldDeclaration> fields;
  const StructDefinition(this.fields);

  @override
  String toString() => 'StructDefinition(${fields.length} fields)';
}

class FieldDeclaration extends StNode {
  final String name;
  final TypeSpec typeSpec;
  final Expression? initialValue;

  const FieldDeclaration({
    required this.name,
    required this.typeSpec,
    this.initialValue,
  });

  @override
  String toString() => 'FieldDeclaration($name)';
}

class EnumDefinition extends TypeDefinition {
  final String? baseType;
  final List<EnumValue> values;
  const EnumDefinition({this.baseType, required this.values});

  @override
  String toString() =>
      'EnumDefinition(${values.length} values${baseType != null ? ', base=$baseType' : ''})';
}

class EnumValue extends StNode {
  final String name;
  final Expression? value;
  const EnumValue({required this.name, this.value});

  @override
  String toString() => 'EnumValue($name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnumValue && name == other.name && value == other.value;

  @override
  int get hashCode => Object.hash(name, value);
}

class AliasDefinition extends TypeDefinition {
  final TypeSpec aliasedType;
  const AliasDefinition(this.aliasedType);

  @override
  String toString() => 'AliasDefinition($aliasedType)';
}

/// GVL (Global Variable List) - separate from POU
class GlobalVarDeclaration extends Declaration {
  final String? name; // GVL name (from XML context)
  final bool qualifiedOnly; // Beckhoff {attribute 'qualified_only'}
  final List<VarBlock> varBlocks;

  const GlobalVarDeclaration({
    this.name,
    this.qualifiedOnly = false,
    this.varBlocks = const [],
  });

  @override
  String toString() => 'GlobalVarDeclaration(${name ?? '<unnamed>'})';
}

// ============================================================
// === Variable Declarations ===
// ============================================================

class VarBlock extends StNode {
  final VarSection section;
  final List<VarQualifier> qualifiers; // RETAIN, PERSISTENT, CONSTANT
  final List<VarDeclaration> declarations;

  const VarBlock({
    required this.section,
    this.qualifiers = const [],
    this.declarations = const [],
  });

  @override
  String toString() =>
      'VarBlock(${section.name}, ${declarations.length} declarations)';
}

enum VarSection {
  var_,
  varInput,
  varOutput,
  varInOut,
  varGlobal,
  varTemp,
  varInst,
  varStat,
}

enum VarQualifier { retain, nonRetain, persistent, constant }

class VarDeclaration extends StNode {
  final String name;
  final TypeSpec typeSpec;
  final String? atAddress; // AT %MW100 etc
  final Expression? initialValue;
  final String? comment;
  final List<Pragma> pragmas; // Beckhoff {attribute ...}

  const VarDeclaration({
    required this.name,
    required this.typeSpec,
    this.atAddress,
    this.initialValue,
    this.comment,
    this.pragmas = const [],
  });

  @override
  String toString() => 'VarDeclaration($name : $typeSpec)';
}

// ============================================================
// === Type Specifications ===
// ============================================================

sealed class TypeSpec extends StNode {
  const TypeSpec();
}

/// Simple named type: INT, REAL, BOOL, FB_Motor, EBOOL, ANY_INT, etc.
class SimpleType extends TypeSpec {
  final String name;
  const SimpleType(this.name);

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SimpleType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

/// STRING[n] or STRING(n)
class StringType extends TypeSpec {
  final bool isWide; // WSTRING vs STRING
  final int? maxLength;
  const StringType({this.isWide = false, this.maxLength});

  @override
  String toString() {
    final prefix = isWide ? 'WSTRING' : 'STRING';
    return maxLength != null ? '$prefix[$maxLength]' : prefix;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StringType &&
          isWide == other.isWide &&
          maxLength == other.maxLength;

  @override
  int get hashCode => Object.hash(isWide, maxLength);
}

/// `ARRAY[lo..hi] OF <type>`  (multi-dimensional: `ARRAY[lo1..hi1, lo2..hi2] OF ...`)
class ArrayType extends TypeSpec {
  final List<ArrayRange> ranges;
  final TypeSpec elementType;
  const ArrayType({required this.ranges, required this.elementType});

  @override
  String toString() => 'ARRAY[...] OF $elementType';
}

class ArrayRange extends StNode {
  final Expression lower;
  final Expression upper;
  const ArrayRange({required this.lower, required this.upper});

  @override
  String toString() => '$lower..$upper';
}

/// Inline anonymous enum type in variable declarations:
/// `state : (IDLE, RUNNING, DONE);`
/// `state : (A := 0, B := 1) UINT;`
class InlineEnumType extends TypeSpec {
  final List<EnumValue> values;
  final String? baseType; // optional base type like UINT, INT
  const InlineEnumType({required this.values, this.baseType});

  @override
  String toString() =>
      'InlineEnumType(${values.length} values${baseType != null ? ', base=$baseType' : ''})';
}

/// `POINTER TO <type>` (Beckhoff)
class PointerType extends TypeSpec {
  final TypeSpec targetType;
  const PointerType(this.targetType);

  @override
  String toString() => 'POINTER TO $targetType';
}

/// `REFERENCE TO <type>` (Beckhoff)
class ReferenceType extends TypeSpec {
  final TypeSpec targetType;
  const ReferenceType(this.targetType);

  @override
  String toString() => 'REFERENCE TO $targetType';
}

// ============================================================
// === Statements ===
// ============================================================

sealed class Statement extends StNode {
  const Statement();
}

class AssignmentStatement extends Statement {
  final Expression target;
  final AssignmentOp operator;
  final Expression value;

  const AssignmentStatement({
    required this.target,
    this.operator = AssignmentOp.assign,
    required this.value,
  });

  @override
  String toString() => 'AssignmentStatement($target ${operator.name} $value)';
}

/// Assignment operators: `:=`, `S=`, `R=`, `REF=`
enum AssignmentOp { assign, set_, reset, refAssign }

class IfStatement extends Statement {
  final Expression condition;
  final List<Statement> thenBody;
  final List<ElsifClause> elsifClauses;
  final List<Statement>? elseBody;

  const IfStatement({
    required this.condition,
    required this.thenBody,
    this.elsifClauses = const [],
    this.elseBody,
  });

  @override
  String toString() => 'IfStatement($condition)';
}

class ElsifClause extends StNode {
  final Expression condition;
  final List<Statement> body;
  const ElsifClause({required this.condition, required this.body});

  @override
  String toString() => 'ElsifClause($condition)';
}

class CaseStatement extends Statement {
  final Expression expression;
  final List<CaseClause> clauses;
  final List<Statement>? elseBody;

  const CaseStatement({
    required this.expression,
    required this.clauses,
    this.elseBody,
  });

  @override
  String toString() => 'CaseStatement($expression)';
}

class CaseClause extends StNode {
  final List<CaseMatch> matches;
  final List<Statement> body;
  const CaseClause({required this.matches, required this.body});
}

sealed class CaseMatch extends StNode {
  const CaseMatch();
}

class CaseValueMatch extends CaseMatch {
  final Expression value;
  const CaseValueMatch(this.value);

  @override
  String toString() => 'CaseValueMatch($value)';
}

class CaseRangeMatch extends CaseMatch {
  final Expression lower;
  final Expression upper;
  const CaseRangeMatch({required this.lower, required this.upper});

  @override
  String toString() => 'CaseRangeMatch($lower..$upper)';
}

class ForStatement extends Statement {
  final String variable;
  final Expression start;
  final Expression end;
  final Expression? step;
  final List<Statement> body;

  const ForStatement({
    required this.variable,
    required this.start,
    required this.end,
    this.step,
    required this.body,
  });

  @override
  String toString() => 'ForStatement($variable := $start TO $end)';
}

class WhileStatement extends Statement {
  final Expression condition;
  final List<Statement> body;
  const WhileStatement({required this.condition, required this.body});

  @override
  String toString() => 'WhileStatement($condition)';
}

class RepeatStatement extends Statement {
  final Expression condition;
  final List<Statement> body;
  const RepeatStatement({required this.condition, required this.body});

  @override
  String toString() => 'RepeatStatement(UNTIL $condition)';
}

class FbCallStatement extends Statement {
  final Expression target; // could be identifier or member access chain
  final List<CallArgument> arguments;
  const FbCallStatement({required this.target, this.arguments = const []});

  @override
  String toString() => 'FbCallStatement($target)';
}

class ReturnStatement extends Statement {
  const ReturnStatement();

  @override
  String toString() => 'ReturnStatement';
}

class ExitStatement extends Statement {
  const ExitStatement();

  @override
  String toString() => 'ExitStatement';
}

/// Beckhoff ExST extension
class ContinueStatement extends Statement {
  const ContinueStatement();

  @override
  String toString() => 'ContinueStatement';
}

class EmptyStatement extends Statement {
  const EmptyStatement();

  @override
  String toString() => 'EmptyStatement';
}

/// A bare expression used as a statement (e.g. `myVar;` or `GVL.x.0;`).
/// TwinCAT allows these for reading a value with no assignment.
class ExpressionStatement extends Statement {
  final Expression expression;
  const ExpressionStatement(this.expression);

  @override
  String toString() => 'ExpressionStatement($expression)';
}

// ============================================================
// === Expressions ===
// ============================================================

sealed class Expression extends StNode {
  const Expression();
}

class BinaryExpression extends Expression {
  final Expression left;
  final BinaryOp operator;
  final Expression right;

  const BinaryExpression({
    required this.left,
    required this.operator,
    required this.right,
  });

  @override
  String toString() => 'BinaryExpression($left ${operator.name} $right)';
}

enum BinaryOp {
  add,
  subtract,
  multiply,
  divide,
  modulo,
  equal,
  notEqual,
  lessThan,
  greaterThan,
  lessOrEqual,
  greaterOrEqual,
  and_,
  or_,
  xor_,
  power, // ** (Beckhoff ExST)
}

class UnaryExpression extends Expression {
  final UnaryOp operator;
  final Expression operand;
  const UnaryExpression({required this.operator, required this.operand});

  @override
  String toString() => 'UnaryExpression(${operator.name} $operand)';
}

enum UnaryOp { negate, not_ }

class ParenExpression extends Expression {
  final Expression inner;
  const ParenExpression(this.inner);

  @override
  String toString() => 'ParenExpression($inner)';
}

class IdentifierExpression extends Expression {
  final String name;
  const IdentifierExpression(this.name);

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentifierExpression && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class MemberAccessExpression extends Expression {
  final Expression target;
  final String member;
  const MemberAccessExpression({required this.target, required this.member});

  @override
  String toString() => '$target.$member';
}

class ArrayAccessExpression extends Expression {
  final Expression target;
  final List<Expression> indices;
  const ArrayAccessExpression({required this.target, required this.indices});

  @override
  String toString() => '$target[...]';
}

class FunctionCallExpression extends Expression {
  final String name;
  final List<CallArgument> arguments;
  const FunctionCallExpression({required this.name, this.arguments = const []});

  @override
  String toString() => '$name(${arguments.length} args)';
}

class CallArgument extends StNode {
  final String? name; // named parameter (null = positional)
  final Expression value;
  final bool isOutput; // => (output capture)

  const CallArgument({
    this.name,
    required this.value,
    this.isOutput = false,
  });

  @override
  String toString() {
    final prefix = name != null ? '$name := ' : '';
    final suffix = isOutput ? ' =>' : '';
    return 'CallArgument($prefix$value$suffix)';
  }
}

/// Aggregate (struct/FB) initializer: `(field1 := value1, field2 := value2)`
///
/// Used in VAR declarations for struct and function block initialization:
/// ```
/// fbTime : FB_LocalSystemTime := (bEnable := TRUE, dwCycle := 1);
/// ```
class AggregateInitializer extends Expression {
  final List<FieldInit> fieldInits;
  const AggregateInitializer(this.fieldInits);

  @override
  String toString() =>
      'AggregateInitializer(${fieldInits.map((f) => '${f.name} := ${f.value}').join(', ')})';
}

/// A single field initialization within an [AggregateInitializer].
class FieldInit extends StNode {
  final String name;
  final Expression value;
  const FieldInit({required this.name, required this.value});

  @override
  String toString() => '$name := $value';
}

/// FB constructor initialization with arguments passed to FB_Init:
/// ```
/// Input1 : FB_EL1008('Switch1', 'Switch2', 'Switch3');
/// ```
/// Arguments can be positional or named (using `:=`).
class FbConstructorInit extends Expression {
  final List<CallArgument> arguments;
  const FbConstructorInit(this.arguments);

  @override
  String toString() => 'FbConstructorInit(${arguments.length} args)';
}

class DerefExpression extends Expression {
  final Expression target;
  const DerefExpression(this.target); // target^

  @override
  String toString() => '$target^';
}

class DirectAddressExpression extends Expression {
  final String address; // e.g. "%MW100", "%I0.3.5"
  const DirectAddressExpression(this.address);

  @override
  String toString() => address;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectAddressExpression && address == other.address;

  @override
  int get hashCode => address.hashCode;
}

/// `THIS^` (Beckhoff)
class ThisExpression extends Expression {
  const ThisExpression();

  @override
  String toString() => 'THIS';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ThisExpression;

  @override
  int get hashCode => (ThisExpression).hashCode;
}

/// `SUPER^` (Beckhoff)
class SuperExpression extends Expression {
  const SuperExpression();

  @override
  String toString() => 'SUPER';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SuperExpression;

  @override
  int get hashCode => (SuperExpression).hashCode;
}

// ============================================================
// === Literals ===
// ============================================================

class IntLiteral extends Expression {
  final int value;
  final String? typePrefix; // INT#, DINT#, etc.
  const IntLiteral(this.value, {this.typePrefix});

  @override
  String toString() =>
      typePrefix != null ? '$typePrefix#$value' : value.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntLiteral &&
          value == other.value &&
          typePrefix == other.typePrefix;

  @override
  int get hashCode => Object.hash(value, typePrefix);
}

class RealLiteral extends Expression {
  final double value;
  final String? typePrefix; // REAL#, LREAL#
  const RealLiteral(this.value, {this.typePrefix});

  @override
  String toString() =>
      typePrefix != null ? '$typePrefix#$value' : value.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealLiteral &&
          value == other.value &&
          typePrefix == other.typePrefix;

  @override
  int get hashCode => Object.hash(value, typePrefix);
}

class BoolLiteral extends Expression {
  final bool value;
  const BoolLiteral(this.value);

  @override
  String toString() => value ? 'TRUE' : 'FALSE';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BoolLiteral && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class StringLiteral extends Expression {
  final String value;
  final bool isWide; // WSTRING literal
  const StringLiteral(this.value, {this.isWide = false});

  @override
  String toString() => isWide ? "WSTRING'$value'" : "'$value'";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StringLiteral &&
          value == other.value &&
          isWide == other.isWide;

  @override
  int get hashCode => Object.hash(value, isWide);
}

class TimeLiteral extends Expression {
  final Duration value;
  final String raw;
  const TimeLiteral({required this.value, required this.raw});

  @override
  String toString() => raw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeLiteral && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class DateLiteral extends Expression {
  final String raw;
  const DateLiteral(this.raw);

  @override
  String toString() => raw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DateLiteral && raw == other.raw;

  @override
  int get hashCode => raw.hashCode;
}

class DateTimeLiteral extends Expression {
  final String raw;
  const DateTimeLiteral(this.raw);

  @override
  String toString() => raw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateTimeLiteral && raw == other.raw;

  @override
  int get hashCode => raw.hashCode;
}

class TimeOfDayLiteral extends Expression {
  final String raw;
  const TimeOfDayLiteral(this.raw);

  @override
  String toString() => raw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeOfDayLiteral && raw == other.raw;

  @override
  int get hashCode => raw.hashCode;
}

// ============================================================
// === Pragmas (Beckhoff) ===
// ============================================================

class Pragma extends StNode {
  final String name; // e.g. 'qualified_only'
  final String? value; // e.g. '1' for pack_mode
  const Pragma({required this.name, this.value});

  @override
  String toString() =>
      value != null ? '{attribute \'$name\' := \'$value\'}' : '{attribute \'$name\'}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Pragma && name == other.name && value == other.value;

  @override
  int get hashCode => Object.hash(name, value);
}

// ============================================================
// === Error Recovery ===
// ============================================================

/// Result of parsing that includes both the AST and any errors encountered.
class ParseResult {
  final CompilationUnit unit;
  final List<ParseError> errors;

  const ParseResult({required this.unit, this.errors = const []});

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => errors.isEmpty;
}

/// A parse error with location and context information.
class ParseError {
  final String message;
  final int position;
  final int? line;
  final int? column;
  final String? skippedText;

  const ParseError({
    required this.message,
    required this.position,
    this.line,
    this.column,
    this.skippedText,
  });

  @override
  String toString() => line != null
      ? 'ParseError at line $line:$column: $message'
      : 'ParseError at position $position: $message';
}

/// A placeholder node for code that couldn't be parsed.
class ErrorNode extends Declaration {
  final String skippedText;
  final ParseError error;
  const ErrorNode({required this.skippedText, required this.error});

  @override
  String toString() => 'ErrorNode(${skippedText.length} chars skipped)';
}
