/// The modal sign-in form: the inline error, the in-flight guard, and the
/// commissioning-window link.
///
/// Everything here drives a fake `AccessSessionController`, so no test reaches
/// a database, a preference store or a timer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/access.dart';
import 'package:tfc/routes.dart';
import 'package:tfc/widgets/access_sign_in_dialog.dart';
import 'package:tfc_access/tfc_access.dart';

/// Answers each `signIn` with the next scripted result, records what it was
/// asked, and can be held mid-flight by [gate].
class _FakeSessionController extends AccessSessionController {
  _FakeSessionController({List<AccessSignInResult>? results})
      : _results = results ?? const [];

  final List<AccessSignInResult> _results;

  final List<List<String>> attempts = <List<String>>[];

  /// When set, `signIn` waits on it before answering — a submission in flight.
  Completer<void>? gate;

  @override
  Future<AccessSession> build() async => AccessSession.anonymous(const {});

  @override
  Future<AccessSignInResult> signIn(String username, String password) async {
    attempts.add(<String>[username, password]);
    final g = gate;
    if (g != null) await g.future;
    final index = attempts.length - 1;
    return index < _results.length
        ? _results[index]
        : AccessSignInResult.badCredentials;
  }
}

/// Opens the real dialog from a button, so the tests exercise
/// [showAccessSignInDialog] and get a Navigator that can actually pop.
Widget _host({
  required _FakeSessionController controller,
  bool firstUserWindowOpen = false,
}) {
  return ProviderScope(
    overrides: [
      accessSessionProvider.overrideWith(() => controller),
      firstUserWindowOpenProvider.overrideWith((ref) async => firstUserWindowOpen),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAccessSignInDialog(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pushes [AccessSignInDialog] directly so the test can read the value it pops
/// with — which is how the first-account link names its destination.
Widget _routeCapturingHost({
  required _FakeSessionController controller,
  required List<String?> popped,
  bool firstUserWindowOpen = false,
}) {
  return ProviderScope(
    overrides: [
      accessSessionProvider.overrideWith(() => controller),
      firstUserWindowOpenProvider.overrideWith((ref) async => firstUserWindowOpen),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped.add(await showDialog<String>(
                  context: context,
                  builder: (_) => const AccessSignInDialog(),
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _fillIn(
  WidgetTester tester, {
  String username = 'anna',
  String password = 'hunter2',
}) async {
  await tester.enterText(find.byKey(kAccessSignInUsernameKey), username);
  await tester.enterText(find.byKey(kAccessSignInPasswordKey), password);
  await tester.pump();
}

void main() {
  group('AccessSignInDialog', () {
    testWidgets('shows a username field, a password field, Sign in and Cancel',
        (tester) async {
      await tester.pumpWidget(_host(controller: _FakeSessionController()));
      await _open(tester);

      expect(find.byKey(kAccessSignInUsernameKey), findsOneWidget);
      expect(find.byKey(kAccessSignInPasswordKey), findsOneWidget);
      expect(find.byKey(kAccessSignInSubmitKey), findsOneWidget);
      expect(find.byKey(kAccessSignInCancelKey), findsOneWidget);
    });

    testWidgets('carries the honesty line: signing in is not a boundary',
        (tester) async {
      await tester.pumpWidget(_host(controller: _FakeSessionController()));
      await _open(tester);

      expect(find.text(kAccessSignInHonestyNote), findsOneWidget);
      expect(kAccessSignInHonestyNote, contains('not a security boundary'));
    });

    testWidgets('valid credentials close the dialog', (tester) async {
      final controller =
          _FakeSessionController(results: [AccessSignInResult.ok]);
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);

      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pumpAndSettle();

      expect(controller.attempts, [
        ['anna', 'hunter2']
      ]);
      expect(find.byKey(kAccessSignInUsernameKey), findsNothing);
    });

    testWidgets('wrong credentials keep the dialog open with an inline error',
        (tester) async {
      final controller = _FakeSessionController(
          results: [AccessSignInResult.badCredentials]);
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);

      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessSignInUsernameKey), findsOneWidget);
      expect(find.text(kAccessSignInBadCredentialsMessage), findsOneWidget);
      expect(kAccessSignInBadCredentialsMessage,
          'Username or password not recognised');
    });

    testWidgets('the error clears as soon as the username is edited',
        (tester) async {
      final controller = _FakeSessionController(
          results: [AccessSignInResult.badCredentials]);
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);
      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pumpAndSettle();
      expect(find.text(kAccessSignInBadCredentialsMessage), findsOneWidget);

      await tester.enterText(find.byKey(kAccessSignInUsernameKey), 'annb');
      await tester.pump();

      expect(find.text(kAccessSignInBadCredentialsMessage), findsNothing);
    });

    testWidgets('the error clears as soon as the password is edited',
        (tester) async {
      final controller = _FakeSessionController(
          results: [AccessSignInResult.badCredentials]);
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);
      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pumpAndSettle();
      expect(find.text(kAccessSignInBadCredentialsMessage), findsOneWidget);

      await tester.enterText(find.byKey(kAccessSignInPasswordKey), 'hunter3');
      await tester.pump();

      expect(find.text(kAccessSignInBadCredentialsMessage), findsNothing);
    });

    testWidgets('an outage names the database, not the credentials',
        (tester) async {
      final controller =
          _FakeSessionController(results: [AccessSignInResult.unavailable]);
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);

      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessSignInUnavailableMessage), findsOneWidget);
      expect(find.text(kAccessSignInBadCredentialsMessage), findsNothing);
      expect(kAccessSignInUnavailableMessage,
          isNot(kAccessSignInBadCredentialsMessage));
      expect(kAccessSignInUnavailableMessage.toLowerCase(),
          contains('database'));
    });

    testWidgets('the password is obscured and rendered nowhere else',
        (tester) async {
      await tester.pumpWidget(_host(controller: _FakeSessionController()));
      await _open(tester);
      await _fillIn(tester, password: 'sup3rsecret');

      final password = tester.widget<TextField>(
        find.byKey(kAccessSignInPasswordKey),
      );
      expect(password.obscureText, isTrue);

      // The only widget carrying the text is the field itself.
      expect(find.widgetWithText(Text, 'sup3rsecret'), findsNothing);
      expect(find.text('sup3rsecret'), findsOneWidget);
    });

    testWidgets('pressing Enter in the password field submits', (tester) async {
      final controller =
          _FakeSessionController(results: [AccessSignInResult.ok]);
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);

      await tester.showKeyboard(find.byKey(kAccessSignInPasswordKey));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.attempts, [
        ['anna', 'hunter2']
      ]);
    });

    testWidgets('Sign in is disabled while a submission is in flight',
        (tester) async {
      final controller =
          _FakeSessionController(results: [AccessSignInResult.ok])
            ..gate = Completer<void>();
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);

      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pump();

      final button =
          tester.widget<FilledButton>(find.byKey(kAccessSignInSubmitKey));
      expect(button.onPressed, isNull);

      controller.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a double tap cannot produce two attempts', (tester) async {
      final controller = _FakeSessionController(
        results: [AccessSignInResult.ok, AccessSignInResult.ok],
      )..gate = Completer<void>();
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);
      await _fillIn(tester);

      await tester.tap(find.byKey(kAccessSignInSubmitKey));
      await tester.pump();
      await tester.tap(find.byKey(kAccessSignInSubmitKey),
          warnIfMissed: false);
      await tester.pump();

      expect(controller.attempts, hasLength(1));

      controller.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the first-account link shows while the window is open',
        (tester) async {
      await tester.pumpWidget(_host(
        controller: _FakeSessionController(),
        firstUserWindowOpen: true,
      ));
      await _open(tester);

      expect(find.byKey(kAccessSignInFirstUserKey), findsOneWidget);
    });

    testWidgets('the first-account link is absent once the window has closed',
        (tester) async {
      await tester.pumpWidget(_host(
        controller: _FakeSessionController(),
        firstUserWindowOpen: false,
      ));
      await _open(tester);

      expect(find.byKey(kAccessSignInFirstUserKey), findsNothing);
    });

    testWidgets('the first-account link pops with the first-user route',
        (tester) async {
      final popped = <String?>[];
      await tester.pumpWidget(_routeCapturingHost(
        controller: _FakeSessionController(),
        popped: popped,
        firstUserWindowOpen: true,
      ));
      await _open(tester);

      await tester.tap(find.byKey(kAccessSignInFirstUserKey));
      await tester.pumpAndSettle();

      expect(popped, [AppRoutes.firstUser]);
      expect(find.byKey(kAccessSignInUsernameKey), findsNothing);
    });

    testWidgets('Cancel closes the dialog without an attempt', (tester) async {
      final controller = _FakeSessionController();
      await tester.pumpWidget(_host(controller: controller));
      await _open(tester);

      await tester.tap(find.byKey(kAccessSignInCancelKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessSignInUsernameKey), findsNothing);
      expect(controller.attempts, isEmpty);
    });

    testWidgets('there is no forgot-password affordance', (tester) async {
      await tester.pumpWidget(_host(controller: _FakeSessionController()));
      await _open(tester);

      expect(
        find.textContaining('orgot', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('eset password'), findsNothing);
    });

    testWidgets('says Sign in, never Login', (tester) async {
      await tester.pumpWidget(_host(controller: _FakeSessionController()));
      await _open(tester);

      expect(find.textContaining('Login'), findsNothing);
      expect(find.textContaining('Log in'), findsNothing);
    });
  });
}
