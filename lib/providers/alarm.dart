import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:tfc_dart/core/state_man.dart' show StateMan, ConnectionStatus;
import 'preferences.dart';
import 'state_man.dart';
part 'alarm.g.dart';

@Riverpod(keepAlive: true)
Future<AlarmMan> alarmMan(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);
  final stateMan = await ref.watch(stateManProvider.future);
  final alarmMan = await AlarmMan.create(prefs, stateMan);

  // In aggregation mode, react to upstream connection status changes.
  if (stateMan.aggregationMode) {
    _watchUpstreamConnections(stateMan, alarmMan, ref);
  }

  return alarmMan;
}

/// Subscribe to [StateMan.upstreamConnectionStream] and inject/remove
/// disconnect alarms when upstream PLCs connect or disconnect.
void _watchUpstreamConnections(
  StateMan stateMan,
  AlarmMan alarmMan,
  Ref ref,
) {
  StreamSubscription<Map<String, (ConnectionStatus, String?)>>? sub;
  sub = stateMan.upstreamConnectionStream.listen((statusMap) {
    for (final entry in statusMap.entries) {
      final alias = entry.key;
      final (status, error) = entry.value;
      final uid = 'connection-$alias';

      if (status == ConnectionStatus.disconnected) {
        _injectDisconnectAlarm(alarmMan, alias, uid, error);
      } else {
        alarmMan.removeExternalAlarm(uid);
      }
    }
  });

  ref.onDispose(() => sub?.cancel());
}

void _injectDisconnectAlarm(AlarmMan alarmMan, String alias, String uid, String? error) {
  final rule = AlarmRule(
    level: AlarmLevel.error,
    expression: ExpressionConfig(
      value: Expression(formula: 'disconnected'),
    ),
    acknowledgeRequired: false,
  );

  final description = error != null
      ? 'OPC UA Server: "$alias" is disconnected: $error'
      : 'OPC UA Server: "$alias" is disconnected';

  final alarmConfig = AlarmConfig(
    uid: uid,
    title: '$alias disconnected',
    description: description,
    rules: [rule],
  );

  alarmMan.addExternalAlarm(AlarmActive(
    alarm: Alarm(config: alarmConfig),
    notification: AlarmNotification(
      uid: uid,
      active: true,
      expression: 'disconnected',
      rule: rule,
      timestamp: DateTime.now(),
    ),
  ));
}
