import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../page_creator/page.dart';
import 'preferences.dart';
import 'static_config.dart';

part 'page_manager.g.dart';

@Riverpod(keepAlive: true)
Future<PageManager> pageManager(Ref ref) async {
  final staticCfg = await ref.watch(staticConfigProvider.future);
  final prefs = await ref.watch(preferencesProvider.future);

  if (staticCfg?.pageEditorJson != null) {
    final pageManager = PageManager(pages: {}, prefs: prefs);
    pageManager.fromJson(staticCfg!.pageEditorJson!);
    return pageManager; // Read-only — don't call save()
  }

  final pageManager = PageManager(
    pages: {},
    prefs: prefs,
  );

  await pageManager.load();
  return pageManager;
}
