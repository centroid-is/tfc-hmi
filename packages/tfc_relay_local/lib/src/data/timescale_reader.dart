/// The four `TimeseriesApi` methods over `tfc_dart`'s `Database` — **the
/// second and last file in this package that knows `Database` exists**, and
/// the mirror of 8b-02's `TimescaleSink`.
///
/// `freeze_test.dart` pins the count of database-importing files at two and
/// names both. The point of the seam is the same in this direction as in the
/// write direction: everything else in the package stays testable with no
/// database, and `Database`'s constructor-started flush timer and its
/// retry-forever connect ladder cannot leak onto the gateway's value path.
///
/// ## PHASE 10 READS AND NEVER WRITES
///
/// There is no insert path here and no retention path, and a sweep in
/// `freeze_test.dart` asserts it over this whole directory.
/// `Database.registerRetentionPolicy` does not merely register: it *uninstalls
/// and reinstalls* a differing policy (`database.dart:847-864`), which is the
/// fight 8b spent a whole verdict avoiding while the application's collector
/// still runs against the same server. A read path that touched it would
/// restart that fight from the side nobody was watching.
///
/// ## One `Database`, borrowed rather than built
///
/// The constructor takes a **supplier**, not an instance. Two reasons, and the
/// first is the one the threat register cares about:
///
///  * *A second pool doubles connections against a plant Postgres* (T-10-28)
///    and gives 8b's `SELECT application_name, count(*) FROM pg_stat_activity
///    GROUP BY 1` a second name to explain. The composition root hands over
///    the instance `TimescaleSink` already owns.
///  * *The sink connects in the background and the gateway does not wait for
///    it* (8b's WR-03). So the instance does not exist yet when this object is
///    constructed, and it is replaced on reconnect. A supplier is what lets
///    the reader borrow whatever the composition currently holds; a pinned
///    instance would be stale after the first reconnect. `null` means the
///    historian is not up, which is [HistorianUnavailable] — retryable, not a
///    refusal, and never a hang.
///
/// `DatabaseConfig.queryTimeout` (declared at `database.dart:107`, defaulting
/// at `:129`, threaded to the pool by drift at `database_drift.dart:503` and
/// `:552`) is the first of the three result-size bounds and the only free one:
/// it makes a badly-planned query die in the database rather than in a send
/// buffer. It is set where the `DatabaseConfig` is built —
/// `CollectionConfig.queryTimeout`, `timescale_sink.dart`'s `_databaseConfig`
/// — which is also the only place it can be set, since this object never
/// builds one.
///
/// ## The member projection
///
/// 10-CONTEXT ruling 2: a struct series is served **one scalar member at a
/// time**, addressed `<series>:<member>`, and the wire's sample type stays
/// `num`. That is a `SELECT` of one column plus `time` — not a fetch of the
/// whole row followed by a filter. The two are indistinguishable in the
/// output, which is exactly why the test asserts the executed query's *column
/// list*: fetching every member to serve one would ship the byte problem
/// ruling 2 exists to solve while claiming to have solved it.
///
/// An **unaddressed** struct is a refusal ([StructSeriesUnaddressed]), not a
/// `Map`. `client_sub_apis.dart:257` decodes every point as
/// `TimeseriesData<num>`; a `Map` there is a `CastError` at the panel, which
/// an operator reads as "the chart is broken" rather than as "you did not say
/// which member" (T-10-30).
///
/// ## What the refusals surface as today
///
/// Every exception in this file reaches the wire as `handlerFailed` (-32011)
/// through `relay_session.dart`'s catch-all, which is right for
/// [HistorianUnavailable] and for a database error, and **wrong for the
/// permanent ones** — -32011 is documented as possibly transient, so a panel
/// may retry a request that can never succeed. Mapping
/// [TimeseriesReadRefusal]'s permanent subclasses to `INVALID_PARAMS` at
/// `data_handlers.dart`, the way `ResultTooLarge` already is (10-03), is a
/// named follow-up rather than something this file can do. They are a sealed
/// family so that mapping is a switch and not a string match. In the composed
/// gateway `_PolicyTimeseries` answers an unmappable series as one that does
/// not exist *before* the reader sees it, so [UnknownSeries] is reachable only
/// when the policy's resolver and the reader's disagree — a mis-composition,
/// which is worth an error rather than an empty chart.
library;

import 'package:drift/drift.dart' show Variable;
// Prefixed, because `tfc_dart` and the protocol package each define a
// `TimeseriesData` and this file's whole job is translating one into the
// other. The seam sweep matches the URI, not the prefix.
import 'package:tfc_dart/core/database.dart' as ts;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show ResolvedSeries, SeriesResolver, TimeseriesApi, TimeseriesData;

/// Whatever `Database` the composition currently holds, or null while the
/// historian is not up.
typedef DatabaseSupplier = ts.Database? Function();

/// Why a read was refused. Sealed so a future mapping at the handler is a
/// switch the compiler checks rather than a string match.
sealed class TimeseriesReadRefusal implements Exception {
  const TimeseriesReadRefusal(this.message);

  final String message;

  /// Whether retrying the identical request could ever succeed. False for
  /// every refusal about the *request*; true only for the historian being
  /// down.
  bool get retryable => this is HistorianUnavailable;

  @override
  String toString() => message;
}

/// The series is not in the collection plan.
final class UnknownSeries extends TimeseriesReadRefusal {
  UnknownSeries(this.wireName)
      : super('no series named "$wireName" is collected by this gateway, so '
            'there is no table to read. If this is a chart that worked '
            'before the cutover, its samples are in the application '
            'collector\'s own unprefixed table and are reached by running '
            'the one-shot migration or by declaring a read-side alias');

  final String wireName;
}

/// The table is a struct and the caller named no member.
final class StructSeriesUnaddressed extends TimeseriesReadRefusal {
  StructSeriesUnaddressed(this.wireName, this.members)
      : super('"$wireName" is recorded as a structure with one column per '
            'member, so it has no single scalar series. Ask for one member: '
            '${members.map((m) => '$wireName:$m').join(', ')}');

  final String wireName;
  final List<String> members;
}

/// The caller named a member the table does not have.
final class UnknownSeriesMember extends TimeseriesReadRefusal {
  UnknownSeriesMember(this.wireName, this.member, this.members)
      : super('"$wireName" has no member "$member". It has: '
            '${members.join(', ')}');

  final String wireName;
  final String member;
  final List<String> members;
}

/// The column holds something a chart cannot plot.
final class SeriesNotNumeric extends TimeseriesReadRefusal {
  SeriesNotNumeric(this.wireName, this.dataType)
      : super('"$wireName" is stored as $dataType, and the pipe carries '
            'samples as numbers. Sending it would be a CastError at whatever '
            'is drawing the chart');

  final String wireName;
  final String dataType;
}

/// An `orderBy` outside the two values the API's own contract uses.
final class UnsupportedOrdering extends TimeseriesReadRefusal {
  UnsupportedOrdering(this.orderBy)
      : super('orderBy must be "time ASC" or "time DESC"; "$orderBy" is '
            'neither. The fragment is concatenated into an ORDER BY clause '
            'unchanged (database_drift.dart:909), so it is refused rather '
            'than sanitized — a sanitizer invites the question of whether it '
            'is complete');

  final String orderBy;
}

/// The historian is not connected right now.
final class HistorianUnavailable extends TimeseriesReadRefusal {
  HistorianUnavailable()
      : super('the historian is not connected; this is worth retrying');
}

/// `TimeseriesApi` over a shared `Database`, with every table name resolved
/// before any statement is built.
final class TimescaleReader implements TimeseriesApi {
  TimescaleReader({required this.database, required this.resolver});

  /// The shared instance, borrowed per call. See the library doc.
  final DatabaseSupplier database;

  /// The only thing between a client-supplied string and a `FROM` clause.
  final SeriesResolver resolver;

  /// The two orderings the frozen signature's own default is drawn from
  /// (`state_man_api.dart:269`). The handler allow-lists these too (10-03);
  /// this is the last belt, for a caller that reaches the reader without
  /// passing through one — a contract leg, or an embedder.
  static const Set<String> _orderings = {'time ASC', 'time DESC'};

  /// Postgres types a chart can plot. Everything else is refused rather than
  /// nulled out sample by sample, which would be a chart of nothing with no
  /// explanation anywhere.
  static const Set<String> _numericTypes = {
    'smallint',
    'integer',
    'bigint',
    'real',
    'double precision',
    'numeric',
    'boolean',
  };

  @override
  Future<List<TimeseriesData>> queryTimeseriesData(
      String tableName, DateTime to,
      {String? orderBy = 'time ASC', DateTime? from}) async {
    _checkOrdering(orderBy);
    final db = _database();
    final series = _resolve(tableName);
    final shape = await _shapeOf(db, tableName, series);
    return _read(db, tableName, series, shape, to, orderBy: orderBy, from: from);
  }

  @override
  Future<Map<String, List<TimeseriesData>>> queryTimeseriesDataMultiple(
      List<String> tableNames, DateTime to,
      {String? orderBy = 'time ASC', DateTime? from}) async {
    _checkOrdering(orderBy);
    final db = _database();

    // **Resolved first, all of them, before a single statement.** One bad
    // name refuses the batch: querying the good names and then refusing
    // would have run the statements this belt exists to prevent, and the
    // refusal would be claiming "no effect" untruthfully.
    final series = <String, ResolvedSeries>{
      for (final name in tableNames) name: _resolve(name),
    };

    // **One query per series rather than `Database.queryTimeseriesDataMultiple`'s
    // full outer join.** Not a preference — that method is unusable here.
    // It hardcodes the column list to `['value', 'time']`
    // (`database.dart:1310`), so it cannot serve a member of a struct table
    // at all, and it `coalesce`s the joined tables' timestamps into one
    // column (`database_drift.dart:937`), so a sample's own instant is lost
    // whenever two series were not sampled on the same clock — which is
    // every pair of entries with different `sample_interval_us`. N bounded
    // queries against a database on the same host is the honest trade; the
    // breadth is bounded at the handler by `maxKeysPerSubscribe` (10-03).
    final answer = <String, List<TimeseriesData>>{};
    for (final entry in series.entries) {
      final shape = await _shapeOf(db, entry.key, entry.value);
      answer[entry.key] = await _read(db, entry.key, entry.value, shape, to,
          orderBy: orderBy, from: from);
    }
    // Built from the REQUEST, so one entry per requested series — including
    // the silent ones — is this gateway's property rather than something it
    // inherits from its source.
    return <String, List<TimeseriesData>>{
      for (final name in tableNames) name: answer[name] ?? const [],
    };
  }

  @override
  Future<List<TimeseriesData>> queryTimeseriesDataDownsampled(
      String tableName, DateTime from, DateTime to,
      {int maxPoints = 1000}) async {
    final db = _database();
    final series = _resolve(tableName);
    final shape = await _shapeOf(db, tableName, series);
    final member = series.member;

    if (member == null) {
      // A scalar table is exactly what the shipped method was written for,
      // including its `_valueColumnType` probe and its array handling.
      return _points(
          tableName,
          shape,
          await db.queryTimeseriesDataDownsampled(series.table, from, to,
              maxPoints: maxPoints));
    }

    // **A struct table has no column named `value`, so the shipped method's
    // `_valueColumnType` probe answers null and it returns the UNBOUNDED raw
    // query instead** (`database.dart:1486-1489`) — silently, for every
    // struct table there is, which is ninety of the live plant's 140
    // collected keys. That is why the bucketing is spelled again here with
    // the member column parameterised: `buildDownsampleSql` hardcodes
    // `value` and takes only a table name, so it cannot be reused. This is
    // the ONE re-spelling of that shape in this repository, and it mirrors
    // the non-array branch (`database.dart:473-492`) point for point: three
    // points per bucket — min, max, last — at the bucket start, its midpoint
    // and its end.
    final startTime = from.isBefore(to) ? from.toUtc() : to.toUtc();
    final endTime = from.isBefore(to) ? to.toUtc() : from.toUtc();
    final rangeMs = endTime.difference(startTime).inMilliseconds;
    final numBuckets = (maxPoints / 3).floor();
    if (rangeMs <= 0 || numBuckets <= 0) {
      // The same two degenerate cases the shipped method has. The wire never
      // reaches them: `ServerConfig.minTimeseriesPoints` refuses a maxPoints
      // under three precisely because the shipped fallback here is unbounded
      // (10-03). A direct caller gets the bounded raw window instead.
      return queryTimeseriesData(tableName, endTime, from: startTime);
    }
    final bucketMs = (rangeMs / numBuckets).ceil();
    final column = _quoted(member);
    final table = _quoted(series.table);
    final sql = '''
        WITH agg AS (
          SELECT
            time_bucket(\$1::interval, time) AS bucket,
            min($column)          AS min_val,
            max($column)          AS max_val,
            last($column, time)   AS last_val
          FROM $table
          WHERE time >= \$2::timestamptz AND time <= \$3::timestamptz
          GROUP BY bucket
        )
        SELECT bucket                      AS time, min_val  AS value FROM agg
        UNION ALL
        SELECT bucket + \$1::interval * 0.5,       max_val  AS value FROM agg
        UNION ALL
        SELECT bucket + \$1::interval,             last_val AS value FROM agg
        ORDER BY 1
      ''';
    final rows = await db.db.customSelect(sql, variables: [
      Variable.withString('$bucketMs milliseconds'),
      Variable.withString(startTime.toIso8601String()),
      Variable.withString(endTime.toIso8601String()),
    ]).get();
    return [
      for (final row in rows)
        _sample(tableName, shape, row.data['value'], row.data['time']),
    ];
  }

  @override
  Future<Map<DateTime, int>> countTimeseriesDataMultiple(
      String tableName, Duration interval, int howMany,
      {DateTime? since}) async {
    final db = _database();
    final series = _resolve(tableName);

    // **The only method in this family with no contract coverage at all**
    // (`allContractChecks` has three timeseries checks and none of them count
    // buckets), and the only one whose table name reaches SQL with *no*
    // quote-doubling: `'SELECT COUNT(*) as count FROM "$tableName"'` at
    // `database.dart:1645`, where `queryTimeseriesDataDownsampled` at least
    // does `replaceAll('"', '""')`. Nothing upstream will notice if this is
    // wrong, so the resolver above and the cases in `timeseries_read_test.dart`
    // are the only things that will. The plan's own table-name validation is
    // the belt on the other side: 8b-01 rejects any name carrying a quote,
    // semicolon, backslash or control character before it can be collected.
    //
    // A member address counts the same rows as the bare series — one row per
    // sample, whichever member a chart later plots — so the member is not
    // consulted here and no column is named.
    //
    // The buckets are delegated: the shipped arithmetic is contiguous,
    // oldest-first, and issues one `SELECT COUNT(*)` per bucket joined with
    // `UNION ALL`, so **an empty bucket comes back as 0 rather than as an
    // absent key**. That is a property worth keeping rather than reinventing:
    // an absent bucket and a bucket with no rows are different claims, and a
    // strip drawing a gap where there was silence is the line that stops in
    // mid-air.
    //
    // The one thing that is NOT delegated is the instant. The bucket bounds
    // are interpolated as bare ISO strings with no zone
    // (`database.dart:1642-1646`), so a local-time `since` would be read in
    // whatever the session's TimeZone happens to be — every bucket shifted,
    // no error anywhere. Normalising to UTC here makes the string carry its
    // own zone.
    return db.countTimeseriesDataMultiple(series.table, interval, howMany,
        since: (since ?? DateTime.now()).toUtc());
  }

  // ---------------------------------------------------------------- internals

  ts.Database _database() {
    final db = database();
    if (db == null) throw HistorianUnavailable();
    return db;
  }

  /// The wire name, resolved — or a refusal. Never a guess.
  ///
  /// A malformed name throws a `FormatException` out of `SeriesAddress.parse`
  /// rather than resolving to null: "you spelled it wrong" and "there is no
  /// such series" are different facts and the caller acts on each differently.
  ResolvedSeries _resolve(String wireName) {
    final series = resolver.resolve(wireName);
    if (series == null) throw UnknownSeries(wireName);
    return series;
  }

  void _checkOrdering(String? orderBy) {
    if (orderBy == null) return; // an explicit "no ordering", not a default
    if (!_orderings.contains(orderBy)) throw UnsupportedOrdering(orderBy);
  }

  /// What one physical table looks like, and whether the address fits it.
  ///
  /// Every refusal a request can earn is decided here, **before any statement
  /// is built**, which is what makes the refusal honestly mean "no effect".
  Future<_Shape> _shapeOf(
      ts.Database db, String wireName, ResolvedSeries series) async {
    final columns = await _columnsOf(db, series.table);
    final members = columns.keys.where((c) => c != 'time').toList()..sort();
    final member = series.member;

    if (member != null) {
      if (!columns.containsKey(member) || member == 'time') {
        throw UnknownSeriesMember(wireName, member, members);
      }
      return _shapeFor(wireName, member, columns[member]!);
    }
    // A scalar table is `("value", "time")` — 8b-03's measured shape. Anything
    // else with more than one non-time column is a struct.
    if (members.length == 1 && members.single == 'value') {
      return _shapeFor(wireName, 'value', columns['value']!);
    }
    throw StructSeriesUnaddressed(wireName, members);
  }

  static _Shape _shapeFor(String wireName, String column, String dataType) {
    if (!_numericTypes.contains(dataType)) {
      throw SeriesNotNumeric(wireName, dataType);
    }
    return _Shape(column: column, isBoolean: dataType == 'boolean');
  }

  /// `column_name → data_type`, from the catalogue.
  ///
  /// Deliberately uncached, for the reason `_valueColumnType` records at
  /// `database.dart:1421-1433`: the type is only stable while the table is,
  /// and a remembered type that outlives a retyped table fails in two
  /// different ways, one of them silently.
  Future<Map<String, String>> _columnsOf(ts.Database db, String table) async {
    final rows = await db.db.customSelect(
      r'''
      SELECT column_name, data_type
      FROM information_schema.columns
      WHERE table_name = $1
      ''',
      variables: [Variable.withString(table)],
    ).get();
    return <String, String>{
      for (final row in rows)
        row.data['column_name'] as String: row.data['data_type'] as String,
    };
  }

  Future<List<TimeseriesData>> _read(ts.Database db, String wireName,
      ResolvedSeries series, _Shape shape, DateTime to,
      {String? orderBy, DateTime? from}) async {
    if (series.member == null) {
      // The scalar path delegates, so the where-clause shapes, the
      // ISO8601/timestamptz handling and the time decoding are not re-spelled
      // here.
      return _points(
          wireName,
          shape,
          await db.queryTimeseriesData(series.table, to.toUtc(),
              orderBy: orderBy, from: from?.toUtc()));
    }

    // The projection: one column plus time. `AppDatabase.tableQuery`
    // interpolates the column list unquoted (`database_drift.dart:907`), so
    // the identifiers are quoted here — and the member has already been
    // checked against the table's real columns, so the quoting is the second
    // belt rather than the first.
    final rows = await db.db.tableQuery(
      series.table,
      columns: [_quoted(shape.column), _quoted('time')],
      where: from != null
          ? r'time >= $1::timestamptz AND time <= $2::timestamptz'
          : r'time >= $1::timestamptz',
      whereArgs: from != null
          ? [
              from.toUtc().toIso8601String(),
              to.toUtc().toIso8601String(),
            ]
          : [to.toUtc().toIso8601String()],
      orderBy: orderBy,
    );
    return [
      for (final row in rows)
        _sample(wireName, shape, row.data[shape.column], row.data['time']),
    ];
  }

  List<TimeseriesData> _points(
          String wireName, _Shape shape, List<ts.TimeseriesData> raw) =>
      [
        for (final point in raw)
          _sample(wireName, shape, point.value, point.time),
      ];

  /// One sample, built through the protocol's own constructor.
  ///
  /// Not around it: `TimeseriesData`'s factory is where a non-finite double
  /// becomes null (`timeseries.dart:63-66`). A weigher divide-by-zero that
  /// reached `jsonEncode` intact would throw and fail the whole batch for
  /// every connected client.
  TimeseriesData _sample(
      String wireName, _Shape shape, Object? raw, Object? rawTime) {
    final DateTime time;
    if (rawTime is DateTime) {
      time = rawTime;
    } else if (rawTime is String) {
      time = DateTime.parse(rawTime);
    } else {
      throw ts.DatabaseException('Unexpected time format: ${rawTime.runtimeType}');
    }
    return TimeseriesData<num?>(_numeric(wireName, shape, raw), time.toUtc());
  }

  /// The wire's sample type is `num`, because the client decodes every point
  /// as `TimeseriesData<num>`.
  ///
  /// A bool charts as 1/0 — which is what `graph.dart:949` already does at the
  /// chart, moved to the one place that can also keep the wire's type honest.
  num? _numeric(String wireName, _Shape shape, Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    if (raw is bool) return raw ? 1 : 0;
    // Reachable only if a column changed type under a live table; the shape
    // check refuses everything else up front.
    throw SeriesNotNumeric(wireName, raw.runtimeType.toString());
  }

  /// Postgres identifier quoting, doubling any embedded quote — the same
  /// treatment `queryTimeseriesDataDownsampled` gives its table name at
  /// `database.dart:1483` and `countTimeseriesDataMultiple` gives its none.
  static String _quoted(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';
}

/// Which column carries this series' samples, and whether it needs the 1/0
/// treatment.
final class _Shape {
  const _Shape({required this.column, required this.isBoolean});

  final String column;
  final bool isBoolean;
}
