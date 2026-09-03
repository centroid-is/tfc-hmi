/// What the reader does *before* it reaches a database — the belt, the
/// projection's column list, and the refusals a struct earns.
///
/// These cases need no server: their whole subject is what SQL was built and
/// whether any was built at all, and that is visible from a recording
/// `AppDatabase` with a `NativeDatabase.memory()` underneath it. Putting them
/// behind the `db` tag would hide the two properties this file exists for —
/// "no query ran" and "these columns and no others" — inside a lane that is
/// excluded on three of the four CI platforms.
///
/// The rows-come-back-from-a-real-TimescaleDB half is `timeseries_read_test.dart`,
/// which is 8b's `db` lane and stays there.
@TestOn('vm')
library;

import 'package:drift/drift.dart'
    show QueryRow, ResultSetImplementation, Selectable, Variable;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/state_man.dart' show KeyMappingEntry, KeyMappings;
import 'package:tfc_relay_local/src/key_router.dart';
import 'package:tfc_relay_local/src/local_state_man.dart';
import 'package:tfc_relay_local/src/data/read_limits.dart';
import 'package:tfc_relay_local/src/data/timescale_reader.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show ResolvedSeries, SeriesAddress, SeriesResolver, TimeseriesApi;

import 'support/fake_upstream_link.dart';

// --------------------------------------------------------------- the recorder

/// Every statement this backend was asked to run, and canned answers for the
/// two paths a reader takes.
///
/// `tableQuery` and `customSelect` are the only two doors to SQL that
/// `Database`'s read methods use, so recording both is what makes "the query
/// never ran" a measurement rather than a hope.
class RecordingBackend extends AppDatabase {
  RecordingBackend()
      : super.forTest(
            DatabaseConfig(), NativeDatabase.memory(logStatements: false));

  /// `(sql, columns)` for every `tableQuery`, in call order.
  final List<({String table, List<String>? columns, String? orderBy})>
      tableQueries = [];

  /// Raw SQL for every `customSelect`.
  final List<String> statements = [];

  /// What `information_schema.columns` should answer: column name → data type.
  Map<String, String> columns = <String, String>{'value': 'double precision'};

  /// Rows `tableQuery` answers with.
  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];

  bool get touchedSql => tableQueries.isNotEmpty || statements.isNotEmpty;

  /// Just the reader's bounded window queries, in call order.
  ///
  /// `statements` also carries the `information_schema` probe that runs before
  /// every read, and a case asserting "the query that was built" means the one
  /// that touches the series' own table.
  List<String> get windowQueries =>
      statements.where((s) => s.contains('::timestamptz')).toList();

  @override
  Future<List<QueryRow>> tableQuery(
    String tableName, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    tableQueries
        .add((table: tableName, columns: columns, orderBy: orderBy));
    return [for (final row in rows) QueryRow(row, this)];
  }

  @override
  Selectable<QueryRow> customSelect(String query,
      {List<Variable> variables = const [],
      Set<ResultSetImplementation<dynamic, dynamic>> readsFrom = const {}}) {
    statements.add(query);
    if (query.contains('::timestamptz')) {
      // The reader's own bounded window query (10-10). Answered from [rows]
      // rather than executed: the backend underneath is SQLite and knows
      // nothing of `timestamptz`, and what these cases measure is the SQL that
      // was built rather than what Postgres would do with it. The db lane in
      // `read_limits_test.dart` is where a real server answers it.
      return _CannedRows([for (final row in rows) QueryRow(row, this)]);
    }
    if (query.contains('information_schema.columns')) {
      // The shape `TimescaleReader._columnsOf` reads.
      return super.customSelect(
        columns.entries
            .map((e) =>
                "SELECT '${e.key}' AS column_name, '${e.value}' AS data_type")
            .join(' UNION ALL '),
      );
    }
    return super.customSelect(query, variables: variables, readsFrom: readsFrom);
  }
}

/// Rows handed straight back, for a statement the SQLite underneath cannot run.
///
/// Only `get()` is answered. Everything else throws by name rather than
/// returning an empty stream, because a `watch()` that silently produced
/// nothing would make a case pass by measuring the absence of its own subject.
final class _CannedRows implements Selectable<QueryRow> {
  _CannedRows(this._rows);

  final List<QueryRow> _rows;

  @override
  Future<List<QueryRow>> get() async => _rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'the recording backend answers only get(); '
      '${invocation.memberName} was called and would have been silently '
      'empty');
}

/// Maps exactly what the cases below need and refuses everything else, so a
/// hostile name has nothing to ride in on.
final class OneSeries implements SeriesResolver {
  const OneSeries({this.table = 'gw_Line1.Motor1'});

  final String table;

  @override
  ResolvedSeries? resolve(String wireName) {
    final address = SeriesAddress.parse(wireName);
    if (address.series != 'Line1.Motor1') return null;
    return ResolvedSeries(
        table: table, member: address.member, plantKey: address.series);
  }

  @override
  String? keyForTable(String t) => t == table ? 'Line1.Motor1' : null;

  @override
  String? keyForNode(String nodeId) => null;
}

final DateTime to = DateTime.utc(2026, 9, 3, 12);
final DateTime from = DateTime.utc(2026, 9, 3, 11);

void main() {
  late RecordingBackend backend;
  late Database db;
  late TimescaleReader reader;

  setUp(() {
    backend = RecordingBackend();
    // `Database`'s constructor starts a 500 ms flush timer before the caller
    // can say a word (`database.dart:503`), so every test that wraps a
    // backend closes it — the caution `fake_write_backend.dart` inherits.
    db = Database(backend);
    reader = TimescaleReader(database: () => db, resolver: const OneSeries());
    addTearDown(db.close);
  });

  group('the belt: a name the plan does not know never reaches a statement',
      () {
    test('a hostile table name is refused and no SQL is built', () async {
      await expectLater(
          reader.queryTimeseriesData('pg_catalog.pg_authid', to),
          throwsA(isA<UnknownSeries>()));

      expect(backend.touchedSql, isFalse,
          reason: 'the resolver is the only thing between a client string '
              'and a FROM clause. countTimeseriesDataMultiple interpolates '
              'its table name with no quote-doubling at all '
              '(database.dart:1645), so a refusal that happens after the '
              'statement is built is not a guard against it');
    });

    test('the same holds on all four methods', () async {
      await expectLater(reader.queryTimeseriesData('nope', to),
          throwsA(isA<UnknownSeries>()));
      await expectLater(reader.queryTimeseriesDataMultiple(['nope'], to),
          throwsA(isA<UnknownSeries>()));
      await expectLater(
          reader.queryTimeseriesDataDownsampled('nope', from, to),
          throwsA(isA<UnknownSeries>()));
      await expectLater(
          reader.countTimeseriesDataMultiple(
              'nope', const Duration(minutes: 1), 4),
          throwsA(isA<UnknownSeries>()));

      expect(backend.touchedSql, isFalse,
          reason: 'a filter fitted to the single-series path and forgotten '
              'on the other three hands the historian to the next chart');
    });

    test('one bad name in a batch refuses the batch', () async {
      await expectLater(
          reader.queryTimeseriesDataMultiple(['Line1.Motor1', 'nope'], to),
          throwsA(isA<UnknownSeries>()));

      expect(backend.touchedSql, isFalse,
          reason: 'refusing after the good names have been queried would '
              'have run the statement this belt exists to prevent, and the '
              'refusal would be claiming "no effect" untruthfully');
    });

    test('a malformed name throws a FormatException, not UnknownSeries',
        () async {
      await expectLater(
          reader.queryTimeseriesData('a:b:c', to), throwsFormatException,
          reason: '"you spelled it wrong" and "there is no such series" are '
              'two different facts');
      expect(backend.touchedSql, isFalse);
    });

    test('an orderBy outside the two-value allow-list is refused', () async {
      await expectLater(
          reader.queryTimeseriesData('Line1.Motor1', to,
              orderBy: 'time ASC, (SELECT 1)'),
          throwsA(isA<UnsupportedOrdering>()));
      await expectLater(
          reader.queryTimeseriesData('Line1.Motor1', to, orderBy: 'value DESC'),
          throwsA(isA<UnsupportedOrdering>()));

      expect(backend.touchedSql, isFalse,
          reason: 'the handler allow-lists this too (10-03). Two belts, and '
              'this is the last one before the fragment is concatenated into '
              'an ORDER BY clause — a caller that reaches the reader without '
              'passing the handler (a contract leg, an embedder) gets the '
              'same answer');
    });

    test('both accepted orderings reach the source verbatim', () async {
      backend.rows = [
        {'value': 1, 'time': to}
      ];
      await reader.queryTimeseriesData('Line1.Motor1', to, orderBy: 'time ASC');
      await reader.queryTimeseriesData('Line1.Motor1', to,
          orderBy: 'time DESC');

      expect(backend.windowQueries, hasLength(2));
      expect(backend.windowQueries[0], contains('ORDER BY time ASC'));
      expect(backend.windowQueries[1], contains('ORDER BY time DESC'),
          reason: 'the anti-vacuity arm: a belt that refused everything '
              'would pass every refusal case above');
    });
  });

  group('the member projection is a SELECT, not a fetch-then-filter', () {
    setUp(() {
      backend.columns = <String, String>{
        'speed': 'double precision',
        'current': 'double precision',
        'temp': 'double precision',
      };
      backend.rows = [
        {'speed': 47.5, 'time': to}
      ];
    });

    test('the executed query names the member column and time, nothing else',
        () async {
      final samples = await reader.queryTimeseriesData(
          'Line1.Motor1:speed', to,
          from: from);

      expect(samples.single.value, 47.5);
      final sql = backend.windowQueries.single;
      expect(sql, contains('SELECT "speed", "time"'),
          reason: 'ruling 2 is "bytes proportional to the chart\'s ask". '
              'Fetching every member and discarding all but one produces the '
              'same output as projecting, so the output cannot tell them '
              'apart — the column list is the only place the difference is '
              'visible, and it is the whole point');
      expect(sql, isNot(contains('current')),
          reason: 'and the members that were not asked for do not appear');
    });

    test('a member the table does not have is refused, naming what it has',
        () async {
      await expectLater(
          reader.queryTimeseriesData('Line1.Motor1:torque', to),
          throwsA(isA<UnknownSeriesMember>().having((e) => e.toString(),
              'message', allOf(contains('torque'), contains('speed')))));

      expect(backend.tableQueries, isEmpty,
          reason: 'a member name is a client-supplied string that would be '
              'concatenated into a select list; it is checked against the '
              'table\'s real columns before anything is built');
    });

    test('an unaddressed struct is a refusal naming its members', () async {
      await expectLater(
          reader.queryTimeseriesData('Line1.Motor1', to),
          throwsA(isA<StructSeriesUnaddressed>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('speed'), contains('current'),
                  contains('temp')))));

      expect(backend.tableQueries, isEmpty,
          reason: 'the client decodes every sample as TimeseriesData<num> '
              '(client_sub_apis.dart:257). A Map on that wire is a CastError '
              'at the panel, which arrives as "the chart is broken" rather '
              'than as "you did not say which member"');
    });
  });

  group('a scalar table is unaffected', () {
    test('the bare series takes the same bounded statement, naming "value"',
        () async {
      backend.rows = [
        {'value': 7, 'time': to}
      ];
      final samples = await reader.queryTimeseriesData('Line1.Motor1', to);

      expect(samples.single.value, 7);
      expect(samples.single.time.isUtc, isTrue);
      expect(backend.windowQueries.single, contains('SELECT "value", "time"'),
          reason: 'ONE spelling, not two. Until 10-10 the scalar path '
              'delegated to Database.queryTimeseriesData and the member path '
              'spelled its own query, so the shapes were already written '
              'twice; the row ceiling needs a LIMIT and the shipped method '
              'has no parameter for one (and tfc_dart is not this phase\'s to '
              'change), so both paths now take the reader\'s own statement');
      expect(backend.tableQueries, isEmpty,
          reason: 'and nothing reaches AppDatabase.tableQuery, which cannot '
              'carry a LIMIT — a bound that one path can bypass is not a '
              'bound');
    });

    test('every window query carries LIMIT maxRows + 1, and nothing else does',
        () async {
      backend.rows = [
        {'value': 7, 'time': to}
      ];
      final bounded = TimescaleReader(
          database: () => db,
          resolver: const OneSeries(),
          limits: ReadLimits(maxTimeseriesRows: 7));

      await bounded.queryTimeseriesData('Line1.Motor1', to, from: from);

      expect(backend.windowQueries.single, contains('LIMIT 8'),
          reason: 'the detection is LIMIT n + 1: the extra row is how the '
              'reader learns the answer is over the cap WITHOUT building it. '
              'Counting first with a second query would double the work and '
              'race the writer; fetching everything and measuring afterwards '
              'would have the rows in memory already, which is the failure '
              'the send buffer is downstream of');
    });

    test('a boolean column charts as 1 and 0', () async {
      backend.columns = <String, String>{'value': 'boolean'};
      backend.rows = [
        {'value': true, 'time': to},
        {'value': false, 'time': to.add(const Duration(seconds: 1))},
      ];
      final samples = await reader.queryTimeseriesData('Line1.Motor1', to);

      expect(samples.map((s) => s.value), [1, 0],
          reason: 'graph.dart:949 already does exactly this at the chart; '
              'doing it here is what keeps the wire\'s sample type num, '
              'which is what the client decodes');
    });

    test('a text column refuses rather than sending an unchartable series',
        () async {
      backend.columns = <String, String>{'value': 'text'};
      backend.rows = [
        {'value': 'RUNNING', 'time': to}
      ];

      await expectLater(reader.queryTimeseriesData('Line1.Motor1', to),
          throwsA(isA<SeriesNotNumeric>()));
    });
  });

  group('the composer answers a reader instead of throwing', () {
    LocalStateMan plant({TimeseriesApi? timeseries}) {
      final link = FakeUpstreamLink(alias: 'plant');
      final man = LocalStateMan(
        links: [link],
        router: KeyRouter.overLinks([link],
            mappings: KeyMappings(nodes: <String, KeyMappingEntry>{})),
        timeseries: timeseries,
      );
      addTearDown(man.dispose);
      return man;
    }

    test('LocalStateMan.timeseries is the reader it was composed with', () {
      final man = plant(timeseries: reader);

      expect(identical(man.timeseries, reader), isTrue,
          reason: 'the same instance every time it is asked for, like '
              '`browse`: a getter that rebuilt would throw away whatever the '
              'composition wired');
    });

    test('a gateway with no historian says so, and does not pretend', () {
      final man = plant();

      expect(() => man.timeseries, throwsA(isA<StateError>()),
          reason: 'a gateway with no `collection:` block constructs no '
              'database object at all (8b-01\'s deliberate two-field act), '
              'so there is nothing to read from. An empty reader would draw '
              'every chart flat forever and nothing anywhere would say why — '
              'and it is NOT an UnimplementedError either, because the '
              'member is implemented and this is a deployment fact');
      expect(() => man.timeseries, isNot(throwsUnimplementedError),
          reason: 'the ledger in freeze_test.dart drops from three to two in '
              'the same commit; an UnimplementedError here would mean the '
              'member is still owed, and it is not');
    });
  });

  group('without a database', () {
    test('the reader says so, and says it is worth retrying', () async {
      final orphan =
          TimescaleReader(database: () => null, resolver: const OneSeries());

      await expectLater(orphan.queryTimeseriesData('Line1.Motor1', to),
          throwsA(isA<HistorianUnavailable>()),
          reason: 'the sink connects in the background and the gateway does '
              'not wait for it (WR-03). A query in that window is retryable '
              'and must not be a refusal or a hang');
    });
  });
}
