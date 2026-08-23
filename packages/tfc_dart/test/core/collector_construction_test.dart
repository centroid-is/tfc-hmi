import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/state_man.dart';

void main() {
  test('a collected key that cannot be subscribed must not throw out of the '
      'Collector constructor', () async {
    // One collected key on an OPC UA server that is not configured at all —
    // the shape of a stale key mapping after a server rename.
    final mappings = KeyMappings(nodes: {
      'ghost.key': KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'i=1'),
        collect: CollectEntry(
            key: 'ghost.key',
            sampleInterval: const Duration(milliseconds: 100)),
      ),
    });
    final stateMan = await StateMan.create(
        config: StateManConfig(opcua: []), keyMappings: mappings);
    final database = Database(AppDatabase.inMemoryForTest());

    final errors = <Object>[];
    runZonedGuarded(() {
      Collector(
        config: CollectorConfig(collect: true),
        stateMan: stateMan,
        database: database,
      );
    }, (e, s) => errors.add(e));

    await Future<void>.delayed(const Duration(milliseconds: 600));
    // ignore: avoid_print
    print('ERRORS: ${errors.length} $errors');
    expect(errors, isEmpty,
        reason: 'The constructor fires collectEntry() and drops the future. '
            'Anything it throws becomes an uncaught isolate error, and the '
            'data-acquisition isolate is spawned with errorsAreFatal.');
  });
}
