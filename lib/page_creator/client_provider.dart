import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'client.dart';

part 'client_provider.g.dart';

@riverpod
StateMan stateMan(Ref ref) {
  // Todo: do differently, config should be in the state man
  final client = StateMan('opc.tcp://localhost:4840');
  ref.onDispose(() {
    client.close();
  });
  return client;
}
