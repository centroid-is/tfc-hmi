/// The Riverpod layer between `AuditTrailStore` and the audit trail page.
///
/// Three providers, and the whole of Phase 2's unavailable-versus-empty ruling
/// lives in the first two:
///
/// | Provider | Lifetime | Answers |
/// |---|---|---|
/// | [auditTrailStoreProvider] | `keepAlive` | a store, or **null** when this station has no database |
/// | [auditWhoOptionsProvider] | autoDispose | the `who` dropdown's options |
///
/// **Refresh is `ref.invalidate`, and this file starts no timer.** That is
/// CONTEXT's ruling and it has a reason: an always-on `Timer.periodic` in this
/// repo's plumbing has broken unrelated widget tests, and a self-scrolling
/// audit list is unreadable while you are trying to read a row. The deferred
/// list already records the live-update design that was offered and not taken
/// (a listener-gated 30s poll showing "N new entries — tap to load"); if it is
/// ever built it must be listener-gated — started in `onListen`, stopped in
/// `onCancel` — and not a bare periodic. `audit_trail_test.dart` asserts the
/// absence on the source text rather than trusting this paragraph.
library;

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/audit_trail_store.dart';
import 'database.dart';

part 'audit_trail.g.dart';

/// Reads of `audit_entry`, or null when this station has no database.
///
/// Null is a normal state, exactly as it is for `accessRepositoryProvider` and
/// for `accessTemplateStoreProvider` next door: no Postgres configured, and
/// again during the boot window before the connection opens. The two causes are
/// **indistinguishable by design** — `databaseProvider` returns null for both —
/// which is why the page's copy names no cause and says only that the trail is
/// unavailable.
///
/// `keepAlive`, unlike the query provider below: this holds the handle
/// `databaseProvider` already owns and rebuilding it on every page visit would
/// be churn for nothing. The query result is the thing worth releasing.
@Riverpod(keepAlive: true)
Future<AuditTrailStore?> auditTrailStore(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  if (db == null) return null;
  // One argument, where `accessTemplateStoreProvider` passes five. The four
  // that are missing — session, audit, station, onDenied — are missing because
  // this store cannot deny and cannot record: it has no write method to guard
  // and a guard on the read would put a row in the trail every time somebody
  // scrolled the trail. The enforcement is the route gate,
  // `kRaisedRoutes['/advanced/audit-trail']`, and `kAuditTrailGroup` is the one
  // word it is spelled from.
  return AuditTrailStore(db: db.db);
}

/// Every distinct `who` in the table, for the filter bar's dropdown.
///
/// Answers an **empty list** — not null and not an error — when the store is
/// null. A `who` dropdown with no options on an unreachable database is
/// correct; an exception here would take the whole filter bar down with it, and
/// the page already says "unavailable" once, from the query provider below.
/// Saying it twice, in two shapes, is not more honest.
@riverpod
Future<List<String>> auditWhoOptions(Ref ref) async {
  final store = await ref.watch(auditTrailStoreProvider.future);
  if (store == null) return const [];
  return store.distinctWho();
}
