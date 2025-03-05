import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/client.dart';

part 'state_man.g.dart';

@Riverpod(keepAlive: true)
StateMan stateMan(Ref ref) {
  // Todo: do differently, config should be in the state man
  final client = StateMan('opc.tcp://localhost:4840');
  return client;
}
