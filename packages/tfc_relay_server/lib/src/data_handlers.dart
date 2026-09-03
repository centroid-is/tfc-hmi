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

import 'server_config.dart';

/// The handler bodies for one session's data-service methods.
///
/// Holds no state of its own: every answer is the source's, encoded. The
/// hiding rule is **not** applied here — it lives one layer down, in
/// `PolicyStateMan`'s `_PolicyBrowse`, so that a handler added by a later plan
/// cannot forget it (T-06-38). What this object is handed is already the
/// policed view.
final class DataHandlers {
  DataHandlers({
    required this.source,
    required this.config,
    required this.resolver,
  });

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

  /// Where this gateway's per-request bounds live.
  ///
  /// The timeseries family is the first data-service family whose arguments
  /// scale the work the *database* does — `maxPoints`, `howMany` and
  /// `intervalMs` all multiply a query's cost, and `tables` multiplies the
  /// number of queries — so it is the first that needs the same ceilings
  /// `subscribe` and `readMany` already have. `browse` needed none: its
  /// arguments are one node each.
  final ServerConfig config;

  /// How a node id and a table name become a plant key.
  ///
  /// Held here and **not consulted by the four browse handlers**: a
  /// `BrowseNode` id is an upstream address-space identifier rather than a
  /// plant key (`client_sub_apis.dart:179-183`), and turning one into a key so
  /// `canSee` can be asked is `_PolicyBrowse`'s job, one layer down, where a
  /// handler added by a later plan cannot forget it. What reads this field is
  /// 10-03's timeseries family, which is keyed by table and has no other way
  /// to find the key its samples belong to.
  ///
  /// Required, with no default, all the way up to `RelayServer` — see that
  /// class's `resolver` parameter for the argument.
  final SeriesResolver resolver;

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

  // -------------------------------------------------------------- timeseries

  /// Samples for one series up to `to`, optionally from `from`.
  ///
  /// The window travels as **epoch milliseconds**, decoded here exactly once
  /// (`served_state_man.dart:762-764`). `to` has no honest default: answering
  /// "now" for a caller that forgot it would answer a different question than
  /// the one asked, and the caller could not tell.
  Future<Object?> timeseriesQuery(rpc.Parameters params) async {
    const method = DataServiceMethods.timeseriesQuery;
    final table = _series(params, 'table', method);
    final to = _requiredInstant(params, 'to', method);
    final from = _instant(params, 'from', method);
    return _points(await _sized(
        method,
        () => source.timeseries.queryTimeseriesData(table, to,
            orderBy: params['orderBy'].valueOr(null) as String?, from: from)));
  }

  /// The same window for several series in one round trip, keyed by name.
  ///
  /// **One entry per requested series, built from the request** — never from
  /// whatever the source happened to answer. An absent entry and an empty
  /// entry are different answers and only one of them is true: a chart that
  /// iterates the names it asked for and finds no entry drops the series from
  /// its legend, which an operator reads as "this tag is flat" rather than as
  /// "nothing was recorded".
  ///
  /// Assembling the map here rather than forwarding the source's is what makes
  /// that a property of the gateway. 10-07's reader answers out of a database
  /// that has no row for a silent table, and the policy filter below this
  /// answers nothing at all for a series the station may not see — both would
  /// produce a short map, and both are covered by this loop.
  Future<Object?> timeseriesQueryMultiple(rpc.Parameters params) async {
    const method = DataServiceMethods.timeseriesQueryMultiple;
    final tables = _seriesList(params, 'tables', method);
    final to = _requiredInstant(params, 'to', method);
    final from = _instant(params, 'from', method);
    final answers = await _sized(
        method,
        () => source.timeseries.queryTimeseriesDataMultiple(tables, to,
            orderBy: params['orderBy'].valueOr(null) as String?, from: from));
    return {
      for (final table in tables) table: _points(answers[table] ?? const []),
    };
  }

  /// At most `maxPoints` samples spanning the window.
  Future<Object?> timeseriesQueryDownsampled(rpc.Parameters params) async {
    const method = DataServiceMethods.timeseriesQueryDownsampled;
    final table = _series(params, 'table', method);
    final from = _requiredInstant(params, 'from', method);
    final to = _requiredInstant(params, 'to', method);
    final maxPoints = _requiredInt(params, 'maxPoints', method);
    return _points(await _sized(
        method,
        () => source.timeseries.queryTimeseriesDataDownsampled(table, from, to,
            maxPoints: maxPoints)));
  }

  /// Sample counts per bucket, newest `howMany` buckets.
  ///
  /// **JSON objects key by String and these keys are instants**, so they
  /// travel as epoch milliseconds — converted here, at the boundary, exactly
  /// once (`served_state_man.dart:546-551`). The client reads them back with
  /// `int.parse` inside its own decoder, where nothing is catching, so a key
  /// converted twice or left as an ISO string is an exception on the panel
  /// rather than a refusal on the wire.
  Future<Object?> timeseriesCountMultiple(rpc.Parameters params) async {
    const method = DataServiceMethods.timeseriesCountMultiple;
    final table = _series(params, 'table', method);
    final intervalMs = _requiredInt(params, 'intervalMs', method);
    final howMany = _requiredInt(params, 'howMany', method);
    final since = _instant(params, 'since', method);
    final counts = await _sized(
        method,
        () => source.timeseries.countTimeseriesDataMultiple(
            table, Duration(milliseconds: intervalMs), howMany,
            since: since));
    return {
      for (final entry in counts.entries)
        '${entry.key.millisecondsSinceEpoch}': entry.value,
    };
  }

  // ------------------------------------------------------------------ shared

  /// A wire series name out of [name].
  ///
  /// A non-empty string is all this asks for; the grammar and the allow-list
  /// are `hostile_params_test.dart`'s subject and live further down this file.
  static String _series(rpc.Parameters params, String name, String method) {
    final raw = params[name].valueOr(null);
    if (raw is! String || raw.isEmpty) {
      throw _refuse(
          method,
          '$method needs a non-empty string "$name": the series to read, '
          'named as `<series>` or `<series>:<member>`');
    }
    return raw;
  }

  /// A list of wire series names out of [name].
  ///
  /// The three arms `readMany` has (`value_handlers.dart:283-302`), in the
  /// same order and with the same message convention, because this is the
  /// same hazard: an unbounded breadth argument on one round trip.
  List<String> _seriesList(
      rpc.Parameters params, String name, String method) {
    final raw = params[name].valueOr(null);
    if (raw is! List) {
      throw _refuse(
          method,
          '$method needs a "$name" list: the one call that exists so a chart '
          'with four lines does not pay four round trips');
    }
    if (raw.isEmpty) {
      throw _refuse(
          method,
          '$method needs at least one series: a request for nothing is a '
          'round trip the client then waits on');
    }
    if (raw.length > config.maxKeysPerSubscribe) {
      throw _refuse(
          method,
          '$method carried ${raw.length} series, over this server\'s limit of '
          '${config.maxKeysPerSubscribe}; split the request or raise '
          'maxKeysPerSubscribe');
    }
    return [
      for (var i = 0; i < raw.length; i++)
        if (raw[i] case final String entry when entry.isNotEmpty)
          entry
        else
          throw _refuse(
              method,
              '$method\'s "$name" carries a non-string or empty entry at '
              'index $i: every entry names a series, as `<series>` or '
              '`<series>:<member>`'),
    ];
  }

  /// A required instant out of [name], as epoch milliseconds.
  static DateTime _requiredInstant(
          rpc.Parameters params, String name, String method) =>
      _instant(params, name, method, required: true)!;

  /// An instant out of [name], or null when it is absent and optional.
  ///
  /// **Epoch milliseconds, never an ISO string.** That is what the client
  /// sends (`client_sub_apis.dart`'s `msOf`), and reading one through
  /// `(raw as num).toInt()` the way the port source does turns a caller's
  /// wrong type into a cast error inside the handler — which the session
  /// reports as `handlerFailed`, documented as "possibly transient: retrying
  /// is legitimate", for a request that will never succeed.
  static DateTime? _instant(rpc.Parameters params, String name, String method,
      {bool required = false}) {
    final raw = params[name].valueOr(null);
    if (raw == null) {
      if (!required) return null;
      throw _refuse(
          method,
          '$method needs "$name": an instant in epoch milliseconds. There is '
          'no default for it — substituting "now" would answer a different '
          'question than the one asked');
    }
    if (raw is! int) {
      throw _refuse(
          method,
          '$method needs "$name" as an integer number of epoch milliseconds, '
          'not ${raw.runtimeType}. Instants travel as milliseconds on this '
          'wire, in both directions');
    }
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }

  /// A required integer out of [name]. Bounds are applied by the caller.
  static int _requiredInt(
      rpc.Parameters params, String name, String method) {
    final raw = params[name].valueOr(null);
    if (raw is! int) {
      throw _refuse(
          method,
          '$method needs an integer "$name", not ${raw.runtimeType}. It '
          'scales the work the database does, so it is read as a bound '
          'rather than coerced');
    }
    return raw;
  }

  /// Samples, encoded.
  static List<Object?> _points(List<TimeseriesData> points) =>
      [for (final point in points) point.toJson()];

  /// Runs [ask], mapping a refused-because-too-large result onto the wire.
  ///
  /// **INVALID_PARAMS, deliberately, and not `handlerFailed` (-32011).** The
  /// wire documents -32011 as "possibly transient: retrying is legitimate",
  /// and a panel that retries a month-long window forever is precisely the
  /// denial of service the bound exists to prevent. A too-large query is a bad
  /// *request*: the limit is fixed, the window is the caller's, and the fix is
  /// in the caller's hands. The message carries the limit, what was measured
  /// and the name of the method that would answer the same question inside it
  /// (`result_too_large.dart`), because a refusal an engineer cannot act on is
  /// a broken chart with extra steps.
  ///
  /// It is also **not a close**. Letting the over-large answer through would
  /// have the conflating send buffer evict the session with `4004`, which
  /// reports "your query was too large" as "you disconnected" — a
  /// query-too-large misread as backpressure, the class of failure this
  /// project exists to prevent (10-CONTEXT amendment 3).
  ///
  /// Nothing raises it yet: 10-07's reader and 10-10's byte ceiling do. The
  /// mapping is here now because the *code* is a wire decision and this is
  /// where the wire is.
  static Future<T> _sized<T>(String method, Future<T> Function() ask) async {
    try {
      return await ask();
    } on ResultTooLarge catch (tooLarge) {
      throw _refuse(method, '$method refused: ${tooLarge.message}');
    }
  }

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
