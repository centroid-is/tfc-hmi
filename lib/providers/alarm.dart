import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:tfc_dart/core/alarm.dart';
import 'preferences.dart';
import 'state_man.dart';
part 'alarm.g.dart';

@Riverpod(keepAlive: true)
Future<AlarmMan> alarmMan(Ref ref) async {
  // Use ref.read to avoid cascade invalidation from DB reconnects.
  // AlarmMan reads config once at creation; it doesn't need live DB updates.
  final prefs = await ref.read(preferencesProvider.future);
  final stateMan = await ref.read(stateManProvider.future);
  return await AlarmMan.create(prefs, stateMan);
}
