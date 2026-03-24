import '../interfaces/plc_code_index.dart';

/// Parse variable declarations from structured text VAR blocks.
///
/// Handles VAR, VAR_INPUT, VAR_OUTPUT, VAR_IN_OUT, VAR_GLOBAL,
/// VAR_TEMP, VAR_INST, and VAR_STAT sections.
/// Keywords are matched case-insensitively per IEC 61131-3.
List<ParsedVariable> parseVariables(String declaration) {
  final variables = <ParsedVariable>[];

  final varBlockPattern = RegExp(
    r'(VAR(?:_INPUT|_OUTPUT|_IN_OUT|_GLOBAL|_TEMP|_INST|_STAT)?)\b'
    r'(.*?)'
    r'END_VAR',
    dotAll: true,
    caseSensitive: false,
  );

  for (final block in varBlockPattern.allMatches(declaration)) {
    final section = block.group(1)!.toUpperCase();
    final body = block.group(2)!;

    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip lines that are only comments or attributes
      if (trimmed.startsWith('//') ||
          trimmed.startsWith('(*') ||
          trimmed.startsWith('{')) {
        continue;
      }

      // Match variable declarations: name [AT %addr] : type [:= init] ;
      final varMatch = RegExp(
        r'^(\w+)\s*(?:AT\s+%\S+\s*)?:\s*(.+?)\s*(?::=\s*[^;]*)?\s*;(.*)$',
      ).firstMatch(trimmed);

      if (varMatch != null) {
        final name = varMatch.group(1)!;
        final type = varMatch.group(2)!.trim();
        final remainder = varMatch.group(3) ?? '';

        // Extract inline comment
        String? comment;
        final lineComment = RegExp(r'//\s*(.*)').firstMatch(remainder);
        final blockComment = RegExp(r'\(\*\s*(.*?)\s*\*\)').firstMatch(remainder);

        if (lineComment != null) {
          comment = lineComment.group(1)!.trim();
        } else if (blockComment != null) {
          comment = blockComment.group(1)!.trim();
        }

        variables.add(ParsedVariable(
          name: name,
          type: type,
          section: section,
          comment: comment,
        ));
      }
    }
  }

  return variables;
}

/// Parse a raw .st file (not XML) into a [ParsedCodeBlock].
///
/// Detects PROGRAM, FUNCTION_BLOCK, or FUNCTION header and extracts
/// the block name, variables, implementation, and full source.
/// Returns null for empty or unparseable content.
ParsedCodeBlock? parseStFile(String content, String filePath) {
  if (content.trim().isEmpty) return null;

  // Find the first non-empty, non-comment line to detect block type
  String? type;
  String? name;

  final headerPattern = RegExp(
    r'^\s*(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s+(\w+)',
    caseSensitive: false,
    multiLine: true,
  );

  final headerMatch = headerPattern.firstMatch(content);
  if (headerMatch == null) return null;

  final keyword = headerMatch.group(1)!.toUpperCase();
  name = headerMatch.group(2)!;

  switch (keyword) {
    case 'PROGRAM':
      type = 'Program';
    case 'FUNCTION_BLOCK':
      type = 'FunctionBlock';
    case 'FUNCTION':
      type = 'Function';
    default:
      return null;
  }

  // Parse variables from the content
  final variables = parseVariables(content);

  // Extract implementation: everything after the last END_VAR
  // up to the final END_PROGRAM / END_FUNCTION_BLOCK / END_FUNCTION
  String? implementation;
  final endVarIndex = content.toUpperCase().lastIndexOf('END_VAR');
  if (endVarIndex != -1) {
    final afterEndVar = content.substring(endVarIndex + 'END_VAR'.length);
    final endBlockPattern = RegExp(
      r'END_(?:PROGRAM|FUNCTION_BLOCK|FUNCTION)\b',
      caseSensitive: false,
    );
    final endMatch = endBlockPattern.firstMatch(afterEndVar);
    if (endMatch != null) {
      implementation = afterEndVar.substring(0, endMatch.start).trim();
    } else {
      implementation = afterEndVar.trim();
    }
  }

  // Declaration is from the start to the end of the last END_VAR
  final declaration = endVarIndex != -1
      ? content.substring(0, endVarIndex + 'END_VAR'.length).trim()
      : content.trim();

  return ParsedCodeBlock(
    name: name,
    type: type,
    declaration: declaration,
    implementation: implementation?.isEmpty == true ? null : implementation,
    fullSource: content,
    filePath: filePath,
    variables: variables,
    children: [], // Raw .st files don't have XML child elements
  );
}
