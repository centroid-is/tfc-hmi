// ---------------------------------------------------------------------------
// Call graph builder: extracts variable references and FB instance mappings
// from parsed PLC code blocks using the ST AST parser.
//
// Builds an in-memory call graph data structure that enables:
// - Finding all readers/writers of a variable
// - Mapping FB instances to their types
// - Tracing call chains for a variable
// ---------------------------------------------------------------------------

import '../interfaces/plc_code_index.dart';
import 'st_ast.dart';
import 'st_parser.dart';

/// The kind of reference to a variable.
enum ReferenceKind {
  /// Variable is read (appears on RHS of assignment or in expressions).
  read,

  /// Variable is written (appears on LHS of assignment).
  write,

  /// FB instance is called (appears as target of FB call statement).
  call,
}

/// A reference to a variable from a specific code block.
class VariableReference {
  /// The fully qualified path of the referenced variable.
  final String variablePath;

  /// The kind of reference (read, write, call).
  final ReferenceKind kind;

  /// The name of the code block where this reference occurs.
  final String blockName;

  /// The type of the code block (Program, FunctionBlock, etc.).
  final String blockType;

  /// Line number within the implementation body where this reference occurs.
  /// Null when line numbers have not been resolved (pre-enrichment).
  final int? lineNumber;

  /// The actual source line at [lineNumber], trimmed.
  /// Null when line numbers have not been resolved (pre-enrichment).
  final String? sourceLine;

  const VariableReference({
    required this.variablePath,
    required this.kind,
    required this.blockName,
    required this.blockType,
    this.lineNumber,
    this.sourceLine,
  });

  /// Returns a copy with [lineNumber] and [sourceLine] set.
  VariableReference withSourceLocation(int line, String source) =>
      VariableReference(
        variablePath: variablePath,
        kind: kind,
        blockName: blockName,
        blockType: blockType,
        lineNumber: line,
        sourceLine: source,
      );

  @override
  String toString() => 'VariableReference($kind $variablePath in $blockName)';
}

/// An FB instance declaration mapping instance name to FB type.
class FbInstance {
  /// The instance variable name (e.g. "pump3").
  final String instanceName;

  /// The FB type name (e.g. "FB_PumpControl").
  final String fbTypeName;

  /// The block where this instance is declared.
  final String declaringBlock;

  const FbInstance({
    required this.instanceName,
    required this.fbTypeName,
    required this.declaringBlock,
  });

  @override
  String toString() =>
      'FbInstance($instanceName : $fbTypeName in $declaringBlock)';
}

/// Aggregated call graph data built from PLC code blocks.
///
/// Provides query methods for variable references, FB instances,
/// and call chains. All data is in-memory for v1.
class CallGraphData {
  final List<VariableReference> _references;
  final List<FbInstance> _fbInstances;
  final Map<String, _VariableInfo> _variableIndex;

  CallGraphData._({
    required List<VariableReference> references,
    required List<FbInstance> fbInstances,
    required Map<String, _VariableInfo> variableIndex,
  })  : _references = references,
        _fbInstances = fbInstances,
        _variableIndex = variableIndex;

  /// All variable references extracted from code block implementations.
  List<VariableReference> get references => _references;

  /// All FB instance declarations found across all blocks.
  List<FbInstance> get fbInstances => _fbInstances;

  /// Get all references to a variable by its path.
  ///
  /// The [variablePath] can be:
  /// - Fully qualified: "MAIN.x", "GVL_Main.globalSpeed"
  /// - Member access: "pump3.speed", "GVL.pump3.speed"
  /// - OPC-UA instance path: "MAIN.fbPump.bRunning" where fbPump is an
  ///   FB instance of FB_Pump — resolved to "FB_Pump.bRunning" via the
  ///   FB instance table.
  ///
  /// Searches exact matches, suffix matches, and FB instance-resolved
  /// matches to handle cross-block references where the block name
  /// prefix or instance name may differ from the stored reference.
  List<VariableReference> getReferences(String variablePath) {
    // First, try direct and suffix matching.
    final directMatches = _references.where((r) {
      return r.variablePath == variablePath ||
          r.variablePath.endsWith('.$variablePath') ||
          variablePath.endsWith('.${r.variablePath}');
    }).toList();

    if (directMatches.isNotEmpty) return directMatches;

    // No direct matches — try resolving through FB instance mappings.
    // For a path like "MAIN.fbPump.bRunning":
    //   1. Find that fbPump is an instance of FB_Pump (from _fbInstances)
    //   2. Build the resolved path "FB_Pump.bRunning"
    //   3. Search again with the resolved path
    final parts = variablePath.split('.');
    if (parts.length >= 3) {
      // Try each segment as a potential FB instance name.
      for (var i = 0; i < parts.length - 1; i++) {
        final candidateInstance = parts[i];
        // Find FB instances with this name.
        final matchingInstances = _fbInstances
            .where((fb) => fb.instanceName == candidateInstance)
            .toList();

        for (final inst in matchingInstances) {
          // Build resolved path: replace instance name with FB type name,
          // keep the remaining member segments.
          final memberPath = parts.sublist(i + 1).join('.');
          final resolvedPath = '${inst.fbTypeName}.$memberPath';

          final resolved = _references.where((r) {
            return r.variablePath == resolvedPath ||
                r.variablePath.endsWith('.$resolvedPath') ||
                resolvedPath.endsWith('.${r.variablePath}');
          }).toList();

          if (resolved.isNotEmpty) return resolved;
        }
      }
    }

    return [];
  }

  /// Get all FB instances of a given type.
  ///
  /// Returns empty list if [fbTypeName] is a primitive type or
  /// has no instances.
  List<FbInstance> getInstances(String fbTypeName) {
    return _fbInstances
        .where((i) => i.fbTypeName == fbTypeName)
        .toList();
  }

  /// Get the call chain for a variable — all code that reads or writes it.
  ///
  /// This is a flattened view of getReferences suitable for display
  /// in a "who touches this variable" context.
  List<VariableReference> getCallChain(String variablePath) {
    return getReferences(variablePath);
  }

  /// Get aggregated context for a variable.
  ///
  /// Returns a map with:
  /// - `declaringBlock`: the block where this variable is declared
  /// - `variableType`: the declared type
  /// - `isFbInstance`: whether this is an FB instance
  /// - `fbTypeName`: the FB type name (if FB instance)
  /// - `fbMembers`: list of member variable names (if FB instance)
  /// - `readers`: list of blocks that read this variable
  /// - `writers`: list of blocks that write this variable
  ///
  /// Returns null if the variable is not found in the index.
  ///
  /// Handles MAIN-prefixed OPC-UA paths (e.g. `MAIN.GarageDoor.p_stat_uposition`)
  /// by trying exact match first, then suffix matching against the variable
  /// index. This handles the common case where the OPC-UA path includes the
  /// program name prefix but the variable index stores `Block.varName`.
  Map<String, dynamic>? getVariableContext(String variablePath) {
    final info = _lookupVariableInfo(variablePath);
    if (info == null) return null;

    final refs = getReferences(variablePath);
    final readers = refs
        .where((r) => r.kind == ReferenceKind.read)
        .map((r) => r.blockName)
        .toSet()
        .toList();
    final writers = refs
        .where((r) => r.kind == ReferenceKind.write)
        .map((r) => r.blockName)
        .toSet()
        .toList();

    final result = <String, dynamic>{
      'declaringBlock': info.declaringBlock,
      'variableType': info.variableType,
      'isFbInstance': info.fbTypeName != null,
      'readers': readers,
      'writers': writers,
    };

    if (info.fbTypeName != null) {
      result['fbTypeName'] = info.fbTypeName;
      result['fbMembers'] = info.fbMembers;
    }

    return result;
  }

  /// Look up a variable in the index using exact match first, then
  /// suffix matching for MAIN-prefixed paths.
  ///
  /// For a query like `MAIN.GarageDoor.p_stat_uposition`, this will:
  /// 1. Try exact match: `_variableIndex['MAIN.GarageDoor.p_stat_uposition']`
  /// 2. Try suffix match: find any key K where `variablePath.endsWith('.$K')`
  ///    (e.g. `MAIN.GarageDoor.p_stat_uposition` ends with
  ///    `.FB_GarageDoor.p_stat_uposition` — NO, that won't match because
  ///    the instance name differs from the type name)
  /// 3. Try stripping segments from the front: `GarageDoor.p_stat_uposition`,
  ///    then `p_stat_uposition`
  ///
  /// For the GarageDoor case, step 3 is key: stripping `MAIN.` gives
  /// `GarageDoor.p_stat_uposition`, which won't be in the index either
  /// (the index has `FB_GarageDoor.p_stat_uposition`). But the variable
  /// name `p_stat_uposition` alone won't be unique. So we also check
  /// if any indexed key is a suffix of the query path.
  _VariableInfo? _lookupVariableInfo(String variablePath) {
    // 1. Exact match
    final exact = _variableIndex[variablePath];
    if (exact != null) return exact;

    // 2. Suffix match: find any index key that the query path ends with.
    //    e.g. query = "MAIN.GarageDoor.p_stat_uposition"
    //    index key = "FB_GarageDoor.p_stat_uposition" — doesn't suffix-match.
    //    But index key = "GarageDoor.p_stat_uposition" would.
    for (final entry in _variableIndex.entries) {
      if (variablePath.endsWith('.${entry.key}')) {
        return entry.value;
      }
    }

    // 3. Progressively strip leading segments from the query path.
    //    "MAIN.GarageDoor.p_stat_uposition" -> "GarageDoor.p_stat_uposition"
    //    This handles the case where the instance name in the OPC-UA path
    //    maps to an FB member via the FB instance table.
    var remaining = variablePath;
    while (remaining.contains('.')) {
      final dotIndex = remaining.indexOf('.');
      remaining = remaining.substring(dotIndex + 1);
      final match = _variableIndex[remaining];
      if (match != null) return match;
    }

    // 4. For multi-segment OPC-UA paths like MAIN.Instance.member, try to
    //    resolve through FB instance mapping. Find the instance in the
    //    variable index, get its FB type, then look up FBType.member.
    final parts = variablePath.split('.');
    if (parts.length >= 3) {
      // Try each possible split point for "instance.member" within the path.
      // For "MAIN.GarageDoor.p_stat_uposition":
      //   instance candidates: "MAIN.GarageDoor", "GarageDoor"
      //   member: "p_stat_uposition"
      final memberName = parts.last;
      for (var i = parts.length - 2; i >= 0; i--) {
        // Build the candidate instance path from parts[0..i]
        final instancePath = parts.sublist(0, i + 1).join('.');
        final instanceInfo = _variableIndex[instancePath];
        if (instanceInfo != null && instanceInfo.fbTypeName != null) {
          // Found an FB instance — look up FBType.member
          final fbMemberKey = '${instanceInfo.fbTypeName}.$memberName';
          final fbMemberInfo = _variableIndex[fbMemberKey];
          if (fbMemberInfo != null) return fbMemberInfo;
        }
      }
    }

    return null;
  }
}

/// Internal variable metadata for indexing.
class _VariableInfo {
  final String declaringBlock;
  final String variableType;
  final String? fbTypeName;
  final List<String>? fbMembers;

  const _VariableInfo({
    required this.declaringBlock,
    required this.variableType,
    this.fbTypeName,
    this.fbMembers,
  });
}

/// IEC 61131-3 primitive types that should NOT be treated as FB types.
const _primitiveTypes = {
  'BOOL',
  'BYTE',
  'WORD',
  'DWORD',
  'LWORD',
  'SINT',
  'INT',
  'DINT',
  'LINT',
  'USINT',
  'UINT',
  'UDINT',
  'ULINT',
  'REAL',
  'LREAL',
  'STRING',
  'WSTRING',
  'TIME',
  'DATE',
  'TIME_OF_DAY',
  'TOD',
  'DATE_AND_TIME',
  'DT',
  'ANY',
  'ANY_INT',
  'ANY_REAL',
  'ANY_NUM',
  'ANY_BIT',
  // Schneider-specific
  'EBOOL',
};

/// Builds call graph data from indexed PLC code blocks.
///
/// Uses the ST AST parser to extract references from implementation
/// bodies while keeping the existing regex parser for variable
/// declarations (which it does well).
class CallGraphBuilder {
  final StParser _parser = StParser();

  /// Build call graph data from all indexed blocks.
  ///
  /// 1. Collects all known block names (to identify FB types)
  /// 2. Maps FB instances to their types
  /// 3. Parses implementations with AST parser to extract references
  CallGraphData build(List<PlcCodeBlock> blocks) {
    final references = <VariableReference>[];
    final fbInstances = <FbInstance>[];
    final variableIndex = <String, _VariableInfo>{};

    // Step 1: Collect all known block names as potential FB types.
    // A variable whose type matches a block name is an FB instance.
    final knownBlockNames = <String>{};
    final blockMembersByName = <String, List<String>>{};

    for (final block in blocks) {
      knownBlockNames.add(block.blockName);
      blockMembersByName[block.blockName] =
          block.variables.map((v) => v.variableName).toList();
    }

    // Step 2: Index variables and identify FB instances.
    for (final block in blocks) {
      for (final variable in block.variables) {
        final qualifiedName = '${block.blockName}.${variable.variableName}';
        final typeUpper = variable.variableType.toUpperCase();
        final isFbInstance = knownBlockNames.contains(variable.variableType) &&
            !_primitiveTypes.contains(typeUpper);

        String? fbTypeName;
        List<String>? fbMembers;

        if (isFbInstance) {
          fbTypeName = variable.variableType;
          fbMembers = blockMembersByName[variable.variableType];
          fbInstances.add(FbInstance(
            instanceName: variable.variableName,
            fbTypeName: variable.variableType,
            declaringBlock: block.blockName,
          ));
        }

        variableIndex[qualifiedName] = _VariableInfo(
          declaringBlock: block.blockName,
          variableType: variable.variableType,
          fbTypeName: fbTypeName,
          fbMembers: fbMembers,
        );
      }
    }

    // Step 3: Parse implementations and extract references.
    for (final block in blocks) {
      final impl = block.implementation;
      if (impl == null || impl.trim().isEmpty) continue;

      // Track starting index so we can enrich just this block's refs.
      final startIdx = references.length;

      final statements = _parseStatementsResilient(impl);
      for (final stmt in statements) {
        _extractReferences(
          stmt,
          block.blockName,
          block.blockType,
          references,
        );
      }

      // Enrich references from this block with source line information.
      _enrichWithSourceLocations(references, startIdx, impl);
    }

    return CallGraphData._(
      references: references,
      fbInstances: fbInstances,
      variableIndex: variableIndex,
    );
  }

  /// Parse statements resiliently using the AST parser.
  ///
  /// Falls back to statement-by-statement parsing on failure,
  /// skipping unparseable lines.
  List<Statement> _parseStatementsResilient(String code) {
    try {
      return _parser.parseStatements(code);
    } catch (_) {
      // If full parse fails, try wrapping in a dummy POU for resilient parse
      final wrapped =
          'PROGRAM _dummy_\nVAR\nEND_VAR\n$code\nEND_PROGRAM';
      final result = _parser.parseResilient(wrapped);
      final statements = <Statement>[];
      for (final decl in result.unit.declarations) {
        if (decl is PouDeclaration) {
          statements.addAll(decl.body);
        }
      }
      return statements;
    }
  }

  /// Enrich variable references with source line numbers and source text.
  ///
  /// After AST-based extraction, we match each reference back to its
  /// source line by searching for the variable path (without block
  /// qualification) in the implementation text lines.
  ///
  /// Each reference is matched to a unique source line occurrence using
  /// a consumption model: once a source line is matched to a reference,
  /// it won't be reused. This ensures that 3 assignments to the same
  /// variable on different lines get 3 different line numbers.
  void _enrichWithSourceLocations(
    List<VariableReference> refs,
    int startIdx,
    String implementation,
  ) {
    final lines = implementation.split('\n');

    // Track which line occurrences have been consumed (line -> count used).
    final consumed = <int, int>{};

    for (var i = startIdx; i < refs.length; i++) {
      final ref = refs[i];
      // Skip if already enriched (shouldn't happen, but be safe).
      if (ref.lineNumber != null) continue;

      // Extract the search token: the variable path without block prefix.
      // e.g. "MAIN.x" -> "x", "i_stDimmer.xLightOnOut" stays as is.
      final searchPath = ref.variablePath.contains('.')
          ? ref.variablePath.substring(ref.variablePath.indexOf('.') + 1)
          : ref.variablePath;
      // Also try the full path and the last segment alone.
      final lastSegment = ref.variablePath.contains('.')
          ? ref.variablePath.split('.').last
          : ref.variablePath;

      // Find the first unconsumed line containing this variable reference.
      for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx];
        final lineLower = line.toLowerCase();

        // Check if the line contains the variable path (case-insensitive).
        final found = lineLower.contains(searchPath.toLowerCase()) ||
            lineLower.contains(ref.variablePath.toLowerCase()) ||
            lineLower.contains(lastSegment.toLowerCase());

        if (!found) continue;

        // Check consumption count for this line.
        final usedCount = consumed[lineIdx] ?? 0;

        // Count how many times this variable appears on this line.
        final occurrences =
            _countOccurrences(lineLower, lastSegment.toLowerCase());
        if (usedCount < occurrences) {
          consumed[lineIdx] = usedCount + 1;
          refs[i] = ref.withSourceLocation(lineIdx + 1, line.trim());
          break;
        }
      }
    }
  }

  /// Count non-overlapping occurrences of [needle] in [haystack].
  static int _countOccurrences(String haystack, String needle) {
    var count = 0;
    var start = 0;
    while (true) {
      final idx = haystack.indexOf(needle, start);
      if (idx == -1) break;
      count++;
      start = idx + needle.length;
    }
    return count;
  }

  /// Recursively extract variable references from a statement.
  void _extractReferences(
    Statement stmt,
    String blockName,
    String blockType,
    List<VariableReference> refs,
  ) {
    switch (stmt) {
      case AssignmentStatement(:final target, :final value, :final operator):
        // LHS is written
        final writePath = _expressionToPath(target);
        if (writePath != null) {
          // Qualify with block name if it's a simple identifier
          final qualifiedWrite = writePath.contains('.')
              ? writePath
              : '$blockName.$writePath';
          refs.add(VariableReference(
            variablePath: qualifiedWrite,
            kind: ReferenceKind.write,
            blockName: blockName,
            blockType: blockType,
          ));
        }

        // For array access targets like arr[i], the array base is written
        // and the index expressions are read
        _extractWriteTargetReads(target, blockName, blockType, refs);

        // RHS is read
        _extractReadReferences(value, blockName, blockType, refs);

        // For S= and R= operators, the target is also effectively read
        if (operator == AssignmentOp.set_ || operator == AssignmentOp.reset) {
          if (writePath != null) {
            final qualifiedRead = writePath.contains('.')
                ? writePath
                : '$blockName.$writePath';
            refs.add(VariableReference(
              variablePath: qualifiedRead,
              kind: ReferenceKind.read,
              blockName: blockName,
              blockType: blockType,
            ));
          }
        }

      case FbCallStatement(:final target, :final arguments):
        // The target is called
        final callPath = _expressionToPath(target);
        if (callPath != null) {
          final qualifiedCall = callPath.contains('.')
              ? callPath
              : '$blockName.$callPath';
          refs.add(VariableReference(
            variablePath: qualifiedCall,
            kind: ReferenceKind.call,
            blockName: blockName,
            blockType: blockType,
          ));
        }

        // Arguments: input params are reads, output captures are writes
        for (final arg in arguments) {
          if (arg.isOutput) {
            // Output capture: => variable is written
            final outPath = _expressionToPath(arg.value);
            if (outPath != null) {
              final qualifiedOut = outPath.contains('.')
                  ? outPath
                  : '$blockName.$outPath';
              refs.add(VariableReference(
                variablePath: qualifiedOut,
                kind: ReferenceKind.write,
                blockName: blockName,
                blockType: blockType,
              ));
            }
          } else {
            // Input param: value is read
            _extractReadReferences(arg.value, blockName, blockType, refs);
          }
        }

      case IfStatement(
          :final condition,
          :final thenBody,
          :final elsifClauses,
          :final elseBody,
        ):
        _extractReadReferences(condition, blockName, blockType, refs);
        for (final s in thenBody) {
          _extractReferences(s, blockName, blockType, refs);
        }
        for (final clause in elsifClauses) {
          _extractReadReferences(clause.condition, blockName, blockType, refs);
          for (final s in clause.body) {
            _extractReferences(s, blockName, blockType, refs);
          }
        }
        if (elseBody != null) {
          for (final s in elseBody) {
            _extractReferences(s, blockName, blockType, refs);
          }
        }

      case CaseStatement(:final expression, :final clauses, :final elseBody):
        _extractReadReferences(expression, blockName, blockType, refs);
        for (final clause in clauses) {
          for (final s in clause.body) {
            _extractReferences(s, blockName, blockType, refs);
          }
        }
        if (elseBody != null) {
          for (final s in elseBody) {
            _extractReferences(s, blockName, blockType, refs);
          }
        }

      case ForStatement(
          :final variable,
          :final start,
          :final end,
          :final step,
          :final body,
        ):
        // FOR variable is written (assigned)
        refs.add(VariableReference(
          variablePath: '$blockName.$variable',
          kind: ReferenceKind.write,
          blockName: blockName,
          blockType: blockType,
        ));
        _extractReadReferences(start, blockName, blockType, refs);
        _extractReadReferences(end, blockName, blockType, refs);
        if (step != null) {
          _extractReadReferences(step, blockName, blockType, refs);
        }
        for (final s in body) {
          _extractReferences(s, blockName, blockType, refs);
        }

      case WhileStatement(:final condition, :final body):
        _extractReadReferences(condition, blockName, blockType, refs);
        for (final s in body) {
          _extractReferences(s, blockName, blockType, refs);
        }

      case RepeatStatement(:final condition, :final body):
        _extractReadReferences(condition, blockName, blockType, refs);
        for (final s in body) {
          _extractReferences(s, blockName, blockType, refs);
        }

      case ExpressionStatement(:final expression):
        _extractReadReferences(expression, blockName, blockType, refs);

      case ReturnStatement():
      case ExitStatement():
      case ContinueStatement():
      case EmptyStatement():
        // No variable references
        break;
    }
  }

  /// Extract read references from an expression.
  void _extractReadReferences(
    Expression expr,
    String blockName,
    String blockType,
    List<VariableReference> refs,
  ) {
    switch (expr) {
      case IdentifierExpression(:final name):
        refs.add(VariableReference(
          variablePath: '$blockName.$name',
          kind: ReferenceKind.read,
          blockName: blockName,
          blockType: blockType,
        ));

      case MemberAccessExpression():
        // Full member path (e.g. GVL.pump3.speed)
        final path = _expressionToPath(expr);
        if (path != null) {
          refs.add(VariableReference(
            variablePath: path,
            kind: ReferenceKind.read,
            blockName: blockName,
            blockType: blockType,
          ));
        }

      case BinaryExpression(:final left, :final right):
        _extractReadReferences(left, blockName, blockType, refs);
        _extractReadReferences(right, blockName, blockType, refs);

      case UnaryExpression(:final operand):
        _extractReadReferences(operand, blockName, blockType, refs);

      case ParenExpression(:final inner):
        _extractReadReferences(inner, blockName, blockType, refs);

      case FunctionCallExpression(:final arguments):
        for (final arg in arguments) {
          _extractReadReferences(arg.value, blockName, blockType, refs);
        }

      case ArrayAccessExpression(:final target, :final indices):
        _extractReadReferences(target, blockName, blockType, refs);
        for (final idx in indices) {
          _extractReadReferences(idx, blockName, blockType, refs);
        }

      case DerefExpression(:final target):
        _extractReadReferences(target, blockName, blockType, refs);

      // Literals and constants produce no variable references
      case IntLiteral():
      case RealLiteral():
      case BoolLiteral():
      case StringLiteral():
      case TimeLiteral():
      case DateLiteral():
      case DateTimeLiteral():
      case TimeOfDayLiteral():
      case DirectAddressExpression():
      case ThisExpression():
      case SuperExpression():
      case AggregateInitializer():
      case FbConstructorInit():
        break;
    }
  }

  /// Extract read references from the target side of an assignment.
  ///
  /// For `arr[i] := 0;`, the index `i` is read even though `arr[i]` is written.
  /// For simple identifiers and member access, nothing extra is needed
  /// (already handled by the write path extraction).
  void _extractWriteTargetReads(
    Expression target,
    String blockName,
    String blockType,
    List<VariableReference> refs,
  ) {
    switch (target) {
      case ArrayAccessExpression(:final target, :final indices):
        // The array base variable is written (already handled), but
        // the index expressions are read
        for (final idx in indices) {
          _extractReadReferences(idx, blockName, blockType, refs);
        }
        // Recurse into the target in case it's nested (e.g. a[i][j])
        _extractWriteTargetReads(target, blockName, blockType, refs);
      case MemberAccessExpression():
      case IdentifierExpression():
      case DerefExpression():
        // No extra reads needed for these target types
        break;
      default:
        break;
    }
  }

  /// Convert an expression to a dot-separated variable path.
  ///
  /// Returns null if the expression cannot be represented as a path
  /// (e.g. array access, function call).
  String? _expressionToPath(Expression expr) {
    switch (expr) {
      case IdentifierExpression(:final name):
        return name;
      case MemberAccessExpression(:final target, :final member):
        final targetPath = _expressionToPath(target);
        if (targetPath != null) return '$targetPath.$member';
        return null;
      case DerefExpression(:final target):
        return _expressionToPath(target);
      default:
        return null;
    }
  }
}
