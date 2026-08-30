/// The routes raised above `operate`, declared once.
///
/// Every other route in the app declares nothing and therefore answers
/// [AccessGroup.operate] — what an anonymous session already holds — so this
/// map is the entire blast radius of route gating. Seven entries are raised
/// because they configure the station rather than run the line; nothing on
/// the floor changes — with one exception, Knowledge Base, which is spelled
/// out below because it does take something away from an operator.
///
/// **The seven, and why each one.**
///
/// * Page Editor, Alarm Editor and Key Repository need `configure`: they
///   author what the station shows and how it alarms, and the key repository
///   surfaces stored secrets (`centroid-hmi/lib/navigation.dart:48-50` says
///   so in as many words).
/// * Knowledge Base needs `configure` too, for the reason below — it is not
///   the read surface its menu label suggests.
/// * Server Config, IP Settings and Preferences need `administer`: they point
///   the station at a database, a PLC and a network.
///
/// **`/advanced/preferences` is a deliberate amendment to the spec's five**,
/// decided by the user on 2026-08-29 after plan review;
/// `docs/access-control-spec.md` §9 still says five and is out of date on
/// this point. `lib/pages/preferences.dart` renders `DatabaseConfigWidget` —
/// the same database configuration Server Config edits, whose Save calls
/// `ref.invalidate(databaseProvider)` — and `PreferencesKeysWidget`, a raw
/// list/edit/delete editor over every preference key (`page.*`, `alarm.*`,
/// `keymap.*`, server/db/network), which is the data behind all three
/// `configure` routes. Gating only the spec's five would leave a one-tap
/// bypass: refused at Server Config, open Preferences one menu entry down and
/// edit the identical data. It takes `administer` because that is what the
/// data it reaches is worth, not because of where it sits in the menu.
///
/// **Knowledge Base is raised because it is not the read surface it looks
/// like.** `docs/access-control-write-path-sweep.md` §3.1 found three raw-Drift
/// index classes reachable from it — twenty-six Drift statements — and one of
/// its callers rewrites `page_editor_data`, which is the key the
/// `configure`-gated page editor saves. A page that can rewrite the page
/// layout is a `configure` surface whatever its menu label says. Plan 03-13
/// guards the controls behind it; this gates the route. Both are needed: the
/// route gate alone would leave those controls unaudited for anyone who does
/// hold `configure`, and the control guards alone would leave a page reaching
/// three write surfaces open to a session holding nothing.
///
/// **The cost, accepted deliberately.** An anonymous operator can no longer
/// read technical documents or browse PLC code at the panel. On a plant floor
/// that is a real loss: somebody wanting a manual at the machine now has to
/// find a person with a `configure` account, or walk. It was chosen over
/// leaving a write path around the page-editor gate, and it is the one place
/// in this milestone where gating a route takes something away from an
/// operator rather than only from a configurer. `docs/access-control-spec.md`
/// §11 defers read permissions on trends and history; this is not that, and
/// the difference is that this page writes.
///
/// **What is not lost.** The drawings overlay on ordinary pages
/// (`centroid-hmi/lib/main.dart:763-781`) is a different surface: not this
/// route, read-only, and plan 03-13's decorators pass reads straight through.
/// A drawing is still available on the page an operator is standing at.
///
/// **The `kKnowledgeEnabled` interaction.** `lib/core/feature_flags.dart:32`
/// defaults the flag to true, so the test suite and every development build
/// have this route. A `--dart-define=TFC_KNOWLEDGE=false` build has neither
/// the route (`centroid-hmi/lib/main.dart`'s statement-level `if`) nor the
/// menu entry (`centroid-hmi/lib/navigation.dart:68`), and
/// [installRaisedRoutes] then declares a group nothing resolves — inert
/// rather than wrong. The map is deliberately **not** made conditional on the
/// flag. It could be: the map is `const` and the flag is a compile-time
/// constant. It would mean a flag-off build with a different [kRaisedRoutes],
/// a different length assertion and a different menu, for no gain. An inert
/// declaration is cheaper than a conditional invariant.
///
/// **[kServerConfigRoute] is the only route exempt while the access
/// repository is unavailable**, and it is exempt in *both* causes of that: a
/// station never configured, and a configured station whose Postgres will not
/// answer. `lib/providers/database.dart:33-42` cannot tell those apart — a
/// failed connection is caught, retried in 2s and returned as `null`, a
/// resolved `AsyncData(null)` indistinguishable from "no Postgres
/// configured". The argument is exactly "you must be able to reach the page
/// that configures the database", and the unreachable case is where it bites
/// hardest: someone mistypes the Postgres IP, saves, and without the
/// exemption the station is recoverable only on site. It extends to nothing
/// else — not to Preferences, which reaches the same widget but also
/// everything else, and not to the editors, which store secrets. The accepted
/// cost is stated rather than hidden: an unreachable database leaves Server
/// Config reachable by anyone at the panel, who could repoint the station at a
/// Postgres they control. That needs physical access plus a prepared server,
/// and physical access already defeats this milestone by design
/// (spec §8) — while bricking a plant's station over a typo is both likelier
/// and worse.
///
/// **IP Settings is on this list at the route level only.** The D-Bus call
/// underneath it is deliberately untouched (spec §6 bypass 3), and
/// `lib/pages/dbus_login.dart` is out of scope for the whole milestone. The
/// D-Bus credential authenticates the *station* to the system bus;
/// `administer` is the human gate above it.
///
/// **`AccessGroup.users` is not used here.** Nothing in this phase manages
/// roles or users; those routes arrive with the audit trail and the admin
/// screens.
///
/// **What stays open, on purpose.** About Linux, Alarm View and History View
/// read rather than configure. The first-account route stays open because
/// gating it is the deadlock the whole design exists to avoid.
///
/// Knowledge Base used to be on that list and is not any more; so was
/// History View, whose destructive Drift deletes plan 03-10 closes at the
/// controls. Both were listed as read surfaces for the same reason — the
/// menu label was read instead of the call sites — and both were wrong. A
/// page named for what an operator does on it is not evidence about what it
/// writes.
///
/// **The `addRoute` edge.** `centroid-hmi/lib/main.dart:588-604` runs after
/// the literal route map and assigns `routes[menuItem.path!]`, so it
/// overwrites by path: a page-manager page slugged to `/advanced/server-config`
/// would replace the gated route with an ungated `AssetView`. No privilege is
/// gained — what you reach is your own asset page, not `ServerConfigPage` —
/// but the menu badge would show a lock on a page that has none. Worth
/// knowing rather than rediscovering.
///
/// **Why the strings are duplicated.** They are copied from
/// `centroid-hmi/lib/main.dart` rather than imported from it, because `lib/`
/// cannot depend on the app package. Tests in
/// `centroid-hmi/test/navigation_test.dart` are what keep the two spellings
/// honest, by building each route and asserting the group it resolved.
library;

import 'package:tfc_access/tfc_access.dart';

import 'route_registry.dart';

/// The Server Config route — the one exemption while the access repository is
/// unavailable. See [routeAllowedWhenRepositoryUnavailable].
const String kServerConfigRoute = '/advanced/server-config';

/// The seven routes raised above `operate`, and the group each one needs.
///
/// One const map so that the route table and the navigation menu can never
/// disagree about which entries are locked. Paths are spelled exactly as in
/// `createLocationBuilder`'s `routes` map in `centroid-hmi/lib/main.dart`; a
/// typo here is a route that silently stays open.
const Map<String, AccessGroup> kRaisedRoutes = {
  '/advanced/page-editor': AccessGroup.configure,
  '/advanced/alarm-editor': AccessGroup.configure,
  '/advanced/key-repository': AccessGroup.configure,
  '/advanced/knowledge-base': AccessGroup.configure,
  kServerConfigRoute: AccessGroup.administer,
  '/advanced/ip-settings': AccessGroup.administer,
  '/advanced/preferences': AccessGroup.administer,
};

/// Whether [path] stays reachable while the access repository is unavailable.
///
/// True for [kServerConfigRoute] and nothing else — not for the other raised
/// routes, not for an unraised path, and not for null. Both the route gate
/// and the menu badge call this rather than each keeping a copy of "except
/// Server Config"; two copies is a lock on a page that opens, or an open page
/// wearing a lock, the first time one of them is edited.
///
/// The name states the condition it actually enforces. It was
/// `routeAllowedWhenUnconfigured` for one revision, back when the exemption
/// was narrower than the outage it now covers; a name that claims a narrower
/// condition than the code enforces is its own defect.
bool routeAllowedWhenRepositoryUnavailable(String? path) {
  return path == kServerConfigRoute;
}

/// Declares [kRaisedRoutes] into [registry], defaulting to the singleton the
/// navigation menu reads. Idempotent — declaring a path replaces its group.
void installRaisedRoutes([RouteRegistry? registry]) {
  final target = registry ?? RouteRegistry();
  kRaisedRoutes.forEach(target.declareRouteGroup);
}

/// The group [path] needs, read from the registry.
///
/// Callers ask here rather than reaching into [RouteRegistry] themselves, so
/// that a route declared by something other than [installRaisedRoutes] is
/// still answered correctly. Answers [AccessGroup.operate] for anything
/// undeclared, including null.
AccessGroup accessGroupForRoute(String? path) {
  return RouteRegistry().groupForRoute(path);
}
