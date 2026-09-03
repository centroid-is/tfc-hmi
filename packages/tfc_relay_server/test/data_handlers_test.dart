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
library;

import 'package:json_rpc_2/error_code.dart' as rpc_error;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/data_handlers.dart';
import 'package:tfc_stateman_contract/testing/fake_data_services.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

/// A node that really is in [FakeBrowse]'s default tree.
const _folder = BrowseNode(
    id: 'ST101.CN01', displayName: 'CN01', type: BrowseNodeType.folder);

/// A leaf the default tree seeds a reading for.
const _leaf = BrowseNode(
    id: 'ST101.CN01.MOT01.setpoint',
    displayName: 'setpoint',
    type: BrowseNodeType.variable,
    dataType: 'Float');

/// The handlers under test, over a source a case can drive.
final class _Kit {
  _Kit(this.handlers, this.api);

  final DataHandlers handlers;
  final FakeStateMan api;
}

_Kit _kit({FakeBrowse? browse}) {
  final api = FakeStateMan(browse: browse);
  addTearDown(api.dispose);
  return _Kit(DataHandlers(source: api), api);
}

rpc.Parameters _params(String method, Map<String, Object?> value) =>
    rpc.Parameters(method, value);

/// One decoded node list, as the wire would carry it.
List<Map<String, Object?>> _nodes(Object? raw) => [
      for (final entry in raw! as List) (entry as Map).cast<String, Object?>(),
    ];

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
}
