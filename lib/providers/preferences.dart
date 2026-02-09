import 'package:shared_preferences/shared_preferences.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/preferences.dart';
import 'database.dart';

part 'preferences.g.dart';

@Riverpod(keepAlive: true)
Future<Preferences> preferences(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  final localCache = SharedPreferencesWrapper(SharedPreferencesAsync());

  return await Preferences.create(db: db, localCache: localCache);
}
