/// The credential check in the `hello` path — the seam, and the permissive
/// default that stands in it until Phase 6.
///
/// **The capability, declared where it is registered.** This phase ships the
/// seam and the wiring that calls it on every `hello` before the version is
/// negotiated; Phase 6 ships the validator that actually reads a token
/// (SEC-03), together with TLS and origin enforcement. SRV-01's "rejects
/// unauthenticated clients" is met today by what the session already refuses:
/// a client that sends any other method before `hello`, a `hello` whose params
/// do not decode, and a `hello` naming no protocol version the server speaks.
/// Those are asserted in `session_hello_test.dart`, so the requirement has
/// teeth now and gains a credential later.
///
/// Writing it as an injected interface rather than a `TODO` is what makes the
/// Phase 6 change a one-line substitution at the call site instead of surgery
/// on the handshake, and what lets this phase test the rejection path — the
/// path that will matter — with a validator that says no.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// Judges the credential a client presented in its `hello`.
///
/// Given the whole [HelloParams] rather than a token string: a credential may
/// arrive in `capabilities`, and an implementation that wants to bind a token
/// to a client name or a resumed session id needs to see them together.
abstract interface class TokenValidator {
  /// Asynchronous because a real validator talks to something — a key set, an
  /// introspection endpoint, a directory — and a synchronous signature would
  /// have to be broken to add one.
  Future<TokenVerdict> validate(HelloParams params);
}

/// The two answers, sealed so a caller must handle both.
sealed class TokenVerdict {
  const TokenVerdict();
}

final class TokenAccepted extends TokenVerdict {
  const TokenAccepted();
}

/// Refused. [reason] is for the server's log and for the error message the
/// client receives; it must not carry anything the client did not already
/// send.
final class TokenRejected extends TokenVerdict {
  final String reason;
  const TokenRejected(this.reason);
}

/// Accepts every client. The default, and the whole of this phase's auth.
///
/// Named for what it does rather than for what it lacks, so a deployment that
/// still has one in Phase 6 is legible in a config diff.
final class PermissiveTokenValidator implements TokenValidator {
  const PermissiveTokenValidator();

  @override
  Future<TokenVerdict> validate(HelloParams params) async =>
      const TokenAccepted();
}
