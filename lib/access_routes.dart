/// The routes raised above `operate`, declared once.
///
/// Every other route in the app declares nothing and therefore answers
/// [AccessGroup.operate] — what an anonymous session already holds — so this
/// map is the entire blast radius of route gating. Six entries are raised
/// because they configure the station rather than run the line; nothing on
/// the floor changes.
///
/// **The six, and why each one.**
///
/// * Page Editor, Alarm Editor and Key Repository need `configure`: they
///   author what the station shows and how it alarms, and the key repository
///   surfaces stored secrets (`centroid-hmi/lib/navigation.dart:48-50` says
///   so in as many words).
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
/// **What stays open, on purpose.** Knowledge Base, About Linux, Alarm View
/// and History View read rather than configure. The first-account route stays
/// open because gating it is the deadlock the whole design exists to avoid.
///
/// **The `addRoute` edge.** `centroid-hmi/lib/main.dart:527-545` runs after
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

/// The six routes raised above `operate`, and the group each one needs.
///
/// One const map so that the route table and the navigation menu can never
/// disagree about which entries are locked. Paths are spelled exactly as in
/// `createLocationBuilder`'s `routes` map in `centroid-hmi/lib/main.dart`; a
/// typo here is a route that silently stays open.
const Map<String, AccessGroup> kRaisedRoutes = {
  '/advanced/page-editor': AccessGroup.configure,
  '/advanced/alarm-editor': AccessGroup.configure,
  '/advanced/key-repository': AccessGroup.configure,
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
