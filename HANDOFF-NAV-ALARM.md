# Navigation alarm pulse — plant-side diagnosis handoff

> **⚠️ This file is working notes for the follow-up on PR #340. It must be
> DELETED from the branch before the PR is merged.** It contains plant
> addresses and diagnostic commands that do not belong in the repo history.
> Remove with:
>
> ```bash
> git rm HANDOFF-NAV-ALARM.md && git commit -m "chore: drop diagnosis handoff" && git push
> ```

## Where the investigation stands

Reported: an alarm with the navigation switch on, and an Alarm beacon asset
placed on a page, does not pulse the navigation bar (feature from #247,
shipped in v2026.8.23). The page carrying the beacon is nested inside a
section, not top-level.

**The code chain is proven working on `main`.** The test in this PR
(`test/widgets/nav_alarm_end_to_end_test.dart`) runs the real chain —
`BaseScaffold` → `navigationAlarmsProvider` → `RouteRegistry` menu →
`NavDropdown` section badge — with exactly that shape (beacon on
`/baader/overview`, bound by uid, alarm firing after the bar is on screen)
and the section icon lights. Also audited and clean:

- All three alarm-editor form paths persist `navigation_indicator`
  (`lib/widgets/alarm.dart`, `lib/pages/alarm_editor.dart`).
- `AlarmMan.updateAlarm` writes `alarm_man_config` and the provider
  invalidation propagates to the nav provider.
- The page editor replaces `pages` in-place on the same `PageManager`
  instance the nav provider reads, then invalidates it.
- Beacon `alarm_uids` are stored by the picker; alarm uid survives edits.

So the silence is in the plant's **data or the operator flow**, not the
framework. That is what this checklist pins down.

## What to run (from a PC on the plant network)

The HMI's config lives in Postgres on the db host, table
`flutter_preferences (key, value, type)`. From the plant network:

```bash
ssh centroid@10.104.29.111
# then, on the host — psql may be inside the timescale/postgres container:
docker exec -i $(docker ps -qf name=timescale) \
  psql -U centroid -d hmi -Atc \
  "SELECT value FROM flutter_preferences WHERE key='alarm_man_config';" \
  > /tmp/alarm_man_config.json
docker exec -i $(docker ps -qf name=timescale) \
  psql -U centroid -d hmi -Atc \
  "SELECT value FROM flutter_preferences WHERE key='page_editor_data';" \
  > /tmp/page_editor_data.json
```

(If `psql` exists directly on the host, skip the `docker exec` wrapper.
`tools/svn_apply_config.py` locates it the same way.)

## The four checks, in order of likelihood

### 1. Was the operator standing on the beacon's page?

No query for this one — it is flow. The page being viewed **never pulses by
design**, and if it is the *only* alarming page in its section, the section
icon stays quiet too. Verify from a **sibling page or another section**
while the alarm is active.

### 2. Does the alarm really carry the flag?

```bash
jq '.alarms[] | {uid, title, navigation_indicator}' /tmp/alarm_man_config.json
```

Expect `"navigation_indicator": true` on the alarm in question. A missing
key means false — the switch was never saved.

### 3. Does a page really carry a beacon bound to that uid?

```bash
jq 'to_entries[] | {page: .key,
     beacons: [.value.assets[]? | select(.asset_name=="AlarmVisibilityConfig")
               | .alarm_uids]}
    | select(.beacons != [])' /tmp/page_editor_data.json
```

Expect the beacon's `alarm_uids` to contain the uid from check 2 (an empty
list is also fine — it watches every alarm). A uid that matches nothing
means the alarm was recreated after the beacon was bound (uids are
regenerated on create, preserved on edit).

### 4. Staleness across machines

Both `pageManagerProvider` and `alarmManProvider` load **once at app
start**. If the beacon was placed or the switch flipped on machine A, a
station B shows nothing until its app restarts (known limitation, see the
comment in `centroid-hmi/lib/main.dart` near `PageManager.load`). Restart
the viewing station and re-test before concluding anything else.

Also confirm the station actually runs **v2026.8.23 or later** — earlier
builds predate the feature.

## If all four come back clean

Then the framework claim in this PR is wrong for some plant-specific
reason. Capture, while the alarm is active:

```bash
docker exec -i $(docker ps -qf name=timescale) \
  psql -U centroid -d hmi -Atc \
  "SELECT * FROM alarm_history ORDER BY created_at DESC LIMIT 20;"
```

plus the station's stderr log (look for `Alarm stream error:`), and bring
both back to the PR. The e2e test file is the starting point for turning
whatever surfaces into a red test.

---

**Reminder: delete this file before merging the PR.**
