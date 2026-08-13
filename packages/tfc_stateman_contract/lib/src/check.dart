/// The shape of a contract check, and the deadline every check must wrap its
/// awaits in.
///
/// Why `within` exists: research reproduced a `BrokenStateMan` that drops a
/// subscription. The check waited on a stream that never emitted, so instead of
/// failing it **hung** — for the full 30-second `package:test` timeout, on
/// every CI run, ending with a message that named the test file rather than the
/// property the implementation had broken. A test-runner timeout is a safety
/// net for a runaway process, not an assertion mechanism.
///
/// Wrapped in `within`, the same sabotage fails in 200 ms saying which property
/// went unobserved. That difference is what makes the sabotage suites in this
/// package diagnostic instead of merely red.
///
/// Deliberately generic over the implementation type: this file must not import
/// `StateManApi`, so it can be written and tested before the interface exists.
library;

import 'dart:async';

import 'package:test/test.dart';

/// A single contract case, run against an implementation `api`.
///
/// Generic so the same helper serves `StateManApi` checks and the meta-tests
/// that prove those checks bite.
typedef Check<A> = Future<void> Function(A api);

/// Awaits [f], but fails the test if it has not settled within [budget].
///
/// [what] names the property being waited for, in operator terms — "the first
/// value for a subscribed key", not "the future". It is what the failure
/// message will say.
///
/// Silence becomes a [TestFailure]. A genuine error is passed through
/// unchanged: this helper converts *nothing happening* into a named failure,
/// and leaves everything else alone.
Future<T> within<T>(
  Future<T> f,
  String what, {
  Duration budget = const Duration(milliseconds: 200),
}) async {
  try {
    return await f.timeout(budget);
  } on TimeoutException {
    fail('$what did not happen within ${budget.inMilliseconds} ms');
  }
}
