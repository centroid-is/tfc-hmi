import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:tfc_core/core/alarm.dart';
import 'preferences.dart';
import 'state_man.dart';
part 'alarm.g.dart';

@Riverpod(keepAlive: true)
Future<AlarmMan> alarmMan(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);
  final stateMan = await ref.watch(stateManProvider.future);
  return await AlarmMan.create(prefs, stateMan);
}
