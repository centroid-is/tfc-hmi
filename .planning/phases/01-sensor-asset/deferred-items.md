# Deferred Items — Phase 01 (Sensor Asset)

Items discovered during plan execution that are out-of-scope for the current
plan. Logged here for follow-up.

## From Plan 01-01 (SensorConfig data model)

### Unrelated `.g.dart` drift surfaced by `build_runner`

When running `dart run build_runner build --delete-conflicting-outputs` to
generate `lib/page_creator/assets/sensor.g.dart`, the build_runner also
regenerated two unrelated files whose committed bytes had drifted from what the
current annotations produce:

- `lib/page_creator/assets/conveyor_gate.g.dart` — picked up
  `techDocId` + `plcAssetKey` BaseAsset fields in (de)serialization that were
  not yet reflected in the committed `.g.dart`. The committed bytes round-trip
  correctly today (those fields are nullable and unused), but a future load of
  a saved page that contains those keys would silently drop them under the
  stale generated code.
- `lib/providers/database.g.dart` — Riverpod hash recomputation
  (`_$databaseHash()` value changed). Cosmetic only.

**Why deferred:** These regenerations are not caused by my changes; they're
pre-existing drift from earlier work. Per `<deviation_rules>` SCOPE BOUNDARY,
I leave them uncommitted in this worktree to keep this plan's commits focused
on the sensor data model. Recommend a separate PR that runs build_runner
across the entire repo and commits the resulting drift in one atomic
"chore: regenerate codegen" commit.

**Files left uncommitted in worktree-agent-a3f0c45a:**
- `lib/page_creator/assets/conveyor_gate.g.dart`
- `lib/providers/database.g.dart`

The orchestrator may want to either (a) include this regeneration in a
follow-up bookkeeping commit before merge, or (b) discard the drift and
schedule a dedicated chore PR.
