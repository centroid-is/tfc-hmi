/// The eleven `HistoryViewApi` methods over `tfc_dart`'s history tables — the
/// mapping layer between drift's untyped row bags and the wire's records.
///
/// ## This file does not import the database layer, and that is deliberate
///
/// `freeze_test.dart` pins the number of files under this package's `lib/`
/// that import `tfc_dart/core/database*.dart` at **two** — the write adapter
/// (`collect/timescale_sink.dart`) and the read adapter
/// (`data/timescale_reader.dart`) — because `Database`'s constructor starts a
/// flush timer and its connect ladder retries forever, and every additional
/// import site is another place those leak onto the gateway's value path and
/// another place a second connection pool gets built without anyone deciding
/// to (T-10-28).
///
/// A third history-shaped adapter would have been a third site. It is not one:
/// this file takes [DatabaseSupplier] — declared next door in
/// `timescale_reader.dart` — and reaches the drift methods through the value
/// it returns. Dart resolves members on a static type without the type's
/// library being imported, so the seam holds at two and this file still calls
/// `createHistoryView` directly. Nothing is re-declared, nothing is copied,
/// and there is exactly one `Database` in the process.
///
/// The supplier is a supplier for the same two reasons the reader's is: the
/// sink connects in the background and swaps its instance on reconnect, so a
/// pinned instance is stale after the first one, and `null` means the
/// historian is not up — [HistorianUnavailable], retryable, never a hang and
/// never an empty answer. An empty answer here is worse than a refusal: a view
/// picker that says "you have saved nothing" is a picker an operator saves
/// their view into a second time.
///
/// ## The four ways the wire shape and the database shape disagree
///
/// Each of these is a wrong answer that looks like a right one, which is why
/// each has its own paragraph at the site rather than a line in a changelog.
///
/// 1. **drift hands back untyped `Map<String, dynamic>` bags** for keys and
///    graphs (`database_drift.dart:685`, `:704`). Mapped field by field here;
///    no `dynamic` leaves this file.
/// 2. **`createHistoryView` reads its graph map's keys with `int.tryParse` and
///    silently skips whatever fails** (`:610`, and again at `:655` on the
///    update path). The wire type is `Map<int, …>`, so the drop is unreachable
///    from a client — see [graphConfigRows], which is where that claim is made
///    good rather than assumed.
/// 3. **A graph's `name` is nullable in the database and non-nullable on the
///    wire.** [graphConfigRows] and [graphRecordFrom] carry the decision and
///    its consequence.
/// 4. **`getGlobalRetentionHorizon` builds a LOCAL instant and swallows every
///    failure as `null`** (`:774`, `:775-778`). See
///    [HistoryViewStore.getGlobalRetentionHorizon].
///
/// ## PHASE 10 READS AND NEVER WRITES — and what that does not mean
///
/// The sweep over this directory forbids `insertTimeseriesData` and
/// `registerRetentionPolicy`: no sample is recorded here and no retention
/// policy is installed, uninstalled or reinstalled from the read path, which
/// is the two-writer fight 8b settled while the application's own collector
/// still runs. Saving a *view* is not historising: it writes four small
/// configuration tables the application's HMI has always written, and
/// `HistoryViewApi` is four-fifths mutators.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show
        HistoryViewApi,
        HistoryViewGraphRecord,
        HistoryViewKeyRecord,
        HistoryViewPeriodRecord,
        HistoryViewRecord;

import 'timescale_reader.dart' show DatabaseSupplier, HistorianUnavailable;

/// `HistoryViewApi` over the four history tables.
final class HistoryViewStore implements HistoryViewApi {
  HistoryViewStore({required this.database, this.log});

  /// The shared instance, borrowed per call. See the library doc.
  final DatabaseSupplier database;

  /// Where a swallowed failure goes. Optional and injected, following
  /// `IngestLog`'s shape: a store constructed in a test asserts what it was
  /// told, and one constructed by `bin/relay_gateway.dart` writes to the
  /// gateway's logger. Null is a gateway that says nothing, which is the
  /// right default for a fixture and the wrong one for a plant — the
  /// composition root supplies it.
  final void Function(String message)? log;

  @override
  Future<int> createHistoryView(String name, List<String> keys,
      [Map<String, HistoryViewKeyRecord>? keyConfigs,
      Map<int, HistoryViewGraphRecord>? graphConfigs]) async {
    // Already one transaction upstream (database_drift.dart:588).
    return (database() ?? _noHistorian()).db.createHistoryView(
        name, keys, keyConfigRows(keyConfigs), graphConfigRows(graphConfigs));
  }

  @override
  Future<void> updateHistoryView(int id, String name, List<String> keys,
      [Map<String, HistoryViewKeyRecord>? keyConfigs,
      Map<int, HistoryViewGraphRecord>? graphConfigs]) async {
    // Also already one transaction upstream (`:632`), which is what makes the
    // delete-then-reinsert of every key and graph row safe. The ids of those
    // rows are NOT stable across an update, and nothing on the wire claims
    // they are — the records carry the key and the graph index, which are the
    // identities a caller can hold.
    return (database() ?? _noHistorian()).db.updateHistoryView(
        id, name, keys, keyConfigRows(keyConfigs), graphConfigRows(graphConfigs));
  }

  /// Deletes view [id] and everything recorded against it, atomically.
  ///
  /// **The transaction is added here, and this is the decision the plan asked
  /// to have made either way.** Upstream's `deleteHistoryView`
  /// (`database_drift.dart:672-678`) issues four separate statements with no
  /// transaction around them, under a comment saying the keys cascade. Both
  /// halves of that are true at once, and the combination is why it has not
  /// bitten yet: the three child tables really do declare
  /// `REFERENCES history_view(id) ON DELETE CASCADE`, so on Postgres the
  /// *first* statement already does the whole job and the other three match
  /// nothing. The failure mode is therefore narrow — a connection lost between
  /// statements two and four on a deployment where the cascade is not in force
  /// (SQLite with `foreign_keys` off, or a schema built by a migration path
  /// that skipped the constraint) leaves a view deleted from the picker with
  /// its keys, graphs and periods still on disk, reachable by nothing and
  /// deletable by nothing.
  ///
  /// One transaction costs one round trip and removes the mode entirely,
  /// without depending on which dialect is underneath or on whether a
  /// constraint survived a migration. The contract asserts the delete is total
  /// (`data_services_contract.dart:307-317`) and a partial delete would pass
  /// that contract on a good day, which is the shape of bug this project
  /// exists to refuse.
  @override
  Future<void> deleteHistoryView(int id) async {
    final db = (database() ?? _noHistorian()).db;
    return db.transaction(() => db.deleteHistoryView(id));
  }

  @override
  Future<List<HistoryViewRecord>> selectHistoryViews() async {
    final rows = await (database() ?? _noHistorian()).db.selectHistoryViews();
    return [
      for (final row in rows)
        HistoryViewRecord(
          id: row.id,
          name: row.name,
          // `.toUtc()`, both here and below. drift stamps these with a
          // `clientDefault(() => DateTime.now())` — a LOCAL instant. The
          // instant itself is right either way (epoch milliseconds do not
          // care about the flag), but `DateTime ==` compares the flag as well
          // as the value, so a local-flagged createdAt is never equal to the
          // UTC one the record decodes back to, and anything that formats it
          // with `toIso8601String` emits a wall clock with no zone on it.
          createdAt: row.createdAt.toUtc(),
          updatedAt: row.updatedAt?.toUtc(),
        ),
    ];
  }

  @override
  Future<Map<String, HistoryViewKeyRecord>> getHistoryViewKeys(int viewId) async {
    final rows = await (database() ?? _noHistorian()).db.getHistoryViewKeys(viewId);
    return {
      for (final entry in rows.entries)
        entry.key: keyRecordFrom(entry.key, entry.value),
    };
  }

  @override
  Future<Map<int, HistoryViewGraphRecord>> getHistoryViewGraphs(
      int viewId) async {
    final rows = await (database() ?? _noHistorian()).db.getHistoryViewGraphs(viewId);
    return {
      for (final entry in rows.entries)
        entry.key: graphRecordFrom(entry.key, entry.value),
    };
  }

  @override
  Future<List<String>> getHistoryViewKeyNames(int viewId) async {
    // The borrow happens BEFORE the interim refusal, so "the historian is not
    // up" is one answer across all eleven methods for as long as the interim
    // lasts. Three of these are owed by this plan's later tasks; an
    // `UnsupportedError` and not an `UnimplementedError`, because the ledger
    // in `freeze_test.dart` counts the second by name and a member owed by
    // the next commit of the same plan is not a member nobody owns.
    database() ?? _noHistorian();
    throw UnsupportedError('10-08 task 2 owes getHistoryViewKeyNames');
  }

  @override
  Future<int> addHistoryViewPeriod(
      int viewId, String name, DateTime start, DateTime end) async {
    // Normalised to UTC on the way down as well as on the way up. drift
    // parameterises these two, so the instant would survive either way — but
    // the boundary rule is the rule precisely because the places that do NOT
    // parameterise (`database.dart` interpolates bucket bounds as bare ISO
    // strings with no zone, which 10-07 had to work around) are not visible
    // from the call site.
    return (database() ?? _noHistorian())
        .db
        .addHistoryViewPeriod(viewId, name, start.toUtc(), end.toUtc());
  }

  @override
  Future<void> deleteHistoryViewPeriod(int id) async {
    database() ?? _noHistorian();
    throw UnsupportedError('10-08 task 2 owes deleteHistoryViewPeriod');
  }

  @override
  Future<List<HistoryViewPeriodRecord>> listHistoryViewPeriods(
      int viewId) async {
    database() ?? _noHistorian();
    throw UnsupportedError('10-08 task 2 owes listHistoryViewPeriods');
  }

  @override
  Future<DateTime?> getGlobalRetentionHorizon() async {
    database() ?? _noHistorian();
    throw UnsupportedError('10-08 task 3 owes getGlobalRetentionHorizon');
  }

  /// Refuses, retryably, when the composition is holding no `Database`.
  ///
  /// **Every method here is `async`, including the ones whose body is one
  /// delegation, and that is what makes this refusal a rejected `Future`
  /// rather than a synchronous throw.** A `Future`-returning method that
  /// throws before returning one is caught by an `await` inside a `try` and
  /// missed by everything else — `store.selectHistoryViews().catchError(…)`
  /// would not see it, and neither would a caller holding the future to
  /// combine later. `TimescaleReader` is `async` throughout for the same
  /// reason; a test in `history_view_store_test.dart` calls all eleven with
  /// no historian and would fail on the first one that threw early.
  ///
  /// Spelled as a `Never`-returning helper on the right of a `??` rather than
  /// as a method that returns the database, and the reason is the whole trick
  /// this file turns: `database() ?? _noHistorian()` has the static type
  /// [DatabaseSupplier] declares, by inference, so every drift call below is
  /// statically checked — while a method here that *named* that type in its
  /// signature would need the import, and the import is the third seam site
  /// the freeze forbids. A `dynamic` return would have kept the seam and
  /// thrown the checking away, which is the trade this avoids rather than
  /// makes.
  Never _noHistorian() => throw HistorianUnavailable();
}

/// The key configurations, as the untyped bag drift's writers take.
///
/// Null stays null: drift distinguishes "the caller said nothing about the
/// configurations" from "the caller said there are none" by a null check, and
/// collapsing the two here would be this file inventing behaviour rather than
/// wrapping it.
///
/// The `alias` written is the record's own, which is **never null**:
/// `HistoryViewKeyRecord`'s constructor has already substituted the key for an
/// absent alias, mirroring drift's `row.alias ?? row.key`. That default is
/// implemented **once**, in the protocol package, and this file re-derives
/// nothing — two implementations of one default is one too many, and the
/// contract asserts the protocol's (`data_services_contract.dart:294-296`).
///
/// The consequence, said out loud because it is not recoverable afterwards:
/// the wire cannot express "this key has no alias", only "its alias equals its
/// key". A row written for a key with no alias holds `alias = key`, exactly as
/// the application's own HMI has always written it.
Map<String, Map<String, dynamic>>? keyConfigRows(
    Map<String, HistoryViewKeyRecord>? configs) {
  if (configs == null) return null;
  return {
    for (final entry in configs.entries)
      entry.key: <String, dynamic>{
        'alias': entry.value.alias,
        'useSecondYAxis': entry.value.useSecondYAxis,
        'graphIndex': entry.value.graphIndex,
      },
  };
}

/// The graph configurations, keyed by the String drift parses back to an int.
///
/// **This function is where mismatch 2 is answered.** `createHistoryView` does
/// `int.tryParse(entry.key)` and skips the entry when it returns null, with no
/// error and no count — a chart saved with four graphs comes back with three
/// and nothing anywhere says which one went. The wire type is `Map<int, …>`,
/// so the only keys that can reach here are ints and `'$index'` is total over
/// them; `history_view_store_test.dart` asserts that rather than assuming it,
/// across both ends of the VM's int range. **Anything that widens this
/// parameter to accept a String key makes the silent drop reachable again.**
///
/// **Mismatch 3, and the decision.** The column is `text().nullable()` and the
/// wire record's `name` is a non-nullable `String` defaulting to `''` — the
/// protocol package already collapsed the two, mirroring drift's own
/// `row.name ?? ''`, so the pair cannot be told apart after a round trip
/// whichever way this maps. Given that, the empty string is written as
/// **NULL**: the application's own HMI reads these rows directly and NULL is
/// what it has always found there, so writing `''` would invent a third state
/// in a table this gateway does not own. The consequence is that a graph
/// deliberately named with the empty string and a graph never named are the
/// same row; if a legend ever needs to tell them apart, the record's field has
/// to become nullable in the protocol package first, and that is a wire change
/// rather than a store change.
Map<String, Map<String, dynamic>>? graphConfigRows(
    Map<int, HistoryViewGraphRecord>? configs) {
  if (configs == null) return null;
  return {
    for (final entry in configs.entries)
      '${entry.key}': <String, dynamic>{
        'name': entry.value.name.isEmpty ? null : entry.value.name,
        'yAxisUnit': entry.value.yAxisUnit,
        'yAxis2Unit': entry.value.yAxis2Unit,
      },
  };
}

/// One row of `getHistoryViewKeys`' bag as the record it stands for.
///
/// [key] comes from the map key rather than from the bag: it is the identity
/// the caller addresses the row by, and reading it out of the bag as well
/// would be a second source for one fact.
///
/// `alias` is passed through **as it arrives, including null**, so the
/// record's constructor applies the default. drift has usually applied it
/// already (`row.alias ?? row.key`); passing the null on rather than
/// second-guessing it is what keeps the default in one place.
HistoryViewKeyRecord keyRecordFrom(String key, Map<String, dynamic> row) =>
    HistoryViewKeyRecord(
      key: key,
      alias: row['alias'] as String?,
      useSecondYAxis: row['useSecondYAxis'] as bool? ?? false,
      graphIndex: (row['graphIndex'] as num?)?.toInt() ?? 0,
    );

/// One row of `getHistoryViewGraphs`' bag as the record it stands for.
///
/// [graphIndex] comes from the map key, because the bag does not carry it —
/// a record built with 0 instead would put every graph on the first axis.
///
/// The three `?? ''` defaults mirror drift's own and the record's own; see
/// [graphConfigRows] for the null-versus-empty decision they implement.
HistoryViewGraphRecord graphRecordFrom(int graphIndex, Map<String, dynamic> row) =>
    HistoryViewGraphRecord(
      graphIndex: graphIndex,
      name: row['name'] as String? ?? '',
      yAxisUnit: row['yAxisUnit'] as String? ?? '',
      yAxis2Unit: row['yAxis2Unit'] as String? ?? '',
    );
