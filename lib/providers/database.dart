import 'dart:io' as io;
import 'dart:async';
import 'package:postgres/postgres.dart' as pg;
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

part 'database.g.dart';

@Riverpod(keepAlive: true)
Future<Database?> database(Ref ref) async {
  final config = await DatabaseConfig.fromPrefs();
  if (config.postgres == null) {
    return null;
  }
  AppDatabase? appDb;
  try {
    appDb = await AppDatabase.spawn(config);
    final db = Database(appDb);
    await db.db.open();

    // Clean up when the provider is invalidated or disposed
    ref.onDispose(() async {
      _retryTimer?.cancel();
      await db.dispose();
      await db.db.close();
    });

    return db;
  } catch (e) {
    // close() now properly kills the DriftIsolate via shutdownAll()
    await appDb?.close();
    io.stderr.writeln('Error opening database: $e');
    _scheduleRetry(ref, config);
    ref.onDispose(() {
      _retryTimer?.cancel();
    });
  }
  return null;
}

Timer? _retryTimer;

void _scheduleRetry(Ref ref, DatabaseConfig config) {
  _retryTimer?.cancel();
  _retryTimer = Timer(const Duration(seconds: 2), () async {
    try {
      // Lightweight probe: open a single pg connection to check reachability.
      // Does NOT spawn a DriftIsolate or pool — avoids leaked isolates.
      final conn = await pg.Connection.open(
        config.postgres!,
        settings: pg.ConnectionSettings(
          sslMode: config.sslMode ?? pg.SslMode.disable,
        ),
      ).timeout(const Duration(seconds: 5));
      await conn.close();
    } catch (e) {
      // Still failing, schedule another attempt
      _scheduleRetry(ref, config);
      return;
    }
    // DB is reachable - invalidate the provider to recreate everything cleanly
    ref.invalidateSelf();
  });
}
