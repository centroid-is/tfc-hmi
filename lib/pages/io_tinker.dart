import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../widgets/beckhoff.dart';
import '../providers/state_man.dart';
import '../widgets/base_scaffold.dart';
import 'loading.dart';

class IoTinkerPage extends ConsumerStatefulWidget {
  final logger = Logger();

  IoTinkerPage({super.key});

  @override
  ConsumerState<IoTinkerPage> createState() => _IoTinkerPageState();
}

class _IoTinkerPageState extends ConsumerState<IoTinkerPage> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ref.watch(stateManProvider.future).then(
            (stateMan) => stateMan
                .readMany(stateMan.keyMappings.nodes.entries
                    .where((entry) => entry.value.io == true)
                    .map((entry) => entry.key)
                    .toList())
                .onError((error, stackTrace) {
              widget.logger.e('IoTinker Error: $error');
              return {};
            }),
          ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          widget.logger.e('IoTinker Error: ${snapshot.error}');
          return LoadingPage(title: 'IoTinker Error: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const LoadingPage(title: 'IoTinker');
        }
        final map = snapshot.data!;

        print(map);
        List<bool> ledStates = [];
        print(map.values.first['raw_state']);
        for (int i = 0; i < 8; i++) {
          ledStates.add((map.values.first['raw_state'].asInt & (1 << i)) != 0);
        }

        return BaseScaffold(
          title: 'IoTinker',
          body: ModuleWidget(ledStates: ledStates),
        );
      },
    );
  }

  Widget _buildUnit(NodeId nodeId, DynamicValue value) {
    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
          (stateMan) => stateMan
              .subscribe(NodeId.fromString(
                      nodeId.namespace, "${nodeId.string}.raw_state")
                  .toString())
              .asStream()
              .switchMap((s) => s)),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return ModuleWidget(ledStates: List.filled(8, false));
        }
        final data = snapshot.data!;
        List<bool> ledStates =
            List.generate(8, (i) => (data.asInt & (1 << i)) != 0);
        return ModuleWidget(ledStates: ledStates);
      },
    );
  }
}
