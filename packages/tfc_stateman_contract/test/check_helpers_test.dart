@Tags(['meta'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

/// A future that will never complete, for the "the implementation went silent"
/// cases. Nothing ever completes this completer.
Future<T> neverCompletes<T>() => Completer<T>().future;

void main() {
  group('within', () {
    test('returns the value when the future is already done', () async {
      expect(await within(Future.value(7), 'x'), 7);
    });

    test('turns silence into a TestFailure naming the property and budget',
        () async {
      await expectLater(
        () => within(
          neverCompletes<int>(),
          'the first value for a subscribed key',
          budget: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<TestFailure>().having(
            (f) => f.message,
            'message',
            allOf(
              contains('the first value for a subscribed key'),
              contains('50 ms'),
            ),
          ),
        ),
      );
    });

    test('the silence failure is a TestFailure, not a TimeoutException',
        () async {
      // This is the whole point of the helper: a bare `.timeout()` yields a
      // TimeoutException, which the meta-assertion cannot tell apart from an
      // implementation that genuinely threw one.
      Object? caught;
      try {
        await within(neverCompletes<int>(), 'a value',
            budget: const Duration(milliseconds: 20));
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<TestFailure>());
      expect(caught, isNot(isA<TimeoutException>()));
    });

    test('lets a genuine error through unchanged — it converts silence only',
        () async {
      await expectLater(
        () => within(Future<int>.error(StateError('boom')), 'x'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });

    test('fails at roughly the budget, not at the test-runner timeout',
        () async {
      final sw = Stopwatch()..start();
      try {
        await within(neverCompletes<int>(), 'a value',
            budget: const Duration(milliseconds: 50));
      } catch (_) {
        // The assertion below is about when, not what.
      }
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });
}
