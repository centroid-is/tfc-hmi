import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:tfc_dart/core/aggregator_server.dart' show AggregatorNodeId;
import 'package:tfc_dart/core/state_man.dart' show StateMan;
import 'preferences.dart';
import 'state_man.dart';
part 'alarm.g.dart';

@Riverpod(keepAlive: true)
Future<AlarmMan> alarmMan(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);
  final stateMan = await ref.watch(stateManProvider.future);
  final alarmMan = await AlarmMan.create(prefs, stateMan);

  // In aggregation mode, register expression-based connection alarms
  // that subscribe to the __agg_<alias>_connected keymapped nodes.
  if (stateMan.aggregationMode) {
    _ensureConnectionAlarms(stateMan, alarmMan);
  }

  return alarmMan;
}

/// Register connection alarms for each upstream server alias.
/// Uses `__agg_<alias>_connected == false` expressions evaluated by the
/// standard alarm subscription pipeline (no polling needed).
///
/// These alarms are ephemeral (not persisted) — they're regenerated from the
/// current config on each startup. Any stale connection alarms left in prefs
/// by older code are cleaned up here.
void _ensureConnectionAlarms(StateMan stateMan, AlarmMan alarmMan) {
  // Remove any stale persisted connection alarms from previous runs
  alarmMan.removeAlarmsWhere((a) => a.uid.startsWith('connection-'));

  for (final opcConfig in stateMan.config.opcua) {
    final alias = opcConfig.serverAlias ?? AggregatorNodeId.defaultAlias;
    final uid = 'connection-$alias';
    final key = '__agg_${alias}_connected';

    alarmMan.addEphemeralAlarm(AlarmConfig(
      uid: uid,
      title: '$alias disconnected',
      description: 'OPC UA Server: "$alias" is disconnected',
      rules: [
        AlarmRule(
          level: AlarmLevel.error,
          expression: ExpressionConfig(
            value: Expression(formula: '$key == false'),
          ),
          acknowledgeRequired: false,
        ),
      ],
    ));
  }
}
