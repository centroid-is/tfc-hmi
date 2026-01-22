import 'dart:io' as io;
import 'dart:async';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

part 'database.g.dart';

@Riverpod(keepAlive: true)
Future<Database?> database(Ref ref) async {
  final config = await DatabaseConfig.fromPrefs();
  final db = Database(await AppDatabase.spawn(config));
  try {
    await db.db.open();
    return db;
  } catch (e) {
    io.stderr.writeln('Error opening database: $e');
    _scheduleRetry(ref, db);
  }
  return null;
}

void _scheduleRetry(Ref ref, Database db) {
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    try {
      await db.db.open();
      timer.cancel();
      ref.invalidateSelf();
    } catch (e) {
      // io.stderr.writeln('Error opening database: $e');
    }
  });
}
