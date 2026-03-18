import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tfc_dart/core/collector.dart';

import 'state_man.dart';
import 'database.dart';

part 'collector.g.dart';

@Riverpod(keepAlive: true)
Future<Collector?> collector(Ref ref) async {
  final stateMan = await ref.watch(stateManProvider.future);
  final database = await ref.watch(databaseProvider.future);
  if (database == null) {
    Logger().e('Cannot create collector: Database is not connected');
    return null;
  }
  final prefs = SharedPreferencesAsync();
  var configJson = await prefs.getString(Collector.configLocation);
  CollectorConfig config;
  if (configJson == null) {
    config = CollectorConfig();
    configJson = jsonEncode(config.toJson());
    await prefs.setString(Collector.configLocation, configJson);
  } else {
    config = CollectorConfig.fromJson(jsonDecode(configJson));
  }

  return Collector(
    config:
        config.copyWith(collect: false), // do not collect data in main isolate
    stateMan: stateMan,
    database: database,
  );
}
