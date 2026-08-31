@TestOn('vm')

/// SEC-03's authorization clause: who may see a tag, and who may actuate one.
///
/// **Source: 06-CONTEXT decision 2**, the user's framing recorded verbatim —
/// *"What if it should be hidden. Let's think about the future even though we
/// don't implement all at once"* — and 06-RESEARCH §E. The seam ships now; the
/// policy data does not. So the shipped rule is trivial (everything visible,
/// `operate` may write) and the *enforcement* is structural: one object per
/// session that every key-touching surface reaches the source through.
///
/// ## What breaks in the plant without this file
///
/// Two different things, and they are worth separating because they fail
/// differently.
///
/// Without the write gate a wall display in the canteen — a `view` station,
/// bolted up precisely because nobody should be actuating a machine from it —
/// can start a conveyor. That is one missing comparison away at all times, and
/// the failure is loud only if somebody is standing next to the belt.
///
/// Without the **hiding rule** the failure is quiet, which is why CONTEXT locks
/// it as architecture rather than as a feature. A refusal that says *forbidden*
/// tells the asker that the tag exists. Ask about a thousand names, keep the
/// ones answered *forbidden* rather than *unknown*, and the gateway has just
/// enumerated the plant's address space for a station that may not read a byte
/// of it. So a hidden key must be **indistinguishable from a key that does not
/// exist** — the same answer on `read`, `readFresh`, `readMany`, `subscribe`
/// and `write`, and absent from `keys`.
///
/// ## Why this check is here and not in the contract kit
///
/// Trap 19 / §E.4. `tfc_stateman_contract`'s `suite_integrity_test.dart` has
/// three gates (`:102-109`, `:133-141`, `:143+`) that force any check written
/// in that package into `allContractChecks`, and three drivers assert against
/// that length for their **full** leg — including the fake leg, which under
/// 06-CONTEXT amendment 3 has no policy at all and could therefore only pass
/// such a check *vacuously*, by comparing a nonexistent key with a nonexistent
/// key. `suite_integrity_test.dart:104-108` names that outcome: "a property
/// nobody is testing that reads like coverage is worse than an absent one".
///
/// A server-side seam has exactly one implementation by construction, so a
/// cross-implementation contract check was never buying anything here. What
/// this file keeps is all the teeth: the production policy object, the
/// production gateway, the production transport, the production error shapes.
/// `allContractChecks.length` does not move.
@Tags(['ws'])
library;

import 'dart:async';
import 'dart:mirrors';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/auth/identity.dart';
import 'package:tfc_relay_server/src/policy/key_policy.dart';
import 'package:tfc_relay_server/src/policy/policy_state_man.dart';
import 'package:tfc_relay_server/src/relay_server.dart';
import 'package:tfc_relay_server/src/relay_session.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/token_validator.dart';
import 'package:tfc_relay_server/src/ws_channel.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart' show within;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A tag in the plant's own naming convention, so the cases read like the
/// thing they model rather than like synthetic strings.
const _key = 'CN01.MOT01.speed';

/// The tag the test policy hides. A second real tag on a real machine — the
/// point being that it is every bit as servable as [_key] and is concealed
/// only because the policy says so.
const _hidden = 'CN02.MOT01.speed';

/// A tag no fixture ever seeds and no policy ever mentions: the control the
/// hidden one is compared against. `nonexistent_key_test.dart`'s `_ghost`, in
/// the same spelling, because the property under test is that the two answers
/// are the same one.
const _ghost = 'CN01.MOT01.speeed';

/// A panel next to a machine, and a display on a wall.
const _panel = Identity(stationId: 'ST101', role: Role.operate);
const _display = Identity(stationId: 'HALL-DISPLAY', role: Role.view);

// ---------------------------------------------------------------------------
// The levers.
// ---------------------------------------------------------------------------

/// A policy that hides exactly the tags it is given, and otherwise ships.
///
/// The lever 06-RESEARCH §E.4 calls for, and the reason `RelayServer` takes a
/// `policy:` argument at all. It is deliberately not clever: hiding is a set
/// membership test, because 06-CONTEXT's scope fence forbids defining the
/// pattern grammar this phase and a test policy that invented one would be
/// specifying policy language by the back door.
final class _HidesTags implements KeyPolicy {
  const _HidesTags(this.hidden);

  final Set<String> hidden;

  @override
  bool canSee(String key, Identity identity) => !hidden.contains(key);

  @override
  bool canWrite(String key, Identity identity) =>
      identity.role == Role.operate;
}

/// A validator that hands every session one fixed identity.
///
/// Cheaper than a token file for cases whose subject is the *policy* rather
/// than the credential — `auth_test.dart` owns the file-shaped cases, and a
/// second copy of its temp-directory machinery here would be a second place
/// the token format is written down.
final class _AlwaysStation implements TokenValidator {
  const _AlwaysStation(this.identity);

  final Identity identity;

  @override
  Future<TokenVerdict> validate(HelloParams params) async =>
      TokenAccepted(identity);
}

// ---------------------------------------------------------------------------
// A gateway with a policy on it, and real sockets in front.
// ---------------------------------------------------------------------------

/// One real [RelayServer] carrying a policy, with the plant behind it.
///
/// Local rather than `ws_harness.dart`'s `relayFixture`, which takes no
/// `policy:` argument and owns exactly one socket. Both matter here: the
/// policy *is* the subject, and the dispose case needs two stations on one
/// gateway so that "closing one leaves the other reading" is a property rather
/// than a single-session tautology.
final class _Gateway {
  _Gateway._(this.plant, this.server);

  /// The reference implementation the gateway serves, driveable directly.
  final FakeStateMan plant;
  final RelayServer server;

  /// The sessions this gateway is holding, in connection order.
  List<RelaySession> get sessions => server.sessions.sessions;

  /// The **production** decorator the first session is serving through.
  ///
  /// Read off the live session rather than rebuilt here, which is the whole
  /// difference between checking the object under test and checking a
  /// second one built the same way.
  PolicyStateMan get served => sessions.first.api;

  static Future<_Gateway> start({
    KeyPolicy policy = const AllVisibleOperatorWrites(),
    Identity identity = _panel,
  }) async {
    final plant = FakeStateMan();
    final server = RelayServer(
      api: plant,
      config: ServerConfig(tick: ServerConfig.minTick),
      validator: _AlwaysStation(identity),
      policy: policy,
      // A collector that discards: several cases here provoke refusals on
      // purpose, and a suite printing a stack trace per provoked refusal
      // trains everyone to scroll past them (`ws_harness.dart:231-235`).
      onError: (_, __, ___) {},
    );
    await server.start();
    addTearDown(() async {
      await server.close();
      await plant.dispose();
    });
    return _Gateway._(plant, server);
  }

  /// A station on this gateway, connected and past the handshake.
  Future<_Station> station() async {
    final opened = server.sessions.opened.first;
    final ws =
        IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${server.port}'));
    await ws.ready;
    final finished = Completer<void>();
    final base = wsChannel(ws);
    final tapped = base.stream.transform(
        StreamTransformer<String, String>.fromHandlers(handleDone: (sink) {
      if (!finished.isCompleted) finished.complete();
      sink.close();
    }));
    final peer = rpc.Client(StreamChannel<String>(tapped, base.sink));
    unawaited(peer.listen().catchError((Object _) => null));
    addTearDown(() async {
      await peer.close();
      await ws.sink.close().catchError((Object _) {});
    });
    // Awaited before the hello so a case reading `sessions` cannot race the
    // accept — `ws_harness.dart:315` makes the same argument for the same
    // reason.
    await opened.timeout(const Duration(seconds: 5));
    final station = _Station._(ws, peer, finished.future);
    await station.hello();
    return station;
  }
}

/// One connected client, past the handshake.
final class _Station {
  _Station._(this._ws, this._peer, this.done);

  final WebSocketChannel _ws;
  final rpc.Client _peer;

  /// Completes when this station's socket has finished, however it finished.
  final Future<void> done;

  bool get isOpen => _ws.closeCode == null;

  Future<void> hello() => request(Methods.hello,
      params: HelloParams(
        protocol: protocolVersion,
        supported: const [protocolVersion],
        client: const PeerInfo('panel-under-test', '0.1.0'),
      ).toJson(),
      what: 'the hello result over a real socket');

  Future<Object?> request(String method,
          {Object? params,
          String? what,
          Duration budget = const Duration(seconds: 2)}) =>
      within(_peer.sendRequest(method, params),
          what ?? 'a $method response over a real socket',
          budget: budget);

  /// Sends [method] expecting a refusal, and hands back the refusal.
  ///
  /// A method that is *answered* fails here rather than at a downstream
  /// matcher, so the report names the property rather than the assertion that
  /// tripped over it (`ws_harness.dart:153-168`).
  Future<rpc.RpcException> refusal(String method,
      {Object? params, required String what}) async {
    try {
      await request(method, params: params, what: what);
    } on rpc.RpcException catch (error) {
      return error;
    }
    fail('$what was answered instead of refused');
  }
}

/// One decoded JSON object, cast where the wire hands back `Object?`.
Map<String, Object?> _asMap(Object? raw) =>
    (raw! as Map).cast<String, Object?>();

void main() {
  group('the shipped policy is trivial, and honestly named', () {
    test('the shipped policy lets an operator write and a viewer not', () {
      const policy = AllVisibleOperatorWrites();

      expect(policy.canSee(_key, _display), isTrue,
          reason: 'CONTEXT decision 2 fixes this phase\'s canSee at "always '
              'true": there is no policy data yet to hide anything with, and '
              'a seam that hid something nobody configured would be policy '
              'invented by the plumbing. A view station reads the plant — '
              'that is what a wall display is for');
      expect(policy.canSee(_key, _panel), isTrue,
          reason: 'the same answer for both roles, because canSee does not '
              'read the role at all this phase. If this ever diverges by role '
              'without a policy file saying so, the divergence came from the '
              'seam rather than from a deployment');

      expect(policy.canWrite(_key, _panel), isTrue,
          reason: 'an operate station is a panel bolted next to a machine, '
              'and refusing its writes would be a gateway that serves nobody. '
              'This is also what keeps every fixture in this workspace '
              'writing: PermissiveTokenValidator grants operate');
      expect(policy.canWrite(_key, _display), isFalse,
          reason: 'a view station actuating a machine is T-06-35, the whole '
              'of SEC-03\'s authorization clause. The canteen display can '
              'start a conveyor if this comparison is missing, and the only '
              'person who finds out is whoever is standing next to the belt');
    });

    test('the shipped policy is const-constructible and reads honestly in a '
        'config diff', () {
      expect(identical(const AllVisibleOperatorWrites(),
              const AllVisibleOperatorWrites()),
          isTrue,
          reason: 'Dart canonicalises const instances, which is what lets a '
              'default be compared by identity the way RelayServer already '
              'compares its permissive validator (relay_server.dart:149). A '
              'non-const default would make that idiom unavailable to the '
              'next plan that needs it');
      expect('$AllVisibleOperatorWrites', 'AllVisibleOperatorWrites',
          reason: 'named for what it *does*, not for what it lacks — '
              'PermissiveTokenValidator\'s argument (token_validator.dart:'
              '70-73), and for the same reason: a deployment still running '
              'the shipped policy in Phase 12 has to be legible in a config '
              'diff. A name like NoPolicy or DefaultPolicy reads as "somebody '
              'configured this"');
    });
  });

  group('the interface itself', () {
    test('the policy interface is synchronous', () {
      final members = reflectClass(KeyPolicy)
          .declarations
          .values
          .whereType<MethodMirror>()
          .where((member) => !member.isConstructor && !member.isPrivate)
          .toList();

      expect(
          members.map((m) => MirrorSystem.getName(m.simpleName)).toSet(),
          {'canSee', 'canWrite'},
          reason: 'two members, and only two. CONTEXT decision 2 names '
              'canSee and canWrite; a third would be policy vocabulary '
              'invented before there is policy data to fill it');

      for (final member in members) {
        final name = MirrorSystem.getName(member.simpleName);
        final returns = MirrorSystem.getName(member.returnType.simpleName);
        expect(returns, 'bool',
            reason: '$name returns $returns. An asynchronous policy is what '
                'introduces the await between the atCapacity check and the '
                'put in session_handlers.dart:255-264 — the comment there '
                'says so in as many words, and names this phase as the '
                'obvious thing to open the race. A subscription that got past '
                'a full ceiling would then be refused as -32011 '
                'handlerFailed, whose documented meaning is "retrying is '
                'legitimate", so a panel would retry a limit it can never get '
                'under. The shipped policy is a constant and a role '
                'comparison over a token file already in memory: there is '
                'nothing here to await');
      }
    });

    test('the policy is not on the wire vocabulary', () {
      // Amendment 3, asserted from the type system rather than from a grep.
      // `KeyPolicy` lives in this package; `StateManApi` lives in the protocol
      // package, which this one depends on and not the reverse. A policy
      // member on the wire interface is therefore impossible to write, and
      // that impossibility is the amendment satisfied by construction —
      // api_surface_test stays at 49 because there is nothing that could move
      // it.
      //
      // Read as the library's **uri** rather than its name: every library in
      // this package is declared `library;` with a doc comment above it, so
      // `simpleName` is the empty string for all of them and a name-based
      // assertion would pass against anything.
      final home = (reflectClass(KeyPolicy).owner! as LibraryMirror).uri;
      expect('$home', startsWith('package:tfc_relay_server/'),
          reason: 'the policy interface moved out of the server package. The '
              'access-control question is not one a connected client may ask: '
              'api_surface_test.dart:213-226 calls the 49-member set "the '
              'access-control policy", so adding a policy *query* to it is '
              'the contradiction 06-CONTEXT amendment 3 forbids');
    });
  });

  group('the decorator hides through the key list', () {
    test('a hidden key is absent from the key list', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      gateway.plant.setValue(_key, 1200);
      gateway.plant.setValue(_hidden, 900);
      await gateway.station();

      expect(gateway.plant.keys, contains(_hidden),
          reason: 'the anti-vacuity half, and it goes first: the source really '
              'does serve this tag. Without it the case below would pass '
              'against a policy that hides nothing, because the tag would be '
              'absent for the ordinary reason');
      expect(gateway.served.keys, isNot(contains(_hidden)),
          reason: '`keys` is the hiding primitive (06-RESEARCH §E.2). It is '
              'the one getter that read, readFresh, readMany, subscribe and '
              'write all already gate on, so filtering it is what makes a '
              'hidden tag take the nonexistent-tag path on every one of them '
              'with no edit to any of those surfaces. A decorator that hid '
              'per-surface instead would be five places to forget');
      expect(gateway.served.keys, contains(_key),
          reason: 'a filter that removed everything would pass the assertion '
              'above and break the plant. The visible tag is the control');
    });

    test('the decorator is transparent under the shipped policy', () async {
      final gateway = await _Gateway.start();
      gateway.plant.setValue(_key, 1200);
      gateway.plant.setValue(_hidden, 900);
      await gateway.station();

      expect(gateway.served.keys, equals(gateway.plant.keys),
          reason: 'under AllVisibleOperatorWrites the decorator must be '
              'invisible — same list, same order. It sits in the path of '
              'every request the whole suite makes, so anything it changes '
              'here it changes for all 454 of them, and a leak found later '
              'would be attributed to the policy instead of to the plumbing');
    });

    test('readFresh answers a hidden key the way it answers a nonexistent one',
        () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      gateway.plant.setValue(_hidden, 900);
      final station = await gateway.station();

      final forHidden =
          _asMap(await station.request(Methods.readFresh, params: {
        'key': _hidden,
      }));
      final forGhost = _asMap(await station.request(Methods.readFresh, params: {
        'key': _ghost,
      }));

      // Compared to each other with only the key name normalized, never
      // against literals: a later phase changing the nonexistent shape must
      // change both, which is exactly the property 06-04 established between
      // `read` and `readFresh` and this one inherits.
      expect(_withoutKeyName(forHidden, _hidden),
          equals(_withoutKeyName(forGhost, _ghost)),
          reason: 'readFresh gave a hidden tag a different answer from one '
              'that never existed. Any difference at all is an existence '
              'oracle: ask about a thousand names, keep the ones answered '
              'differently, and the plant\'s address space has been '
              'enumerated by a station that may not read a byte of it');
      expect(_asMap(forHidden['value'])['v'], isNull,
          reason: 'the reading itself must not come through. A hidden tag '
              'that answered 900 under a bad quality would be the value '
              'leaking behind the concealment');
    });

    test('the decorator\'s readFresh refuses a hidden key without asking the '
        'source', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      gateway.plant.setValue(_hidden, 900);
      await gateway.station();

      final before = gateway.plant.roundTrips;
      final answer = await gateway.served.readFresh(_hidden);

      expect(gateway.plant.roundTrips, before,
          reason: 'readFresh is an override and not a delegation, on purpose '
              '(§E.2 item 2). Forwarding would make the answer the source\'s '
              'to choose: FakeStateMan happens to answer q:258, and '
              'LocalStateMan over a real DeviceClient may throw — neither is '
              'the nonexistent shape this gateway promises, and a round trip '
              'to the plant for a tag the caller may not know exists is a '
              'side channel besides');
      expect(answer.quality, Quality.errorConfig,
          reason: 'the quality the gateway gives a tag its source does not '
              'serve (06-04): 770 is "the source affirmatively said the tag '
              'is gone", which is the sentence a hidden tag must also get. '
              '258 would say "wait, it is coming" about something that never '
              'will');
      expect(answer.value, isNull);
    });
  });

  group('the decorator owns nothing it could tear down', () {
    test('closing one session leaves another\'s reads working', () async {
      final gateway = await _Gateway.start();
      gateway.plant.setValue(_key, 1200);
      final first = await gateway.station();
      final second = await gateway.station();
      expect(gateway.sessions, hasLength(2));

      await gateway.sessions.first
          .close(CloseCodes.serverDraining, 'the first station is going away');
      await within(first.done, 'the first station\'s socket to finish',
          budget: const Duration(seconds: 3));

      final answer =
          _asMap(await second.request(Methods.read, params: {'key': _key}));

      expect(second.isOpen, isTrue,
          reason: 'the surviving station lost its socket when its neighbour '
              'closed. The decorator holds no resources of its own, so its '
              'dispose must delegate and nothing more — the source is one '
              'instance shared by every panel on this gateway '
              '(relay_server.dart:213-214, "One instance, shared"), and a '
              'per-session teardown that disposed it would take the whole '
              'plant down with one panel');
      expect(_asMap(answer['value'])['v'], 1200,
          reason: 'the surviving station can still read. An open socket over '
              'a disposed source is the quieter half of the same failure');
    });
  });
}

/// One answer with the tag name taken out of it, so two answers about
/// different tags can be compared for everything else.
///
/// The key is the one field that legitimately differs between "the tag you
/// hid" and "the tag that never was", and normalizing it is what lets the
/// rest be compared structurally instead of field by hand-written field.
Map<String, Object?> _withoutKeyName(Map<String, Object?> answer, String key) {
  String scrub(String text) => text.replaceAll(key, '<tag>');

  Object? walk(Object? node) {
    if (node is String) return scrub(node);
    if (node is List) return node.map(walk).toList();
    if (node is Map) {
      return {
        for (final entry in node.entries) scrub('${entry.key}'): walk(entry.value),
      };
    }
    return node;
  }

  return (walk(answer)! as Map).cast<String, Object?>();
}
