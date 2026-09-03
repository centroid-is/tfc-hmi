@TestOn('vm')

/// The data-service handler bodies, judged as bodies rather than over a wire.
///
/// Called the way `RelaySession._on` calls them — one `rpc.Parameters` in, one
/// answer or one `RpcException` out — which is `value_handlers_test.dart`'s
/// dialect and for the same reason: registration is asserted over a real
/// socket in `surface_test.dart` and `ws_malformed_test.dart`, so what is left
/// for this file is what each body *answers* once it has been reached.
///
/// Two distinctions carry the file, and both are the kind that a plausible
/// implementation gets wrong silently:
///
///  * **Null is not the empty list.** `resolvePath` answers null for a target
///    that does not exist and a list for one that does. An empty list would
///    claim the target sits zero nodes from a root, and a panel restoring a
///    saved selection would render a breadcrumb with nothing in it instead of
///    dropping the pre-selection (`served_state_man.dart:501-507`).
///  * **A wrong-shaped parameter is a refusal, not a crash.** Every refusal on
///    this wire carries a pre-substituted `data.request`, because
///    `RpcException.serialize` otherwise copies the offending request into the
///    error — and one request carrying `1e999` then makes the *error*
///    unencodable, at which point the peer drops it and a caller with no
///    deadline waits forever (the 02-05 hang).
///
/// **10-03** adds the timeseries four. Their arguments are not decoration: two
/// of the four frozen signatures carry a string that upstream interpolates
/// straight into SQL (`database_drift.dart`'s `tableQuery`, `database.dart`'s
/// `countTimeseriesDataMultiple`), so what those bodies *refuse* is as much of
/// the surface as what they answer. The hostile half lives in
/// `hostile_params_test.dart`; what is here is the ordinary shape of an answer
/// and the one refusal that is about size rather than about shape.
library;

import 'package:json_rpc_2/error_code.dart' as rpc_error;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/data_handlers.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_stateman_contract/testing/fake_data_services.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

import 'support/permissive_resolver.dart';
import 'support/ws_harness.dart';

/// A node that really is in [FakeBrowse]'s default tree.
const _folder = BrowseNode(
    id: 'ST101.CN01', displayName: 'CN01', type: BrowseNodeType.folder);

/// A leaf the default tree seeds a reading for.
const _leaf = BrowseNode(
    id: 'ST101.CN01.MOT01.setpoint',
    displayName: 'setpoint',
    type: BrowseNodeType.variable,
    dataType: 'Float');

/// The series the timeseries cases record against, named the way the database
/// names tables rather than the way the key space names tags — the frozen
/// parameter is `tableName` (`state_man_api.dart:263-266`).
const _series = 'st101_cn01_mot01_setpoint';

/// A second series, deliberately never seeded: the one a multi-series query
/// must still hand back an entry for.
const _unrecorded = 'st201_cn04_mot01_setpoint';

/// The instant every timeseries case measures from. Fixed and UTC, so nothing
/// in this file is a reading of the machine's clock.
final _base = DateTime.utc(2026, 8, 13, 6);

/// Epoch milliseconds, which is how an instant travels on this wire.
int _ms(DateTime at) => at.millisecondsSinceEpoch;

/// A regular series, one sample a minute from [_base].
List<TimeseriesData> _minutely(int count) => [
      for (var i = 0; i < count; i++)
        TimeseriesData<num>(1200 + i, _base.add(Duration(minutes: i))),
    ];

/// The handlers under test, over a source a case can drive.
final class _Kit {
  _Kit(this.handlers, this.api);

  final DataHandlers handlers;
  final FakeStateMan api;
}

_Kit _kit({FakeBrowse? browse, FakeTimeseries? timeseries}) {
  final api = FakeStateMan(browse: browse, timeseries: timeseries);
  addTearDown(api.dispose);
  return _Kit(
      DataHandlers(
          source: api,
          config: ServerConfig(),
          resolver: const PermissiveSeriesResolver()),
      api);
}

rpc.Parameters _params(String method, Map<String, Object?> value) =>
    rpc.Parameters(method, value);

/// One decoded node list, as the wire would carry it.
List<Map<String, Object?>> _nodes(Object? raw) => [
      for (final entry in raw! as List) (entry as Map).cast<String, Object?>(),
    ];

/// A resolver that fails the case if anything asks it a question.
///
/// Used to prove a *negative* — that the browse handlers never consult the
/// mapping — which a permissive resolver cannot do, because a handler that
/// asked it would get a plausible answer and the case would pass.
final class _RefusesEverything implements SeriesResolver {
  const _RefusesEverything();

  @override
  ResolvedSeries? resolve(String wireName) =>
      throw StateError('a browse handler asked the resolver to resolve '
          '"$wireName"');

  @override
  String? keyForTable(String table) =>
      throw StateError('a browse handler asked the resolver about table '
          '"$table"');

  @override
  String? keyForNode(String nodeId) =>
      throw StateError('a browse handler asked the resolver about node '
          '"$nodeId"');
}

/// The refusal a body raised, or a failure naming what it answered instead.
Future<rpc.RpcException> _refusal(
    Future<Object?> Function() ask, String what) async {
  final Object? answered;
  try {
    answered = await ask();
  } on rpc.RpcException catch (error) {
    return error;
  }
  fail('$what was answered with $answered instead of refused');
}

void main() {
  group('browse.fetchRoots', () {
    test('answers the source\'s roots as a list of nodes', () async {
      final kit = _kit();

      final answer = _nodes(
          await kit.handlers.browseFetchRoots(_params('browse.fetchRoots', {})));

      expect(answer.map((node) => node['id']).toList(),
          [for (final root in FakeBrowse.defaultRoots) root.id],
          reason: 'the roots are the top level of the address space, in the '
              'order the source gave them. A panel renders this list as the '
              'first thing an engineer sees, and a reordering is a tree that '
              'moves under the cursor between two sessions');
      expect(answer.first['type'], 'folder',
          reason: 'the node kind survives the encode: it is what decides '
              'whether the row gets a disclosure triangle');
    });

    test('an empty address space is the empty list, never null', () async {
      final kit = _kit(browse: FakeBrowse(roots: const [], children: const {}));

      final answer =
          await kit.handlers.browseFetchRoots(_params('browse.fetchRoots', {}));

      expect(answer, isEmpty,
          reason: 'a source with nothing to browse has an empty address '
              'space, which is a fact. Null would decode on the client as a '
              'missing answer and the tree would show a spinner forever');
      expect(answer, isA<List<Object?>>(),
          reason: 'and it must still be a list, so one decoder reads both the '
              'populated and the empty case');
    });
  });

  group('browse.fetchChildren', () {
    test('answers the children of the node it was given', () async {
      final kit = _kit();

      final answer = _nodes(await kit.handlers.browseFetchChildren(
          _params('browse.fetchChildren', {'parent': _folder.toJson()})));

      expect(answer.map((node) => node['id']).toList(),
          ['ST101.CN01.MOT01', 'ST101.CN01.SEN01'],
          reason: 'the level under ST101.CN01, and only that one');
    });

    test('reads its argument rather than serving one canned level', () async {
      final kit = _kit();

      final first = _nodes(await kit.handlers.browseFetchChildren(
          _params('browse.fetchChildren', {'parent': _folder.toJson()})));
      final second = _nodes(await kit.handlers.browseFetchChildren(_params(
          'browse.fetchChildren', {
        'parent': const BrowseNode(
                id: 'ST201.CN04',
                displayName: 'CN04',
                type: BrowseNodeType.folder)
            .toJson()
      })));

      expect(second.map((node) => node['id']).toList(), ['ST201.CN04.MOT01'],
          reason: 'the two folders share no child id, which is what lets this '
              'case tell "decoded the parent" from "answered the last level '
              'it happened to hold"');
      expect(first, isNot(equals(second)));
    });

    test('a parent that is not an object is refused, not thrown through',
        () async {
      final kit = _kit();

      final error = await _refusal(
          () => kit.handlers.browseFetchChildren(
              _params('browse.fetchChildren', {'parent': 'ST101.CN01'})),
          'a fetchChildren whose parent is a bare string');

      expect(error.code, rpc_error.INVALID_PARAMS,
          reason: 'a caller that sent the wrong shape gets the wrong-shape '
              'code, not a handler failure — the difference is whether the '
              'panel retries');
      expect(error.message, contains('parent'),
          reason: 'the refusal must name the parameter, or the only way to '
              'find out which one was wrong is to read this file');
      expect((error.data! as Map)['request'], isA<String>(),
          reason: 'the request is pre-substituted. Without it '
              'RpcException.serialize copies the offending request into the '
              'error, and one carrying 1e999 makes the refusal itself '
              'unencodable — the caller then waits forever on a path with no '
              'deadline');
      expect((error.data! as Map)['method'], 'browse.fetchChildren');
    });

    test('a missing parent is refused the same way', () async {
      final kit = _kit();

      final error = await _refusal(
          () => kit.handlers
              .browseFetchChildren(_params('browse.fetchChildren', {})),
          'a fetchChildren with no parent at all');

      expect(error.code, rpc_error.INVALID_PARAMS);
      expect((error.data! as Map)['request'], isA<String>(),
          reason: 'the armor is on every arm of the refusal, not only the one '
              'a case happened to write first');
    });
  });

  group('browse.fetchDetail', () {
    test('answers the detail of the node it was given', () async {
      final kit = _kit();

      final answer = (await kit.handlers.browseFetchDetail(
          _params('browse.fetchDetail', {'node': _leaf.toJson()})))! as Map;
      final detail =
          BrowseNodeDetail.fromJson(answer.cast<String, Object?>());

      expect(detail.dataType, 'Float',
          reason: 'the data type is what the detail pane renders the reading '
              'with');
      expect(detail.value?.value, 1450.0,
          reason: 'a variable\'s detail carries its reading. A detail with no '
              'value would render an empty pane for a tag the tree just '
              'listed');
    });

    test('a node that is not an object is refused', () async {
      final kit = _kit();

      final error = await _refusal(
          () => kit.handlers.browseFetchDetail(
              _params('browse.fetchDetail', {'node': 42})),
          'a fetchDetail whose node is a number');

      expect(error.code, rpc_error.INVALID_PARAMS);
      expect(error.message, contains('node'));
      expect((error.data! as Map)['request'], isA<String>());
    });
  });

  group('the resolver seam', () {
    test('the handlers hold the resolver they were built with', () {
      const resolver = PermissiveSeriesResolver();
      final api = FakeStateMan();
      addTearDown(api.dispose);

      final handlers = DataHandlers(
          source: api, config: ServerConfig(), resolver: resolver);

      expect(identical(handlers.resolver, resolver), isTrue,
          reason: 'the same object, not an equal one: there is exactly one '
              'mapping per gateway and it is built from the keymappings the '
              'composition root already loaded. 10-03\'s timeseries handlers '
              'read it to turn a wire series name into a table, and a copy '
              'made somewhere in between is a second place a mapping could '
              'go stale');
    });

    test('the browse handlers do not consult it', () async {
      // Browse is the one family that does not need the mapping in the
      // handler: a node id is an upstream address-space identifier
      // (`client_sub_apis.dart:179-183`), and turning one into a plant key is
      // the *policy's* job, one layer down, so that a handler cannot forget
      // it. This case pins that division by handing the handlers a resolver
      // that would throw if it were asked.
      final api = FakeStateMan();
      addTearDown(api.dispose);
      final handlers = DataHandlers(
          source: api,
          config: ServerConfig(),
          resolver: const _RefusesEverything());

      final roots = await handlers
          .browseFetchRoots(_params('browse.fetchRoots', {}));

      expect(roots, isNotEmpty,
          reason: 'fetchRoots asked the resolver a question. Filtering by '
              'visibility belongs to _PolicyBrowse, which is already between '
              'these handlers and the source — a second filter here would be '
              'a second place to keep in step');
    });
  });

  group('browse.resolvePath', () {
    test('answers the chain root to leaf', () async {
      final kit = _kit();

      final answer = _nodes(await kit.handlers.browseResolvePath(_params(
          'browse.resolvePath', {'targetId': 'ST101.CN01.MOT01.setpoint'})));

      expect(answer.map((node) => node['id']).toList(), [
        'ST101',
        'ST101.CN01',
        'ST101.CN01.MOT01',
        'ST101.CN01.MOT01.setpoint',
      ], reason: 'root first, leaf last, every step a real edge. The panel '
          'expands the tree by walking this list, so a gap in it is a level '
          'that never opens');
    });

    test('a target that does not exist answers null, not the empty list',
        () async {
      final kit = _kit();

      final answer = await kit.handlers.browseResolvePath(
          _params('browse.resolvePath', {'targetId': 'ST101.CN01.MOT99.gone'}));

      expect(answer, isNull,
          reason: 'null is "cannot resolve" and the empty list claims a '
              'zero-length chain. A page saved last year against a tag since '
              'renamed in the PLC is the ordinary case: it must degrade to no '
              'pre-selection, and a panel that read [] as a resolved chain '
              'would select the root');
      expect(answer, isNot(isA<List<Object?>>()),
          reason: 'stated the other way round too, because the failure this '
              'guards against is a body that answered [] and a matcher that '
              'called it falsy');
    });

    test('a targetId that is not a string is refused', () async {
      final kit = _kit();

      final error = await _refusal(
          () => kit.handlers.browseResolvePath(
              _params('browse.resolvePath', {'targetId': 7})),
          'a resolvePath whose targetId is a number');

      expect(error.code, rpc_error.INVALID_PARAMS);
      expect(error.message, contains('targetId'));
      expect((error.data! as Map)['request'], isA<String>());
    });
  });

  group('timeseries.queryTimeseriesData', () {
    test('a recorded series comes back inside the window, oldest first',
        () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(7)));

      final answer = _samples(await kit.handlers.timeseriesQuery(
          _params(DataServiceMethods.timeseriesQuery, {
        'table': _series,
        'to': _ms(_base.add(const Duration(minutes: 5))),
        'from': _ms(_base.add(const Duration(minutes: 1))),
        'orderBy': 'time ASC',
      })));

      expect(answer.map((sample) => sample['t']).toList(),
          [for (var i = 1; i <= 5; i++) _ms(_base.add(Duration(minutes: i)))],
          reason: 'seven samples were recorded and minutes one to five were '
              'asked for. Samples outside the window make a chart draw beyond '
              'the axis it was given; samples out of time order make it draw a '
              'scribble, because a line chart joins consecutive points and '
              'nothing sorts them on the way to the screen');
      expect(answer.map((sample) => sample['v']).toList(),
          [1201, 1202, 1203, 1204, 1205],
          reason: 'the samples that came back are not the ones that were '
              'recorded, so the chart is showing numbers the plant never '
              'produced');
    });

    test('every instant is epoch milliseconds and every sample is a num',
        () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(3)));

      final answer = _samples(await kit.handlers.timeseriesQuery(
          _params(DataServiceMethods.timeseriesQuery, {
        'table': _series,
        'to': _ms(_base.add(const Duration(minutes: 9))),
      })));

      expect(answer, hasLength(3));
      for (final sample in answer) {
        expect(sample['t'], isA<int>(),
            reason: 'an instant travels as epoch milliseconds, decoded on the '
                'far side by `TimeseriesData.fromJson` reading `t` through '
                '`num`. An ISO string here would decode to instant zero and '
                'the chart would draw 1970');
        expect(sample['v'], isA<num>(),
            reason: 'the wire sample type is num (10-CONTEXT ruling 2), and '
                'the client decodes it as one. A string would break every '
                'chart\'s arithmetic at the point of plotting rather than at '
                'the point of decoding');
      }
      expect(
          DateTime.fromMillisecondsSinceEpoch(answer.first['t']! as int,
              isUtc: true),
          _base,
          reason: 'read back as UTC it must be the instant that was recorded. '
              'A local-time encode would shift every chart in the plant by '
              'the machine\'s offset and nothing on the wire would say so');
    });

    test('a "to" that is missing is refused, not defaulted to now', () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(3)));

      final error = await _refusal(
          () => kit.handlers.timeseriesQuery(
              _params(DataServiceMethods.timeseriesQuery, {'table': _series})),
          'a queryTimeseriesData with no window end');

      expect(error.code, rpc_error.INVALID_PARAMS,
          reason: '`to` is the one positional argument of the frozen '
              'signature and there is no honest default for it: substituting '
              '"now" would answer a different question than the one asked and '
              'the caller could not tell');
      expect(error.message, contains('to'));
      expect((error.data! as Map)['request'], isA<String>());
    });

    test('a "to" that is not a number is refused', () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(3)));

      final error = await _refusal(
          () => kit.handlers.timeseriesQuery(
                  _params(DataServiceMethods.timeseriesQuery, {
                'table': _series,
                'to': '2026-08-13T06:00:00Z',
              })),
          'a queryTimeseriesData whose window end is an ISO string');

      expect(error.code, rpc_error.INVALID_PARAMS,
          reason: 'instants travel as epoch milliseconds on this wire '
              '(`client_sub_apis.dart` sends `msOf`). An ISO string reaching '
              '`(raw as num).toInt()` is a cast error inside the handler, '
              'which the session reports as handlerFailed — "possibly '
              'transient, retrying is legitimate" — for a request that will '
              'never succeed');
      expect(error.message, contains('to'));
    });
  });

  group('timeseries.queryTimeseriesDataMultiple', () {
    test('every requested series gets an entry, including the silent ones',
        () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(5)));

      final answer = _object(await kit.handlers.timeseriesQueryMultiple(
          _params(DataServiceMethods.timeseriesQueryMultiple, {
        'tables': [_series, _unrecorded],
        'to': _ms(_base.add(const Duration(hours: 1))),
        'from': _ms(_base),
      })));

      expect(answer.keys, containsAll([_series, _unrecorded]),
          reason: 'two series were asked for and ${answer.keys.toList()} came '
              'back. A name with no entry is a series the chart silently drops '
              'from its legend, which an operator reads as "this tag is flat" '
              'rather than as "nothing was recorded" — an absent entry and an '
              'empty entry are different answers and only one of them is true');
      expect(answer[_unrecorded], isEmpty,
          reason: 'the unrecorded series came back with samples in it, so the '
              'gateway is answering for a table it has nothing for');
      expect(answer[_series], isNotEmpty,
          reason: 'the recorded series came back empty in a multi-series query '
              'while it has samples, so the batching path is losing what the '
              'single-series path finds');
    });

    test('the answer is keyed by the names the caller asked for', () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(2)));

      final answer = _object(await kit.handlers.timeseriesQueryMultiple(
          _params(DataServiceMethods.timeseriesQueryMultiple, {
        'tables': [_unrecorded, _series],
        'to': _ms(_base.add(const Duration(hours: 1))),
      })));

      expect(answer.keys.toSet(), {_unrecorded, _series},
          reason: 'the gateway builds this map from the request rather than '
              'from the source\'s answer, so "one entry per requested series" '
              'is a property of the handler and not something it inherits '
              'from whatever is behind it. A source that omitted a silent '
              'table would still produce a complete map here, and 10-07\'s '
              'reader is exactly such a source');
    });

    test('a "tables" that is not a list is refused', () async {
      final kit = _kit(timeseries: FakeTimeseries());

      final error = await _refusal(
          () => kit.handlers.timeseriesQueryMultiple(
                  _params(DataServiceMethods.timeseriesQueryMultiple, {
                'tables': _series,
                'to': _ms(_base),
              })),
          'a multi-series query whose "tables" is a bare string');

      expect(error.code, rpc_error.INVALID_PARAMS,
          reason: 'the same three arms readMany has, for the same reason: a '
              'wrong-shaped breadth argument is the caller\'s mistake and it '
              'is refused before anything is read');
      expect(error.message, contains('tables'));
      expect((error.data! as Map)['request'], isA<String>());
    });
  });

  group('timeseries.queryTimeseriesDataDownsampled', () {
    test('honours maxPoints and still reaches both ends of the window',
        () async {
      final points = [
        for (var i = 0; i < 500; i++)
          TimeseriesData<num>(i, _base.add(Duration(seconds: i))),
      ];
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, points));
      final to = _base.add(const Duration(seconds: 499));

      final answer = _samples(await kit.handlers.timeseriesQueryDownsampled(
          _params(DataServiceMethods.timeseriesQueryDownsampled, {
        'table': _series,
        'from': _ms(_base),
        'to': _ms(to),
        'maxPoints': 50,
      })));

      expect(answer.length, lessThanOrEqualTo(50),
          reason: '500 samples were downsampled to 50 and ${answer.length} '
              'came back. A bound that is not kept means a year of one-second '
              'samples crosses the link the moment somebody widens a chart');
      expect(answer, isNotEmpty);
      expect(answer.first['t'], _ms(_base),
          reason: 'the downsampled series must start where the window starts, '
              'or the chart draws a line that begins after its own axis does');
      expect(answer.last['t'], _ms(to),
          reason: 'and end where the window ends. The newest sample is the '
              'one an operator reads as the current value, and a downsample '
              'that drops it shows the plant as it was with no indication of '
              'when');
    });
  });

  group('timeseries.countTimeseriesDataMultiple', () {
    test('answers a map keyed by the bucket instant as epoch milliseconds',
        () async {
      final kit = _kit(timeseries: FakeTimeseries()..seed(_series, _minutely(5)));

      final answer = _object(await kit.handlers.timeseriesCountMultiple(
          _params(DataServiceMethods.timeseriesCountMultiple, {
        'table': _series,
        'intervalMs': const Duration(minutes: 1).inMilliseconds,
        'howMany': 10,
        'since': _ms(_base),
      })));

      expect(answer, isNotEmpty,
          reason: 'five samples a minute apart fall in five one-minute '
              'buckets; an empty strip reads as "the recorder stopped"');
      for (final key in answer.keys) {
        expect(int.tryParse(key), isNotNull,
            reason: 'JSON objects key by String and these keys are instants, '
                'so they travel as epoch milliseconds — converted at the '
                'boundary exactly once, which is what the client\'s '
                '`int.parse(entry.key)` expects. A key converted twice, or '
                'left as an ISO string, throws inside the client\'s decoder '
                'where nothing is catching');
      }
      expect(answer.values, everyElement(isA<int>()));
      expect(answer.keys.map(int.parse).toList()..sort(),
          [for (var i = 0; i < 5; i++) _ms(_base.add(Duration(minutes: i)))],
          reason: 'the buckets are the minutes the samples landed in');
    });
  });

  group('a result too large to send is a refusal, not a failure and not a '
      'close', () {
    test('the refusal is INVALID_PARAMS and names the bounded method it '
        'suggests', () async {
      final kit = _kit(timeseries: _TooLargeTimeseries());

      final error = await _refusal(
          () => kit.handlers.timeseriesQuery(
                  _params(DataServiceMethods.timeseriesQuery, {
                'table': _series,
                'to': _ms(_base.add(const Duration(days: 31))),
                'from': _ms(_base),
              })),
          'a month-long raw query the source refused to answer');

      expect(error.code, rpc_error.INVALID_PARAMS,
          reason: 'and deliberately not handlerFailed (-32011), which the '
              'wire documents as "possibly transient: retrying is '
              'legitimate". A panel that retries a month-long window forever '
              'is the denial of service the bound exists to prevent. A '
              'too-large query is a bad *request*, and the fix is in the '
              'caller\'s hands');
      expect(error.message,
          contains(DataServiceMethods.timeseriesQueryDownsampled),
          reason: 'the refusal has to name the method that would answer the '
              'same question within the limit, or it is a dead end reported '
              'as a broken chart');
      expect(error.message, contains('${_TooLargeTimeseries.limit}'),
          reason: 'and the limit, so an engineer knows whether to narrow the '
              'window a little or a lot');
      expect((error.data! as Map)['request'], isA<String>(),
          reason: 'the armor is on this arm too — it is the arm most likely '
              'to carry a wide window full of numbers');
    });

    test('the session answers the next request normally', () async {
      final fixture = relayFixture(timeseries: _TooLargeTimeseries());
      await fixture.ready;
      await fixture.hello();

      final error = await fixture.refusal(DataServiceMethods.timeseriesQuery,
          params: {
            'table': _series,
            'to': _ms(_base.add(const Duration(days: 31))),
            'from': _ms(_base),
          },
          what: 'a query the source refuses as too large');

      expect(error.code, rpc_error.INVALID_PARAMS);
      expect(error.message,
          contains(DataServiceMethods.timeseriesQueryDownsampled));
      await fixture.request(Methods.ping,
          what: 'a ping after a refused over-large query');
      expect(fixture.observedClose.closeCode, isNull,
          reason: 'a refusal must be cheaper than the request that caused it. '
              'The other tempting failure is to let the over-large answer '
              'through and have the conflating send buffer evict the session '
              'with 4004 — which reports "your query was too large" as "you '
              'disconnected", the class of failure this project exists to '
              'prevent (10-CONTEXT amendment 3)');
    }, tags: 'ws');
  });
}

/// One decoded sample list, as the wire would carry it.
List<Map<String, Object?>> _samples(Object? raw) => [
      for (final entry in raw! as List) (entry as Map).cast<String, Object?>(),
    ];

/// One decoded JSON object, cast where the handler hands back `Object?`.
Map<String, Object?> _object(Object? raw) =>
    (raw! as Map).cast<String, Object?>();

/// A source that refuses every raw query as too large.
///
/// Nothing raises [ResultTooLarge] yet — 10-07's reader and 10-10's byte
/// ceiling do — so the mapping is driven from a source that throws it. That is
/// the honest way round: the *code* the wire answers is chosen at the handler
/// and deliberately not inside the exception (`result_too_large.dart:26-31`),
/// so the handler is where it has to be asserted.
final class _TooLargeTimeseries extends FakeTimeseries {
  /// A month of one-second samples, which is the number
  /// `result_too_large.dart` uses to make "rows" and "bytes" feel different.
  static const limit = 2678400;

  @override
  Future<List<TimeseriesData>> queryTimeseriesData(
          String tableName, DateTime to,
          {String? orderBy = 'time ASC', DateTime? from}) async =>
      throw const ResultTooLarge.rows(
        limit: limit,
        measured: limit * 2,
        suggestion: DataServiceMethods.timeseriesQueryDownsampled,
      );
}
