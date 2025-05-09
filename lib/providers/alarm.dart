import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/alarm.dart';
import 'preferences.dart';

part 'alarm.g.dart';

@Riverpod(keepAlive: true)
Future<AlarmMan> alarmMan(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);
  return await AlarmMan.create(prefs);
}
