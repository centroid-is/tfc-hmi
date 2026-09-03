/// The bodies of the data-service methods: browse, and — from 10-03 onward —
/// timeseries, history views and preferences.
///
/// Same rule as `value_handlers.dart` and `session_handlers.dart`, for the same
/// reason: **nothing in here registers anything.** Handlers are handed to
/// `RelaySession._on`, which is the one seam where a method enters the table
/// and therefore the one place the handshake gate and the error armor are
/// applied. A handler that registered itself would be a handler that arrived
/// ungated, and an ungated `browse.fetchRoots` is the plant's whole address
/// space enumerated by a peer that never authenticated. A grep for the peer's
/// registration call over this file is meant to come back empty.
///
/// ## The bodies are copied from the contract kit, never imported
///
/// The contract kit's `served_state_man.dart:482-510` already serves these four
/// methods correctly over its own channel, and this file is a deliberate copy
/// of them rather than a call into it. `handler_table_test.dart:264-296` sweeps
/// this package's production `lib/` for the kit's package name and requires
/// **zero** hits — including in prose, which is why the name is not written
/// anywhere in this file. It is a **dev** dependency, the harness a test suite
/// runs against, and a gateway that imported its test kit at runtime would ship
/// the fake plant, the seeding levers and the fault injectors into the plant.
///
/// So the duplication is the point, and the two copies are expected to drift
/// only where the wire differs: the kit wraps every body in its own `_answer`,
/// and this one does not, because `RelaySession._on` already supplies exactly
/// that armor (`relay_session.dart:813-835`).
///
/// ## What a refusal here looks like
///
/// `_refuse`, copied in shape from `value_handlers.dart:883-885`: the general
/// `RpcException` constructor with INVALID_PARAMS and a **pre-substituted**
/// `data`, never `RpcException.invalidParams`, which takes no `data` — and a
/// refusal with no `data` is exactly the one `serialize` fills in for you with
/// the offending request. One request carrying `1e999` then makes the error
/// itself unencodable, the peer drops it, and a caller with no deadline waits
/// forever (the 02-05 hang).
library;

import 'package:json_rpc_2/error_code.dart' as rpc_errors;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The handler bodies for one session's data-service methods.
///
/// Holds no state of its own: every answer is the source's, encoded. The
/// hiding rule is **not** applied here — it lives one layer down, in
/// `PolicyStateMan`'s `_PolicyBrowse`, so that a handler added by a later plan
/// cannot forget it (T-06-38). What this object is handed is already the
/// policed view.
final class DataHandlers {
  DataHandlers({required this.source});

  /// The source being served, already seen through this session's policy.
  ///
  /// **Named `source`, and it must not be renamed to `api`.** The same pin
  /// `policy_state_man.dart:97-104` records:
  /// `tfc_relay_client/test/no_retry_test.dart:216-262` counts `api.write(`,
  /// `api.holdToRun(` and `hold.release(` over this package's `lib/` at
  /// exactly one occurrence each, because those are the gateway's only
  /// crossings into the plant and a second one is a second actuation. None of
  /// the thirty-four data-service methods writes to the plant, so the hazard
  /// here is purely the name — and the failure it produces is a message about
  /// *retries* on a file that has nothing to do with retrying.
  final StateManApi source;

  // ------------------------------------------------------------------ browse

  /// The top level of the address space.
  ///
  /// An empty list is a legitimate answer — a source with nothing to browse —
  /// and null is not: the client decodes null as a missing answer and the tree
  /// shows a spinner that never resolves.
  Future<Object?> browseFetchRoots(rpc.Parameters _) async =>
      [for (final node in await source.browse.fetchRoots()) node.toJson()];

  /// One level, under the node the caller names.
  Future<Object?> browseFetchChildren(rpc.Parameters params) async {
    final parent = _node(params, 'parent', DataServiceMethods.browseFetchChildren);
    return [
      for (final node in await source.browse.fetchChildren(parent))
        node.toJson(),
    ];
  }

  /// Everything the detail pane shows about one node.
  Future<Object?> browseFetchDetail(rpc.Parameters params) async {
    final node = _node(params, 'node', DataServiceMethods.browseFetchDetail);
    return (await source.browse.fetchDetail(node)).toJson();
  }

  /// The chain from a root to [targetId], root first, or null.
  ///
  /// **Null and the empty list stay apart** (`served_state_man.dart:501-507`).
  /// Null is "cannot resolve"; an empty list would claim the target sits zero
  /// nodes from a root, and a panel restoring a saved selection would select
  /// the root instead of dropping the pre-selection. A page saved last year
  /// against a tag since renamed in the PLC is the ordinary case.
  Future<Object?> browseResolvePath(rpc.Parameters params) async {
    final raw = params['targetId'].valueOr(null);
    if (raw is! String || raw.isEmpty) {
      throw _refuse(
          DataServiceMethods.browseResolvePath,
          'browse.resolvePath needs a non-empty string "targetId": the id of '
          'the node to resolve a path to');
    }
    final chain = await source.browse.resolvePath(raw);
    return chain == null ? null : [for (final node in chain) node.toJson()];
  }

  // ------------------------------------------------------------------ shared

  /// One [BrowseNode] out of [name], or a refusal that names the parameter.
  ///
  /// The decode is guarded rather than left to `params[name].asMap`, which
  /// raises a `RpcException` of its own with **no** `data` — and json_rpc_2
  /// then fills that `data` with the offending request, which is the shape
  /// this whole file exists to avoid.
  static BrowseNode _node(rpc.Parameters params, String name, String method) {
    final raw = params[name].valueOr(null);
    if (raw is! Map) {
      throw _refuse(
          method,
          '$method needs an object "$name": a browse node as the client '
          'received it, with at least an "id"');
    }
    return BrowseNode.fromJson(_object(raw));
  }

  /// A JSON map with its keys narrowed to strings.
  ///
  /// `json_rpc_2` hands back `Map<Object?, Object?>` and every `fromJson` in
  /// the protocol package takes `Map<String, Object?>`. Copied verbatim from
  /// `served_state_man.dart:746-747`.
  static Map<String, Object?> _object(Map<Object?, Object?> raw) =>
      {for (final entry in raw.entries) '${entry.key}': entry.value};

  /// A refusal with the armor already on it.
  ///
  /// See this library's doc for why `data` is pre-substituted and why the
  /// general constructor is used rather than `RpcException.invalidParams`.
  static rpc.RpcException _refuse(String method, String why) =>
      rpc.RpcException(rpc_errors.INVALID_PARAMS, why,
          data: _substitute(method));

  /// Copied verbatim from `value_handlers.dart` and `served_state_man.dart`.
  static Map<String, Object?> _substitute(String method) => {
        'method': method,
        'request': 'omitted: echoing a request that may carry a non-finite '
            'number is what makes the error itself unencodable, and an '
            'unencodable error on a path with no deadline is a hang',
      };
}
