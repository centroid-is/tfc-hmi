import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tfc_dart/core/config_source.dart';

import '../core/config_loader.dart';

part 'static_config.g.dart';

@Riverpod(keepAlive: true)
Future<StaticConfig?> staticConfig(Ref ref) async {
  return loadStaticConfig();
}
