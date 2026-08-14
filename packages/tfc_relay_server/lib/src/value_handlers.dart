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

import 'dart:async';

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

  /// The hold-to-run deadmen this **session** has engaged, by plant key.
  ///
  /// Per session because this object is: `relay_session.dart` builds one
  /// `ValueHandlers` per `RelaySession`, and that is what makes teardown free
  /// — the session's `_teardown` calls [releaseAllHolds] and a panel that
  /// vanished stops feeding the machine it was jogging (05-RESEARCH §G.4,
  /// D-P5-J). A hold map on the *server* would outlive the socket that
  /// engaged it, which is a machine being fed by nobody.
  ///
  /// It is also the authorization boundary for the tick (T-05-16). A `'h'`
  /// frame names a key; this map decides whether that name means anything.
  /// Without it the tick would be a write primitive with no engage in front
  /// of it, no cmd, no outcome and no refusal path.
  final _holds = <String, HoldHandle>{};

  /// STUB (05-05 task 2 RED): declared so the cases can fail by name.
  int get droppedHoldTicks => 0;

  /// STUB (05-05 task 2 RED): declared so the cases can fail by name.
  Future<Object?> holdTick(rpc.Parameters params) async => null;

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
    // The hold flag's vocabulary on the *write* path is exactly two values,
    // and this is a pre-plant refusal like the ones above it: raised before
    // `api.holdToRun` and before `api.write`, so `INVALID_PARAMS` here means
    // what it means everywhere else on this path — definitively no effect.
    //
    // Anything else would make `write` a way to put an arbitrary integer on a
    // deadman tag while calling it an engage. Intermediate counter values are
    // ticks: notifications, no cmd, no outcome, and only ever for a hold this
    // session already engaged.
    //
    // `num` rather than `int` on purpose: a REAL tag's 1.0 and a DINT's 1 are
    // the same operator intent, and this refusal is about the number 7, not
    // about which Dart type a JSON decoder chose.
    if (request.hold) {
      final value = request.value;
      if (value is! num || (value != 1 && value != 0)) {
        throw _refuse(
            Methods.write,
            'a hold-to-run write carries 1 to engage or 0 to release, and '
            'this one carries ${request.value}. Intermediate counter values '
            'arrive as ticks — notifications for a hold already engaged — '
            'and never as writes, so nothing was sent: no hold was taken and '
            'no device was consulted');
      }
    }

    // The request this outcome will be recorded for, and the request a second
    // frame under the same id is compared against. Built from the decoded
    // params *after* `sanitize` ran at the top of this method — so the value
    // stored is the value that goes upstream, and the deep comparison below is
    // bounded in depth by that same sanitize pass (`json_equality.dart`
    // recurses; ingress is what keeps that finite).
    final fingerprint = (
      key: request.key,
      value: request.value,
      expect: request.expect,
    );

    // **One id, one actuation** (04-REVIEW CR-05), and — since 05-03 — one id,
    // one *answer*. The `cmd` arrives from the wire and is accepted verbatim,
    // so any peer past the handshake can send a second frame under an id this
    // gateway has already recorded. Two of those are not the same event, and
    // the difference is the request itself:
    //
    //  * **The same key, value and expect** is one operator action arriving
    //    twice — a client that restarted still holding the id it minted at the
    //    keyboard. It is answered with the outcome that action already got,
    //    from the log, with no second `api.write`. That is the Stripe
    //    semantic, and the `upstreamWriteAttempts` assertion in
    //    `value_handlers_test.dart` is the property: one press, one movement
    //    of the machine.
    //
    //    Including while the first write is still upstream (**D-P5-A**). The
    //    pre-record below means such a replay reads `unknown(in_flight)`, and
    //    that is deliberately not a refusal: a refusal reaches the client as
    //    `WriteRejected(server_refused)` and *settles* the id, against a write
    //    that is at that instant on its way to a machine. An `unknown` leaves
    //    it unresolved, so the next `ready` re-queries `writeStatus`.
    //
    //  * **Anything else** — a different key, a different value, or a
    //    different compare-and-set guard (**D-P5-B**: "set 1450" and "set 1450
    //    only if it still reads 1200" are two different intents) — stays a
    //    refusal. There is no reading of two different writes under one id
    //    that an operator can act on, and reporting the first one's outcome
    //    for the second would put "applied" on a setpoint nobody applied.
    //
    // The comparison is `WriteOutcomeEntry.matches` (`write_outcome_log.dart`,
    // which also carries why the fingerprint is a record and why a null one
    // never matches), over `jsonEquals` — deep, insensitive to JSON object key
    // order, and holding numbers to their runtime type so a DINT 1 and a REAL
    // 1.0 stay two different writes.
    //
    // The refusal is a shape refusal raised before the plant is touched, which
    // is the one class of refusal this path allows: `INVALID_PARAMS` on a
    // write means "definitively no effect", and here that is exactly true.
    final held = outcomes.entryFor(request.cmd);
    if (held != null) {
      if (held.matches(fingerprint)) {
        // No `api.write`, and no new `_record`: nothing happened this time
        // round, so there is nothing new to remember. `_withCmd` already
        // normalized the stored result under this client's id when it was
        // recorded, and `WriteResult.fromJson` decodes it on the far side like
        // any other write answer — a replay of an applied write therefore
        // re-adopts the same readback onto the mimic.
        return held.result.toJson();
      }
      throw _refuse(
          Methods.write,
          'the command id "${request.cmd}" is already recorded on this '
          'gateway for a different write. One id is one operator action: a '
          'second, different write under it would actuate the plant twice and '
          'leave one writeStatus answer covering both, so nothing was sent: '
          'this write had no effect of any kind and no device was consulted '
          'about it. The two frames disagree about the key, the value or the '
          'expect guard, which is a defect in the caller and not a condition '
          'of the machine. Mint a new id per action');
    }

    // Recorded *before* the call so a writeStatus arriving while this is
    // upstream is answered "unknown" and not "never received": the command is
    // on its way to a machine at that exact moment.
    _record(
        request.cmd,
        WriteUnknown(
            request.cmd,
            const WriteReason('in_flight',
                message: 'the gateway has sent this write upstream and has not '
                    'heard back yet')),
        fingerprint);

    WriteResult result;
    try {
      // **The hold branch (D-P5-C).** An engage and a release are ordinary
      // writes — same idempotency window above, same in-flight pre-record,
      // same three-state outcome, same two record sites below — and the flag
      // changes only which seam they travel through.
      //
      //  * `hold: true, value: 1` → `api.holdToRun`, and the handle it
      //    returns is what this session's ticks feed. An `api.write(key, 1)`
      //    here would put a 1 on the tag with nothing behind it: the number
      //    would be right for one instant and there would be no way to
      //    advance it afterwards, which is a jog button that stops the
      //    machine a second after it starts it.
      //  * `hold: true, value: 0` → the handle's own `release()`, which
      //    writes the 0 and completes `onReleased`.
      //  * `hold: true, value: 0` with **no** handle held → falls through to
      //    the ordinary write below, deliberately. Writing 0 to a deadman tag
      //    is a legitimate thing to do, and a gateway that restarted holds no
      //    handle for a hold its predecessor engaged; refusing would make a
      //    sensible release read as a caller defect.
      //
      // The outcome is relabelled by the same `_withCmd` every other write
      // answer goes through: the source mints its own id inside `holdToRun`,
      // and an answer carrying an id the client never minted is one
      // `writeStatus` could never match.
      final hold = request.hold ? _holds[request.key] : null;
      if (request.hold && request.value == 1) {
        final handle = await api.holdToRun(request.key);
        // Recorded only when it took. A refused engage produces an inert
        // handle (`hold_handle.dart`), and keeping one would make the next
        // tick look authorized for a hold that never existed.
        if (handle.isHeld) _holds[request.key] = handle;
        result = _withCmd(handle.engagement, request.cmd);
      } else if (hold != null && request.value == 0) {
        _holds.remove(request.key);
        result = _withCmd(await hold.release(), request.cmd);
      } else {
        // The client's cmd goes upstream, and the gateway does not mint one of
        // its own. It is not this process's action to identify: the id was
        // minted at the operator's keyboard (design §4.6) and everything that
        // will ever ask about this write — the `writeStatus` re-query after a
        // reconnect, the outcome log below, the plant's own count of how many
        // times the command reached the device — has to be keyed by that one
        // id or the three-state answer stops being attributable to anything.
        //
        // Minting here instead was a write-safety defect, not a cosmetic one:
        // the plant recorded the attempt under an id the client could never
        // name, so "how many times did my write reach the machine" had no
        // answer from either end, and `_withCmd` relabelling the outcome on
        // the way back made the loss invisible at exactly the point it
        // mattered.
        result = _withCmd(
            await api.write(request.key, request.value,
                expect: request.expect, cmd: request.cmd),
            request.cmd);
      }
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

    _record(request.cmd, result, fingerprint);
    return result.toJson();
  }

  /// Ends every hold this session engaged, because the session has ended.
  ///
  /// Called from `RelaySession._teardown`, so it runs for **every** way a
  /// session can end — a graceful close, a protocol refusal, the heartbeat
  /// reaper, a backpressure eviction, a yanked cable. A hold that outlived
  /// its socket would be a counter still advancing for a panel that went
  /// home, which is the one shape of this feature that could hurt somebody
  /// (T-05-20).
  ///
  /// The release writes are **not** awaited. The machine stops when the
  /// counter stops, which happens synchronously here; the release write's
  /// outcome is informational, and a teardown that waited for one would hang
  /// on exactly the dead link that caused it. Errors are swallowed for the
  /// same reason — the source may already be disposed underneath us.
  void releaseAllHolds() {
    for (final hold in List<HoldHandle>.of(_holds.values)) {
      unawaited(hold
          .release(reason: HoldEnded.disposed)
          .then((_) {}, onError: (Object _) {}));
    }
    _holds.clear();
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

  /// The one place an outcome enters the log.
  ///
  /// [fingerprint] is the write the outcome is about, and it is not optional
  /// here even though [WriteOutcomeLog.record] allows a null one: both callers
  /// are inside `write`, with the decoded and sanitized [WriteParams] in scope,
  /// and an entry recorded without a fingerprint would refuse every replay of
  /// itself.
  void _record(String cmd, WriteResult result, WriteFingerprint fingerprint) =>
      outcomes.record(cmd, result,
          ownerHint: ownerOf?.call(), fingerprint: fingerprint);

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
