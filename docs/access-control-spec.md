# Access control — implementation spec

Companion to [access-control-research.md](access-control-research.md). That
note surveys the field; this one is the buildable version. Written 2026-08-26
to be executed by an implementation agent without re-deriving the discussion.

## Decisions locked

| Question | Answer |
|---|---|
| Does an operator log in? | **No.** Unauthenticated *is* the operator level. Login only to elevate. |
| Definition of done | **Demoable end to end on macOS.** Not deployed to an SVN station. |
| Who configures roles | **Engineering (us), at commissioning.** Plant self-serve is a later follow-up. |
| Identity | **Local username + password now.** OIDC (Microsoft/Google) later, without a migration. |
| Permission model | **Fixed groups in code; roles created by the customer and mapped onto groups.** |
| Audit | **Retained.** Append-only, never pruned. |

## Scope

**In:** users, roles, role→group mapping, login/logout, session with inactivity
timeout, an `AccessPolicy`, guards on both write interfaces, rerouting the three
bypass paths, per-asset and per-route level declaration, the audit table, and a
minimal roles/users screen.

**Explicitly out — do not build these:**

- Badge / RFID / PIN-pad login. Anonymous-is-operator makes it unnecessary now.
- OIDC or SAML. Only the *shape* that keeps it cheap later (see §3).
- Read permissions. Assets read Postgres outside both interfaces
  (`bpm.dart:640`, `ratio_number.dart:510`, `rate_value.dart:672`); gating reads
  is a separate piece of work and is not wanted.
- Four-eyes / verified writes. The MCP proposal flow
  (`mcp_bridge_notifier.dart:104`) is where this would grow later.
- Per-user OPC UA sessions or PLC-side validation. See §8 — this spec ships a
  guardrail, not an enforcement boundary, and must say so in its own UI copy.
- Plant-facing user self-service, password reset flows, password policy.

---

## 1. The model

Three concepts. Two are fixed in code; one is customer data.

**Groups** — fixed, defined in Dart, referenced by assets and routes. Exactly
these seven. Do not add an eighth without a decision.

```dart
enum AccessGroup {
  operate,     // start/stop/jog, gates, alarm acknowledge
  setpoints,   // targets, limits, recipes
  device,      // drive parameters, calibration, scaling
  force,       // forced I/O and overrides
  configure,   // page editor, alarm rules, key mappings
  administer,  // server config, database, network, updates
  users,       // managing roles and users
}
```

`users` is deliberately separate from `configure`: otherwise anyone who can edit
a page can grant themselves everything.

**Roles** — customer data. A name plus a set of groups. Seeded with four, which
are ordinary rows and may be edited or deleted:

| Role | Groups |
|---|---|
| Operator | `operate` |
| Shift Leader | `operate`, `setpoints` |
| Maintenance | `operate`, `device`, `force` |
| Engineering | all seven |

Whether Maintenance also gets `setpoints` is a checkbox, not a code change.
This is the point of the group model — there is no ladder to decide on.

**Users** — a name, a password hash, and exactly one role. One role per user,
not many; multi-role adds union semantics and an "effective permissions"
inspector, and is not worth it at this size.

**The anonymous role.** A single preference names which role applies with no
session. Seeded to Operator. This is how "anonymous is operator" is expressed
without special-casing it through the codebase.

---

## 2. Schema

Drift, in `packages/tfc_dart/lib/core/database_drift.dart`. Follow the existing
table style exactly. Bump `schemaVersion` from **5 to 6** and add an
`if (from < 6)` branch to the existing `onUpgrade`.

```dart
class AppRole extends Table {
  TextColumn get name => text()();                    // primary key, matched
  TextColumn get groups => text()();                  // JSON array of enum names
  BoolColumn get seeded => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {name};
}

class AppUser extends Table {
  TextColumn get username => text()();
  TextColumn get roleName => text().references(AppRole, #name)();
  TextColumn get passwordHash => text()();            // PBKDF2, see §4
  TextColumn get salt => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {username};
}

class AuditEntry extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get at => dateTime()();
  TextColumn get who => text()();                     // username, or 'anonymous'
  TextColumn get station => text()();                 // hostname
  TextColumn get roleName => text()();
  TextColumn get surface => text()();                 // 'tag' | 'pref' | 'route'
  TextColumn get itemKey => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get groupRequired => text()();
  BoolColumn get allowed => boolean()();              // record denials too
  TextColumn get reason => text().nullable()();
}
```

`role.name` is the primary key rather than a surrogate id **on purpose**: when
OIDC lands, an incoming group claim of `"Shift Leader"` matches the role by name
with no mapping table, exactly as Ignition and SIMATIC Logon do it. Do not
replace it with an integer id.

Record denials as well as successes. A denied write is the more interesting
audit line, and it is how you find a role that is configured too tightly.

**Both backends must work.** `AppDatabase` runs on SQLite (`native == true`) and
Postgres. The migration already branches on `native`; follow that. Drift's
`m.createTable()` covers both — no raw DDL needed for new tables.

---

## 3. Keeping OIDC cheap later

Do these three things now; do not build anything else for SSO.

1. Role assignment resolves **by role name**, never by id.
2. Put authentication behind one interface so a second implementation can be
   added without touching callers:

   ```dart
   abstract class AuthProvider {
     Future<AuthenticatedUser?> authenticate(String username, String password);
   }
   ```

   Ship `LocalAuthProvider` only.
3. `AuthenticatedUser` carries `{username, roleName, displayName}` — no
   password-specific fields — so an OIDC implementation can populate it from
   claims.

---

## 4. Passwords

PBKDF2 via `package:cryptography`, per-user random salt, stored base64.

The repo already has this pattern: `lib/pages/server_config.dart:50` has
`kdfIterationsForTest` overriding `_kdfIterations`. **Reuse that hook** — tests
that run a real KDF at production iteration counts are unusably slow.

That crypto currently lives in a *page* file. Extract the reusable part to
`lib/core/` as part of this work rather than importing a page from a provider.

Password hashes must never travel through `Preferences` / the
`flutter_preferences` table. They live in `AppUser` and nowhere else.

---

## 5. Session

Station-local, never synced. Sessions belong in Riverpod state plus
`localPreferencesProvider`, not the shared database — a session is a property of
the person standing at *this* panel.

```dart
class AccessSession {
  final AuthenticatedUser? user;   // null == anonymous
  final Set<AccessGroup> groups;   // resolved from the role, anonymous role if null
  bool can(AccessGroup g) => groups.contains(g);
}
```

- Inactivity timeout drops back to anonymous. Default 15 minutes, stored in
  device-local preferences.
- **The inactivity timer must be listener-gated** — started in `onListen`,
  stopped in `onCancel`. An always-on `Timer.periodic` in shared plumbing breaks
  unrelated widget tests; this has happened in this repo before.
- Logging out is explicit and always available in the app bar when elevated.
- Show *who* is logged in, always, when elevated. An operator must be able to
  see at a glance that the panel is still in a raised state.

---

## 6. The guards

Two decorators, each implementing the interface it wraps. Callers change
nothing. This is the same idiom the repo already uses
(`SharedPreferencesWrapper implements PreferencesApi`, `_FakeStateMan implements
StateMan` in tests).

```dart
class GuardedStateMan implements StateMan {
  @override
  Future<void> write(String key, DynamicValue value) async {
    final need = policy.groupForKey(key);
    if (!session.can(need)) {
      await audit.denied(key: key, group: need, surface: 'tag');
      throw AccessDenied(key, need);
    }
    await audit.allowed(key: key, group: need, surface: 'tag',
                        oldValue: ..., newValue: value);
    return inner.write(key, value);
  }
}
```

`GuardedPreferences` wraps `setBool` / `setInt` / `setDouble` / `setString` /
`setStringList` / `remove` / `clear` the same way. Reads pass straight through.

### The three bypasses must be rerouted

These reach their store without passing either interface. A guard that does not
cover them is decorative:

1. `ServerConfigDb.publish()` / `.remove()` — writes `flutter_preferences`
   through Drift directly. Route through the injected `PreferencesApi`.
2. `lib/providers/collector.dart:21` — constructs its own
   `SharedPreferencesAsync()` and writes config at line 27. Take the injected
   `PreferencesApi` instead.
3. IP settings / D-Bus network and hostname calls — gate at the route level
   (§7); the D-Bus call itself stays as is.

**Add a CI check** asserting that nothing outside `lib/providers/` constructs
`SharedPreferencesAsync()`. This is the invariant that will rot silently — every
future feature that news up its own preferences reopens the hole and the type
system will not object. A grep in the existing workflow is enough.

---

## 7. Where the requirement is declared

| Surface | Declared | Default |
|---|---|---|
| Process tags | Nullable `requiredGroup` on the asset `*Config`, one dropdown in `configure()`, serialised into the page JSON | `operate` |
| Config keys | Pattern match on the preference key in `AccessPolicy` — `page.*`, `alarm.*`, `keymap.*` → `configure`; server/db/network → `administer` | `administer` |
| Routes | Optional `AccessGroup` on `RouteRegistry.registerRoute()` | `operate` |

Tags fail **open** (default `operate`, so nothing existing breaks); config keys
fail **closed** (anything unrecognised needs `administer`). That asymmetry is
intentional: a wrongly-open setpoint is a nuisance, a wrongly-open config write
is a broken plant.

Raised routes stay **visible but locked** in the menu, not hidden. A locked
entry tells a technician the page exists and to find someone; a hidden one looks
like a bug.

---

## 8. Audit

Append-only. Never pruned.

- **Exempt it from the collector's retention policies.** `registerRetentionPolicy`
  exists for time-series; if the audit table is ever swept by it the trail is
  worthless. Assert this in a test.
- On Postgres, add a second role with `INSERT`-only grant on the audit table,
  and ensure the station's main credential has *no* privileges there. The
  station can then forge an entry but cannot erase one. Document the SQL in
  `docs/`; it is a deployment step, not app code.
- On SQLite (dev/demo) that separation does not exist. Say so in the doc rather
  than implying the guarantee holds everywhere.
- Capture a `reason` for `configure` and `administer` writes — a free-text
  prompt on the elevated confirm. Reason is what turns a log into an audit
  trail.

### Honesty requirement

Both connections authenticate the *station*, not a person: one `OpcUAConfig`
username/cert (`state_man.dart:133`), one Postgres credential
(`database.dart:148`). Everything in this spec lives inside the Dart process and
is bypassed by anyone with UaExpert or `psql`.

This is an operational guardrail against accident, **not** an access control.
Say that in the PR description and in the admin screen's own help text. The
failure mode is not the guardrail — it is someone concluding "the HMI has
logins" and deprioritising network segmentation.

---

## 9. Phases

Each phase is a PR. Review between phases.

### Phase 1 — identity and audit
Schema + migration to v6, `AuthProvider` / `LocalAuthProvider`, PBKDF2 helper
extracted to `lib/core/`, `AccessSession`, login and logout UI, inactivity
timeout, audit table and sink, seed migration for the four roles and the
anonymous-role preference.

*Done when:* a user can log in and out, the session times out, and every login,
logout and failed attempt lands in the audit table. Nothing is gated yet.

### Phase 2 — the guards
`AccessPolicy`, `GuardedStateMan`, `GuardedPreferences`, `requiredGroup` on the
asset common config (+ `build_runner`), route-level group on `RouteRegistry`,
reroute the three bypasses, CI grep.

*Done when:* an anonymous session cannot open the page editor or write a raised
tag; an Engineering session can; both outcomes appear in the audit table; the
three bypasses go through `PreferencesApi`.

### Phase 3 — administration and polish
Roles screen (name + seven checkboxes), users screen (add/remove, set role,
change password), goldens for the locked and elevated states, and the deployment
doc for the INSERT-only Postgres role.

*Done when:* roles and users are manageable from the UI and the goldens have
been looked at.

**If the schedule slips, Phase 3 is what goes.** Roles seeded by migration and
edited through the existing config page is complete, just unpleasant. Losing
Phase 2 instead would leave login that gates nothing.

---

## 10. Repo traps

Things that will cost days if rediscovered:

- **Never run `dart format` on existing files.** The repo predates Dart 3.11's
  formatter and CI does not enforce it. Format only the lines you add.
- **Codegen order**: after any `@JsonSerializable` change run
  `dart run build_runner build --delete-conflicting-outputs` in
  `packages/tfc_dart` *first*, then at the root.
- **Widget tests** mock OPC UA with a local `_FakeStateMan implements StateMan`
  and override `stateManProvider` — see
  `test/page_creator/assets/start_stop_button_widget_test.dart`.
- **Goldens**: macOS only, generated with
  `flutter test --update-goldens --run-skipped <file>`, and the pinned SDK must
  pass `./scripts/check-flutter-version.sh` first. Look at the PNGs.
- **Colours** come from `HmiStateColors` / `PaneStatus`, never raw `Colors.*`.
  Forced/override is orange by repo convention — reuse it for the elevated
  state, it is the same idea.
- **Device-local vs shared**: sessions and the inactivity timeout are
  device-local (`localPreferencesProvider`); users, roles and audit are shared.
  Never sync a session.
- **`pg_notify` has an 8000-byte cap** and the backend config watcher fires on
  preference writes — keep role config small and do not stuff audit data through
  it.
- **Timers must be listener-gated** (§5).
- A `Database` wrapper in widget tests needs an end-of-body dispose.

---

## 11. Deferred, deliberately

Recorded so they are not silently forgotten:

- OIDC / SAML sign-in (the shape is ready; the implementation is not).
- Badge or PIN login, and with it, attributing *operator* actions to a person.
- Read permissions on trends and history.
- Four-eyes approval, building on the MCP proposal flow.
- Real enforcement: per-user OPC UA sessions, or PLC-side validation in
  `~/Projects/sildarvinnsla`.
- Plant-facing user self-service and password policy.
