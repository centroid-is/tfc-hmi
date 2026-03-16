import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'package:tfc/chat/elicitation_dialog.dart';
import 'package:tfc/mcp/mcp_bridge_notifier.dart';

// ── Helpers ─────────────────────────────────────────────────────────────

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

/// Creates an [ElicitRequest] with a simple confirm schema.
ElicitRequest _makeRequest({
  String message = 'Do you want to create this alarm?',
}) {
  return ElicitRequest.form(
    message: message,
    requestedSchema: JsonSchema.object(
      properties: {
        'confirm': JsonSchema.boolean(
          description: 'Accept this proposal?',
          defaultValue: false,
        ),
      },
      required: ['confirm'],
    ),
  );
}

// ── Tests ───────────────────────────────────────────────────────────────

void main() {
  group('ElicitationDialog', () {
    testWidgets('shows the elicitation message', (tester) async {
      final completer = Completer<ElicitResult>();

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(
                  message:
                      '**Risk Level:** HIGH\n\nCreate alarm "Pump Overcurrent"',
                ),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Should display the message text
      expect(find.textContaining('Pump Overcurrent'), findsOneWidget);
      // Should show the risk level
      expect(find.textContaining('HIGH'), findsOneWidget);
    });

    testWidgets('confirm button returns accept with confirm:true',
        (tester) async {
      final completer = Completer<ElicitResult>();

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Tap the confirm button
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final result = await completer.future;
      expect(result.action, 'accept');
      expect(result.content, {'confirm': true});
    });

    testWidgets('deny button returns decline action', (tester) async {
      final completer = Completer<ElicitResult>();

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Tap the deny button
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      final result = await completer.future;
      expect(result.action, 'decline');
      expect(result.content, isNull);
    });

    testWidgets('dialog has semantic keys for testability', (tester) async {
      final completer = Completer<ElicitResult>();

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('elicitation-confirm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('elicitation-deny')),
        findsOneWidget,
      );
    });

    testWidgets('shows title with proposal type icon', (tester) async {
      final completer = Completer<ElicitResult>();

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Should have a title
      expect(find.text('Confirm Action'), findsOneWidget);
      // Should have a warning/question icon
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });

    testWidgets('dismissing dialog returns cancel', (tester) async {
      final completer = Completer<ElicitResult>();

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Dismiss by tapping outside the dialog
      await tester.tapAt(const Offset(0, 0));
      await tester.pumpAndSettle();

      final result = await completer.future;
      expect(result.action, 'cancel');
    });

    testWidgets('parses markdown-style message with detail fields',
        (tester) async {
      final completer = Completer<ElicitResult>();

      const message = '**Risk Level:** MEDIUM\n\n'
          'Create alarm "Motor Overtemp"\n\n'
          '---\n\n'
          '**title:** Motor Overtemp\n'
          '**description:** Motor temperature exceeds threshold\n'
          '**rules:** warning: motor.temp > 80';

      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showElicitationDialog(
                context: context,
                request: _makeRequest(message: message),
                completer: completer,
              );
            },
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Should display the full message content
      expect(find.textContaining('Motor Overtemp'), findsWidgets);
      expect(find.textContaining('MEDIUM'), findsOneWidget);
    });
  });

  group('McpBridgeNotifier elicitation handler', () {
    test('elicitationHandler property can be set and cleared', () {
      final notifier = McpBridgeNotifier();
      addTearDown(notifier.dispose);

      notifier.elicitationHandler = (request) async {
        return const ElicitResult(
          action: 'accept',
          content: {'confirm': true},
        );
      };

      expect(notifier.elicitationHandler, isNotNull);

      notifier.elicitationHandler = null;
      expect(notifier.elicitationHandler, isNull);
    });
  });
}
