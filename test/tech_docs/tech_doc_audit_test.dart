import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:tfc/tech_docs/tech_doc_audit.dart';

/// A test Logger output that captures log messages for assertion.
class _CapturingOutput extends LogOutput {
  final List<String> messages = [];

  @override
  void output(OutputEvent event) {
    messages.addAll(event.lines);
  }
}

void main() {
  late Logger logger;
  late _CapturingOutput output;

  setUp(() {
    output = _CapturingOutput();
    logger = Logger(
      output: output,
      printer: SimplePrinter(printTime: false),
      level: Level.all,
    );
  });

  group('auditTechDocOperation', () {
    test('logs action, user, timestamp, and docId for upload action', () async {
      await auditTechDocOperation<int>(
        action: TechDocAuditAction.upload,
        user: 'testUser',
        docId: null,
        docName: 'ATV320 Manual.pdf',
        operation: () async => 42,
        logger: logger,
      );

      final allLogs = output.messages.join('\n');
      expect(allLogs, contains('upload'));
      expect(allLogs, contains('testUser'));
      expect(allLogs, contains('ATV320 Manual.pdf'));
      expect(allLogs, contains('completed'));
    });

    test('logs action, user, timestamp, and docId for rename action', () async {
      await auditTechDocOperation<void>(
        action: TechDocAuditAction.rename,
        user: 'admin',
        docId: 5,
        docName: 'Old Name',
        operation: () async {},
        logger: logger,
      );

      final allLogs = output.messages.join('\n');
      expect(allLogs, contains('rename'));
      expect(allLogs, contains('admin'));
      expect(allLogs, contains('5'));
    });

    test('logs action, user, timestamp, and docId for delete action', () async {
      await auditTechDocOperation<void>(
        action: TechDocAuditAction.delete,
        user: 'operator1',
        docId: 10,
        docName: 'Sensor Datasheet',
        operation: () async {},
        logger: logger,
      );

      final allLogs = output.messages.join('\n');
      expect(allLogs, contains('delete'));
      expect(allLogs, contains('operator1'));
      expect(allLogs, contains('10'));
    });

    test('logs action, user, timestamp, and docId for replace action',
        () async {
      await auditTechDocOperation<void>(
        action: TechDocAuditAction.replace,
        user: 'eng1',
        docId: 3,
        docName: 'Pump Manual',
        operation: () async {},
        logger: logger,
      );

      final allLogs = output.messages.join('\n');
      expect(allLogs, contains('replace'));
      expect(allLogs, contains('eng1'));
      expect(allLogs, contains('3'));
    });

    test('returns the result of the wrapped operation', () async {
      final result = await auditTechDocOperation<int>(
        action: TechDocAuditAction.upload,
        user: 'user',
        docId: null,
        docName: 'test.pdf',
        operation: () async => 99,
        logger: logger,
      );

      expect(result, equals(99));
    });

    test('rethrows exceptions and logs failure', () async {
      expect(
        () => auditTechDocOperation<void>(
          action: TechDocAuditAction.delete,
          user: 'user',
          docId: 1,
          docName: 'test.pdf',
          operation: () async => throw Exception('DB error'),
          logger: logger,
        ),
        throwsException,
      );
    });
  });
}
