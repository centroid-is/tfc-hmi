/// The server's decode boundary, driven by the only tool that reaches it.
///
/// `ws_fault_test.dart` breaks bytes and proves the session tears down; it
/// cannot prove anything about the decoder, because RFC 6455's UTF-8 validation
/// sits in front of the decoder and drops the frame with a 1007 (03-RESEARCH
/// Finding 12). `MalformedPeer` corrupts at the **message** level, so every
/// frame it produces is a well-formed WebSocket frame carrying malformed
/// contents — which is exactly, and only, what arrives at
/// `RelaySession`'s decode path. Phase 1's review found the decode boundary was
/// 5 of 5 Critical findings (STATE.md); this file is the server's.
///
/// ## Two rules copied from `malformed_peer_test.dart`, verbatim in intent
///
/// **Never a throws-matcher for a hang.** `json_rpc_2.Peer` wraps its channel
/// in `respondToFormatExceptions`: a frame it cannot parse is answered with
/// `-32700` to the *sender* and the peer carries on, and the caller waiting on
/// a request is never told anything at all. Nine of the thirteen catalogued
/// corruptions therefore leave a request unsettled **forever** with the link
/// still healthy. A hang is asserted here by converting a deadline into a bool
/// and asserting on the bool; a throws-matcher would be asserting that
/// something happened, which is the opposite of the property.
///
/// **Every budget is short and named**, so silence fails fast and the failure
/// names the property instead of the runner's 30-second timeout.
///
/// ## The closing property, which is the point of the file
///
/// A malformed frame may take **one request** down invisibly. It may not wedge
/// the session. So every case ends the same way: the session is still
/// registered, and a following *valid* request still gets its answer inside a
/// budget. That second half is what separates "the decoder rejected something"
/// from "the decoder rejected something and the client is now talking to a
/// corpse".
///
/// ## The highest-risk case in the phase
///
/// `poisonNumber` — `1e999` — is RESEARCH R7 and Pitfall 7, and it has its own
/// named case rather than living only in the sweep. `jsonDecode('1e999')`
/// yields `Infinity` silently, and `RpcException.serialize` copies the
/// offending **request** into `error.data` unless `data.request` is already set
/// (`json_rpc_2-4.1.0/lib/src/exception.dart:46-57`). An error response
/// carrying an Infinity cannot be encoded, so it is discarded *inside* the
/// Peer, and the caller waits forever on a path that has no deadline — Phase 4
/// owns deadlines and does not exist yet. `relay_session.dart`'s
/// `_answer`/`_substitute` is the mitigation (T-03-28) and this case is its
/// teeth: delete `_substitute` and this case fails on its budget rather than
/// passing quietly.
@Tags(['ws'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
// `subscriptionCount` is an extension on `SessionRegistry`; the registry
// itself arrives through the harness.
import 'package:tfc_relay_server/src/subscription_registry.dart';
// The catalogue and `oversizeBytes` live behind the channel-harness entry, not
// the contract barrel.
import 'package:tfc_stateman_contract/channel_harness.dart';

import 'support/bands.dart';
import 'support/ws_harness.dart';

/// A plant key the server will accept in a subscribe.
const _key = 'CN01.MOT01.speed';

/// How long a following **valid** request has to be answered.
///
/// The whole file's closing property runs on this budget. Ten times the
/// platform [ceiling] so a slow runner widens it in step with the rest of the
/// package rather than by a number chosen here; the tick is 50 ms and is also
/// the response pump (`ws_harness.dart:57-63`), so this is several pumps wide.
final _answerBudget = ceiling * 10;

/// How long the `1e999` error has to reach the client.
///
/// The same budget as an ordinary answer, deliberately: the property is that a
/// failing request fails *like a request*, not that it fails eventually. When
/// `_substitute` is removed this budget is what the case dies on.
final _poisonBudget = ceiling * 10;

/// How long an 8 MiB frame gets to cross loopback and be dealt with.
///
/// Wider than the others because this one is a measurement of a megabyte-scale
/// transfer rather than of a decision, and a budget sized for a decision would
/// make the case a flaky test of the runner's disk-free memory bandwidth.
final _oversizeBudget = ceiling * 40;

/// The corruptions this run actually drove, filled by the sweep.
///
/// The anti-vacuity arm reads it: a sweep that iterated nothing passes every
/// assertion it never made, and a catalogue entry added in a later phase with
/// no case here would be invisible without this.
final _exercised = <String>{};

void main() {
  group('every catalogued corruption leaves the session answering', () {
    for (final entry in malformedPeerCatalogue.entries) {
      test('${entry.key} takes one request down and leaves the session up',
          () async {
        final fixture = relayFixture();
        await fixture.ready;
        await fixture.hello();

        final sessions = fixture.server.sessions;
        final priorSessions = sessions.sessionCount;

        // A valid request, corrupted on its way out. Sent on the raw socket
        // rather than through the fixture's peer, because the peer would
        // refuse to encode several of these — and because a corruption the
        // sender's own encoder had to accept is not a corruption a peer can
        // actually receive.
        fixture.client.sink.add(entry.value(_request('sweep-${entry.key}')));

        // Several turns before the count is read: a session killed by the
        // corrupt frame dies asynchronously, so an assertion made in the same
        // turn as the send would pass against a server that was already
        // tearing the session down.
        await pumpEventQueue(times: 5);

        expect(sessions.sessionCount, priorSessions,
            reason: 'a malformed frame takes one request down; a session that '
                'disappeared here means the decode boundary answers bad input '
                'by dropping the client, and a panel would be reconnecting '
                'once per corrupt frame');

        expect(await _stillAnswers(fixture), isTrue,
            reason: 'the session stopped answering after a ${entry.key} frame '
                '— the corruption did not take one request down, it wedged '
                'the link, which is the failure this whole file exists to '
                'catch');

        // An error escaping into the ambient isolate is attributed by
        // package:test to whichever case is running when it lands, so the
        // turns given here are what make that failure land on this case.
        await pumpEventQueue(times: 5);

        _exercised.add(entry.key);
      }, timeout: const Timeout.factor(2));
    }
  });

  test('the sweep drove every catalogued corruption', () {
    expect(_exercised, isNotEmpty,
        reason: 'a sweep that iterated nothing passes every assertion it never '
            'made');
    expect(_exercised.length, malformedPeerCatalogue.length,
        reason: 'every entry in the catalogue must have been driven against '
            'the server: a corruption added in a later phase is covered here '
            'automatically only while this equality holds');
    expect(_exercised, malformedPeerCatalogue.keys.toSet(),
        reason: 'the driven set and the catalogue must be the same names, not '
            'merely the same size');
  });

  group('the corruptions with their own consequences', () {
    test('a handler throwing on a request carrying 1e999 still delivers an '
        'error over a real socket', () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();

      // `1e999` is written as text because there is no way to reach it through
      // `jsonEncode` — encoding an Infinity is exactly what throws, which is
      // the asymmetry the whole trap is built on. `sub` is where a String
      // belongs, so decoding this drives the handler into a TypeError and
      // `_answer` has to turn that into an error the client can receive.
      const id = 'poison-1';
      fixture.client.sink.add('{"jsonrpc":"2.0","id":"$id",'
          '"method":"${Methods.subscribe}","params":'
          '{"sub":1e999,"keys":["$_key"]}}');

      final delivered =
          await _untilFrame(fixture, '"$id"', budget: _poisonBudget);

      expect(delivered, isTrue,
          reason: 'the caller was never told its request failed. An error '
              'response that echoes a request carrying Infinity cannot be '
              'encoded, so json_rpc_2 discards it inside the Peer and the '
              'caller waits forever — Phase 4 owns deadlines and does not '
              'exist yet, so forever is the literal duration. '
              'relay_session.dart\'s _substitute is what keeps the answer '
              'sendable; this case is what notices when it is gone');

      expect(await _stillAnswers(fixture), isTrue,
          reason: 'a poisoned request must cost one request, not the session');
    });

    test('an oversized frame does not kill the session', () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();

      final sessions = fixture.server.sessions;
      final priorSessions = sessions.sessionCount;

      // A genuine oversized *request* — padded inside `params`, so the server
      // decodes and dispatches it rather than routing it to the client half as
      // a stray response. There is no frame-size limit anywhere in the path
      // (T-02-29 / T-03-29); what this case fixes is the consequence, so that
      // a ceiling added later changes the verdict here and is noticed.
      final pad = 'x' * oversizeBytes;
      fixture.client.sink.add('{"jsonrpc":"2.0","id":"oversize-1",'
          '"method":"${Methods.ping}","params":{"pad":${jsonEncode(pad)}}}');

      expect(await _stillAnswers(fixture, budget: _oversizeBudget), isTrue,
          reason: 'an 8 MiB frame must cost at most the request that carried '
              'it; a session that died here would let one oversized query '
              'from one panel disconnect that panel every time it retried');
      expect(sessions.sessionCount, priorSessions,
          reason: 'the oversized frame must not take the session with it');
    }, timeout: const Timeout.factor(4));

    test('two documents concatenated in one frame leave the session answering',
        () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();

      final sessions = fixture.server.sessions;
      final priorSessions = sessions.sessionCount;

      // A framing bug that concatenated two documents. Neither copy is valid
      // JSON in the same frame, so *both* are lost — including the first,
      // which on its own would have been answered.
      final one = _request('duplicate-1');
      fixture.client.sink.add('$one$one');

      expect(await _stillAnswers(fixture), isTrue,
          reason: 'a concatenated frame is a framing bug on the client side; '
              'the server must reject it and keep serving, not treat it as a '
              'reason to end the session');
      expect(sessions.sessionCount, priorSessions,
          reason: 'the concatenated frame must not take the session with it');
      expect(sessions.subscriptionCount, 0,
          reason: 'a rejected frame must not have changed any state on the '
              'way to being rejected');
    });
  });
}

/// A valid JSON-RPC request, as the text a corruption is applied to.
String _request(String id) =>
    '{"jsonrpc":"2.0","id":"$id","method":"${Methods.ping}"}';

/// Whether a following **valid** request is answered inside [budget].
///
/// The closing property of every case in this file, in one place so that all
/// of them mean the same thing by it. A deadline converted into a bool: silence
/// is the failure mode being guarded against, and a matcher cannot express it.
Future<bool> _stillAnswers(RelayFixture fixture, {Duration? budget}) async {
  final within = budget ?? _answerBudget;
  try {
    await fixture.request(Methods.ping, budget: within);
    return true;
  } on rpc.RpcException {
    // An *error* answer is still an answer: the server was reachable, it
    // decided, and it replied. Only a session that says nothing is wedged.
    return true;
  } catch (_) {
    // Everything else is a session that did not answer, and the distinction is
    // load-bearing rather than defensive. A blanket `return true` here reads as
    // "it threw, so it was alive", which is exactly backwards: a peer whose
    // stream has errored, or a sink that has been closed under it, throws
    // *synchronously* and instantly — so a dead session would score as the
    // liveliest one in the file. That version of this helper passed against a
    // deliberately broken server during this plan's RED run, which is why the
    // clause above is narrowed to the one exception that means "answered".
    // `within()`'s TestFailure for silence lands here too, and means the same
    // thing: no answer.
    return false;
  }
}

/// Whether a frame containing [needle] reaches the client inside [budget].
///
/// Reads `fixture.inbound` rather than awaiting a peer request, because the
/// requests these cases send are written straight onto the socket — the
/// fixture's own peer has no pending entry for their ids and would discard the
/// answers. A deadline turned into a bool, for the same reason as everywhere
/// else here.
Future<bool> _untilFrame(RelayFixture fixture, String needle,
    {required Duration budget}) async {
  final deadline = DateTime.now().add(budget);
  while (!fixture.inbound.any((frame) => frame.contains(needle))) {
    if (DateTime.now().isAfter(deadline)) return false;
    await pumpEventQueue(times: 1);
  }
  return true;
}
