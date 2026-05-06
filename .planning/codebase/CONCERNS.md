# Codebase Concerns

**Analysis Date:** 2026-05-05

---

## Tech Debt

**Collector periodic-sample null-crash:**
- Issue: `latestValue!` force-unwrap inside a `Timer.periodic` callback is wrapped by commented-out null-guard (`// if (latestValue != null)`). If the timer fires before the first OPC UA value arrives, the app crashes.
- Files: `packages/tfc_dart/lib/core/collector.dart:200`
- Impact: Hard crash in any deployment where a `sampleInterval` is set and the PLC hasn't emitted the first value before the first tick.
- Fix approach: Uncomment the null-guard. Restore the guarded block (lines 199–203) and null-reset `latestValue` after each sample.

**`CollectTable` grouping — commented-out incomplete feature:**
- Issue: `CollectTable` (multi-entry grouped collection config) is commented out with `// TODO: implement this`. `CollectorConfig` exposes only a single `collect: bool` flag with the table list removed.
- Files: `packages/tfc_dart/lib/core/collector.dart:42–60`
- Impact: No multi-table grouped collection is possible. Config schema will break if `CollectTable` is added later without a migration.
- Fix approach: Either complete the implementation or remove the dead comment block; don't leave half-schema code in production.

**Postgres `Interval.toDuration()` month approximation:**
- Issue: Extension on `pg.Interval` converts months to days using `months * 30`. Acknowledged in code as `// TODO: THIS IS BAD`. Retention policies expressed in months silently accumulate ~4-day errors over 5-month windows.
- Files: `packages/tfc_dart/lib/core/database.dart:20–31`
- Impact: Data retention queries against TimescaleDB may drop data too early or too late when the retention policy uses month units.
- Fix approach: Use `months * 30` only as documented fallback; prefer callers expressing retention in exact `Duration` days.

**`preferences.remove()` does not delete from Postgres:**
- Issue: The `remove()` method deletes from in-memory cache and local (SQLite) cache but has `// TODO: remove from postgres`, leaving preference values in PostgreSQL permanently.
- Files: `packages/tfc_dart/lib/core/preferences.dart:368–373`
- Impact: Stale preference keys accumulate in `flutter_preferences` table indefinitely; preference deletions appear successful to callers but are not persisted on the database-backed path.
- Fix approach: Add `await db.customStatement("DELETE FROM flutter_preferences WHERE key = \$1", [key])` inside `remove()`.

**`_nextSeq` static counter is global (all `Database` instances share one sequence):**
- Issue: `_PendingWrite._nextSeq` is a `static int` — it is class-wide, not per-`Database`. In tests or multi-DB scenarios, sequence numbers are shared across instances.
- Files: `packages/tfc_dart/lib/core/database.dart:221`
- Impact: Low risk in production (single `Database` instance), but causes test isolation issues and the sequence can theoretically overflow (though dart ints are 64-bit).
- Fix approach: Move `_nextSeq` to the enclosing `Database` class as an instance field, or use a per-instance counter injected into `_PendingWrite`.

**`updateRetentionPolicy` is TimescaleDB-only (`// TODO: SQLITE`):**
- Issue: `AppDatabase.updateRetentionPolicy()` calls `create_hypertable` and TimescaleDB-specific `add_retention_policy`. This will throw on any SQLite or plain-Postgres deployment.
- Files: `packages/tfc_dart/lib/core/database_drift.dart:852–870`
- Impact: Any non-TimescaleDB configuration silently breaks retention cleanup.
- Fix approach: Guard the hypertable path with a runtime check, or provide a no-op path for SQLite.

**`ModbusEpochRegister` milliseconds branch is unreachable:**
- Issue: `epochType` is hardcoded to `ModbusEpochType.seconds` (line 11) and is not settable via constructor. The milliseconds branch in `setValueFromBytes` and `_getRawValue` will never execute. Companion `// TODO` notes the correct fix.
- Files: `packages/modbus_client/lib/src/element_type/modbus_element_epoch.dart:6–40`
- Impact: Any caller wanting millisecond-epoch registers silently gets seconds. No warning.
- Fix approach: Expose `epochType` as a constructor parameter (already suggested by the TODO).

**`ModbusWriteGroupRequest` is commented-out dead code:**
- Issue: The class is fully written but wrapped in `/* TODO: define multiple write "strategy"! ... */`. Multi-register write grouping is unavailable.
- Files: `packages/modbus_client/lib/src/modbus_request.dart:228–end of block`
- Impact: Callers that need atomic multi-register writes must implement workarounds; API surface is misleading.
- Fix approach: Decide on the write strategy and uncomment, or delete and document the limitation.

**`secureChannelLifeTime` hardcoded to 1 minute with debug TODO:**
- Issue: Both `ClientIsolate.create` and `Client` are instantiated with `secureChannelLifeTime: Duration(minutes: 1)`. The inline comment reads `// TODO can I reproduce the problem more often` — this is a debugging artifact that slipped into production.
- Files: `packages/tfc_dart/lib/core/state_man.dart:1050–1061`
- Impact: OPC UA secure channels renegotiate every minute. This adds unnecessary overhead on long-lived connections and may cause transient disconnects under load.
- Fix approach: Remove the 1-minute override and let `open62541_dart` use its default (typically 3600 s), or make it configurable via `OpcUaConfig`.

**`server_config.dart` is a 2791-line god-file:**
- Issue: All server configuration UI — OPC UA, JBTM, Modbus, certificates, key mapping — lives in a single file with 23 widget classes. The file has 36 `setState` calls.
- Files: `lib/pages/server_config.dart`
- Impact: High merge-conflict risk; slow incremental builds; difficult to test individual sections in isolation.
- Fix approach: Split into separate files per protocol section (e.g., `lib/pages/server_config/opcua_section.dart`).

**`lib/models/history_models.dart` marked `TODO REMOVE` but still imported:**
- Issue: The file header says `// TODO REMOVE` but three production files still import it.
- Files: `lib/models/history_models.dart`, imported by `lib/pages/history_view.dart`, `lib/widgets/history_table_pane.dart`, `lib/widgets/history_graph_pane.dart`
- Impact: Dead-code accumulation; removal would break the build without updating callers.
- Fix approach: Migrate the three remaining callers to the canonical types, then delete the file.

---

## Known Bugs

**BUG-02 — Modbus response byte-count mismatch returns `requestRxFailed` silently:**
- Symptoms: If a Modbus device returns a response PDU with a byte count field that does not match the expected size, the request returns `requestRxFailed` without retrying or logging at error level (only `ModbusAppLogger.warning`).
- Files: `packages/modbus_client/lib/src/modbus_request.dart:84–93`
- Trigger: Real Modbus devices that send padded responses.
- Workaround: None currently. The warning is logged but callers see a failed request.

**BUG-03 — Unit ID validation in MBAP header:**
- Symptoms: Mismatched unit ID in response MBAP header (byte 6) triggers a warning. Behavior after mismatch is not fully specified.
- Files: `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart:419`
- Trigger: Modbus gateways that rewrite unit IDs in responses.

**BUG-01 — Modbus address validation not enforced at write path:**
- Symptoms: Invalid Modbus register addresses (out of 0–65535 range) are not rejected by `ModbusClientWrapper` before sending, relying on test coverage only.
- Files: `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart:2685–2700`
- Trigger: Config JSON with out-of-range addresses silently sends invalid packets.

**Gate visual issues — diverter concave/straight edge may be swapped:**
- Symptoms: Memory note from 2026-03-07 records that the user reported "wrong edge is straight" for the pneumatic diverter. The current painter has `GateSide.left = concave top`, but the original intent may have been `left = straight top`.
- Files: `lib/page_creator/assets/conveyor_gate_painter.dart:114–196`
- Trigger: Visible whenever a pneumatic diverter is placed in a live page.
- Workaround: User adjusts `side` setting manually.

**Gate animation direction identical for both sides (diverter):**
- Symptoms: Memory note records that when `GateSide.right`, the diverter should animate in the opposite direction. Current code applies the same `progress.value` scaling regardless of side; only the `dir` (drawing direction) flips.
- Files: `lib/page_creator/assets/conveyor_gate_painter.dart:145–151`
- Trigger: Right-hinged pneumatic diverter animates in the same rotational direction as left-hinged.

**`viewtheme.dart` TextField hardcoded to `'ERROR!'` string:**
- Symptoms: The theme preview page shows a TextField pre-filled with `'ERROR!'` and a label that says `'This should be in error TODO'`. This is a placeholder that was never completed.
- Files: `lib/pages/viewtheme.dart:54–58`
- Trigger: Opening the View Theme page.

---

## Security Considerations

**No security concerns identified that are not already mitigated.**
- OPC UA uses configurable security modes and certificate-based auth (`packages/tfc_dart/lib/core/state_man.dart`).
- Postgres connections use configurable SSL mode via `DatabaseConfig.sslMode`.
- Credentials are not stored in source files; config is loaded from external YAML/JSON.

---

## Performance Bottlenecks

**`collector.dart` — `unawaited(insertValue(value))` with no backpressure:**
- Problem: Every OPC UA value emission fires a PostgreSQL insert without awaiting. Under high-frequency signals, pending async inserts accumulate unboundedly.
- Files: `packages/tfc_dart/lib/core/collector.dart:177–178`
- Cause: The intentional "fire and forget for better performance" trades correctness for throughput.
- Improvement path: Add an insert semaphore or use the existing `sampleInterval` throttling for high-frequency keys.

**`database_drift.dart:786` — emoji `print()` in query path:**
- Problem: `print('⏱️  tableQuery: Query execution took ${duration.inMilliseconds}ms')` is a bare `print()` call in the production query path, not behind a flag.
- Files: `packages/tfc_dart/lib/core/database_drift.dart:786`
- Cause: Debug instrumentation left in production code.
- Improvement path: Replace with `logger.d(...)` or remove.

**`collector.dart:297` — `print("throttling rtStream...")` in stream setup path:**
- Problem: `print("throttling rtStream for ${entry.sampleInterval}")` emits to stdout every time a throttled stream is configured.
- Files: `packages/tfc_dart/lib/core/collector.dart:297`
- Cause: Debug statement not removed.
- Improvement path: Replace with `logger.d(...)`.

**`beckhoff.dart` (2198 lines) and `history_view.dart` (1812 lines) — oversized widgets:**
- Problem: Large single-file widgets rebuild expensive subtrees together and cannot be lazy-loaded.
- Files: `lib/page_creator/assets/beckhoff.dart`, `lib/pages/history_view.dart`
- Cause: Incremental feature addition without decomposition.
- Improvement path: Extract independent sections into separate `StatelessWidget`/`ConsumerWidget` classes; use `const` constructors where possible.

---

## Fragile Areas

**`_PendingWrite` retry queue double-trimming:**
- Files: `packages/tfc_dart/lib/core/database.dart:479–492`
- Why fragile: `insertTimeseriesData` trims from the retry queue first, then from the write buffer. `_queueForRetry` also trims. Two separate overflow paths operate on shared mutable lists. Logic is correct but tightly coupled; any future refactor risks re-introducing the Windows datetime-sort bug fixed in commits `cca8fe3` / `7326ed7`.
- Safe modification: Always sort by `seq` (not `time`) before any trim. Cover with a regression test using a tight loop that saturates the 100-item cap.
- Test coverage: `packages/tfc_dart/test/subscription_inactivity_test.dart` indirectly covers this via `data_acquisition_resilience_test`. No dedicated unit test for the trim logic itself.

**OPC UA resubscription — monId collision window:**
- Files: `packages/tfc_dart/lib/core/state_man.dart:980–1005`
- Why fragile: The two-phase cancel-then-create resubscription relies on no `await` between the cancel loop and the create loop so that `runIterate` cannot process sends in between. This is an ordering invariant invisible to future maintainers. A single `await` inserted between the loops would silently break it.
- Safe modification: Add a comment block (already partially present at line 998–1000) and a dedicated integration test that exercises resubscription under concurrent subscription creation.

**`_ConveyorGateState` uses `ref.watch` inside a `StreamBuilder` builder:**
- Files: `lib/page_creator/assets/conveyor_gate.dart:336–340`
- Why fragile: `ref.watch(stateManProvider.future).asStream().asyncExpand(...)` creates a new stream on every build. If the provider rebuilds, the stream is replaced and the subscription restarts, potentially missing values or double-animating.
- Safe modification: Move the stream construction to `initState`/`didChangeDependencies` and store it in a field, then pass the field into `StreamBuilder`.

**Golden tests are macOS-only and not enforced in CI:**
- Files: `test/page_creator/assets/conveyor_gate_golden_test.dart:67`, `test/painter/atv320_golden_test.dart`
- Why fragile: All golden tests are guarded by `skip: !Platform.isMacOS`. If a painter change is made on Linux or Windows, no CI job catches a visual regression. The golden images in `test/page_creator/assets/goldens/` are committed manually.
- Safe modification: Use `flutter_goldens` with a pinned font/renderer, or run golden comparison only in the macOS CI matrix job.

**`subscription_inactivity_test.dart` — misplaced tests:**
- Files: `packages/tfc_dart/test/subscription_inactivity_test.dart:1–5`
- Why fragile: The file's own header says `// TODO: These tests belong in the open62541_dart bindings package`. They test raw OPC UA server/client behavior via a live server. They will break if `open62541_dart` changes internal subscription lifecycle, and there is no way to fix them from within this repo.
- Safe modification: Move them to `open62541_dart` when that package has a test harness, or copy the relevant setup into a dedicated integration test directory.

**`lib/dbus/remote.dart` uses bare `print()` for SSH session progress:**
- Files: `lib/dbus/remote.dart:46–97`
- Why fragile: All SSH connection progress, including authentication status, goes to stdout via `print()`. On embedded Linux (elinux) targets, stdout is often captured by the init system; these messages disappear silently. Errors would be invisible to the logger system.
- Safe modification: Replace all `print()` calls with `logger.i()` / `logger.e()` using the existing `logger` pattern.

---

## Scaling Limits

**Retry queue cap at 100 items per table:**
- Current capacity: 100 pending writes per table (write buffer + retry queue combined).
- Limit: Above 100 items, oldest writes are dropped with a `logger.w` warning. No metric is surfaced to the UI.
- Scaling path: Make `_maxRetryQueueSize` configurable via `DatabaseConfig`; add a provider-level metric so operators can see queue depth.

**Single Postgres connection per `AppDatabase` isolate:**
- Current capacity: One connection via `postgres` package, no connection pooling.
- Limit: Heavy concurrent read+write workloads (history view + collector simultaneously) will serialize on a single socket.
- Scaling path: Use `pg.Pool` from the `postgres` package or `pgvroom`/`pgbouncer` in front.

---

## Dependencies at Risk

**`open62541_dart` pinned to `ref: main` (mutable):**
- Risk: `open62541_dart` (the FFI wrapper for the OPC UA C library) is pinned to `ref: main` in both `pubspec.yaml` and `packages/tfc_dart/pubspec.yaml`. Any breaking change merged to that repo's `main` will silently change the resolved dependency on the next `pub get`.
- Impact: OPC UA connectivity (the core of the entire HMI) can break on CI after an unrelated upstream commit.
- Migration plan: Pin to a commit SHA or a semver tag once `open62541_dart` publishes stable releases.

**`cristalyse` (charting library) pinned to `ref: dev`:**
- Risk: `cristalyse` is pinned to `ref: dev` in `pubspec.yaml`. The `dev` branch is likely unstable.
- Impact: Graph and history-view rendering can regress without a local change.
- Migration plan: Pin to a commit SHA or tag.

**`board_datetime_picker` on a feature branch (`ref: subtitle-for-start-end-date`):**
- Risk: The branch may be rebased or force-pushed by the upstream maintainer.
- Impact: Date picker in scheduler UI breaks silently.
- Migration plan: Merge the needed change upstream or vendor the patch locally.

**`riverpod` / `riverpod_annotation` v2 — generated code emits `@Deprecated` annotations:**
- Risk: Generated `.g.dart` files include `@Deprecated('Will be removed in 3.0. Use Ref instead')`. Migrating to Riverpod 3.0 will require regenerating all providers.
- Files: `lib/providers/alarm.g.dart:22`, `lib/providers/preferences.g.dart:22`, `lib/providers/state_man.g.dart:22`, and others.
- Impact: When Riverpod 3.0 ships, all generated provider files must be regenerated simultaneously. Missing any file will produce compile errors.
- Migration plan: Run `dart run build_runner build` after upgrading; track all `.g.dart` files affected.

**`ExpansionTileController` deprecated since Flutter 3.31:**
- Risk: `ExpansionTileController()` is constructed with a `// todo deprecated since 3.31` comment. Depending on the upgrade path, this API may be removed in a future stable release.
- Files: `lib/widgets/preferences.dart:793`
- Migration plan: Replace with the current recommended `ExpansionTileController.of(context)` pattern.

---

## Missing Critical Features

**No gate top/bottom positioning control in the config editor:**
- Problem: The `ChildGateEntry` records `GateSide` (left/right hinge) but there is no UI control for placing a gate on the top vs. bottom edge of the conveyor. The memory note from 2026-03-07 records the user could not find how to change this.
- Blocks: Conveyor layouts where gates need to appear on both sides of the belt cannot be configured without manually editing raw JSON.

**`Collector` multi-table grouping is unimplemented:**
- Problem: `CollectTable` class is fully commented out. There is no way to group collection entries into separate named tables.
- Blocks: Any deployment that needs separate timeseries tables per machine or per product line.

**Preference deletion does not remove from Postgres:**
- Problem: See Tech Debt section above. Preferences removed at runtime persist in the `flutter_preferences` DB table indefinitely.
- Blocks: Clean factory-reset or reconfiguration workflows.

---

## Test Coverage Gaps

**Gate painters (pneumatic diverter, slider, pusher) — no behavioral unit tests:**
- What's not tested: Paint output is covered by golden snapshots, but no test verifies `shouldRepaint` logic, animation controller disposal, or that `_createPainter` returns the correct painter type for each `GateVariant`.
- Files: `lib/page_creator/assets/conveyor_gate.dart`, `lib/page_creator/assets/conveyor_gate_painter.dart`
- Risk: A `shouldRepaint` regression would cause stale frames silently — no crash, just wrong visuals.
- Priority: Medium

**`Collector.collectStream()` — no test for buffering race between historical load and live events:**
- What's not tested: The `collectStream()` method uses a local `buffer` queue to hold live events arriving while the historical DB query is in flight. No test simulates concurrent historical + live path.
- Files: `packages/tfc_dart/lib/core/collector.dart:287–330`
- Risk: Events arriving during the DB query can be emitted out of order or lost if the buffer is not drained correctly.
- Priority: High

**`_PendingWrite` overflow trimming — no unit test:**
- What's not tested: The per-table trim logic in `insertTimeseriesData` (write buffer + retry queue combined cap) has no dedicated unit test. The Windows CI flake was caught only by an integration test.
- Files: `packages/tfc_dart/lib/core/database.dart:479–492`
- Risk: Future refactors could re-introduce the non-deterministic sort bug.
- Priority: High

**`preferences.remove()` Postgres deletion path — no test:**
- What's not tested: No test verifies that calling `remove()` deletes the row from `flutter_preferences` in Postgres (because the deletion is not implemented).
- Files: `packages/tfc_dart/lib/core/preferences.dart:368`
- Priority: Medium (blocked by the implementation gap above)

**`lib/pages/server_config.dart` sections — no integration tests:**
- What's not tested: The 23 widget classes in `server_config.dart` have no test file. Certificate generation, server card add/remove/edit flows are untested.
- Files: `lib/pages/server_config.dart`
- Risk: UI regressions in the primary configuration screen go undetected.
- Priority: High

---

*Concerns audit: 2026-05-05*
