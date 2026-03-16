import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/safety/safety_scanner.dart';

void main() {
  late SafetyScanner scanner;

  setUp(() {
    scanner = SafetyScanner();
  });

  group('SafetyScanner', () {
    group('scanForForbiddenImports', () {
      test('detects import of open62541 package', () {
        final source = '''
import 'package:open62541/open62541.dart';

void main() {}
''';
        final violations = scanner.scanForForbiddenImports(source);
        expect(violations, hasLength(1));
        expect(violations.first.reason, contains('open62541'));
      });

      test('detects import of jbtm package', () {
        final source = '''
import 'package:jbtm/jbtm.dart';

void main() {}
''';
        final violations = scanner.scanForForbiddenImports(source);
        expect(violations, hasLength(1));
        expect(violations.first.reason, contains('jbtm'));
      });

      test('allows import of mcp_dart, drift, logger', () {
        final source = '''
import 'package:mcp_dart/mcp_dart.dart';
import 'package:drift/drift.dart';
import 'package:logger/logger.dart';

void main() {}
''';
        final violations = scanner.scanForForbiddenImports(source);
        expect(violations, isEmpty);
      });
    });

    group('scanForForbiddenMethodCalls', () {
      test('detects StateMan write methods', () {
        final source = '''
void doStuff(stateMan) {
  stateMan.setValue('key', 42);
  stateMan.writeValue('key', 42);
}
''';
        final violations = scanner.scanForForbiddenMethodCalls(source);
        expect(violations, hasLength(2));
        expect(violations[0].reason, contains('StateMan'));
        expect(violations[1].reason, contains('StateMan'));
      });

      test('allows StateReader read methods', () {
        final source = '''
void doStuff(stateReader) {
  stateReader.getValue('key');
  stateReader.keys;
}
''';
        final violations = scanner.scanForForbiddenMethodCalls(source);
        expect(violations, isEmpty);
      });

      test('detects OPC UA write patterns', () {
        final source = '''
void doStuff(client) {
  client.write(nodeId, value);
  writeNodeValue(nodeId, value);
  opcua.write(data);
}
''';
        final violations = scanner.scanForForbiddenMethodCalls(source);
        expect(violations, hasLength(greaterThanOrEqualTo(3)));
      });
    });

    group('scanDirectory', () {
      test('scans all .dart files and reports violations', () async {
        final tempDir = await Directory.systemTemp.createTemp('safety_test_');
        try {
          // Create a clean file
          await File('${tempDir.path}/clean.dart').writeAsString('''
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  print('hello');
}
''');

          // Create a violating file
          await File('${tempDir.path}/bad.dart').writeAsString('''
import 'package:open62541/open62541.dart';

void main() {
  stateMan.setValue('key', 42);
}
''');

          final violations = await scanner.scanDirectory(tempDir);
          expect(violations, isNotEmpty);
          // Only the bad file should produce violations
          expect(
            violations.every((v) => v.file.contains('bad.dart')),
            isTrue,
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      });

      test('returns empty list for clean codebase', () async {
        final tempDir = await Directory.systemTemp.createTemp('safety_test_');
        try {
          await File('${tempDir.path}/clean1.dart').writeAsString('''
import 'package:drift/drift.dart';

void main() {}
''');
          await File('${tempDir.path}/clean2.dart').writeAsString('''
import 'package:test/test.dart';

void main() {}
''');

          final violations = await scanner.scanDirectory(tempDir);
          expect(violations, isEmpty);
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    });
  });
}
