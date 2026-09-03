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

import 'package:json_rpc_2/error_code.dart' as rpc_error;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/auth/identity.dart';
import 'package:tfc_relay_server/src/error_codes.dart';
import 'package:tfc_relay_server/src/health/session_health_state_man.dart';
import 'package:tfc_relay_server/src/policy/key_policy.dart';
import 'package:tfc_relay_server/src/policy/policy_state_man.dart';
import 'package:tfc_relay_server/src/relay_server.dart';
import 'package:tfc_relay_server/src/relay_session.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/token_validator.dart';
import 'package:tfc_relay_server/src/ws_channel.dart';
import 'package:tfc_stateman_contract/testing/fake_data_services.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart' show within;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/permissive_resolver.dart';

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

/// The folder the hidden tag lives under, named as if it were a key.
///
/// One case hides *this* — a folder id, not a tag — to pin the rule that
/// browse asks `canSee` about variables and nothing else. See
/// `a folder is never asked about`.
const _hiddenParent = 'CN02.MOT01';

// ---------------------------------------------------------------------------
// The address space, whose leaf ids are plant keys.
// ---------------------------------------------------------------------------

/// The visible tag, as a browse node.
const _visibleNode = BrowseNode(
    id: _key,
    displayName: 'speed',
    type: BrowseNodeType.variable,
    dataType: 'Float');

/// The hidden tag, as a browse node. Every field but the id matches
/// [_visibleNode] and [_probeNodeFor], which is what lets the detail answers
/// be compared rather than described.
const _hiddenNode = BrowseNode(
    id: _hidden,
    displayName: 'speed',
    type: BrowseNodeType.variable,
    dataType: 'Float');

/// The node a case hands to `fetchDetail`, for any id.
///
/// A client already holds these fields — they came off a browse list, or it
/// made them up — so echoing them back discloses nothing. The *id* is the only
/// thing that varies, and it is the only thing `fetchDetail` could answer
/// differently about.
BrowseNode _probeNodeFor(String id) => BrowseNode(
    id: id,
    displayName: 'speed',
    type: BrowseNodeType.variable,
    dataType: 'Float');

/// A tree whose **leaf ids are plant keys**, so a permissive resolver's
/// identity mapping is the real thing rather than a stand-in.
///
/// `FakeBrowse`'s default tree uses OPC-UA-shaped ids (`ST101.CN01…`) that
/// map to no key this file's policy has ever heard of, which would make every
/// browse case here pass by hiding nothing. The reading on [_hidden] is
/// seeded so the anti-vacuity arm can show what the hiding actually removed.
FakeBrowse _browseTree() => FakeBrowse(
      roots: const [
        BrowseNode(
            id: 'CN01', displayName: 'CN01', type: BrowseNodeType.folder),
        BrowseNode(
            id: 'CN02', displayName: 'CN02', type: BrowseNodeType.folder),
      ],
      children: const {
        'CN01': [
          BrowseNode(
              id: 'CN01.MOT01',
              displayName: 'MOT01',
              type: BrowseNodeType.folder),
        ],
        'CN01.MOT01': [_visibleNode],
        'CN02': [
          BrowseNode(
              id: _hiddenParent,
              displayName: 'MOT01',
              type: BrowseNodeType.folder),
        ],
        _hiddenParent: [_hiddenNode],
      },
      details: {
        _hidden: BrowseNodeDetail(
            dataType: 'Float', value: DynamicValue(value: 900)),
      },
    );

// ---------------------------------------------------------------------------
// Recorded history, for the timeseries surface (10-03).
// ---------------------------------------------------------------------------

/// The instant the seeded series starts at. Fixed and UTC.
final _tsBase = DateTime.utc(2026, 8, 13, 6);

/// A series name the fixtures' resolver maps to **no** key at all.
///
/// The third thing a station can ask about, alongside "hidden" and "never
/// existed": a name that is well formed, that the gateway has no mapping for,
/// and that must therefore be answered as a series that does not exist — while
/// still being *counted*, because 10-CONTEXT amendment 6 requires an unmappable
/// table to be visible rather than merely refused.
const _unmapped = 'CN09.MOT01.speed';

int _ms(DateTime at) => at.millisecondsSinceEpoch;

/// Both real tags have history, so no timeseries case can pass by asking about
/// a series that was never recorded in the first place.
FakeTimeseries _seededHistory() => FakeTimeseries()
  ..seed(_key, [
    for (var i = 0; i < 5; i++)
      TimeseriesData<num>(1200 + i, _tsBase.add(Duration(minutes: i))),
  ])
  ..seed(_hidden, [
    for (var i = 0; i < 5; i++)
      TimeseriesData<num>(900 + i, _tsBase.add(Duration(minutes: i))),
  ]);

/// A resolver that maps the two real tags and refuses everything else.
///
/// `PermissiveSeriesResolver` maps every name to itself, which is honest for
/// this file's browse tree but cannot express "no mapping" — and "no mapping"
/// is the whole of what the unmappable cases are about. Everything it does map
/// it maps to itself, so the hiding comparison is unchanged for the names that
/// resolve.
final class _MapsTheRealTags implements SeriesResolver {
  const _MapsTheRealTags();

  static const _mapped = {_key, _hidden, _ghost};

  @override
  ResolvedSeries? resolve(String wireName) {
    final address = SeriesAddress.parse(wireName);
    if (!_mapped.contains(address.series)) return null;
    return ResolvedSeries(
        table: address.series,
        member: address.member,
        plantKey: address.series);
  }

  @override
  String? keyForTable(String table) =>
      _mapped.contains(table) ? table : null;

  @override
  String? keyForNode(String nodeId) => nodeId;
}

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
    SeriesResolver resolver = const PermissiveSeriesResolver(),
  }) async {
    final plant =
        FakeStateMan(browse: _browseTree(), timeseries: _seededHistory());
    final server = RelayServer(
      // Identity mapping by default: this file's tree names its leaves after
      // the plant keys they are, so `keyForNode` returning its argument is the
      // honest answer rather than a fixture's shortcut.
      // `permissive_resolver.dart` carries the sentence about what it would
      // mean in production. The timeseries cases override it with
      // `_MapsTheRealTags`, which is the same mapping plus the one thing a
      // permissive resolver cannot express: a name it will not map.
      resolver: resolver,
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

// ---------------------------------------------------------------------------
// The six surfaces, as one comparable answer each.
// ---------------------------------------------------------------------------

/// One surface, and how to ask it about a tag.
///
/// A list rather than six hand-written comparisons, so that adding a surface
/// in Phase 10 — `browse` is the obvious next one — is one entry here and the
/// indistinguishability case covers it automatically. That is the "cannot rot"
/// half of the property: a new way to ask about a tag is a new way to leak
/// that it exists, and the check should not have to be remembered.
typedef _Surface = ({
  String name,
  Future<Object?> Function(_Gateway gateway, _Station station, String key) ask,
});

const List<_Surface> _surfaces = [
  (name: 'read', ask: _askRead),
  (name: 'readFresh', ask: _askReadFresh),
  (name: 'readMany', ask: _askReadMany),
  (name: 'subscribe', ask: _askSubscribe),
  (name: 'write', ask: _askWrite),
  (name: 'keys', ask: _askKeys),
  // 10-02. The doc above invited browse as the seventh, and it is one entry
  // exactly as promised. **What "indistinguishable" means here is different
  // from the six above, and the difference is worth a reader's attention.**
  // Those six answer a *value* or a *refusal*, so the comparison is between
  // two answers about one tag. Browse answers *lists*, and a hidden tag is
  // not refused out of one — it is **absent** from it, which is the same
  // thing a nonexistent tag is. So the comparable shape below is "was this id
  // anywhere in the tree, what did resolvePath say, and what did the detail
  // pane get", and hidden and nonexistent have to agree on all three.
  (name: 'browse', ask: _askBrowse),
  // 10-03. The eighth, and it fits the existing shape without reshaping the
  // loop: a timeseries method is keyed by a *series name*, this file's tree
  // and its resolver both name a series after the plant key it records, so
  // "ask this surface about a tag" is a well-formed request here in exactly
  // the way it is for the other seven. What it compares is all four
  // timeseries methods at once, for browse's reason: a filter fitted to the
  // single-series path and forgotten on the multi-series one would hide a
  // tag from one chart and hand its history to the next.
  (name: 'timeseries', ask: _askTimeseries),
];

/// Whatever the gateway said, refusal or answer, in one comparable shape.
///
/// Both outcomes are captured rather than one being allowed to throw, because
/// "one surface refused and the other answered" is precisely the difference
/// the case is hunting and it should be *reported* rather than thrown out of
/// the loop.
Future<Object?> _outcome(
    Future<Object?> Function() ask, String key) async {
  try {
    return _withoutKeyName({'answered': await ask()}, key);
  } on rpc.RpcException catch (error) {
    return _withoutKeyName({
      'refused': {
        'code': error.code,
        'message': error.message,
        'data': error.data,
      },
    }, key);
  }
}

Future<Object?> _askRead(_Gateway gateway, _Station station, String key) =>
    _outcome(() => station.request(Methods.read, params: {'key': key}), key);

Future<Object?> _askReadFresh(_Gateway gateway, _Station station, String key) =>
    _outcome(
        () => station.request(Methods.readFresh, params: {'key': key}), key);

Future<Object?> _askReadMany(_Gateway gateway, _Station station, String key) =>
    _outcome(
        () => station.request(Methods.readMany, params: {
              'keys': [key]
            }),
        key);

/// `subscribe`, minus the bookkeeping that is about the *subscription* rather
/// than about the tag.
///
/// `sub` is the name the caller chose, `epoch` and `seq` belong to the
/// session, and `generation` is a server-global counter that increments on
/// every establishment — so two subscribes can never agree on it and none of
/// the four is a statement about the key. What is left is exactly the part
/// that carries existence: a key the gateway serves appears in `handles`,
/// `meta` and `snapshot`; a key it does not appears in `rejected` and in none
/// of the other three.
Future<Object?> _askSubscribe(
        _Gateway gateway, _Station station, String key) =>
    _outcome(() async {
      final answer = _asMap(await station.request(Methods.subscribe, params: {
        'sub': 'probe-${DateTime.now().microsecondsSinceEpoch}',
        'keys': [key],
      }));
      return {
        'handles': answer['handles'],
        'meta': answer['meta'],
        'snapshot': answer['snapshot'],
        'rejected': answer['rejected'],
      };
    }, key);

Future<Object?> _askWrite(_Gateway gateway, _Station station, String key) =>
    _outcome(
        () => station.request(Methods.write,
            params: {'cmd': newUlid(), 'key': key, 'value': 1450}),
        key);

/// Every node id the address space will show this station, walked over the
/// wire the way a panel expands a tree.
///
/// Read through the socket rather than off `gateway.served.browse`, because
/// the property is about what a *client* can learn and the handler is part of
/// the path that decides it.
Future<Set<String>> _reachableNodeIds(_Station station) async {
  final seen = <String>{};

  Future<void> walk(List<Object?> level) async {
    for (final raw in level) {
      final node =
          BrowseNode.fromJson((raw! as Map).cast<String, Object?>());
      if (!seen.add(node.id)) continue;
      final children = await station.request(
          DataServiceMethods.browseFetchChildren,
          params: {'parent': node.toJson()},
          what: 'the children of ${node.id}');
      await walk(children! as List<Object?>);
    }
  }

  final roots = await station.request(DataServiceMethods.browseFetchRoots,
      params: const <String, Object?>{}, what: 'the roots');
  await walk(roots! as List<Object?>);
  return seen;
}

/// Browse, as one comparable answer: listed, resolvable, and what its detail
/// pane got.
///
/// All three, not one. A filter that dropped a node from `fetchChildren` and
/// left `resolvePath` answering a full chain would hide the tag from the tree
/// and hand it back to anyone who asked for a path to it — and the panel that
/// restores a saved selection asks for exactly that on every page load.
Future<Object?> _askBrowse(
        _Gateway gateway, _Station station, String key) =>
    _outcome(() async {
      final listed = (await _reachableNodeIds(station)).contains(key);
      final chain = await station.request(
          DataServiceMethods.browseResolvePath,
          params: {'targetId': key},
          what: 'a path to $key');
      final detail = await station.request(
          DataServiceMethods.browseFetchDetail,
          params: {'node': _probeNodeFor(key).toJson()},
          what: 'the detail of $key');
      return {'listed': listed, 'path': chain, 'detail': detail};
    }, key);

/// All four timeseries methods, as one comparable answer.
///
/// Four rather than one, and the reason is browse's: a filter fitted to
/// `queryTimeseriesData` and forgotten on `queryTimeseriesDataMultiple` hides
/// a series from one chart and hands its history to the next, and the
/// multi-series path is the one every real chart with more than one line
/// uses.
///
/// The window is wide enough to contain everything [_seededHistory] records,
/// so an empty answer here means the *filter* emptied it rather than the
/// window.
Future<Object?> _askTimeseries(
        _Gateway gateway, _Station station, String key) =>
    _outcome(() async {
      final to = _tsBase.add(const Duration(hours: 1));
      final one = await station.request(DataServiceMethods.timeseriesQuery,
          params: {'table': key, 'to': _ms(to), 'from': _ms(_tsBase)},
          what: 'the recorded series for $key');
      final many =
          await station.request(DataServiceMethods.timeseriesQueryMultiple,
              params: {
                'tables': [key],
                'to': _ms(to),
                'from': _ms(_tsBase),
              },
              what: 'the multi-series answer for $key');
      final downsampled = await station.request(
          DataServiceMethods.timeseriesQueryDownsampled,
          params: {
            'table': key,
            'from': _ms(_tsBase),
            'to': _ms(to),
            'maxPoints': 100,
          },
          what: 'the downsampled series for $key');
      final counts =
          await station.request(DataServiceMethods.timeseriesCountMultiple,
              params: {
                'table': key,
                'intervalMs': const Duration(minutes: 1).inMilliseconds,
                'howMany': 10,
                'since': _ms(_tsBase),
              },
              what: 'the recording strip for $key');
      return {
        'one': one,
        'many': many,
        'downsampled': downsampled,
        'counts': counts,
      };
    }, key);

/// The key list, read off the production decorator.
///
/// Not on the wire — the handler table is nine names and none of them returns
/// a key list — so this one is asked of the object the gateway is actually
/// serving through rather than over the socket. It is in the loop because it
/// is the surface the other five inherit their answer from, and a
/// regression here would show up as five failures with no obvious cause.
Future<Object?> _askKeys(_Gateway gateway, _Station station, String key) async =>
    {'present': gateway.served.keys.contains(key)};

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

      expect(
          gateway.served.keys,
          equals([
            ...gateway.plant.keys,
            ...SessionHealthStateMan.perSessionKeys,
          ]),
          reason: 'under AllVisibleOperatorWrites the decorator must be '
              'invisible — same list, same order. It sits in the path of '
              'every request the whole suite makes, so anything it changes '
              'here it changes for all of them, and a leak found later '
              'would be attributed to the policy instead of to the plumbing. '
              'The six trailing names are not the policy: they are the '
              'per-session health overlay underneath it (08-12), and naming '
              'them here rather than relaxing the matcher is what keeps this '
              'case able to see the policy add or drop one');
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

  group('a series the gateway cannot map is a series that does not exist', () {
    test('an unmapped series answers exactly as a hidden one does', () async {
      final gateway = await _Gateway.start(
          policy: const _HidesTags({_hidden}),
          resolver: const _MapsTheRealTags());
      final station = await gateway.station();

      final forUnmapped = await _askTimeseries(gateway, station, _unmapped);
      final forHidden = await _askTimeseries(gateway, station, _hidden);

      expect(_withoutKeyName(forUnmapped! as Map<String, Object?>, _unmapped),
          equals(_withoutKeyName(forHidden! as Map<String, Object?>, _hidden)),
          reason: 'a series with no mapping was told apart from one the '
              'station may not see. Both must be the answer a series that '
              'does not exist gets, and the reason they must agree is that '
              'the difference is an oracle: the first says "this gateway '
              'does not collect that", which is a fact about the collection '
              'plan, and the second says "there is history here you may not '
              'have", which is the enumeration the hiding rule closes. '
              'Compared structurally rather than restated as a literal, so a '
              'later phase changing the nonexistent shape has to change both');
    });

    test('an unmapped series answers exactly as a nonexistent one does',
        () async {
      final gateway = await _Gateway.start(resolver: const _MapsTheRealTags());
      final station = await gateway.station();

      final forUnmapped = await _askTimeseries(gateway, station, _unmapped);
      final forGhost = await _askTimeseries(gateway, station, _ghost);

      expect(_withoutKeyName(forUnmapped! as Map<String, Object?>, _unmapped),
          equals(_withoutKeyName(forGhost! as Map<String, Object?>, _ghost)),
          reason: 'under the *shipped* policy, which hides nothing, an '
              'unmappable series must still be indistinguishable from a '
              'mapped series with no samples. Otherwise a station learns '
              'which names the collection plan contains without ever being '
              'refused anything');
    });

    test('the multi-series path answers an empty entry, never an omission',
        () async {
      final gateway = await _Gateway.start(
          policy: const _HidesTags({_hidden}),
          resolver: const _MapsTheRealTags());
      final station = await gateway.station();

      final answered = _asMap(await station.request(
          DataServiceMethods.timeseriesQueryMultiple,
          params: {
            'tables': [_key, _hidden, _unmapped],
            'to': _ms(_tsBase.add(const Duration(hours: 1))),
            'from': _ms(_tsBase),
          },
          what: 'one visible, one hidden and one unmappable series'));

      expect(answered.keys, containsAll([_key, _hidden, _unmapped]),
          reason: 'check 8\'s rule holds for hidden and unmappable series '
              'too: an absent entry and an empty entry are different answers '
              'and only one of them is true. An omission would also be a '
              'perfect existence oracle — the chart would learn exactly which '
              'of the three names the gateway is willing to serve');
      expect(answered[_hidden], isEmpty);
      expect(answered[_unmapped], isEmpty);
      expect(answered[_key], isNotEmpty,
          reason: 'and the visible series is still answered, or the filter '
              'is emptying everything and the two assertions above are true '
              'for the wrong reason');
    });

    test('the unmappable count moves exactly once per unmappable query, and '
        'is readable without a debugger', () async {
      final gateway = await _Gateway.start(resolver: const _MapsTheRealTags());
      final station = await gateway.station();
      final tally = gateway.server.seriesTally;

      final before = tally.unmappableQueries;
      await station.request(DataServiceMethods.timeseriesQuery,
          params: {
            'table': _unmapped,
            'to': _ms(_tsBase.add(const Duration(hours: 1))),
          },
          what: 'one query for a series with no mapping');

      expect(tally.unmappableQueries, before + 1,
          reason: 'the wire answer for an unmappable series is deliberately '
              'silent, so this count is the only place the gap is visible. '
              '10-CONTEXT amendment 6 requires an unmappable table to be '
              '*visible*, not merely refused, and the refusal itself cannot '
              'name what it refused without breaking the hiding rule — so '
              'the gateway-side count is the reconciliation. A chart pointed '
              'at a pre-cutover table looks exactly like a database problem '
              'the first time it happens, and this is what makes it one '
              'query instead of one afternoon');
      expect(tally.unmappableNames, contains(_unmapped),
          reason: 'a bare count says something is wrong; the name says which '
              'series to add to the collection plan. This is read off the '
              'server, never sent');

      await station.request(DataServiceMethods.timeseriesQuery,
          params: {
            'table': _key,
            'to': _ms(_tsBase.add(const Duration(hours: 1))),
          },
          what: 'one query for a series that does map');

      expect(tally.unmappableQueries, before + 1,
          reason: 'a series that resolves must not be counted. A count that '
              'rose on every query would be a count nobody could read '
              'anything out of');
    });

    test('a member address is resolved once, and canSee is asked about the '
        'series', () async {
      final gateway = await _Gateway.start(
          policy: const _HidesTags({_hidden}),
          resolver: const _MapsTheRealTags());
      final station = await gateway.station();
      final tally = gateway.server.seriesTally;

      final visible = await station.request(
          DataServiceMethods.timeseriesQuery,
          params: {
            'table': '$_key:speed',
            'to': _ms(_tsBase.add(const Duration(hours: 1))),
            'from': _ms(_tsBase),
          },
          what: 'one member of a visible series');
      final hidden = await station.request(DataServiceMethods.timeseriesQuery,
          params: {
            'table': '$_hidden:speed',
            'to': _ms(_tsBase.add(const Duration(hours: 1))),
            'from': _ms(_tsBase),
          },
          what: 'one member of a hidden series');

      expect(visible, isNotEmpty,
          reason: '`<series>:<member>` is the addressing 10-CONTEXT ruling 2 '
              'settled on. The member is stripped before the table is '
              'resolved, so a member address reaches the same table the bare '
              'name does — otherwise every struct chart in the plant reads as '
              'a series that does not exist');
      expect(hidden, isEmpty,
          reason: 'and canSee is asked about the *series* key, not about the '
              'member. A policy is written about tags; "CN02.MOT01.speed" is '
              'a tag and "CN02.MOT01.speed:speed" is a chart\'s way of '
              'selecting a column out of one. Asking about the second would '
              'answer true for every hidden struct in the plant');
      expect(tally.unmappableQueries, 0,
          reason: 'a member of a series that maps is not an unmappable '
              'series; counting it would fill the diagnostic with names that '
              'are fine');
    });
  });

  // ---------------------------------------------------------------------
  // History views (10-04).
  //
  // **Deliberately a sibling group rather than a ninth `_surfaces` entry**,
  // and the reason is a property rather than a shape mismatch — so it is
  // written here rather than left for a reader to rediscover.
  //
  // The loop's premise is that asking a surface about a tag tells you whether
  // the *plant* has it, which is why "hidden" and "never existed" must answer
  // identically on all eight. A history view is not that kind of surface: its
  // key list is data the **client itself supplied**, so a view saved holding
  // `_ghost` comes back holding `_ghost` — the gateway stored a string, and
  // handing it back says nothing about the plant. A view saved holding
  // `_hidden` comes back without it. The two therefore differ *by design*, and
  // adding this to the loop would demand one of two changes, both worse than
  // the difference: keeping hidden keys (which is the leak the seam exists to
  // close), or dropping every key the gateway does not currently serve (which
  // would silently destroy an operator's saved view every time a tag is
  // renamed or a station is reconfigured).
  //
  // **What that leaves is a residual oracle, and it is recorded rather than
  // waved past.** A station that may write views can save one holding a
  // candidate key, read it back, and learn from the key's absence that the
  // key exists and is hidden. It is a much narrower channel than the ones
  // T-06-36 closes — it costs a write, it needs the `operate` role, and PR
  // #403's logging is on that path — and every alternative examined is worse
  // (see `_PolicyHistoryViews`'s own doc for the write-side argument). Under
  // the shipped `AllVisibleOperatorWrites` it does not exist at all. Whoever
  // ships per-key hiding for real inherits this paragraph.
  group('a view holding a hidden key comes back without it', () {
    /// Saves a view over the wire and answers its id.
    Future<int> saveView(_Station station, List<String> keys,
            {Map<String, Object?>? graphConfigs}) async =>
        (await station.request(DataServiceMethods.historyCreateView,
            params: {
              'name': 'Vaktir',
              'keys': keys,
              if (graphConfigs != null) 'graphConfigs': graphConfigs,
            },
            what: 'saving a view over $keys'))! as int;

    Future<List<Object?>> keyNames(_Station station, int id) async =>
        (await station.request(DataServiceMethods.historyGetKeyNames,
            params: {'viewId': id}, what: 'the key names of view $id'))!
            as List<Object?>;

    test('the shipped policy keeps every key a view was saved with', () async {
      // **The anti-vacuity companion, and it goes first**, on this file's
      // convention: every case below asserts a key is *absent*, and without
      // this one they would all pass against a gateway whose views came back
      // empty for everybody.
      final gateway = await _Gateway.start();
      final station = await gateway.station();

      final id = await saveView(station, [_key, _hidden]);

      expect(await keyNames(station, id), containsAll([_key, _hidden]),
          reason: 'under the shipped policy nothing is hidden, so a view '
              'holding two keys holds two keys. If this fails, every "the '
              'hidden key is gone" assertion below is true because views are '
              'broken rather than because a filter ran');
    });

    test('the view still comes back, without the key', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final id = await saveView(station, [_key, _hidden]);

      final listed = (await station.request(
          DataServiceMethods.historySelectViews,
          params: const <String, Object?>{},
          what: 'the view picker'))! as List<Object?>;
      expect(listed.map((view) => (view! as Map)['id']), contains(id),
          reason: 'the view itself is not hidden and must not be: a view that '
              'vanished would say a view exists — the operator saved it, the '
              'picker offered it a moment ago, and its disappearance is a '
              'louder statement about the hidden key than the key\'s own '
              'absence is (T-10-13)');

      expect(await keyNames(station, id), [_key],
          reason: 'the hidden key is dropped from the key list, not from the '
              'view');

      final keys = _asMap(await station.request(
          DataServiceMethods.historyGetKeys,
          params: {'viewId': id},
          what: 'the keys of view $id'));
      expect(keys.keys, [_key],
          reason: 'and the record accessor agrees with the name-only one. A '
              'filter fitted to one and forgotten on the other would hide the '
              'key from the legend and hand it back to the chart');
    });

    test('a view all of whose keys are hidden is a view with no keys, never '
        'no view', () async {
      // **The boundary case**, and the only one where "drop the key" and
      // "drop the view" produce different answers. Everything else in this
      // group passes under either rule.
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final id = await saveView(station, [_hidden]);

      final listed = (await station.request(
          DataServiceMethods.historySelectViews,
          params: const <String, Object?>{},
          what: 'the view picker'))! as List<Object?>;
      expect(listed, hasLength(1),
          reason: 'the view is still there. Dropping it would be the one '
              'thing the rule forbids: an operator opening the picker would '
              'see a view they saved simply gone, which is a statement about '
              'the key it held');
      expect((listed.single! as Map)['id'], id);
      expect((listed.single! as Map)['name'], 'Vaktir',
          reason: 'and it still carries its name — a view is more than its '
              'key list');

      expect(await keyNames(station, id), isEmpty,
          reason: 'with an empty key list, which is an honest answer: the '
              'chart draws no lines and the operator can see that it draws '
              'none');
    });

    test('graphs are untouched by the filter', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final id = await saveView(station, [_hidden],
          graphConfigs: historyViewGraphsToJson(const {
            0: HistoryViewGraphRecord(graphIndex: 0, name: 'Hraði'),
            1: HistoryViewGraphRecord(
                graphIndex: 1, name: 'Hitastig', yAxisUnit: '°C'),
          }));

      final graphs = _asMap(await station.request(
          DataServiceMethods.historyGetGraphs,
          params: {'viewId': id},
          what: 'the graphs of a view whose every key is hidden'));

      expect(graphs.keys, hasLength(2),
          reason: 'a graph index is not a key and there is nothing to hide in '
              'a title or an axis unit. Filtering graphs alongside keys is '
              'the plausible over-reach here, and it would leave a view whose '
              'axes lost their labels for a reason nobody could find');
      expect(_asMap(graphs['1'])['yAxisUnit'], '°C');
    });

    test('a hidden key never reaches the store on the way in', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final id = await saveView(station, [_key, _hidden]);

      // Read off the **unpoliced** source, which is the only way to tell a
      // key that was dropped on the way in from one that is merely filtered
      // on the way out. The read-side filter would make both look identical
      // over the wire.
      final stored =
          await gateway.plant.historyViews.getHistoryViewKeys(id);
      expect(stored.keys, [_key],
          reason: 'the hidden key was dropped from the *input*, silently, so '
              'nothing about it was written down. Refusing the save would '
              'have named it — "this view holds a key you may not see" is the '
              'same disclosure a `forbidden` is — and storing it would leave '
              'the gateway holding a row whose only protection is that a '
              'filter remembers to run on every future read path');
    });

    test('an update drops a hidden key too', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final id = await saveView(station, [_key]);
      await station.request(DataServiceMethods.historyUpdateView,
          params: {
            'id': id,
            'name': 'Vaktir',
            'keys': [_key, _hidden],
          },
          what: 'an update adding a hidden key to a view');

      expect(await keyNames(station, id), [_key],
          reason: 'update is the other write-shaped door into the same rows, '
              'and a filter fitted to create and forgotten on update would '
              'let any station store any key by saving an empty view and then '
              'editing it');
      expect((await gateway.plant.historyViews.getHistoryViewKeys(id)).keys,
          [_key],
          reason: 'on the way in, as with create');
    });
  });

  group('a hidden key is a key that does not exist', () {
    test('a hidden key is indistinguishable from a key that does not exist',
        () async {
      final gateway = await _Gateway.start(
          policy: const _HidesTags({_hidden}),
          resolver: const _MapsTheRealTags());
      gateway.plant.setValue(_key, 1200);
      gateway.plant.setValue(_hidden, 900);
      final station = await gateway.station();

      // Anti-vacuity: a loop over an empty list asserts nothing, and the
      // count is named so that *deleting* a surface is as visible as adding
      // one. Seven since 10-02 added browse, eight since 10-03 added
      // timeseries.
      expect(_surfaces, hasLength(8),
          reason: 'the loop below covers ${_surfaces.length} surfaces. Each '
              'one is a way to ask about a tag and therefore a way to learn '
              'that it exists; a surface missing from this list is one '
              'nobody is comparing');

      for (final surface in _surfaces) {
        final forHidden = await surface.ask(gateway, station, _hidden);
        final forGhost = await surface.ask(gateway, station, _ghost);

        expect(forHidden, equals(forGhost),
            reason: '${surface.name} told a station apart. "$_hidden" is a tag '
                'the policy hides and "$_ghost" is a tag that never existed, '
                'and this surface answered them differently — so a station '
                'that may not know the first one exists can find out by '
                'asking, and by asking a thousand more it has the plant\'s '
                'address space. That is the whole of what 06-CONTEXT decision '
                '2 locks: hiding means "does not exist for you", not '
                '"exists, but no". Compared structurally with only the tag '
                'name normalized, so a later phase changing the nonexistent '
                'shape has to change both answers rather than this literal');
      }
    });

    test('the test policy really hides something', () async {
      // **The anti-vacuity companion.** Without it the case above passes
      // against a policy that hides nothing at all — both answers would be
      // the nonexistent answer, because neither tag would be served. This is
      // the same gateway and the same tag under the *shipped* policy, and it
      // must be visible and readable there.
      final gateway = await _Gateway.start();
      gateway.plant.setValue(_hidden, 900);
      final station = await gateway.station();

      expect(gateway.served.keys, contains(_hidden),
          reason: 'the tag the hiding case conceals is not servable in the '
              'first place, so that case is comparing two nonexistent keys '
              'and asserting nothing');

      final answer =
          _asMap(await station.request(Methods.read, params: {'key': _hidden}));
      expect(_asMap(answer['value'])['v'], 900,
          reason: 'and it must be *readable* under the shipped policy, not '
              'merely listed. A tag present in keys but unreadable would let '
              'the hiding case pass for the wrong reason too');
      expect(answer.containsKey('rejected'), isFalse,
          reason: 'a served tag carries no rejection map — the state the '
              'hidden one is being compared against is a genuinely healthy '
              'read');
    });

    test('the seeded history is really there under the shipped policy',
        () async {
      // The timeseries surface's own anti-vacuity companion, and it is
      // separate from the `read` one above because it can fail on its own:
      // the loop would pass against a gateway whose history was empty for
      // *every* tag, and an empty historian is a plausible fixture bug.
      final gateway = await _Gateway.start(resolver: const _MapsTheRealTags());
      final station = await gateway.station();

      final answered = await station.request(
          DataServiceMethods.timeseriesQuery,
          params: {
            'table': _hidden,
            'to': _ms(_tsBase.add(const Duration(hours: 1))),
            'from': _ms(_tsBase),
          },
          what: 'the hidden tag\'s history, unhidden');

      expect(answered, hasLength(5),
          reason: 'the series the hiding case conceals has nothing recorded '
              'in the first place, so that case is comparing two empty '
              'answers and asserting nothing');
      expect(((answered! as List).first as Map)['v'], 900,
          reason: 'and the samples must be the ones seeded, so that "empty" '
              'under the hiding policy is a filter having run rather than a '
              'window that never contained anything');
    });

    test('a hidden key\'s write is not answered forbidden', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      gateway.plant.setValue(_hidden, 900);
      final station = await gateway.station();

      final error = await station.refusal(Methods.write,
          params: {'cmd': newUlid(), 'key': _hidden, 'value': 1450},
          what: 'a write naming a tag this station may not see');

      expect(error.code, isNot(ServerErrorCodes.forbidden),
          reason: 'the gateway answered -32005 forbidden for a hidden tag, '
              'and forbidden means "this exists and you may not touch it". '
              'That is the leak the whole hiding architecture exists to '
              'close: it distinguishes a concealed tag from a misspelled one '
              'in a single round trip. The two refusals must stay different '
              'facts — a typo to fix versus a permission to obtain '
              '(06-RESEARCH §E.7 rows 2 and 3)');
      expect(error.code, rpc_error.INVALID_PARAMS,
          reason: 'and it must be the nonexistent-key refusal exactly, not '
              'merely something other than forbidden');
      expect(error.message, contains('does not serve'),
          reason: 'the sentence is _unknownKeyMessage\'s, read from the one '
              'place all four surfaces read it from (06-04). A hidden tag and '
              'a nonexistent one cannot be byte-identical if this refusal '
              'writes its own');
    });
  });

  group('browse hides by omission, never by refusal', () {
    test('the tree really carries the hidden tag under the shipped policy',
        () async {
      // **The anti-vacuity companion, and it goes first.** Every case below
      // asserts something is absent; without this one they would all pass
      // against a tree that never held it, which is the state
      // `FakeBrowse`'s *default* fixture is in for these keys.
      final gateway = await _Gateway.start();
      final station = await gateway.station();

      expect(await _reachableNodeIds(station), contains(_hidden),
          reason: 'the address space does not list "$_hidden" even with '
              'nothing hidden, so every absence asserted below is the '
              'ordinary kind');

      final detail = BrowseNodeDetail.fromJson(_asMap(await station.request(
          DataServiceMethods.browseFetchDetail,
          params: {'node': _probeNodeFor(_hidden).toJson()},
          what: 'the hidden tag\'s detail under the shipped policy')));
      expect(detail.value?.value, 900,
          reason: 'and its detail carries a reading, so the hidden answer '
              'below is provably missing something rather than matching a '
              'source that had nothing to give');
    });

    test('a hidden leaf is dropped from the level it belongs to', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final ids = await _reachableNodeIds(station);

      expect(ids, isNot(contains(_hidden)),
          reason: 'a node naming a tag this station may not see is dropped '
              'from the list. Refusing the call instead would name what it '
              'refused, which is the enumeration the hiding rule exists to '
              'prevent (T-06-36)');
      expect(ids, contains(_key),
          reason: 'a filter that emptied the tree would satisfy the '
              'assertion above and blind every panel. The visible tag is the '
              'control');
    });

    test('a folder is never asked about', () async {
      // The rule the plan states and the one a reader will not guess:
      // `canSee` takes a **plant key**, and a folder is not one. A resolver
      // that happens to answer for a folder id — this file's identity one
      // does — must not turn a policy entry into a pruned branch.
      final gateway =
          await _Gateway.start(policy: const _HidesTags({_hiddenParent}));
      final station = await gateway.station();

      final ids = await _reachableNodeIds(station);

      expect(ids, contains(_hiddenParent),
          reason: 'the folder "$_hiddenParent" was dropped because the policy '
              'names it. Browse asks about *variables*: a folder, an '
              'intermediate struct or a method is not a tag and has no '
              'reading to conceal, and pruning one takes every tag under it '
              'off the tree — including tags the station may see');
      expect(ids, contains(_hidden),
          reason: 'and the leaf under it is still there, which is the half '
              'that makes the assertion above about the folder rather than '
              'about the walk stopping early');
    });

    test('a hidden node\'s detail answers exactly as a nonexistent one does',
        () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final forHidden = _asMap(await station.request(
          DataServiceMethods.browseFetchDetail,
          params: {'node': _probeNodeFor(_hidden).toJson()},
          what: 'the hidden node\'s detail'));
      final forGhost = _asMap(await station.request(
          DataServiceMethods.browseFetchDetail,
          params: {'node': _probeNodeFor(_ghost).toJson()},
          what: 'a nonexistent node\'s detail'));

      // Compared to each other, never against a literal: a later phase that
      // changes what a source answers for a node it has never heard of has to
      // change both, which is the property 06-04 established between `read`
      // and `readFresh` and this surface inherits.
      expect(forHidden, equals(forGhost),
          reason: 'the detail pane can tell a concealed tag from a misspelt '
              'one. -32005 forbidden would be the loudest way to do it and '
              'this is the quietest: any difference at all is an existence '
              'oracle');
      expect(forHidden.containsKey('value'), isFalse,
          reason: 'the reading itself must not come through. A hidden node '
              'whose detail carried 900 would be the value leaking behind '
              'the concealment');
    });

    test('a path to a hidden node is null, not a truncated chain', () async {
      final gateway = await _Gateway.start(policy: const _HidesTags({_hidden}));
      final station = await gateway.station();

      final chain = await station.request(
          DataServiceMethods.browseResolvePath,
          params: {'targetId': _hidden},
          what: 'a path to the hidden tag');

      expect(chain, isNull,
          reason: 'a chain that stopped at the last visible node would claim '
              'an edge that is not there, and would say "something is under '
              'here you may not see" as clearly as a refusal. Null is what a '
              'target that does not exist gets, and that is what a hidden one '
              'has to get');

      final visible = await station.request(
          DataServiceMethods.browseResolvePath,
          params: {'targetId': _key},
          what: 'a path to the visible tag');
      expect(visible, isA<List<Object?>>(),
          reason: 'a resolver that answered null for everything would pass '
              'the assertion above and break the picker for every tag');
    });
  });

  group('a station that may not actuate is refused before the plant', () {
    test('a view station\'s write is refused before the device layer',
        () async {
      final gateway = await _Gateway.start(identity: _display);
      gateway.plant.setValue(_key, 1200);
      final station = await gateway.station();

      final cmd = newUlid();
      final error = await station.refusal(Methods.write,
          params: {'cmd': cmd, 'key': _key, 'value': 1450},
          what: 'a write from a station whose role is view');

      expect(error.code, ServerErrorCodes.forbidden,
          reason: 'a visible tag this station may not actuate is -32005, and '
              'the code has to be its own: the client behaves differently '
              'about it than about anything else on this path. Do not retry, '
              'the session is fine, keep reading — this action needs a '
              'permission the station does not have. INVALID_PARAMS would say '
              '"fix the request", and there is nothing wrong with the request');

      // **Nothing was sent.**
      expect(gateway.plant.upstreamWriteAttempts(cmd), 0,
          reason: 'the refusal must be raised above api.write. A device '
              'consulted before the refusal makes the whole gate a report '
              'about a frame that already reached a contactor');
      expect(gateway.plant.read(_key)?.value, 1200,
          reason: 'and the tag still reads what it read before. This is the '
              'one assertion an operator would recognise');

      // **And nothing was remembered.** The gate sits above the in-flight
      // pre-record, so a freshly minted ULID inside the window earns
      // `not_received` — the only re-send-safe answer this gateway gives, and
      // the honest one about an action that provably never happened.
      final status = _asMap(await station
          .request(Methods.writeStatus, params: {'cmds': [cmd]}));
      expect(
          WriteResult.fromJson(_asMap((status['results']! as List).single)),
          isA<WriteNotReceived>(),
          reason: 'writeStatus found something logged for a write that was '
              'refused before the plant was touched, so the gate was placed '
              'below the in-flight pre-record. The panel\'s reconnect '
              're-query would then answer "unknown" about an action that '
              'never happened, and an unknown on a setpoint is what makes an '
              'operator press the button again');
    });

    test('a view station\'s hold-to-run engage is refused before the hold is '
        'taken', () async {
      final gateway = await _Gateway.start(identity: _display);
      gateway.plant.setValue(_key, 0);
      final station = await gateway.station();

      final error = await station.refusal(Methods.write,
          params: {'cmd': newUlid(), 'key': _key, 'value': 1, 'hold': true},
          what: 'an engage from a station whose role is view');

      expect(error.code, ServerErrorCodes.forbidden,
          reason: 'one canWrite gates both write and holdToRun (ruling OQ5), '
              'because the engage seam is reachable only through the write '
              'path. A station that may not set a setpoint certainly may not '
              'jog the machine by hand');
      expect(gateway.plant.mintedCmds, isEmpty,
          reason: 'the source was never asked for a handle: the gate is above '
              'api.holdToRun, which is where "no device was consulted" stops '
              'being a claim and becomes a fact');
      expect(gateway.plant.read(_key)?.value, 0,
          reason: 'nothing was put on the deadman tag');
    });

    test('an operate station\'s write is unchanged in every respect',
        () async {
      final gateway = await _Gateway.start();
      gateway.plant.setValue(_key, 1200);
      final station = await gateway.station();

      final cmd = newUlid();
      final answer = _asMap(await station.request(Methods.write,
          params: {'cmd': cmd, 'key': _key, 'value': 1450}));

      expect(WriteResult.fromJson(answer), isA<WriteApplied>(),
          reason: 'the gate must cost a view station and nothing else. A '
              'panel that stopped writing is a jog button that stopped '
              'working, and PermissiveTokenValidator grants operate precisely '
              'so every fixture in this workspace keeps writing through the '
              'new gate');
      expect(gateway.plant.upstreamWriteAttempts(cmd), 1,
          reason: 'one press, one movement of the machine — the gate adds no '
              'second attempt and swallows no first one');
      expect(gateway.plant.read(_key)?.value, 1450);
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
