import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../page_creator/page.dart';
import 'preferences.dart';

part 'page_manager.g.dart';

@Riverpod(keepAlive: true)
Future<PageManager> pageManager(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);

  final pageManager = PageManager(
    pages: {},
    prefs: prefs,
  );

  await pageManager.load();
  return pageManager;
}
