import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/state_man.dart';
import '../widgets/base_scaffold.dart';
import 'loading.dart';

class IoTinkerPage extends ConsumerStatefulWidget {
  const IoTinkerPage({super.key});

  @override
  ConsumerState<IoTinkerPage> createState() => _IoTinkerPageState();
}

class _IoTinkerPageState extends ConsumerState<IoTinkerPage> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ref.read(stateManProvider.future).then(
            (stateMan) => stateMan
                .readMany(stateMan.keyMappings.keys.toList())
                .onError((error, stackTrace) {
              print('IoTinker Error: $error');
              return {};
            }),
          ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return LoadingPage(title: 'IoTinker Error: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const LoadingPage(title: 'IoTinker');
        }
        final map = snapshot.data!;
        print(map);

        return BaseScaffold(
          title: 'IoTinker',
          body: const Placeholder(),
        );
      },
    );
  }
}
