import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../page_creator/page.dart';
import 'preferences.dart';

part 'page_manager.g.dart';

/// The page layout as it was the last time this station spoke to the database,
/// loaded from local SharedPreferences before `runApp`.
///
/// [pageManagerProvider] is the authority and this is never consulted once it
/// has answered. It exists only to fill the wait: that provider hangs off
/// `preferencesProvider` → `databaseProvider`, and measured against the real
/// plant config the plant page appeared in 75 ms when Postgres was reachable,
/// 5 ms when the port refused — and **10 012 ms** when the host was routable
/// but never answered, which is what a powered-off server or a cut link looks
/// like on a plant network. For those ten seconds the operator got a blank
/// page. Loading this copy costs 2.3 ms and the app already did it, then threw
/// the result away.
///
/// Null when nothing has been cached yet (a first run, or a station whose
/// local store was wiped) — the app then behaves exactly as it did before.
/// `main()` overrides it; the default keeps every other entry point and every
/// test working without one.
final bootstrapPageManagerProvider = Provider<PageManager?>((ref) => null);

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
