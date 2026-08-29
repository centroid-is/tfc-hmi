# Write-path sweep — every path from Dart code to a persistent store

## 1. What this is, and why it exists

`docs/access-control-spec.md` §6 lists the write paths that reach a store
without passing `StateMan.write` or `PreferencesApi.set*` — the two interfaces
the Phase 3 guards wrap. It was written as three. A fourth of exactly the same
shape, the history view's Drift deletes, had been sitting in the tree the whole
time and was found during Phase 2 only because somebody read the ungated-routes
list and checked one claim. §6 is now amended to four and says outright: assume
there is a fifth. A guard beside an unenumerated hole is the decorative outcome
§6 exists to prevent, and this phase's failure mode is the silent one — a guard
that misses a write path looks identical to one that covers it, from every
screen, forever.

This document is the enumeration, and the verdict for each site. It is
reproducible: **`bash scripts/sweep-write-paths.sh`** from the repository root
re-runs every search and prints the same list. That script is a report, not a
gate; plan 03-11 turns a subset of its section 4 into a CI check, and plan 03-12
re-runs the whole thing and asserts every hit still has a row here. Sites are
matched by **file and call**, not by line number — line numbers move on every
edit, and a check that fails on reformatting gets deleted rather than fixed.

**Sweep run: 2026-08-29**, over `lib`, `centroid-hmi/lib`, `demo` and
`packages/*/lib`, excluding `test`, `build` and `.dart_tool`. The script's own
header records its two output conventions: comment-only lines are dropped (a
comment is not a call, which is why `centroid-hmi/lib/main.dart:449` quoting
`adb.deleteHistoryView` in a note is not a site), and hits inside generated
files are collapsed to a counted line per file rather than listed. Both are
limits on the search and both are restated in §6 below.

**The answer to "is there a fifth?" is yes**, and it is in §4. The largest new
finding is a family the spec never mentions: three raw-Drift index classes in
`packages/tfc_mcp_server`, called directly from the Knowledge Base page, which
Phase 2 deliberately left ungated because it reads as a read surface.

---

## 2. The table

The verdict vocabulary is fixed at five terms. Every row carries exactly one;
no row is blank and no row says "probably".

| Verdict | Meaning |
|---|---|
| `guarded by 03-NN` | a plan in this phase routes it through a guard |
| `route-gated (Phase 2)` | reachable only from a route in `kRaisedRoutes` |
| `not widget-reachable` | provider or core machinery with no path from a widget; the row says which and why the claim holds |
| `correct as-is` | the audit sink, the guards themselves, and the stores' own declarations |
| `left open: <reason>` | found, understood, and deliberately not closed |

Where a file carries many calls of one shape, the row names the shape and lists
the lines, because that is how plan 03-12 compares — by file and call.

### 2.1 Named Drift write helpers on `AppDatabase` (script §1 — 44 hits)

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/pages/history_view.dart:1108` | `adb.deleteHistoryView(v.id)` | `history_view` + cascades | delete-view button `:722` on `/advanced/history-view` (**not** raised) | `guarded by 03-10` |
| `lib/pages/history_view.dart:1127` | `dbWrap.db.addHistoryViewPeriod(...)` | `history_view_period` | save-period control on the same page | `guarded by 03-10` |
| `lib/pages/history_view.dart:1165` | `dbWrap.db.deleteHistoryViewPeriod(p.id)` | `history_view_period` | delete-period button `:1074` | `guarded by 03-10` |
| `lib/pages/history_view.dart:1281` | `adb.createHistoryView(...)` | `history_view` | save-as control | `guarded by 03-10` |
| `lib/pages/history_view.dart:1329` | `adb.updateHistoryView(...)` | `history_view` | save control | `guarded by 03-10` |
| `packages/tfc_dart/lib/core/database_drift.dart:698, 742, 785, 845, 855, 898, 1116` | the seven method **declarations** | — | — | `correct as-is` (this is the API section 1 searches for; declaring it is not calling it) |
| `packages/tfc_dart/lib/core/database_drift.dart:424-427, 466-476, 506-508` | `m.createTable(<table>)` | schema | drift `Migrator` inside `onUpgrade`/`onCreate` | `not widget-reachable` — a different method of the same name on `Migrator`, called only by drift's migration callback at database open |
| `packages/tfc_mcp_server/lib/src/database/server_database.dart:356-397` | `m.createTable(<table>)` | schema | same, for the MCP server's own database | `not widget-reachable` — same reason |
| `packages/tfc_dart/lib/core/database.dart:930` | `db.updateRetentionPolicy(tableName, retention)` | timescale policy | `Database._applyRetentionPolicy` ← `registerRetentionPolicy` ← `Collector` (`collector.dart:216`) | `not widget-reachable` — no widget calls it; the widget-reachable input is the `collector_config` key, which `03-09` guards |
| `packages/tfc_dart/lib/core/database.dart:1715, 1738` | `db.createTable(tableName, ...)` | timeseries tables | `Database` creating a table on first insert | `not widget-reachable` — driven by a sample arriving, not by a control |

**Both accessors are present.** `:1108` uses `adb`, `:1165` uses `dbWrap.db`.
The script finds both because section 1 searches the *method names*, not a
receiver spelling — the exact mistake `.planning/phases/02-route-gating/deferred-items.md`
§4 names. Spec §6 lists two of these five; all five are here, and plan 03-10
moves all five.

### 2.2 Raw Drift statement API (script §2 — 116 hits)

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/core/server_config_db.dart:58` | `db.into(db.flutterPreferences).insertOnConflictUpdate(...)` | `flutter_preferences` | `ServerConfigDb.publish()` ← `lib/pages/server_config.dart:3224` | `guarded by 03-08` |
| `lib/core/server_config_db.dart:85-87` | `(db.delete(db.flutterPreferences)..where(...)).go()` | `flutter_preferences` | `ServerConfigDb.remove()` | `guarded by 03-08` |
| `packages/tfc_dart/lib/core/access/drift_audit_sink.dart:75` | `_db.into(_db.auditEntry).insert(...)` | `audit_entry` | `auditSinkProvider` (`lib/providers/access.dart:104`) | `correct as-is` — append-only and retention-exempt by design; the class doc explains why, and this sweep does not restate it |
| `packages/tfc_mcp_server/lib/src/services/drift_tech_doc_index.dart:65, 230-236, 242, 251-253, 260, 306, 322` | `_db.into(...)`, `_db.delete(...)`, `_db.update(...)` | tech-doc tables | **`lib/tech_docs/tech_doc_upload_service.dart:104, 149, 221-222, 275`**, wired at `lib/providers/tech_doc.dart`, driven by the Knowledge Base page | `left open: reachable from an ungated route; no Phase 3 plan owns it` — see §3.1 |
| `packages/tfc_mcp_server/lib/src/services/drift_plc_code_index.dart:84, 102, 121, 154, 169, 189, 257-276, 565` | `_db.into(...)`, `_db.delete(...)`, `_db.update(...)` | PLC index tables | **`lib/tech_docs/tech_doc_library_section.dart:1075` (`reindexAsset`) and `:1133` (`deleteAssetIndex`)**, wired at `lib/providers/plc.dart:65` | `left open: reachable from an ungated route; no Phase 3 plan owns it` — see §3.1 |
| `packages/tfc_mcp_server/lib/src/services/drift_drawing_index.dart:56, 68, 89-97, 219, 232` | `_db.into(...)`, `_db.delete(...)` | drawing tables | `lib/drawings/drawing_upload_service.dart:46, 61, 75`, wired at `lib/providers/drawing.dart:14`; `DrawingUploadDialog` has **no caller in the tree today** | `left open: reachable in principle, unwired in fact; no Phase 3 plan owns it` — see §3.1 |
| `packages/tfc_mcp_server/lib/src/audit/audit_log_service.dart:47, 85` | `_db.into(_auditLog).insert(...)`, `_db.update(_auditLog)` | `audit_log` (MCP's own) | `TfcMcpServer`, which runs **in the HMI process** (`lib/mcp/mcp_bridge_notifier.dart:266`, `lib/mcp/mcp_sse_server.dart:56`) | `left open: reached over MCP, not from a widget` — see §3.2 |
| `packages/tfc_dart/lib/core/access/access_repository.dart:177, 185, 201, 240, 247-249, 285, 340` | `db.into/update/delete` on `app_role` / `app_user` | roles and users | `accessRepositoryProvider`; Phase 6 owns the screens that drive it | `left open: the authorization store itself; Phase 6 gates it on \`users\`` — see §3.3 |
| `packages/tfc_dart/lib/core/preferences.dart:210, 254, 428` | `secureStorage.delete(key:)`, `db.customInsert(...)`, `database!.db.customUpdate(...)` | secure store, `flutter_preferences` | inside `Preferences` — the implementation `GuardedPreferences` wraps | `correct as-is` — these are the store the guard decorates; the check happens above them |
| `lib/core/preferences.dart:54-84` | `_prefs.setBool/setInt/setDouble/setString/setStringList/remove/clear` | device-local | `SharedPreferencesWrapper implements PreferencesApi` | `correct as-is` — pure delegation with the caller's key |
| `packages/tfc_dart/lib/core/database_drift.dart:374, 394, 444-527, 702-790, 847-856, 907, 990-1007, 1127-1317` | `into(...)`, `delete(...)`, `customStatement`, `customInsert` | every table | the database's own methods and migrations | `correct as-is` — this file *is* the store |
| `packages/tfc_dart/lib/core/database.dart:1127, 1647-1656` | `db.customStatement(...)` | timeseries DDL | `Database` table management | `not widget-reachable` — DDL run when a table is created or repaired, not from a control |
| `packages/tfc_dart/lib/core/alarm.dart:341` | `db.customInsert(r'''...''')` | alarm history | `AlarmMan` recording an alarm transition | `not widget-reachable` — driven by a PLC transition; the operator-facing ack path writes nothing here |
| `packages/tfc_mcp_server/lib/src/database/server_database.dart:376-389` | `customStatement(...)` | schema | migration callback | `not widget-reachable` — same as 2.1 |
| `lib/core/secure_storage/macos.dart:123, 152, 172`, `lib/core/secure_storage/other.dart:29`, `packages/tfc_dart/lib/core/secure_storage/linux.dart:52` | `_storage.delete(key:)` / `_legacy.delete(key:)` | OS keychain | the `MySecureStorage` implementations | `left open: secure storage is outside both guards` — see §3.4 |
| `lib/pages/ip_settings.dart:303, 916` | `connection.delete()`, `connection.update(settings)` | NetworkManager | `/advanced/ip-settings` | `route-gated (Phase 2)` — `kRaisedRoutes` raises it to `administer` |
| `lib/pages/ip_settings.dart:453` | `_tracker.update(...)` | — | in-memory traffic-rate tracker | `not widget-reachable` — not a store; a false positive of a deliberately broad grep, recorded rather than filtered away |
| `packages/centroidx_upgrader/lib/src/manager_launcher.dart:170` | `staged.delete()` | filesystem | cleanup of a failed staging write; see 2.7 | `left open: the update path is ungated` — see §3.5 |
| `packages/tfc_dart/lib/core/state_man.dart:2175` | `wrapper.client.delete()` | — | OPC UA client teardown | `not widget-reachable` — not a store; disposes a connection |

**Nothing further found** in this section beyond `server_config_db.dart`, the
three MCP index classes and the audit stores: every other hit is either the
store's own implementation, a migration, or a `.delete(`/`.update(` on
something that is not a database at all.

### 2.3 `AppDatabase` handles and the `.db` accessor (script §3 — 60 hits, plus 176 collapsed in `database_drift.g.dart`)

This section exists to catch a *new accessor spelling* the first time it
appears. It found no handle that is not already covered by 2.1 or 2.2. Rows
here are therefore grouped by what the handle is used for.

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/pages/history_view.dart:72, 1107, 1253, 1303` | `final adb = dbWrap.db` | `AppDatabase` | the history view | `guarded by 03-10` — the handle the five writes of 2.1 use |
| `lib/pages/history_view.dart:119, 138, 1217-1218` | `dbWrap.db.listHistoryViewPeriods/getHistoryViewKeys/getHistoryViewGraphs/getGlobalRetentionHorizon` | reads | the history view | `left open: read permissions are deferred` — spec §11 |
| `lib/providers/database.dart:17-29` | `AppDatabase.spawn(config)`, `db.db.open()/close()` | connection lifecycle | `databaseProvider` | `not widget-reachable` — opens and closes the connection; writes nothing |
| `lib/providers/access.dart:71, 104` | `AccessRepository(db.db)`, `DriftAuditSink(db.db)` | handles | `accessRepositoryProvider`, `auditSinkProvider` | `correct as-is` — the audit sink is the one direct Drift write that is correct by design |
| `lib/providers/mcp_bridge.dart:210`, `lib/providers/chat.dart:998, 1182`, `lib/providers/server_database.dart:13` | `dbWrapper.db` as `McpDatabase` | handle | MCP bridge and chat | `left open: reached over MCP, not from a widget` — see §3.2 |
| `lib/pages/server_config.dart:3209, 3224, 3258` | `ServerConfigDb.fetch(db.db)` / `publish(db.db, ...)` | `flutter_preferences` | `/advanced/server-config` | `guarded by 03-08` — and `route-gated (Phase 2)` besides |
| `lib/page_creator/assets/graph.dart:820-821`, `lib/page_creator/assets/helper/timeseries_notify_mixin.dart:189-191` | `db.db.enableNotificationChannel(...)`, `listenToChannel(...)` | LISTEN/NOTIFY | graph assets | `not widget-reachable` as a write — `enableNotificationChannel` issues DDL for a notify channel, not a data write; noted here rather than left silent |
| `lib/widgets/panes/database_stats_pane.dart:74, 86` | `db.db.config`, `db.db.customSelect(...)` | reads | the database stats pane | `left open: read permissions are deferred` |
| `packages/tfc_dart/lib/core/preferences.dart:250, 465, 556`, `preferences_watch.dart:59-77`, `alarm.dart:338, 362`, `database.dart:512-580`, `access_repository.dart:98-100`, `drift_audit_sink.dart:53` | `final db = ...!.db`, `AppDatabase db` fields | handles | core machinery | `correct as-is` — the stores holding their own handle |
| `packages/tfc_dart/lib/core/database_drift.g.dart` (176 occurrences) | generated `_$AppDatabase` boilerplate | — | drift codegen | `not widget-reachable` — regenerated from `database_drift.dart`, which is searched above; collapsed by the script and counted |

**No accessor spelling other than `adb`, `dbWrap.db`, `db.db`, `dbWrapper.db`,
`_tsDb!.db`, `database!.db` and `preferences.database!.db` appears anywhere in
the tree.** All seven are covered above. That is the claim this section is for.

### 2.4 `SharedPreferencesAsync()` constructed rather than injected (script §4 — 12 hits)

Spec §6 names **one** of these. There are twelve, in eight files, and nine of
the twelve are outside `lib/providers/` — the directory the spec's own CI check
would allow.

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/providers/preferences.dart:14, 24` | `SharedPreferencesWrapper(SharedPreferencesAsync())` | device-local | the two preference providers | `correct as-is` — this is the one place that is meant to construct it |
| `lib/providers/collector.dart:21` | `final prefs = SharedPreferencesAsync()` | device-local | `collectorProvider`, at boot | `guarded by 03-09` — spec §6 bypass 2 |
| `lib/core/update_channel.dart:23, 35` | `prefs ?? SharedPreferencesAsync()` | device-local | `readUpdateChannel` / `writeUpdateChannel`, called as tear-offs from `centroid-hmi/lib/main.dart:333, 368` and `lib/widgets/preferences.dart:81-82` | `guarded by 03-11` |
| `lib/tech_docs/tech_doc_library_section.dart:1194` | field on `_SharedPrefsReader` | device-local | the Knowledge Base page's delete-document flow | `guarded by 03-11` |
| `lib/pages/page_view.dart:253` | field on `_AssetStackState` | device-local | every asset page, on mount | `guarded by 03-11` |
| `lib/widgets/preferences.dart:556` | field on `_DatabaseConfigEditorState` | device-local | nothing — `grep -n sharedPreferences lib/widgets/preferences.dart` returns this line and no other | `guarded by 03-11` — 03-11 deletes it rather than rerouting it |
| `lib/widgets/preferences.dart:825` | `SharedPreferencesWrapper(SharedPreferencesAsync())` in `_loadData` | device-local | the preferences page, read path (`localPrefs.getAll()`) | `route-gated (Phase 2)` — `/advanced/preferences` is `administer`; still reconstructed, and 03-11 covers the construction |
| `lib/widgets/panes/color_picker_dialog.dart:42, 66` | inline in two statics | device-local | any colour picker, anywhere in the app | `guarded by 03-11` |
| `centroid-hmi/lib/main.dart:269` | `SharedPreferencesWrapper(SharedPreferencesAsync())` | device-local | app boot, feeding `PageManager(prefs:)` at `:270` and `pageManager.load()` at `:271` | `guarded by 03-11` — this is the boot write of `page_editor_data` outside any provider |

### 2.5 Legacy synchronous `SharedPreferences.getInstance()` (script §5 — 6 hits)

Spec §6 does not mention this API, and the CI check it asks for
(`SharedPreferencesAsync()`) would never catch it. It is in the tree today.

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/providers/theme.dart:15, 22, 44, 51` | `await SharedPreferences.getInstance()` | device-local | the theme and colour-scheme notifiers | `left open: device-local UI state, and inside \`lib/providers/\`` — see §3.6 |
| `lib/pages/dbus_login.dart:124, 141` | `await SharedPreferences.getInstance()` | device-local | the D-Bus login form | `left open: spec §2 excludes changing this file` — see §3.7 |

### 2.6 Secure storage (script §6 — 33 hits)

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/pages/dbus_login.dart:134` | `secureStorage.write(key: 'dbus_password', ...)` | OS keychain | the D-Bus login form | `left open: spec §2 excludes changing this file` — see §3.7 |
| `packages/tfc_dart/lib/core/database.dart:214-215, 226` | `SecureStorage.getInstance().write(key: _configLocation, ...)` | OS keychain | `DatabaseConfig` persistence, from `/advanced/server-config` and `/advanced/preferences` | `route-gated (Phase 2)` — both routes are `administer`; the store itself stays outside the guards, see §3.4 |
| `packages/tfc_dart/lib/core/preferences.dart:205` | `secureStorage.write(key: key, value: value)` | OS keychain | `Preferences.setString(..., secret: true)` | `correct as-is` — inside the object `GuardedPreferences` wraps, so the check happens above it |
| `lib/core/secure_storage/macos.dart:118, 139, 144`, `lib/core/secure_storage/other.dart:24`, `packages/tfc_dart/lib/core/secure_storage/linux.dart:47` | `_storage.write(key:, value:)` | OS keychain | the platform implementations behind `MySecureStorage` | `left open: secure storage is outside both guards` — see §3.4 |
| `packages/tfc_dart/lib/core/secure_storage/secure_storage.dart:10-30`, `interface.dart:1`, `packages/tfc_dart/lib/tfc_dart_core.dart:22`, `centroid-hmi/lib/main.dart:244` | the singleton, the interface, the barrel export of the interface, and the one `setInstance` at boot | — | — | `not widget-reachable` — type declarations, an export line, and one boot-time platform selection; no key is written |

### 2.7 File writes (script §7 — 3 hits)

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/pages/key_repository.dart:1886` | `file.writeAsString(jsonString)` | filesystem | key-mapping export, `/advanced/key-repository` | `route-gated (Phase 2)` — `configure` |
| `lib/pages/server_config.dart:2923` | `.writeAsString(...convert(envelope))` | filesystem | server-config export, `/advanced/server-config` | `route-gated (Phase 2)` — `administer` |
| `packages/centroidx_upgrader/lib/src/manager_launcher.dart:159` | `staged.writeAsBytes(bytes)` | filesystem | `managerLauncher.launchForUpdate(...)` at `centroid-hmi/lib/main.dart:369` | `left open: the update path is ungated` — see §3.5 |

**Nothing further found** in this section: three file writes in the whole tree,
all three identified, two of them already behind a raised route.

### 2.8 D-Bus — network and hostname (script §8 — 31 hits)

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/pages/ip_settings.dart:263, 919-925, 1107-1125` | `activateConnection`, `deactivateConnection`, `addAndActivateConnection`, `settings.addConnection` | NetworkManager over D-Bus | `/advanced/ip-settings` | `route-gated (Phase 2)` — spec §6 bypass 3, gated at the route with the D-Bus call itself deliberately untouched |
| `lib/pages/ip_settings.dart:39, 68, 84, 399, 819, 1048` | `NetworkManagerClient` fields and construction | — | the same page | `route-gated (Phase 2)` |
| `lib/pages/about_linux.dart:98` | `nm.NetworkManagerClient(bus: ...)` | — | `/advanced/about-linux` (read-only page) | `not widget-reachable` as a write — the client is constructed to *read* device state; no write member is called in that file |
| `lib/widgets/tfc_operations.dart:22, 24, 69` | `_operationMode.callSetMode('running' \| 'stopped' \| 'cleaning')` | `is.centroid.OperationMode` over D-Bus | `OperationModeAppBarLeftWidgetProvider`, which **nothing in the repository constructs** — `globalAppBarLeftWidgetProvider` (`lib/widgets/base_scaffold.dart:36`) defaults to null and is never overridden | `left open: unwired today, and start/stop is an operator action by design` — see §3.8 |
| `lib/dbus/generated/hostname1.dart:290-356` | `callSetHostname`, `callSetStaticHostname`, `callSetPrettyHostname`, `callSetIconName`, `callSetChassis`, `callSetDeployment`, `callSetLocation` | systemd-hostnamed | **no caller anywhere in the tree** | `not widget-reachable` — generated D-Bus bindings with zero call sites; a grep for each name outside this file returns nothing |
| `lib/dbus/generated/login1.dart:1140-1563` | `callSetUserLinger`, `callSetRebootParameter`, `callSetRebootToFirmwareSetup`, `callSetRebootToBootLoaderMenu`, `callSetRebootToBootLoaderEntry`, `callSetWallMessage` | systemd-logind | **no caller anywhere in the tree** | `not widget-reachable` — same |
| `lib/dbus/generated/operations.dart:88` | `callSetMode` declaration | — | the binding `tfc_operations.dart` calls | `correct as-is` — a generated binding; the call site is the row above |

### 2.9 Writes through the injected preferences interface (script §9 — 76 + 17 hits)

These are **not bypasses**. They are the surface plan 03-01 classifies, and the
reason they are enumerated is that neither a construction search nor a Drift
search produces a single hit for them. Every key expression below is resolved
in §5.

| File and line | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `lib/core/startup_url.dart:24, 26` | `prefs.remove/setString(startupUrlPrefsKey)` | preferences | the startup-page control | `guarded by 03-06` |
| `lib/core/update_channel.dart:36` | `p.setString(updateChannelPrefsKey, ...)` | preferences | the update-channel control | `guarded by 03-11` then `03-06` — the construction moves first |
| `lib/chat/chat_widget.dart:189, 361, 392, 394` | `prefs.setString/remove(...)` | preferences | the chat provider-settings dialog | `guarded by 03-06` |
| `lib/providers/state_man.dart:26` | `prefs.setString('key_mappings', ...)` | preferences | `stateManProvider` at boot | `guarded by 03-06` — routed through `systemWrites` |
| `lib/providers/collector.dart:27` | `prefs.setString(Collector.configLocation, ...)` | preferences | `collectorProvider` at boot | `guarded by 03-09` |
| `lib/providers/access.dart:694` | `local.setString(kAccessSessionPrefKey, ...)` | device-local preferences | every `poke()`, i.e. every pointer-down | `guarded by 03-06` |
| `lib/providers/chat.dart:340, 370, 405, 449, 453, 494, 505, 525, 529, 532, 535, 538, 548, 558, 905` | `prefs.setString/remove(chat.*)` | preferences | chat conversation management | `guarded by 03-06` |
| `lib/providers/theme.dart:23, 52` | `prefs.setString(_key, ...)` | device-local, **legacy sync API** | theme and colour-scheme controls | `left open: device-local UI state, and inside \`lib/providers/\`` — see §3.6 |
| `lib/tech_docs/tech_doc_upload_service.dart:267` | `prefsReader.setString('page_editor_data', ...)` | preferences | deleting a tech doc on the ungated Knowledge Base page | `guarded by 03-11` — the store it writes through is constructed privately at `tech_doc_library_section.dart:1194`; see also §3.1 |
| `lib/tech_docs/tech_doc_library_section.dart:1203` | `_prefs.setString(key, value)` | device-local | the `PrefsReader` adapter the row above uses | `guarded by 03-11` |
| `lib/pages/key_repository.dart:637, 1933` | `prefs.setString('key_mappings', ...)` | preferences | `/advanced/key-repository` | `guarded by 03-06` — and `route-gated (Phase 2)` besides |
| `lib/pages/page_view.dart:264` | `prefs.setString('asset_stack_config', ...)` | device-local | every asset page, on the read path when the key is absent | `guarded by 03-11` |
| `lib/pages/dbus_login.dart:127-131` | `prefs.setString/setBool(...)` | device-local, **legacy sync API** | the D-Bus login form | `left open: spec §2 excludes changing this file` — see §3.7 |
| `lib/page_creator/page.dart:247` | `prefs.setString(storageKey, jsonString)` | preferences | `PageManager.load()` at boot, **unawaited** | `guarded by 03-06` — routed through `systemWrites` |
| `lib/page_creator/page.dart:252, 257` | `prefs.setString(storageKey \| orderStorageKey, ...)` | preferences | the page editor's save | `guarded by 03-06` |
| `lib/page_creator/assets/image_store.dart:96, 129` | `prefs.setString/remove('$keyPrefix$id')` | preferences | page-editor image add and delete | `guarded by 03-06` |
| `lib/page_creator/assets/common.dart:444` | `prefs.setString('key_mappings', ...)` | preferences | asset key-mapping edits | `guarded by 03-06` |
| `lib/page_creator/assets/recipes.dart:269` | `prefs.setString(prefKey, jsonEncode(recipes))` | preferences | `_getRecipes` on the **read** path | `guarded by 03-06` |
| `lib/page_creator/assets/recipes.dart:281` | `prefs.setString(prefKey, ...)` | preferences | `_saveRecipes`, behind a control | `guarded by 03-06` |
| `lib/widgets/preferences.dart:949-957, 979, 981` | `target.setBool/setInt/setDouble/setStringList/setString(e.key, ...)`, `prefs.remove(e.key)`, `localPrefs.remove(e.key)` | preferences and device-local | the raw preference editor on `/advanced/preferences` | `route-gated (Phase 2)` — `administer`; the key is whatever the operator typed, see §5 |
| `lib/widgets/panes/color_picker_dialog.dart:66` | `SharedPreferencesAsync().setStringList(prefsKey, ...)` | device-local | confirming a colour anywhere in the app | `guarded by 03-11` |
| `lib/core/preferences.dart:54-84` | `_prefs.set*/remove/clear(key)` | device-local | `SharedPreferencesWrapper` | `correct as-is` — delegation with the caller's key |
| `packages/tfc_dart/lib/core/preferences.dart:344-413, 485-493, 524-532, 565-585` | `_memoryCache.set*`, `localCache?.set*`, `cache.set*` | in-memory and device-local caches | inside `Preferences` | `correct as-is` — the cache fan-out below the guard |
| `packages/tfc_dart/lib/core/state_man.dart:442` | `prefs.setString(configKey, ..., secret: true, saveToDb: false)` | secure store | `StateManConfig.fromPrefs` at boot when the key is absent | `guarded by 03-06` — routed through `systemWrites` |
| `packages/tfc_dart/lib/core/state_man.dart:450` | `prefs.setString(configKey, ...)` | secure store | `StateManConfig.toPrefs`, behind a control | `guarded by 03-06` |
| `packages/tfc_dart/lib/core/state_man.dart:626` | `prefs.setString('key_mappings', ...)` | preferences | key-mapping save | `guarded by 03-06` |
| `packages/tfc_dart/lib/core/alarm.dart:220` | `preferences.setString('alarm_man_config', ...)` | preferences | `AlarmMan.create` at boot when the key is absent | `guarded by 03-06` — routed through `systemWrites` |
| `packages/tfc_dart/lib/core/alarm.dart:303` | `preferences.setString('alarm_man_config', ...)` | preferences | `addAlarm`/`removeAlarm`/`updateAlarm`, behind the `configure`-gated alarm editor. **Not** `ackAlarm` | `guarded by 03-06` |
| `packages/tfc_mcp_server/lib/src/tools/read_toggles.dart:38, 114` | `prefs.setString(McpConfig.kPrefKey, ...)`, `local.setString(...)` | preferences and device-local | an MCP tool call, in the HMI process | `left open: reached over MCP, not from a widget` — see §3.2 |
| `packages/tfc_mcp_server/lib/src/services/config_service.dart:64` | `_prefCache.clear()` | — | `invalidateCache()` | `not widget-reachable` — `_prefCache` is a `TtlCache` (`config_service.dart:45`), not a preferences store. A false positive of section 9b's receiver-spelling filter, recorded rather than quietly dropped |

### 2.10 Two rows that exist because of this phase's design

These are not search results. They are holes the guards themselves open, and
they get rows so that they are visible rather than implied.

| Site | Call | Store | Reached from | Verdict |
|---|---|---|---|---|
| `GuardedPreferences.systemWrites` (plan 03-05) | the seven write members with the session check skipped | preferences | the boot defaults enumerated in plan 03-06 | `left open: the deliberately unchecked write path` — see §3.9 |
| `GuardedPreferences.database` (plan 03-05) | `guardedPrefs.database.db` → any raw Drift statement | every table | anything holding the guarded object | `left open: \`implements Preferences\` forces the getter` — see §3.10 |

---

## 3. What is left open, and why

Each entry says what closing it would take, so a later phase can price it.

### 3.1 Three raw-Drift index classes reachable from the Knowledge Base page

**What.** `DriftTechDocIndex`, `DriftPlcCodeIndex` and `DriftDrawingIndex` live
in `packages/tfc_mcp_server/lib/src/services/`, and each writes Drift directly —
twenty-six `into(...)` / `delete(...)` / `update(...)` statements between them
(twelve, eight and six respectively). They were built for the MCP server, but all three are wired into the
Flutter app through providers (`lib/providers/tech_doc.dart`,
`lib/providers/plc.dart:65`, `lib/providers/drawing.dart:14`) and their write
methods are called from app code:

- `lib/tech_docs/tech_doc_upload_service.dart:104, 149, 221-222, 275` —
  `storeDocument`, `updateSections`, `updatePdfBytes`, `deleteDocument`.
- `lib/tech_docs/tech_doc_library_section.dart:1075, 1133` — `reindexAsset` and
  `deleteAssetIndex` on `DriftPlcCodeIndex`, called straight from the page.
- `lib/drawings/drawing_upload_service.dart:46, 61, 75` — `storeDrawing` and
  `deleteDrawing`. `DrawingUploadDialog` has no caller in the tree today, so
  this third one is reachable in principle and unwired in fact.

**Where the operator is.** `/advanced/knowledge-base`
(`centroid-hmi/lib/main.dart:584-585`) is deliberately **not** in
`kRaisedRoutes` — `lib/access_routes.dart` names it among the pages that "read
rather than configure". It does not only read: an anonymous session at the panel
can delete a technical document, delete a PLC asset's index, and — through
`tech_doc_upload_service.dart:267` — rewrite `page_editor_data`.

**Why this is the same defect as the history view.** A destructive control on a
page that should stay readable. §6's fourth bypass was exactly that, on
`/advanced/history-view`, and plan 03-10 fixes it at the controls rather than at
the route for exactly this reason.

**Why not closed here.** This plan finds and records; it changes no source file.
No plan in this phase owns these call sites — 03-08, 03-09 and 03-10 close the
three §6 bypasses this document was written to go beyond.

**What closing it would take.** The same shape as plan 03-10: one store object
per index holding the write methods, checking a group on the destructive ones
and auditing all of them, with the page's call sites changing only their
receiver. `configure` is the natural group — this is authored content, the same
concern as the page editor. Cost is bounded: ten call sites in three app-side
files, no change to the index classes themselves.

### 3.2 Writes reached over MCP rather than from a widget

**What.** `TfcMcpServer` runs **inside the HMI process**
(`lib/mcp/mcp_bridge_notifier.dart:266`, `lib/mcp/mcp_sse_server.dart:56`), so
its tool handlers reach the same stores the app does:
`read_toggles.dart:38, 114` writes `mcp.config`, and
`audit_log_service.dart:47, 85` writes the MCP audit table.

**Why not closed here.** No widget reaches them; the caller is a remote agent
over SSE. Spec §7c already decides what happens: MCP tools that change
authorization are gated on `users` and audited with `origin = 'mcp'` and `who` =
the approving human. That is Phase 4's work, not this phase's.

**What closing it would take.** The `origin` column and the MCP tool gating §7c
describes. Nothing in this document changes that plan; the entry exists so the
reachability is written down rather than assumed absent.

### 3.3 The access repository writes its own store

`packages/tfc_dart/lib/core/access/access_repository.dart:177-340` writes
`app_role` and `app_user` through raw Drift. It is the authorization store
itself; a guard consulting the policy to decide whether the policy's own data
may change would be circular. Spec §7c and §9 put roles and users behind
`AccessGroup.users`, and Phase 6 builds the screens that drive it. Closing it
means gating those screens, not decorating this class.

### 3.4 Secure storage is outside both guards

`MySecureStorage` (`packages/tfc_dart/lib/core/secure_storage/interface.dart:1`)
is reached through a process-wide singleton, `SecureStorage.getInstance()`, and
neither `GuardedStateMan` nor `GuardedPreferences` wraps it. Three things live
there: `state_man_config`, the database config
(`packages/tfc_dart/lib/core/database.dart:214-226`) and the D-Bus password.

The first two are already covered in practice — `state_man_config` is written
through `Preferences.setString(..., secret: true)`, which the guard *does* wrap
(`packages/tfc_dart/lib/core/preferences.dart:205` is below the decorator), and
the database config is written only from two `administer`-gated routes. The
third is §3.7.

**What closing it would take.** A third decorator over `MySecureStorage`, or
replacing the singleton with an injected instance so the existing decorator can
reach it. The singleton is the obstacle: `SecureStorage.getInstance()` has
callers that hold no `Preferences` at all.

### 3.5 The update path writes and launches a binary, ungated

`packages/centroidx_upgrader/lib/src/manager_launcher.dart:159` writes the
centroidx-manager binary to disk and `:160` renames it into place; the caller is
`managerLauncher.launchForUpdate(...)` at `centroid-hmi/lib/main.dart:369`,
driven by the app's update affordance. No route gates it and no guard sees it.

This is the highest-consequence write in the sweep and the least like the
others: it is not configuration, it is code. It is recorded here rather than
fixed because the update flow is outside this milestone's scope entirely — the
spec does not mention it, and gating it is a product decision about who may
update a station, not an access-control mechanism question.

**What closing it would take.** Either an `administer` check at the update
affordance in `centroid-hmi/lib/main.dart`, or accepting it explicitly on the
grounds that the binary is signature-checked upstream. Somebody should decide
which; today neither has been decided, which is why this entry exists.

### 3.6 `lib/providers/theme.dart` — device-local UI state on the legacy API

Four `SharedPreferences.getInstance()` calls writing `theme_mode` and
`color_scheme`. Plan 03-01 classifies both as `operate`: they are what a panel
writes about itself, not plant configuration. The file is inside
`lib/providers/`, so spec §6's CI grep does not apply to it even once plan 03-11
extends that grep to the legacy API.

**What closing it would take.** Routing both notifiers through
`localPreferencesProvider` so the writes pass the guard and appear in the audit
trail. It is cheap; it is left open because the value is low — an `operate` key
an anonymous session may write anyway — and because moving it touches the theme
path, which every golden in the repository depends on.

### 3.7 `lib/pages/dbus_login.dart` — excluded by the spec

Two `SharedPreferences.getInstance()` calls writing five bare keys
(`connectionType`, `host`, `username`, `autoLogin`, `sshPrivateKeyPath`) and one
`secureStorage.write(key: 'dbus_password', ...)`.

Spec §2 excludes changing this file from the whole milestone, and says why: the
D-Bus credential is a **station** credential, the same kind of thing as the OPC
UA session and the Postgres login, and D-Bus is the mechanism *underneath*
`administer` rather than something `administer` governs. Plan 03-01 still
classifies all five keys as `administer`, so if the writes are ever routed
through the guard the classification is already there.

**What closing it would take.** Lifting the §2 exclusion, then the same
treatment as any other page. The exclusion is a decision, not an oversight.

### 3.8 `lib/widgets/tfc_operations.dart` — an unwired D-Bus operation-mode write

`callSetMode('running' | 'stopped' | 'cleaning')` at `:22`, `:24` and `:69`
changes the plant's operation mode over D-Bus from an app-bar button. It is
**not wired**: `OperationModeAppBarLeftWidgetProvider` is constructed nowhere,
and `globalAppBarLeftWidgetProvider` (`lib/widgets/base_scaffold.dart:36`)
defaults to null with no override anywhere in the tree.

Left open for two reasons. It writes nothing today. And if it were wired,
starting and stopping the line is an operator action by design — the first line
of `REQUIREMENTS.md`'s acceptance criteria is that an unauthenticated session
can jog, start and stop.

**What closing it would take.** Nothing, unless it is wired. If somebody wires
it, the cleaning-mode call is the one worth a second look — cleaning is a mode
change with process consequences, not a start/stop.

### 3.9 `GuardedPreferences.systemWrites`

Plan 03-05 gives `GuardedPreferences` a `systemWrites` getter returning a
`Preferences` whose write members skip the session check. It exists because five
writes fire at boot with nobody signed in, on keys that are not `operate`:

| Write | Key | Group | Owner |
|---|---|---|---|
| `lib/page_creator/page.dart:247` (unawaited, from `PageManager.load()`) | `page_editor_data` | `configure` | 03-06 |
| `lib/providers/state_man.dart:26` (`fetchKeyMappings`) | `key_mappings` | `configure` | 03-06 |
| `packages/tfc_dart/lib/core/state_man.dart:442` (`StateManConfig.fromPrefs`) | `state_man_config` | `administer` | 03-06 |
| `packages/tfc_dart/lib/core/alarm.dart:220` (`AlarmMan.create`) | `alarm_man_config` | `configure` | 03-06 |
| `lib/providers/collector.dart:27` (`collectorProvider`) | `collector_config` | `administer` | 03-09 |

Without `systemWrites` each of these is denied on a fresh station and the
station is broken in a way no screen shows — the page editor case takes the
pages away entirely.

**The residual risk.** It is a bypass by construction. Anything holding a
`GuardedPreferences` can reach it. The controls are that it is a distinct object
rather than a `system: true` flag (a flag is one keystroke from an operator
path), that every `systemWrites` write still produces exactly one audit row with
`origin: 'system'` and the group that *would* have been required, and that plan
03-06 caps the call sites: `kSystemWriteCallSites` in
`lib/providers/access_policy.dart` names every file allowed to use it, and a
test compares the grep result to that list in both directions.

**What closing it would take.** Removing the need for it — making the five boot
defaults lazy, or writing them under an explicit commissioning identity rather
than an anonymous session. Both are larger than this phase.

### 3.10 `GuardedPreferences.database`

`GuardedPreferences implements Preferences`, and `Preferences` declares a
`database` getter. The decorator must therefore supply one, so anything holding
the guarded object can write `guardedPrefs.database.db` and issue raw Drift —
past the guard it is holding.

**The control, stated exactly.** Section 3 of `scripts/sweep-write-paths.sh`
searches the `AppDatabase` type and the `.db` accessor, so such a call appears
in the sweep the first time it is written, and plan 03-12 fails when a hit has
no row here. That is a *detection* control, not a prevention: it finds the call
after it exists, on the next run.

**Why it is not preventable cheaply.** Dropping `implements Preferences` means
every caller changes, which is the whole reason the decorator idiom was chosen.
Returning null from the getter breaks the callers that legitimately need the
database handle (`preferences.database!.db` at
`packages/tfc_dart/lib/core/alarm.dart:338, 362`, among others).

**What closing it would take.** Splitting `Preferences` so that the database
handle lives on a narrower interface the decorator does not have to expose. That
is a refactor of `tfc_dart`'s core, not a guard change.

---

## 4. Is there a fifth?

**Yes.** Spec §6's four are each owned by a plan in this phase. Beyond them the
sweep found five further things, listed here by name with who owns each.

### 4.1 New, and owned by no plan in this phase

**A. Three raw-Drift index classes reachable from the ungated Knowledge Base
page.** `DriftTechDocIndex`, `DriftPlcCodeIndex` and `DriftDrawingIndex` in
`packages/tfc_mcp_server/lib/src/services/`, called from
`lib/tech_docs/tech_doc_upload_service.dart:104, 149, 221-222, 275`,
`lib/tech_docs/tech_doc_library_section.dart:1075, 1133` and
`lib/drawings/drawing_upload_service.dart:46, 61, 75`. An anonymous session on
`/advanced/knowledge-base` can delete a technical document, delete a PLC asset's
index and rewrite `page_editor_data`. **This is the fifth bypass, and it is the
same shape as the fourth**: a destructive control on a page classified as a read
surface. Owner: none. Priced in §3.1.

**B. An ungated write-and-launch of the manager binary.**
`packages/centroidx_upgrader/lib/src/manager_launcher.dart:159`, reached from
`centroid-hmi/lib/main.dart:369`. Owner: none. Priced in §3.5.

**C. An unwired D-Bus operation-mode write.**
`lib/widgets/tfc_operations.dart:22, 24, 69`. Writes nothing today because
nothing constructs its provider. Owner: none. Priced in §3.8.

### 4.2 Beyond §6's list, but already owned

**D. Nine further `SharedPreferencesAsync()` constructions outside
`lib/providers/`.** Spec §6 names `lib/providers/collector.dart:21`. The script
finds twelve constructions in eight files; three are inside `lib/providers/`
(two of them the sanctioned ones in `preferences.dart`), and the other nine are:
`lib/core/update_channel.dart:23, 35`,
`lib/tech_docs/tech_doc_library_section.dart:1194`, `lib/pages/page_view.dart:253`,
`lib/widgets/preferences.dart:556, 825`,
`lib/widgets/panes/color_picker_dialog.dart:42, 66` and
`centroid-hmi/lib/main.dart:269`. Owner: plan 03-11, whose own table already
names each. `lib/widgets/preferences.dart:556` is a dead field with no other
reference in the file.

**E. Six legacy `SharedPreferences.getInstance()` calls.** An API spec §6 does
not mention and its proposed CI check would not catch:
`lib/providers/theme.dart:15, 22, 44, 51` and `lib/pages/dbus_login.dart:124, 141`.
Owner: plan 03-11, which extends the check to the legacy API. Both files stay
open on purpose — §3.6 and §3.7.

### 4.3 Where the answer was "nothing further"

Recorded so a later phase does not repeat the search or, worse, assume it:

- **The raw Drift statement API (script §2, 116 hits).** Beyond
  `lib/core/server_config_db.dart` and the three index classes of finding A,
  **nothing further found**. Every other hit is the store's own implementation,
  a drift `Migrator` callback, the audit sink, the access repository, or a
  `.delete(` / `.update(` on something that is not a database.
- **`AppDatabase` handles (script §3, 60 hits).** Seven accessor spellings exist
  in the tree — `adb`, `dbWrap.db`, `db.db`, `dbWrapper.db`, `_tsDb!.db`,
  `database!.db`, `preferences.database!.db` — and every one is accounted for in
  2.3. **Nothing further found**: no eighth spelling, and no handle that leads to
  a write not already listed.
- **File writes (script §7, 3 hits).** Three in the entire tree, all three in
  2.7. **Nothing further found.**
- **The preference key inventory (script §9).** Every key expression resolves to
  a rule in `kPrefAccessRules`; **no key the app writes rests on the
  `administer` default.** See §5.

### 4.4 What §5 checked and did not find

The rule this document is meant to enforce — *a key the app writes in normal
operation may not rest on the `administer` default* — is satisfied. Every one of
the thirty-odd key expressions in §5 is matched by an explicit rule. There is no
finding of that shape to raise here.

There is a related risk that is **not** a rule violation and is named anyway,
because it is the same failure with a different cause: five keys are written at
boot by an anonymous session on groups that session does not hold
(`page_editor_data`, `key_mappings`, `state_man_config`, `alarm_man_config`,
`collector_config`). Under a fail-closed guard with no escape hatch, every one
of them is denied on a fresh station. Plan 03-05's `systemWrites` and plan
03-06's wiring exist for exactly these five, and 03-09 covers the last. §3.9
lists them with their owners.

---

## 5. Config keys, reconciled

One row per key expression from script section 9, against `kPrefAccessRules` in
`packages/tfc_access/lib/src/access_policy.dart`. **Plan 03-01 landed while this
sweep ran**, so this reconciles against the code rather than against plan text.
Plan 03-12 checks the reconciliation again.

The **when** column is the point of the table. A write that fires before anybody
can sign in, or merely because an operator opened a page, is a different risk
from one behind a Save button.

| Call site | Expression as written | Resolves to | Rule in `kPrefAccessRules` | Group | When |
|---|---|---|---|---|---|
| `startup_url.dart:24, 26` | `startupUrlPrefsKey` | `startup_url` | exact `startup_url` | `operate` | behind a control |
| `update_channel.dart:36` | `updateChannelPrefsKey` | `update_channel` | exact `update_channel` | `administer` | behind a control |
| `chat_widget.dart:189` | `kSelectedProvider` | `llm.selected_provider` | prefix `llm.` | `administer` | behind a control |
| `chat_widget.dart:361` | `prefKey` (switch on provider) | `llm.claude.api_key`, `llm.openai.api_key`, `llm.gemini.api_key` | prefix `llm.` | `administer` | behind a control |
| `chat_widget.dart:392, 394` | `urlPrefKey` (ternary) | `llm.claude.base_url`, `llm.openai.base_url` | prefix `llm.` | `administer` | behind a control |
| `providers/state_man.dart:26` | `'key_mappings'` | `key_mappings` | exact `key_mappings` | `configure` | **boot-time** — `fetchKeyMappings` writes a default when absent |
| `providers/collector.dart:27` | `Collector.configLocation` | `collector_config` | exact `collector_config` | `administer` | **boot-time** — default written when absent |
| `providers/access.dart:694` | `kAccessSessionPrefKey` | `access.session` | exact `access.session` | `operate` | **read-path** — every `poke()`, i.e. every pointer-down |
| `providers/chat.dart:340, 370, 405, 449, 525, 905` | `'$kConversationPrefix$id'` | `chat.conversation.<id>` | prefix `chat.` | `operate` | behind a control |
| `providers/chat.dart:529, 548` | `kConversationList` | `chat.conversations` | prefix `chat.` | `operate` | behind a control |
| `providers/chat.dart:532, 558` | `kActiveConversation` | `chat.active_conversation` | prefix `chat.` | `operate` | behind a control |
| `providers/chat.dart:453, 494, 505, 535, 538` | `kChatHistory` | `chat.history` | prefix `chat.` | `operate` | behind a control, plus a one-time migration |
| `providers/theme.dart:23` | `_key` (`ThemeModeNotifier`) | `theme_mode` | exact `theme_mode` | `operate` | behind a control — **legacy API; never reaches the guard**, §3.6 |
| `providers/theme.dart:52` | `_key` (`ColorSchemeNotifier`) | `color_scheme` | exact `color_scheme` | `operate` | behind a control — same |
| `tech_doc_upload_service.dart:267` | `'page_editor_data'` | `page_editor_data` | exact `page_editor_data` | `configure` | **delete-path** — rewritten when a tech doc is deleted, from an ungated route (§3.1) |
| `tech_doc_library_section.dart:1203` | `key` (a `PrefsReader` parameter) | `page_editor_data` — the adapter's only caller is the row above | exact `page_editor_data` | `configure` | same |
| `key_repository.dart:637, 1933` | `'key_mappings'` | `key_mappings` | exact `key_mappings` | `configure` | behind a control, on a `configure`-gated route |
| `page_view.dart:264` | `'asset_stack_config'` | `asset_stack_config` | exact `asset_stack_config` | `operate` | **read-path** — written when the key is absent, on mount of any asset page |
| `dbus_login.dart:127-131` | five literals | `connectionType`, `host`, `username`, `autoLogin`, `sshPrivateKeyPath` | five exact rules | `administer` | behind a control — **legacy API**, §3.7 |
| `page_creator/page.dart:247` | `storageKey` | `page_editor_data` | exact `page_editor_data` | `configure` | **boot-time, unawaited** — a denial here surfaces as an unhandled async error and a default that never persists |
| `page_creator/page.dart:252` | `storageKey` | `page_editor_data` | exact | `configure` | behind a control |
| `page_creator/page.dart:257` | `orderStorageKey` | `page_editor_top_level_order` | exact `page_editor_top_level_order` | `configure` | behind a control |
| `image_store.dart:96, 129` | `'$keyPrefix$id'` | `page_editor_image:<id>` | prefix `page_editor_image:` | `configure` | behind a control |
| `page_creator/assets/common.dart:444` | `'key_mappings'` | `key_mappings` | exact | `configure` | behind a control |
| `recipes.dart:269` | `'${widget.config.recipesBucket}.recipes'` | `<bucket>.recipes` | suffix `.recipes` | `setpoints` | **read-path** — `_getRecipes` writes an empty default, so an anonymous operator merely opening a recipes asset triggers it |
| `recipes.dart:281` | same expression | `<bucket>.recipes` | suffix `.recipes` | `setpoints` | behind a control |
| `widgets/preferences.dart:949-957, 979, 981` | `e.key` | **cannot be resolved to a literal or a prefix** — the key is whatever row the operator is editing, so the group is whatever rule matches at runtime | every rule, at runtime | varies | behind a control, on the `administer`-gated `/advanced/preferences` |
| `color_picker_dialog.dart:66` | `prefsKey` | `color_picker_recent_colors` | exact `color_picker_recent_colors` | `operate` | behind a control (confirming a colour) |
| `tfc_dart/core/state_man.dart:442` | `configKey` | `state_man_config` | exact `state_man_config` | `administer` | **boot-time** — `StateManConfig.fromPrefs` writes a default when absent |
| `tfc_dart/core/state_man.dart:450` | `configKey` | `state_man_config` | exact | `administer` | behind a control |
| `tfc_dart/core/state_man.dart:626` | `'key_mappings'` | `key_mappings` | exact | `configure` | behind a control |
| `tfc_dart/core/alarm.dart:220` | `'alarm_man_config'` | `alarm_man_config` | exact `alarm_man_config` | `configure` | **boot-time** — `AlarmMan.create` writes a default when absent |
| `tfc_dart/core/alarm.dart:303` | `'alarm_man_config'` | `alarm_man_config` | exact | `configure` | behind a control — `addAlarm`/`removeAlarm`/`updateAlarm` only. **`ackAlarm` writes nothing**, so this rule does not stand between an operator and an alarm ack |
| `read_toggles.dart:38, 114` | `McpConfig.kPrefKey` | `mcp.config` | prefix `mcp.` | `administer` | over MCP, not from a widget (§3.2) |
| `lib/core/preferences.dart:54-84` | `key` (a parameter) | pass-through — `SharedPreferencesWrapper` delegates the caller's key | n/a | the caller's | n/a |
| `tfc_dart/core/preferences.dart:344-585` | `key` / `entry.key` (parameters) | pass-through — the cache fan-out inside `Preferences` | n/a | the caller's | n/a |
| `config_service.dart:64` | `_prefCache.clear()` | **not a preference key** — `_prefCache` is a `TtlCache` (`:45`) | n/a | n/a | n/a |

**One key is written outside section 9 and belongs in this table anyway.**
`server_config_envelope` (`lib/core/server_config_db.dart:55`) is written
through raw Drift today, so no `set*` search finds it; it has an exact rule
resolving to `administer`, and plan 03-08 turns it into a `setString` call that
this table's search *will* find on the next run.

**The reconciliation's result.** Every resolvable key expression is matched by
an explicit rule. **No key the app writes in normal operation rests on the
`administer` default.** The one unresolvable expression — `e.key` in the raw
preference editor — is unresolvable by construction rather than by omission, and
sits behind an `administer`-gated route.

The five bold **boot-time** rows and the three **read-path** rows are the ones
that would have broken a plant, and they are why the `when` column exists. Their
owners are in §3.9.

---

## 6. What this sweep does not cover

Read this before treating the table above as an inventory.

It is a **static text search of the Dart sources in this repository**. It does
not cover reflection, code generated at build time, native plugin channels,
platform channels into Swift/Kotlin/C++, or anything a future package brings in.
It searches `lib`, `centroid-hmi/lib`, `demo` and `packages/*/lib`, and nothing
else — not `test`, not `build`, not `tool`, not the Go manager, not the PLC
sources in `~/Projects/sildarvinnsla`.

Three deliberate limits inside the search itself:

- **Comment-only lines are dropped.** A commented-out call that somebody
  restores is a site the sweep would not have reported until it was restored.
- **Hits in generated files are collapsed to a counted line per file.** The
  counts are printed, so a generated file acquiring hits in an unexpected
  section is visible, but the individual lines are not listed.
- **Section 9b filters `remove` and `clear` by receiver spelling**
  (`pref` / `prefs` / `preferences`). That is a filter on a name, which is the
  exact failure mode this script was built against — a `PreferencesApi` held in
  a field called `_store` would not match it. Section 9c exists as the
  compensation: it prints the census of every receiver 9b dropped, 110 distinct
  spellings, so the omission is scannable rather than silent. It is a weaker
  control than the searches around it, and it is the first place to look if a
  missed preference write is ever found.

**It does not prove a site is unreachable from a widget.** Where a row says
`not widget-reachable` it names the reasoning — a drift `Migrator` callback, a
generated binding with no caller, a `TtlCache` rather than a store — and the
reasoning is checkable by the next reader. That is not the same as a proof, and
this document does not claim it is.

No sentence here says the enumeration is complete. The entire reason this
document exists is that the last such claim was wrong: §6 named three, a fourth
was in the tree the whole time, and §4 above names a fifth. Assume there is a
sixth, re-run `scripts/sweep-write-paths.sh`, and add its rows.

Spec §6 is **not modified by this document**. It is authoritative input to this
phase and plan 03-11 owns any amendment; findings A, B and C in §4.1 are
candidates for it.
