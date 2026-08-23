import 'package:drift/native.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// An [AppDatabase] whose write path can be taken down, brought back up, and
/// made to fail with a specific SQLSTATE.
///
/// The outage handling in [Database] — the retry queue, its overflow trimming,
/// and the rows it discards — had no tests at all before this, because reaching
/// it needs a backend that fails on demand and then recovers. An in-memory
/// sqlite [AppDatabase] cannot do either: [tableExists] queries
/// `information_schema`, which sqlite does not have, so it is permanently
/// "down" and can never come back. Hence [AppDatabase.forTest], and hence this.
class FakeWriteBackend extends AppDatabase {
  FakeWriteBackend()
      : super.forTest(
            DatabaseConfig(), NativeDatabase.memory(logStatements: false));

  /// While true, every call fails the way an unreachable server does.
  bool down = false;

  /// If set, [tableInsertBatch] throws this instead of storing (used to stand
  /// in for a server that rejects the batch's *contents*).
  Object? rejectWith;

  /// Every row the backend was ever asked to store, in arrival order.
  final List<Map<String, dynamic>> stored = [];

  /// How many times [tableInsertBatch] has been called, successful or not.
  int insertAttempts = 0;

  @override
  Future<bool> tableExists(String tableName) async {
    if (down) throw Exception('SocketException: Connection refused');
    return true;
  }

  @override
  Future<int> tableInsertBatch(
      String tableName, List<Map<String, dynamic>> rows) async {
    insertAttempts++;
    if (down) throw Exception('SocketException: Connection refused');
    final reject = rejectWith;
    if (reject != null) throw reject;
    stored.addAll(rows);
    return rows.length;
  }

  /// The `value` column of every stored row, as numbers.
  List<num> get storedValues =>
      stored.map((r) => r['value'] as num).toList(growable: false);
}
