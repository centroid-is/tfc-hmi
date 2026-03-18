/// Web stub for umas_client.dart
///
/// UMAS (Schneider PLC communication via Modbus FC90) is not available on web.
/// This stub provides type definitions so that conditional imports compile.

import '../umas_types.dart';

class UmasClient {
  UmasClient({required dynamic sendFn, int? unitId}) {
    throw UnsupportedError('UmasClient not available on web');
  }

  Future<UmasInitResult> init() async =>
      throw UnsupportedError('UmasClient not available on web');

  Future<List<UmasVariableTreeNode>> browse() async =>
      throw UnsupportedError('UmasClient not available on web');
}
