import 'dart:io';

/// A violation detected by the [SafetyScanner].
class SafetyViolation {
  /// Creates a safety violation record.
  SafetyViolation({
    required this.file,
    required this.line,
    required this.reason,
    required this.lineNumber,
  });

  /// Path to the file containing the violation.
  final String file;

  /// The source line that triggered the violation.
  final String line;

  /// Human-readable reason for the violation.
  final String reason;

  /// 1-based line number within the file.
  final int lineNumber;

  @override
  String toString() => '$file:$lineNumber: $reason\n  $line';
}

/// Static analysis scanner that enforces write boundary safety rules.
///
/// The MCP server must never import packages that provide write access to
/// OPC UA or StateMan, and must never call write methods on those objects.
/// This scanner reads Dart source files as text and reports violations.
///
/// Designed to run as a CI test:
/// ```
/// dart test test/safety/safety_scanner_test.dart
/// ```
class SafetyScanner {
  /// Package imports that are forbidden in the MCP server codebase.
  ///
  /// These packages provide write access to physical equipment or
  /// system state and must never be imported by tool handlers.
  static const _forbiddenPackages = [
    'package:open62541',
    'package:jbtm',
    'package:amplify_secure_storage_dart',
  ];

  /// Regex patterns for forbidden method calls that mutate state.
  ///
  /// These cover StateMan write methods and OPC UA write patterns.
  static final _forbiddenMethodPatterns = [
    _ForbiddenPattern(
      pattern: RegExp(r'stateMan\.\s*setValue\s*\('),
      reason: 'Forbidden StateMan write: setValue()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'stateMan\.\s*writeValue\s*\('),
      reason: 'Forbidden StateMan write: writeValue()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'stateMan\.\s*setValues\s*\('),
      reason: 'Forbidden StateMan write: setValues()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'stateMan\.\s*removeValue\s*\('),
      reason: 'Forbidden StateMan write: removeValue()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'stateMan\.\s*mutate\s*\('),
      reason: 'Forbidden StateMan mutation: mutate()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'client\.write\s*\('),
      reason: 'Forbidden OPC UA write: client.write()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'writeNodeValue\s*\('),
      reason: 'Forbidden OPC UA write: writeNodeValue()',
    ),
    _ForbiddenPattern(
      pattern: RegExp(r'opcua\.write\s*\('),
      reason: 'Forbidden OPC UA write: opcua.write()',
    ),
  ];

  /// Scans source code for forbidden import statements.
  ///
  /// Returns a list of [SafetyViolation]s for each import line that
  /// references a forbidden package.
  List<SafetyViolation> scanForForbiddenImports(
    String source, {
    String? filePath,
  }) {
    final violations = <SafetyViolation>[];
    final lines = source.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import ')) continue;

      for (final pkg in _forbiddenPackages) {
        if (line.contains(pkg)) {
          final pkgName = pkg.replaceFirst('package:', '');
          violations.add(SafetyViolation(
            file: filePath ?? '<unknown>',
            line: line,
            reason: 'Forbidden import: $pkgName',
            lineNumber: i + 1,
          ));
        }
      }
    }

    return violations;
  }

  /// Scans source code for forbidden method calls that mutate state.
  ///
  /// Returns a list of [SafetyViolation]s for each line that matches
  /// a forbidden write pattern (StateMan mutations, OPC UA writes).
  List<SafetyViolation> scanForForbiddenMethodCalls(
    String source, {
    String? filePath,
  }) {
    final violations = <SafetyViolation>[];
    final lines = source.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      for (final fp in _forbiddenMethodPatterns) {
        if (fp.pattern.hasMatch(line)) {
          violations.add(SafetyViolation(
            file: filePath ?? '<unknown>',
            line: line.trim(),
            reason: fp.reason,
            lineNumber: i + 1,
          ));
        }
      }
    }

    return violations;
  }

  /// Scans all `.dart` files in [dir] recursively and returns any violations.
  ///
  /// Combines results from [scanForForbiddenImports] and
  /// [scanForForbiddenMethodCalls] for each file.
  ///
  /// Files matching [excludeFileNames] are skipped. By default, the scanner
  /// excludes its own source file (`safety_scanner.dart`) since it necessarily
  /// contains the forbidden patterns as string literal definitions.
  Future<List<SafetyViolation>> scanDirectory(
    Directory dir, {
    Set<String> excludeFileNames = const {'safety_scanner.dart'},
  }) async {
    final violations = <SafetyViolation>[];
    final entities = dir.listSync(recursive: true);

    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      // Skip excluded files (e.g., the scanner itself).
      final fileName = entity.uri.pathSegments.last;
      if (excludeFileNames.contains(fileName)) continue;

      final source = await entity.readAsString();
      final filePath = entity.path;

      violations.addAll(scanForForbiddenImports(source, filePath: filePath));
      violations
          .addAll(scanForForbiddenMethodCalls(source, filePath: filePath));
    }

    return violations;
  }
}

/// Internal helper binding a regex pattern to a human-readable reason.
class _ForbiddenPattern {
  _ForbiddenPattern({required this.pattern, required this.reason});

  final RegExp pattern;
  final String reason;
}
