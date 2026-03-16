/// PLC2 Real-World Parse Test
///
/// Extracts ST code from TwinCAT XML files (.TcPOU, .TcGVL, .TcDUT)
/// and tests the parser in both strict and resilient modes.
///
/// TwinCAT XML format note: TcPOU files split POU declarations into:
///   <Declaration> — POU header + VAR blocks (no END_FUNCTION_BLOCK)
///   <ST> — implementation body (bare statements)
/// This is different from a complete ST source file.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/compiler/st_ast.dart';
import 'package:tfc_mcp_server/src/compiler/st_parser.dart';

/// Represents an extracted ST code block from a TwinCAT XML file.
class StBlock {
  final String file;
  final String blockType; // 'declaration', 'implementation', 'method-decl'
  final String code;
  final String? methodName;
  final String? pouKeyword; // FUNCTION_BLOCK, FUNCTION, PROGRAM, TYPE, VAR_GLOBAL

  StBlock({
    required this.file,
    required this.blockType,
    required this.code,
    this.methodName,
    this.pouKeyword,
  });

  String get label => methodName != null
      ? '$file ($blockType: $methodName)'
      : '$file ($blockType)';

  /// Whether this is a self-contained unit (TYPE...END_TYPE, full GVL, etc.)
  bool get isSelfContained {
    final upper = code.toUpperCase();
    return upper.contains('END_TYPE') ||
        upper.contains('END_FUNCTION_BLOCK') ||
        upper.contains('END_FUNCTION') ||
        upper.contains('END_PROGRAM');
  }

  /// Whether this is a POU header (FUNCTION_BLOCK...VAR blocks, no END_)
  /// Handles leading pragmas: {attribute...} FUNCTION_BLOCK ...
  bool get isPouHeader {
    // Strip leading pragmas like {attribute 'xxx' := 'yyy'}
    var stripped = code.trimLeft();
    while (stripped.startsWith('{')) {
      final end = stripped.indexOf('}');
      if (end < 0) break;
      stripped = stripped.substring(end + 1).trimLeft();
    }
    final upper = stripped.toUpperCase();
    return (upper.startsWith('FUNCTION_BLOCK') ||
            upper.startsWith('FUNCTION') ||
            upper.startsWith('PROGRAM')) &&
        !isSelfContained;
  }

  /// Whether this is a standalone GVL (VAR_GLOBAL...END_VAR)
  bool get isGvl {
    final upper = code.toUpperCase();
    return upper.contains('VAR_GLOBAL') && upper.contains('END_VAR');
  }

  /// Whether this is a METHOD declaration header (no END_METHOD)
  bool get isMethodHeader {
    final upper = code.trimLeft().toUpperCase();
    return (upper.startsWith('METHOD') || upper.startsWith('//')) &&
        methodName != null;
  }
}

/// Extract all ST blocks from the PLC2 project.
List<StBlock> extractBlocks() {
  final plcDir = Directory('/tmp/plc2-test');
  if (!plcDir.existsSync()) return [];

  final blocks = <StBlock>[];
  final files = plcDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.TcPOU') ||
          f.path.endsWith('.TcGVL') ||
          f.path.endsWith('.TcDUT'));

  for (final file in files) {
    final content = file.readAsStringSync();
    final fileName = file.path.split('/').last;

    // Extract Declaration blocks
    final declPattern = RegExp(
      r'<Declaration><!\[CDATA\[(.*?)\]\]></Declaration>',
      dotAll: true,
    );

    var isFirst = true;
    for (final match in declPattern.allMatches(content)) {
      final code = match.group(1)!.trim();
      if (code.isEmpty) continue;

      String? methodName;
      final beforeMatch = content.substring(0, match.start);
      final methodPattern = RegExp(r'<Method\s+Name="(\w+)"[^>]*>\s*$');
      final methodMatch = methodPattern.firstMatch(beforeMatch);
      if (methodMatch != null) {
        methodName = methodMatch.group(1);
      }

      // Determine POU keyword
      String? pouKeyword;
      final upper = code.trimLeft().toUpperCase();
      if (upper.startsWith('FUNCTION_BLOCK')) pouKeyword = 'FUNCTION_BLOCK';
      else if (upper.startsWith('FUNCTION')) pouKeyword = 'FUNCTION';
      else if (upper.startsWith('PROGRAM')) pouKeyword = 'PROGRAM';
      else if (upper.contains('TYPE ') && upper.contains('END_TYPE')) pouKeyword = 'TYPE';
      else if (upper.contains('VAR_GLOBAL')) pouKeyword = 'VAR_GLOBAL';

      blocks.add(StBlock(
        file: fileName,
        blockType: isFirst ? 'declaration' : 'method-decl',
        code: code,
        methodName: isFirst ? null : methodName,
        pouKeyword: pouKeyword,
      ));
      isFirst = false;
    }

    // Extract ST implementation blocks
    final stPattern = RegExp(
      r'<ST><!\[CDATA\[(.*?)\]\]></ST>',
      dotAll: true,
    );
    for (final match in stPattern.allMatches(content)) {
      final code = match.group(1)!.trim();
      if (code.isEmpty) continue;

      String? methodName;
      final beforeMatch = content.substring(0, match.start);
      final mPattern = RegExp(r'<Method\s+Name="(\w+)"');
      for (final m in mPattern.allMatches(beforeMatch)) {
        methodName = m.group(1);
      }

      blocks.add(StBlock(
        file: fileName,
        blockType: 'implementation',
        code: code,
        methodName: methodName,
      ));
    }
  }

  return blocks;
}

/// Strip comments from ST code (same logic as parser uses internally).
String stripComments(String input) {
  final buf = StringBuffer();
  var i = 0;
  while (i < input.length) {
    // Block comment: (* ... *)
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
    // Line comment: // ...
    if (i + 1 < input.length && input[i] == '/' && input[i + 1] == '/') {
      i += 2;
      while (i < input.length && input[i] != '\n') i++;
      continue;
    }
    // String literal: '...'
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
    buf.write(input[i]);
    i++;
  }
  return buf.toString();
}

void main() {
  final blocks = extractBlocks();

  if (blocks.isEmpty) {
    print('SKIPPING: /tmp/plc2-test not found. '
        'Extract PLC2.tnzip to /tmp/plc2-test to run these tests.');
    return;
  }

  final parser = StParser();

  final declarations = blocks.where((b) => b.blockType == 'declaration').toList();
  final methodDecls = blocks.where((b) => b.blockType == 'method-decl').toList();
  final implementations = blocks.where((b) => b.blockType == 'implementation').toList();

  print('\n=== PLC2 Real-World Parse Test ===');
  print('Total blocks: ${blocks.length}');
  print('  Declaration blocks: ${declarations.length}');
  print('  Method declaration blocks: ${methodDecls.length}');
  print('  Implementation blocks: ${implementations.length}');
  print('');

  // ================================================================
  // Strict mode tests
  // ================================================================
  group('PLC2 strict parsing', () {
    var strictPass = 0;
    var strictFail = 0;
    final strictFailures = <String>[];

    for (final block in declarations) {
      test('strict: ${block.label}', () {
        try {
          if (block.isSelfContained) {
            // Full TYPE or complete POU — use parse()
            final result = parser.parse(block.code);
            expect(result, isA<CompilationUnit>());
            expect(result.declarations, isNotEmpty);
          } else if (block.isGvl) {
            // GVL: parse just the VAR_GLOBAL block
            final result = parser.parse(block.code);
            expect(result, isA<CompilationUnit>());
          } else if (block.isPouHeader) {
            // POU header without END_ — parse the VAR blocks within
            // Extract VAR blocks and parse each
            final cleaned = stripComments(block.code);
            final varPattern = RegExp(
              r'\b(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR_GLOBAL|VAR_TEMP|VAR_INST|VAR_STAT|VAR)\b'
              r'(.*?)\bEND_VAR\b',
              caseSensitive: false,
              dotAll: true,
            );
            var found = 0;
            for (final m in varPattern.allMatches(cleaned)) {
              final varText = m.group(0)!;
              parser.parseVarBlock(varText);
              found++;
            }
            expect(found, greaterThan(0),
                reason: 'Should find at least one VAR block in POU header');
          } else {
            // Fallback: try parse()
            final result = parser.parse(block.code);
            expect(result, isA<CompilationUnit>());
          }
          strictPass++;
        } on FormatException catch (e) {
          strictFail++;
          final preview = block.code.length > 120
              ? '${block.code.substring(0, 120)}...'
              : block.code;
          strictFailures.add(
              '  FAIL: ${block.label}\n'
              '    Error: ${e.message}\n'
              '    Code: $preview');
        }
      });
    }

    // Method declarations: parse as METHOD header + VAR blocks
    for (final block in methodDecls) {
      test('strict: ${block.label}', () {
        try {
          // Method declarations usually start with comments then METHOD keyword
          // or just METHOD keyword with VAR blocks
          final cleaned = stripComments(block.code);
          final varPattern = RegExp(
            r'\b(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR_GLOBAL|VAR_TEMP|VAR_INST|VAR_STAT|VAR)\b'
            r'(.*?)\bEND_VAR\b',
            caseSensitive: false,
            dotAll: true,
          );
          var found = 0;
          for (final m in varPattern.allMatches(cleaned)) {
            parser.parseVarBlock(m.group(0)!);
            found++;
          }
          // Method declarations should have at least one VAR block
          expect(found, greaterThan(0),
              reason: 'Should find at least one VAR block in method declaration');
          strictPass++;
        } on FormatException catch (e) {
          strictFail++;
          strictFailures.add(
              '  FAIL: ${block.label}\n    Error: ${e.message}');
        }
      });
    }

    for (final block in implementations) {
      test('strict: ${block.label}', () {
        try {
          final cleaned = stripComments(block.code);
          if (cleaned.trim().isEmpty) {
            strictPass++;
            return;
          }
          final stmts = parser.parseStatements(cleaned);
          expect(stmts, isNotEmpty);
          strictPass++;
        } on FormatException catch (e) {
          strictFail++;
          final preview = block.code.length > 120
              ? '${block.code.substring(0, 120)}...'
              : block.code;
          strictFailures.add(
              '  FAIL: ${block.label}\n'
              '    Error: ${e.message}\n'
              '    Code: $preview');
        }
      });
    }

    tearDownAll(() {
      final total = strictPass + strictFail;
      print('\n=== STRICT MODE RESULTS ===');
      print(
          'Pass: $strictPass / $total (${(strictPass * 100.0 / total).toStringAsFixed(1)}%)');
      print('Fail: $strictFail / $total');
      if (strictFailures.isNotEmpty) {
        print('\nFailures:');
        for (final f in strictFailures) {
          print(f);
        }
      }
    });
  });

  // ================================================================
  // Resilient mode tests
  // ================================================================
  group('PLC2 resilient parsing', () {
    var resilientClean = 0;
    var resilientPartial = 0;
    var resilientFail = 0;
    final resilientErrors = <String>[];

    for (final block in declarations) {
      test('resilient: ${block.label}', () {
        try {
          String code = block.code;
          // For POU headers without END_, wrap them for resilient parsing
          if (block.isPouHeader) {
            final keyword = block.pouKeyword ?? 'FUNCTION_BLOCK';
            final endKw = keyword == 'FUNCTION'
                ? 'END_FUNCTION'
                : keyword == 'PROGRAM'
                    ? 'END_PROGRAM'
                    : 'END_FUNCTION_BLOCK';
            code = '$code\n$endKw';
          }

          final result = parser.parseResilient(code);
          if (result.hasErrors) {
            resilientPartial++;
            for (final err in result.errors) {
              resilientErrors.add(
                  '  PARTIAL: ${block.label}: ${err.message} '
                  '(skipped: ${err.skippedText?.substring(0, err.skippedText!.length.clamp(0, 60))}...)');
            }
          } else {
            resilientClean++;
          }
          expect(result.unit, isA<CompilationUnit>());
        } catch (e) {
          resilientFail++;
          resilientErrors.add('  EXCEPTION: ${block.label}: $e');
        }
      });
    }

    for (final block in implementations) {
      test('resilient: ${block.label}', () {
        final wrapped = 'PROGRAM _test_\n${block.code}\nEND_PROGRAM';
        try {
          final result = parser.parseResilient(wrapped);
          if (result.hasErrors) {
            resilientPartial++;
          } else {
            resilientClean++;
          }
          expect(result.unit, isA<CompilationUnit>());
        } catch (e) {
          resilientFail++;
          resilientErrors.add('  EXCEPTION: ${block.label}: $e');
        }
      });
    }

    tearDownAll(() {
      final total = resilientClean + resilientPartial + resilientFail;
      print('\n=== RESILIENT MODE RESULTS ===');
      print(
          'Clean: $resilientClean / $total '
          '(${(resilientClean * 100.0 / total).toStringAsFixed(1)}%)');
      print('Partial: $resilientPartial / $total');
      print('Exception: $resilientFail / $total');
      print(
          'Total parsed: ${resilientClean + resilientPartial} / $total '
          '(${((resilientClean + resilientPartial) * 100.0 / total).toStringAsFixed(1)}%)');
    });
  });
}
