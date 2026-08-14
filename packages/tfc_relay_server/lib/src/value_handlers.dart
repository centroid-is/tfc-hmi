/// The bodies of `read`, `readFresh`, `readMany`, `write` and `writeStatus`.
///
/// Same rule as `session_handlers.dart`, for the same reason: **nothing in
/// here registers anything.** Handlers are handed to `RelaySession._on`, which
/// is the one seam where a method enters the table and therefore the one place
/// the handshake gate and the error armor are applied. A handler that
/// registered itself would be a handler that arrived ungated, and `write`
/// ungated is a client that never said hello reaching a contactor.
/// A grep for the peer's registration call over this file is meant to come
/// back empty — and unlike `session_handlers.dart`, this doc does not spell
/// that call out, so the grep is a check anyone can run rather than a sentence
/// that answers itself.
///
/// ## Why these five exist in Phase 4 rather than Phase 5
///
/// 04-RESEARCH Finding 4 ran the method sweep against a live `RelayServer`:
/// every one of these answered `-32601 Unknown method`, which put 28 of the
/// contract suite's 44 checks out of reach over the real gateway. The
/// contract leg cannot run against a socket that cannot read or write, so the
/// plumbing was pulled forward. Only the plumbing.
///
/// ## What Phase 5 still owns, and this file deliberately does not do
///
///  * **Write semantics.** Three-state depth beyond forwarding what the source
///    reports, dedup of a re-sent `cmd` against a live window, hold-to-run and
///    the rest of the write-safety machinery (WRT-*).
///  * **Authorization.** Which keys a session may read and which it may
///    actuate is Phase 6 (SEC-03, T-04-03). Every method here is reachable by
///    anyone who completes the handshake. That is not an oversight being
///    hidden — it is the same posture `subscribe` has had since Phase 3, and
///    it attaches at the same per-key seam.
///
/// ## The outcome log, and the one answer it must never invent
///
/// `writeStatus` is answered from [WriteOutcomeLog] — a short-TTL map of
/// `cmd` → outcome, pruned on access rather than by a timer, and owned by the
/// **server** rather than by this per-session object. That lifetime is
/// 04-REVIEW CR-02 and the whole of why the log is a class of its own; its
/// library doc carries the argument.
///
/// [WriteNotReceived] is the only outcome that tells an operator a re-send is
/// safe. A gateway that has merely *forgotten* a command must therefore never
/// spell its amnesia that way — so absence from the log is not enough to say
/// "never received". Three pieces of evidence are required, all of them the
/// gateway's own: the `cmd` is a ULID and can be dated, the instant it names
/// is one this log was already recording at, and it is inside the TTL.
/// Anything else is [WriteUnknown], because the gateway cannot tell "never
/// arrived" from "arrived while I was not looking".
library;

import 'package:json_rpc_2/error_code.dart' as rpc_errors;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'server_config.dart';
import 'session_handlers.dart' show KeyRejectKinds;
import 'write_outcome_log.dart';

/// The handler bodies for one session's value methods.
///
/// Holds no outcome state of its own. The log it writes to and reads from
/// belongs to the server and outlives this object, because the only caller of
/// `writeStatus` is a client that has just reconnected — see
/// `write_outcome_log.dart`.
final class ValueHandlers {
  ValueHandlers({
    required this.api,
    required this.config,
    required this.now,
    WriteOutcomeLog? outcomes,
    this.ownerOf,
  }) : outcomes =
            outcomes ?? WriteOutcomeLog(ttl: config.writeOutcomeTtl, now: now);

  final StateManApi api;
  final ServerConfig config;

  /// Wall-clock epoch milliseconds. Injected rather than read, because every
  /// promise the outcome log makes is arithmetic about *when*.
  final int Function() now;

  /// The server's outcome log. Defaulted to a fresh one so a handler can be
  /// driven on its own in a unit test, exactly as it is over a socket.
  final WriteOutcomeLog outcomes;

  /// Which session recorded an outcome, carried into the log for Phase 6's
  /// identity narrowing.
  ///
  /// A callback rather than a value because these handlers are built during
  /// the session's `_start` and the session id is minted later, by `hello` —
  /// the same reason `SessionHandlers` reads its epoch through one.
  final String? Function()? ownerOf;

  /// How many outcomes are being held. Read by the test that proves the log
  /// is bounded (T-04-06); nothing in production depends on it.
  int get recordedOutcomes => outcomes.recordedOutcomes;

  /// `read`: the cached value, no round trip.
  ///
  /// **Why it stays on the table even though `RemoteStateMan` never sends it**
  /// (04-REVIEW WR-11). `read` is `StateManApi`'s cached read and this gateway
  /// exists to serve that interface; the panel client happens to hold its own
  /// `ValueStore` and answers from it synchronously, which is a property of
  /// *that* client and not of the protocol. A browser bundle, a diagnostic
  /// tool or a script has no cache to peek, and for them the gateway's cache
  /// is the only one there is. It adds no exposure class its neighbours do not
  /// already have — every method here is reachable by anyone past the
  /// handshake until Phase 6 attaches authorization at the same per-key seam.
  Future<Object?> read(rpc.Parameters params) async {
    // Sanitize before decode, every time, on every ingress path:
    // `jsonDecode('1e999')` yields Infinity in silence, and an Infinity that
    // reaches an error response makes the *error* unencodable — the 02-05 hang.
    final decoded = sanitize(params.asMap).value as Map;
    final key = _requireKey(decoded['key'], Methods.read);

    if (!api.keys.contains(key)) {
      // An answer, not a throw. The caller asked a legitimate question and
      // "this source does not serve that tag" is the answer to it; a refusal
      // would make a page editor's key check indistinguishable from a broken
      // gateway.
      //
      // **Keyed by tag, exactly as `readMany` keys it** (04-REVIEW WR-11).
      // This used to answer `'rejected': <one KeyReject>` while its neighbour
      // answered `'rejected': {key: KeyReject}`, so a client written against
      // either decoded the other wrongly — and the wrong decode is silent: a
      // `kind` read off a map that has none comes back null, and the tag
      // renders as merely quiet instead of as misconfigured.
      return {
        'key': key,
        'value': WireValue.of(null, quality: Quality.errorConfig).toJson(),
        'rejected': {
          key: KeyReject(KeyRejectKinds.unknownKey,
                  message: 'this source does not serve "$key" — usually a typo '
                      'in a page config, occasionally a tag renamed upstream')
              .toJson(),
        },
      };
    }

    return {'key': key, 'value': _wire(api.read(key)).toJson()};
  }

  /// `readFresh`: force the round trip the cache is under suspicion of.
  Future<Object?> readFresh(rpc.Parameters params) async {
    final decoded = sanitize(params.asMap).value as Map;
    final key = _requireKey(decoded['key'], Methods.readFresh);

    final value = await api.readFresh(key);
    return {'key': key, 'value': _wire(value).toJson()};
  }

  /// `readMany`: one round trip, an answer per key.
  ///
  /// A key this source cannot serve costs that one key. The argument is
  /// `session_handlers.dart:30-44`'s, unchanged: a page config carries ~1500
  /// hand-edited keys, so one typo must not cost the call.
  Future<Object?> readMany(rpc.Parameters params) async {
    final decoded = sanitize(params.asMap).value as Map;
    final raw = decoded['keys'];
    if (raw is! List) {
      throw _refuse(Methods.readMany,
          'readMany needs a "keys" list: the one call that exists so a '
          'diagnostics page does not pay N round trips');
    }
    if (raw.isEmpty) {
      throw _refuse(Methods.readMany,
          'readMany needs at least one key: a request for nothing is a '
          'round trip the client then waits on');
    }
    if (raw.length > config.maxKeysPerSubscribe) {
      throw _refuse(
          Methods.readMany,
          'readMany carried ${raw.length} keys, over this server\'s limit of '
          '${config.maxKeysPerSubscribe}; split the request or raise '
          'maxKeysPerSubscribe');
    }

    final servable = api.keys.toSet();
    final wanted = <String>[];
    final rejected = <String, Object?>{};
    for (final entry in raw) {
      if (entry is! String || entry.trim().isEmpty) {
        rejected['$entry'] = const KeyReject(KeyRejectKinds.invalidKey,
                message: 'an empty key is not a tag; something built this '
                    'list from a blank field')
            .toJson();
        continue;
      }
      if (!servable.contains(entry)) {
        rejected[entry] = KeyReject(KeyRejectKinds.unknownKey,
                message: 'this source does not serve "$entry" — usually a '
                    'typo in a page config, occasionally a tag renamed '
                    'upstream')
            .toJson();
        continue;
      }
      wanted.add(entry);
    }

    // One call for the whole list even when the list is empty after
    // filtering — an empty upstream read is cheap, and skipping it would make
    // the round-trip count depend on how many keys were mistyped.
    final values = wanted.isEmpty
        ? const <String, DynamicValue>{}
        : await api.readMany(wanted);

    return {
      'values': {
        for (final entry in values.entries) entry.key: _wire(entry.value).toJson(),
      },
      'rejected': rejected,
    };
  }

  /// `write`: forward the operator's intent, report what became of it.
  ///
  /// Never throws to report an outcome. A JSON-RPC error on this path means
  /// "definitively no effect, safe to re-send" (`write_result.dart:6-8`), so
  /// the only refusals here are shape refusals raised *before* the plant is
  /// touched; anything that goes wrong after that is [WriteUnknown].
  Future<Object?> write(rpc.Parameters params) async {
    final sanitized = sanitize(params.asMap);
    if (sanitized.hadNonFinite) {
      // Refused rather than cleaned up, and the asymmetry is the point.
      // Sanitizing is right for telemetry, where the alternative is a frame
      // that fails for every client. Here a nulled `value` actuates the device
      // with something nobody chose, and a nulled `expect` is this path's
      // encoding of "no guard at all" — the operator's "only if it still reads
      // 1200" silently becomes "whatever it reads".
      throw _refuse(
          Methods.write,
          'this write carries a non-finite number. Nulling the value would '
          'actuate the device with something the operator did not choose, and '
          'nulling an expect would turn a guarded write into an unconditional '
          'one, so neither is done for you');
    }
    final decoded = (sanitized.value as Map).cast<String, Object?>();

    final WriteParams request;
    try {
      request = WriteParams.fromJson(decoded);
    } on FormatException catch (error) {
      throw _refuse(Methods.write, 'write params could not be read: $error');
    } on TypeError {
      throw _refuse(
          Methods.write,
          'write needs a "cmd" and a "key", both strings: the cmd is the '
          'operator action this outcome will be reconciled against, and '
          'without it nothing can be re-queried later');
    }
    if (request.cmd.trim().isEmpty) {
      throw _refuse(
          Methods.write,
          'write needs a non-empty "cmd": it is the id the operator\'s action '
          'was minted under, and the only handle writeStatus has on it');
    }
    if (request.key.trim().isEmpty) {
      throw _refuse(Methods.write, 'write needs a non-empty "key"');
    }

    // **One id, one actuation** (04-REVIEW CR-05). The `cmd` arrives from the
    // wire and was accepted verbatim, so any peer that completed the handshake
    // could send two different writes under one id: both went upstream, the
    // second overwrote the first's outcome, and `writeStatus` then reported
    // one answer for two actuations — the wrong one for at least one of them.
    //
    // A shape refusal, raised before the plant is touched, which is the one
    // class of refusal this path allows: `INVALID_PARAMS` on a write means
    // "definitively no effect", and here that is exactly true.
    //
    // Phase 5's idempotency window is what makes the *same* key and value a
    // genuine replay — answered from the log rather than refused, the Stripe
    // semantic — and it attaches here. A differing key or value stays a
    // refusal even then, because there is no reading of two different writes
    // under one id that an operator can act on.
    if (outcomes.holds(request.cmd)) {
      throw _refuse(
          Methods.write,
          'the command id "${request.cmd}" is already recorded on this '
          'gateway. One id is one operator action: a second write under it '
          'would actuate the plant twice and leave one writeStatus answer '
          'covering both, so nothing was sent. Mint a new id per action');
    }

    // Recorded *before* the call so a writeStatus arriving while this is
    // upstream is answered "unknown" and not "never received": the command is
    // on its way to a machine at that exact moment.
    _record(request.cmd, WriteUnknown(request.cmd,
        const WriteReason('in_flight',
            message: 'the gateway has sent this write upstream and has not '
                'heard back yet')));

    WriteResult result;
    try {
      // The client's cmd goes upstream, and the gateway does not mint one of
      // its own. It is not this process's action to identify: the id was minted
      // at the operator's keyboard (design §4.6) and everything that will ever
      // ask about this write — the `writeStatus` re-query after a reconnect,
      // the outcome log below, the plant's own count of how many times the
      // command reached the device — has to be keyed by that one id or the
      // three-state answer stops being attributable to anything.
      //
      // Minting here instead was a write-safety defect, not a cosmetic one:
      // the plant recorded the attempt under an id the client could never name,
      // so "how many times did my write reach the machine" had no answer from
      // either end, and `_withCmd` relabelling the outcome on the way back made
      // the loss invisible at exactly the point it mattered.
      result = _withCmd(
          await api.write(request.key, request.value,
              expect: request.expect, cmd: request.cmd),
          request.cmd);
    } catch (error) {
      // The source failed in a way it does not describe as an outcome. The
      // write may still have reached the device, so this is unknown — not an
      // RPC error, which would read as "definitely did not happen" and is
      // what makes an operator press the button a second time.
      result = WriteUnknown(
          request.cmd,
          WriteReason('gateway_lost_track',
              message: 'the gateway lost track of this write: $error'));
    }

    _record(request.cmd, result);
    return result.toJson();
  }

  /// `writeStatus`: what became of these commands, as far as this gateway can
  /// honestly say.
  Future<Object?> writeStatus(rpc.Parameters params) async {
    final decoded = sanitize(params.asMap).value as Map;
    final raw = decoded['cmds'];
    if (raw is! List) {
      throw _refuse(Methods.writeStatus,
          'writeStatus needs a "cmds" list of the ids to re-query');
    }
    if (raw.isEmpty) {
      throw _refuse(Methods.writeStatus,
          'writeStatus needs at least one cmd: a re-query about nothing is a '
          'reconnect that learns nothing');
    }
    if (raw.length > config.maxKeysPerSubscribe) {
      throw _refuse(
          Methods.writeStatus,
          'writeStatus carried ${raw.length} cmds, over this server\'s limit '
          'of ${config.maxKeysPerSubscribe}');
    }

    outcomes.prune();
    return {
      'results': [
        for (final entry in raw) _statusOf('$entry').toJson(),
      ],
    };
  }

  /// The answer for one cmd, after the log has been pruned.
  WriteResult _statusOf(String cmd) {
    final held = outcomes.entryFor(cmd);
    if (held != null) return held.result;

    final mintedAt = _ulidMs(cmd);
    if (mintedAt == null) {
      return WriteUnknown(
          cmd,
          const WriteReason('unrecognized_cmd',
              message: 'this is not an id this gateway could have issued an '
                  'outcome for, so nothing about it can be ruled out'));
    }
    if (!outcomes.witnessed(mintedAt)) {
      // Either minted before this log existed — which, on a gateway that has
      // restarted, is every command that crossed the outage — or minted in a
      // future this gateway's clock has not reached, which is a panel whose
      // clock runs ahead and which would otherwise have bought itself a
      // `not_received` window of `ttl + skew`. Neither is evidence. Forgetting
      // is not evidence of never happening, and neither is never having been
      // told.
      return WriteUnknown(
          cmd,
          const WriteReason('outcome_unwitnessed',
              message: 'this command was minted outside the window this '
                  'gateway can vouch for with its own clock — before it '
                  'started recording, or ahead of it. Nothing about it can be '
                  'ruled out; read the value back before acting'));
    }
    if (outcomes.insideWindow(mintedAt)) {
      // Inside the window, dated by a clock this gateway trusts, and nothing
      // was recorded: the command genuinely never arrived. The only re-send-
      // safe answer, and it is only safe because of the three checks above.
      return WriteNotReceived(cmd);
    }
    return WriteUnknown(
        cmd,
        WriteReason('outcome_expired',
            message: 'this command is older than the gateway\'s '
                '${config.writeOutcomeTtl.inSeconds} s memory. Forgetting is '
                'not evidence that it never happened — read the value back '
                'before acting'));
  }

  void _record(String cmd, WriteResult result) =>
      outcomes.record(cmd, result, ownerHint: ownerOf?.call());

  /// The same outcome under the client's own [cmd].
  ///
  /// A **belt-and-braces** normalization since the client's cmd started going
  /// upstream: a source that honours the forwarded id already answers under it,
  /// and this is a no-op. It stays because `StateManApi.write`'s [cmd] is
  /// optional, so an implementation is free to ignore it and mint anyway, and
  /// an answer carrying an id the client never minted is an answer
  /// `writeStatus` could never match — the one failure the client cannot detect
  /// for itself.
  ///
  /// What it deliberately does *not* do is make ignoring the forwarded id
  /// harmless. The outcome is relabelled; the plant's own attempt count is not,
  /// and that discrepancy is what the contract's
  /// `exactly one upstream attempt per cmd` check reads.
  static WriteResult _withCmd(WriteResult result, String cmd) =>
      switch (result) {
        WriteApplied(:final readback, :final at) =>
          WriteApplied(cmd, readback: readback, at: at),
        WriteRejected(:final reason, :final at) =>
          WriteRejected(cmd, reason, at: at),
        WriteUnknown(:final reason) => WriteUnknown(cmd, reason),
        WriteNotReceived() => WriteNotReceived(cmd),
      };

  String _requireKey(Object? raw, String method) {
    if (raw is! String || raw.trim().isEmpty) {
      throw _refuse(method,
          '$method needs a non-empty "key": the tag being asked about');
    }
    return raw;
  }

  /// A refusal with the armor already on it.
  ///
  /// `data['request']` is pre-substituted because `RpcException.serialize`
  /// copies the offending request into `error.data` when it is not — and one
  /// request carrying `1e999` then makes the *error* unencodable, at which
  /// point the peer drops it and every caller without a deadline waits forever
  /// (STATE.md, the 02-05 hang).
  ///
  /// Spelled with the general constructor rather than
  /// `RpcException.invalidParams`, which takes no `data` — and a refusal with
  /// no `data` is exactly the one the serializer fills in for you.
  static rpc.RpcException _refuse(String method, String why) =>
      rpc.RpcException(rpc_errors.INVALID_PARAMS, why,
          data: _substitute(method));

  static Map<String, Object?> _substitute(String method) => {
        'method': method,
        'request': 'omitted: echoing a request that may carry a non-finite '
            'number is what makes the error itself unencodable, and an '
            'unencodable error on a path with no deadline is a hang',
      };

  /// A value on the wire. Null means "not known yet" — a distinct thing from a
  /// known-bad value, and the wire says which.
  static WireValue _wire(DynamicValue? value) {
    if (value == null) {
      return WireValue.of(null, quality: Quality.uncertainNotYetKnown);
    }
    return WireValue.of(
      value.toJson(slim: true),
      quality: value.quality,
      t: value.sourceTime?.millisecondsSinceEpoch,
    );
  }

  /// Crockford base32, the same alphabet `newUlid` encodes with.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The millisecond a ULID was minted at, or null when [cmd] is not one.
  ///
  /// The decode half of `ulid.dart`'s encoder, kept here rather than there
  /// because this is the only place that needs it and the property it is used
  /// for — "could this command still be inside the not-received window?" — is
  /// a gateway question, not an id question.
  static int? _ulidMs(String cmd) {
    if (cmd.length != 26) return null;
    var ms = 0;
    for (var i = 0; i < 10; i++) {
      final digit = _alphabet.indexOf(cmd[i]);
      if (digit < 0) return null;
      ms = (ms << 5) | digit;
    }
    return ms;
  }
}
