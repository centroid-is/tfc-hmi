/// The session's front door: what a client may do before it has said hello,
/// what a hello buys it, and what a request that cannot be answered does.
///
/// Driven over `channelPair()` — an in-memory `StreamChannel<String>` with a
/// real `json_rpc_2` client on the far end and no sockets anywhere. The socket
/// is 03-04's subject; every property below is a property of the session, and
/// a property that needs a port to be asserted is a property that gets
/// asserted rarely.
///
/// Two of these cases are the verification of something research could only
/// mark [ASSUMED] or measure once:
///
///  * **Pre-hello rejection.** 03-CONTEXT rules that gating lives in the
///    handler wrapper rather than in `registerFallback`, whose behaviour is
///    untested upstream. The wrapper either gates or it does not, and the case
///    below is how we know which.
///  * **The 02-05 hang.** `RpcException.serialize` copies the offending
///    request into `error.data` unless `data['request']` is already set. One
///    request carrying `1e999` decodes to `Infinity`, the error response
///    becomes unencodable, the peer drops it, and a caller with no deadline
///    waits forever. The case below asserts a *bool derived from a deadline*
///    rather than waiting on a matcher, for the reason
///    `malformed_peer_test.dart:1-33` gives: a matcher that waits for
///    something that never happens reports this file's name instead of the
///    broken property.
library;

import 'dart:async';
import 'dart:convert';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/error_codes.dart';
import 'package:tfc_relay_server/src/handle_table.dart';
import 'package:tfc_relay_server/src/relay_session.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/token_validator.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

/// One session, one client, both wired and listening.
final class _Link {
  _Link(this.session, this.client, this.api);
  final RelaySession session;
  final rpc.Client client;
  final FakeStateMan api;

  /// Everything this session started, stopped. The fake keeps a periodic
  /// freshness sweep running, and a timer left behind by a finished case is
  /// the leak class F23 exists to catch.
  Future<void> dispose() async {
    await client.close();
    await session.close(1000, 'test over');
    await api.dispose();
  }
}

_Link _link({TokenValidator? validator, List<String>? serverSupported}) {
  final pair = channelPair();
  final api = FakeStateMan();
  final session = RelaySession.serve(
    channel: pair.server,
    api: api,
    config: ServerConfig(),
    handles: HandleTable(),
    buffer: ConflatingSendBuffer(maxPending: 4096),
    validator: validator ?? const PermissiveTokenValidator(),
    serverSupported: serverSupported ?? const [protocolVersion],
  );
  final client = rpc.Client(pair.client);
  unawaited(client.listen());
  return _Link(session, client, api);
}

Map<String, Object?> _hello({List<String>? supported}) => HelloParams(
      protocol: supported?.first ?? protocolVersion,
      supported: supported ?? const [protocolVersion],
      client: const PeerInfo('panel-under-test', '0.1.0'),
    ).toJson();

/// Sends [method] expecting a refusal, and hands back the refusal.
Future<rpc.RpcException> _refusal(
    Future<Object?> call, String what) async {
  try {
    await within(call, what);
  } on rpc.RpcException catch (error) {
    return error;
  }
  fail('$what was answered instead of refused');
}

/// A validator that turns every client away, standing in for Phase 6's.
final class _RejectingValidator implements TokenValidator {
  @override
  Future<TokenVerdict> validate(HelloParams params) async =>
      const TokenRejected('no credential presented');
}

void main() {
  test('a request before hello is refused and the link stays open', () async {
    final link = _link();
    addTearDown(link.dispose);

    // `ping`, because it is one of the two methods that exist today; 03-05's
    // `subscribe` will be gated by the same wrapper without touching it, which
    // is the point of gating at the registration seam rather than per handler.
    final refusal =
        await _refusal(link.client.sendRequest(Methods.ping), 'a pre-hello ping');

    expect(refusal.code, ServerErrorCodes.helloRequired,
        reason: 'an unauthenticated client must be told what is missing, not '
            'served');
    expect((refusal.data as Map)['request'], isA<String>(),
        reason: 'even a refusal must carry the substituted request, or the '
            'refusal itself is unencodable when the request was poison');

    final result = await within(
        link.client.sendRequest(Methods.hello, _hello()), 'a hello after the '
            'refusal');
    expect(HelloResult.fromJson((result as Map).cast()).protocol,
        protocolVersion,
        reason: 'a pre-hello request is refused *without closing* (Home '
            'Assistant\'s pre-auth rule): the client gets to correct itself');
  });

  test('a valid hello negotiates a version and opens a session', () async {
    final link = _link();
    addTearDown(link.dispose);
    final before = DateTime.now().millisecondsSinceEpoch;

    final raw = await within(
        link.client.sendRequest(Methods.hello, _hello()), 'the hello result');
    final result = HelloResult.fromJson((raw as Map).cast());

    expect(result.protocol, protocolVersion);
    expect(result.sessionId, isNotEmpty);
    expect(result.epoch, isNotEmpty);
    expect(result.resumed, isFalse,
        reason: 'nothing is resumable yet; a client told otherwise would keep '
            'a cache the server cannot honour');
    expect(result.serverTime,
        inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
        reason: 'the client derives its clock offset from this, so staleness '
            'is measured against one clock');

    final other = _link();
    addTearDown(other.dispose);
    final second = HelloResult.fromJson(
        ((await within(other.client.sendRequest(Methods.hello, _hello()),
                'a second session\'s hello')) as Map)
            .cast());
    expect(second.sessionId, isNot(result.sessionId),
        reason: 'two sessions sharing an id merge in every log the gateway '
            'writes');
  });

  test('a second hello on the same session is refused', () async {
    final link = _link();
    addTearDown(link.dispose);
    await within(
        link.client.sendRequest(Methods.hello, _hello()), 'the first hello');

    final refusal = await _refusal(
        link.client.sendRequest(Methods.hello, _hello()), 'a second hello');
    expect(refusal.code, ServerErrorCodes.alreadyHelloed);

    expect(await within(link.client.sendRequest(Methods.ping), 'a ping after '
        'the refused second hello'), isA<Map>(),
        reason: 'a renegotiation attempt is a client bug, not a hostile act: '
            'the session it already has keeps working');
    expect(link.session.sentCloseCode, isNull);
  });

  test('an unspeakable version records 4005 with both lists', () async {
    final link = _link();
    addTearDown(link.dispose);

    final refusal = await _refusal(
        link.client
            .sendRequest(Methods.hello, _hello(supported: ['1999-01-01'])),
        'a hello naming a version the server cannot speak');

    expect(refusal.code, ServerErrorCodes.versionMismatch);
    final data = (refusal.data as Map).cast<String, Object?>();
    expect(data['supported'], contains(protocolVersion));
    expect(data['requested'], contains('1999-01-01'),
        reason: 'both lists, MCP\'s rule: a client that is told only "no" has '
            'nothing to log and nothing to fix');

    expect(link.session.sentCloseCode, CloseCodes.protocolMismatch,
        reason: 'asserted on the session\'s own record, never on a socket\'s '
            'closeCode — that field is unreliable for a self-initiated close '
            '(web_socket_channel #1698)');
  });

  test('a rejected credential refuses hello and records 4001', () async {
    final link = _link(validator: _RejectingValidator());
    addTearDown(link.dispose);

    final refusal = await _refusal(
        link.client.sendRequest(Methods.hello, _hello()),
        'a hello with a credential the validator rejects');

    expect(refusal.code, ServerErrorCodes.unauthorized);
    expect(link.session.sentCloseCode, CloseCodes.authExpired);
  });

  test('a handler throwing on a request carrying 1e999 still delivers an error',
      () async {
    // Hand-written frame: `jsonEncode` refuses to emit Infinity, so a poison
    // request can only be built as text — which is exactly how it arrives from
    // a non-Dart client, and how `1e999` got into the catalogue.
    final pair = channelPair();
    final api = FakeStateMan();
    final session = RelaySession.serve(
      channel: pair.server,
      api: api,
      config: ServerConfig(),
      handles: HandleTable(),
      buffer: ConflatingSendBuffer(maxPending: 4096),
    );
    addTearDown(() async {
      await session.close(1000, 'test over');
      await api.dispose();
    });

    final answered = Completer<Map<String, Object?>>();
    pair.client.stream.listen((frame) {
      if (!answered.isCompleted) {
        answered.complete((jsonDecode(frame) as Map).cast<String, Object?>());
      }
    });
    pair.client.sink.add('{"jsonrpc":"2.0","id":"poison","method":"hello",'
        '"params":{"protocol":1e999,"supported":[],"client":{"name":"p",'
        '"version":"1"}}}');

    const budget = Duration(milliseconds: 500);
    final delivered = await within(
        answered.future.then((_) => true).timeout(budget, onTimeout: () => false),
        'the error answer to a request carrying 1e999',
        budget: const Duration(seconds: 2));

    expect(delivered, isTrue,
        reason: 'this is the 02-05 hang: an error response that echoes a '
            'request carrying Infinity cannot be encoded, the peer drops it, '
            'and a caller with no deadline waits forever');

    final error = ((await answered.future)['error'] as Map).cast<String, Object?>();
    expect(error['code'], ServerErrorCodes.typeMismatch);
    expect(((error['data'] as Map)['request'] as String), contains('omitted'),
        reason: 'the substitution is what keeps the answer sendable');
  });

  test('the handler table is exactly hello, ping, subscribe and unsubscribe',
      () async {
    final link = _link();
    addTearDown(link.dispose);

    expect(
        link.session.registeredMethods,
        {
          Methods.hello,
          Methods.ping,
          Methods.subscribe,
          Methods.unsubscribe,
        },
        reason: 'the wire surface is a closed set: 03-05 added subscribe and '
            'unsubscribe, 03-08 freezes it. A handler nobody counted is '
            'surface nobody reviewed');
  });
}
