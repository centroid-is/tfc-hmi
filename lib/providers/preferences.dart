import '../core/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod/riverpod.dart';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';

part 'preferences.g.dart';

@Riverpod(keepAlive: true)
Future<Preferences> preferences(Ref ref) async {
  final prefs = SharedPreferencesAsync();

  final db = await ref.watch(databaseProvider.future);

  // Create Preferences instance
  return await Preferences.create(db: db);
}
