import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/safety/safety_scanner.dart';

void main() {
  group('Codebase safety', () {
    test('8. SafetyScanner finds zero violations in MCP server lib/', () async {
      final scanner = SafetyScanner();

      // Scan the actual MCP server source code.
      // The test runner cwd is the package root, so lib/src/ is relative.
      final libDir = Directory('lib/src/');
      expect(libDir.existsSync(), isTrue,
          reason: 'lib/src/ directory must exist');

      final violations = await scanner.scanDirectory(libDir);

      if (violations.isNotEmpty) {
        final details =
            violations.map((v) => '  ${v.toString()}').join('\n');
        fail('Safety violations found:\n$details');
      }

      expect(violations, isEmpty);
    });
  });
}
