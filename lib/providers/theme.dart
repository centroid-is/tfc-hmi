import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';

part 'theme.g.dart';

@Riverpod(keepAlive: true)
Future<ThemeNotifier> themeState(Ref ref) async {
  return ThemeNotifier.create();
}
