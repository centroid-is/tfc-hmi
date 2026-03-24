import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc/mcp/mcp_bridge_notifier.dart';

void main() {
  group('McpBridgeNotifier.elicitationHandler', () {
    late McpBridgeNotifier notifier;

    setUp(() {
      notifier = McpBridgeNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('is null by default', () {
      expect(notifier.elicitationHandler, isNull);
    });

    test('can be set to a custom handler', () {
      notifier.elicitationHandler = (request) async {
        return const ElicitResult(
          action: 'accept',
          content: {'confirm': true},
        );
      };
      expect(notifier.elicitationHandler, isNotNull);
    });

    test('can be cleared by setting to null', () {
      notifier.elicitationHandler = (request) async {
        return const ElicitResult(action: 'decline');
      };
      expect(notifier.elicitationHandler, isNotNull);

      notifier.elicitationHandler = null;
      expect(notifier.elicitationHandler, isNull);
    });

    test('buildElicitHandler returns auto-accept when handler is null',
        () async {
      final handler = notifier.buildElicitHandler();
      final result = await handler(ElicitRequest.form(
        message: 'Test',
        requestedSchema: JsonSchema.object(
          properties: {
            'confirm': JsonSchema.boolean(
              description: 'Accept?',
              defaultValue: false,
            ),
          },
          required: ['confirm'],
        ),
      ));

      expect(result.action, 'accept');
      expect(result.content, {'confirm': true});
    });

    test('buildElicitHandler delegates to custom handler when set', () async {
      notifier.elicitationHandler = (request) async {
        return const ElicitResult(action: 'decline');
      };

      final handler = notifier.buildElicitHandler();
      final result = await handler(ElicitRequest.form(
        message: 'Test',
        requestedSchema: JsonSchema.object(
          properties: {
            'confirm': JsonSchema.boolean(
              description: 'Accept?',
              defaultValue: false,
            ),
          },
          required: ['confirm'],
        ),
      ));

      expect(result.action, 'decline');
    });
  });
}
