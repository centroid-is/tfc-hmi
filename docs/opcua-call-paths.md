# OPC UA failure call paths — Dart bindings and open62541 C

**Status:** verified against live incidents on 10.104.60.83, 2026-08-26, running
`open62541` (dart) 1.5.7+2 with its vendored open62541 C sources. Companion to
`docs/opcua-frozen-session-repro.md` (PR #345). Line numbers refer to the pub-cache
copy of `open62541-1.5.7+2` and the C tree the build hook downloads
(`.dart_tool/hooks_runner/shared/open62541/build/dl/src`).

The point of this document: when values freeze again, the on-call person should be
able to go from a log line to the exact code path in minutes, not hours.

---

## Path 1 — the monId=0 race (boot-time `Error converting data for: null` flood)

**Symptom:** at connect, one giant stderr line repeating
`Error converting data for: null to type DynamicValue: Null check operator used on a
null value` (the writes carry no newline, so hundreds of errors concatenate into ONE
docker-log line — `grep -c` undercounts massively).

**Verified mechanism:**

1. C `MonitoredItem_createBegin` (`ua_client_subscriptions.c` ~555) inserts the
   monitored item into the client's dispatch tree **at request time**, keyed by
   `clientHandle`, with the data callback already wired. `mon->monitoredItemId`
   is left **0**; it is only filled by `MonitoredItem_createFinish` when the
   CreateMonitoredItemsResponse is processed.
2. The server (Beckhoff) can put a PublishResponse carrying the initial values on
   the wire before the client has processed the create response. C
   `processDataChangeNotification` (~1476) then finds the item by `clientHandle`
   — that lookup succeeds — and invokes the Dart callback with
   `monId = mon->monitoredItemId` = **0**.
3. Dart `client.dart:1324`: `monIdToNodeAndAttribute[monId]!` — the map is only
   populated in the create-response callback (`client.dart:1487`), and never with
   key 0. The `!` throws; the catch at 1387 stderr-writes one error per item.

**Fix direction (bindings PR):** identify items by something that exists at
request time. Either pass a per-item context (`monContext`, which C hands to the
callback) holding the node+attribute, or key the Dart map by `clientHandle`
(requires plumbing the handle out). Guarding `[monId]` for null merely silences
the flood — the initial values are still lost.

---

## Path 2 — iterate-death → half-reconnect zombie (deterministic on baader/.74)

**Symptom sequence (3/3 boots today):** session activates, items create, data
flows for ~1 s, then:

    info/client   Client Status: ChannelState: Closing, SessionState: CreateRequested, ConnectStatus: BadSecurityChecksFailed
    error/client  Processing the message returned the error code BadInvalidState
    [endpoint] runIterate failed, stopping event loop

then a reconnect that reaches `UA_SECURECHANNELSTATE_OPEN` with
`UA_SESSIONSTATE_CLOSED` — and **zero further log lines for that endpoint,
forever**. Channel renewals for other endpoints continue; this one never renews.

**Verified C chain:**

1. The baader Beckhoff advertises EndpointUrl `opc.tcp://centroid-baader-beckhoff:4840`
   while we connect to `opc.tcp://10.104.60.74:4840`. That hostname resolves
   nowhere (host or container). After GetEndpoints, `ua_client_connect.c` ~1474
   and ~1487: endpoint mismatch (SecurityMode/Policy, then discoveryUrl vs
   endpointUrl) → `closeSecureChannel` + reconnect with the advertised URL in the
   HEL. (TCP still dials the IP, so an `extra_hosts` mapping alone does NOT fix
   it — tried live, no change.)
2. During the second handshake a message fails processing with
   BadSecurityChecksFailed. `ua_client_connect.c` ~2228: if this happens **before
   the channel is OPEN**, the comment says it plainly — *"the client cannot
   recover"* — and `setConnectStatus(client, res)` latches the fatal status.
3. Every subsequent request returns BadInvalidState; in the bindings' isolate
   (`isolate.dart`, RunIterateMessage handler) `client.runIterate()` returns
   false → the iterate Timer cancels → `runIterate()`'s future errors → tfc_dart's
   per-client loop catches, disconnects, sleeps 1 s, and retries.
4. The retry gets a channel to OPEN but the session is never re-created: the
   loop's `connect()` is fired **un-awaited** (`state_man.dart` per-client loop),
   so its failure only logs; `runIterate()` then parks forever against a client
   whose connectStatus is latched fatal. Zombie: socket Established, channel
   formally open, no session, no retry, no log lines.

**Fix directions:**
- Bindings: a `runIterate` death must reset the client (or recreate it) before
  the next connect — a latched fatal `connectStatus` must not survive into the
  retry loop. `connect()` must be awaited/bounded (also PR #345's list).
- Plant config option: set the baader endpoint in server config to the
  advertised hostname URL (now resolvable in the flutter container via
  `extra_hosts`) so the endpoint-switch reconnect never fires at all. Untested.

---

## Path 3 — Inactivity: birth in C, storm in Dart

**C origin, two triggers** (`ua_client_subscriptions.c`):
- ~1686: a PublishResponse comes back `BadTimeout` → `subscriptionInactivityCallback`.
- ~1792 `__Client_Subscriptions_backgroundPublishInactivityCheck`: no publish
  response within the expected window → same callback.

**Dart propagation:** the bindings surface it as
`config.subscriptionInactivityStream` → per-monitoredItems listener
(`client.dart:1426`) → `controller.addError(Inactivity())` → every key stream
attached to that subscription gets `raw stream error: Instance of 'Inactivity'`
→ tfc_dart heartbeat `onError` sets `_inactive = true` (`state_man.dart`,
heartbeat listener); recovery happens when the next heartbeat tick calls
`_handleRecovery`.

**The storm shape** (latest-release, 03:59Z and 06:33Z today): the callback fires
continuously (~17/s across all servers) while every socket stays Established and
values are frozen; recovery never comes. The PR #346 branch calibrates the
inactivity test to the bindings' bounded timeouts. On 1.5.7+2 we observed the
healthy version of this machinery: a 193-error burst over 3 s, then "Heartbeat
recovered" everywhere — transient network hiccup, correctly self-healed.

---

## Path 4 — the silent frozen session (PR #345, still the worst case)

No error, no event, nothing: `runIterate()`'s future only completes when
`client.runIterate` returns false, so a session that dies while iteration keeps
"succeeding" parks the caller forever (`isolate.dart` RunIterateMessage handler;
`state_man.dart` per-client loop). TCP Established, channel renewing, values
frozen. Not detectable from logs at all today.

**Mitigations in flight:**
- UI: PR #355 derives server health from heartbeat age on a 2 s timer — the chip
  drops to deep-orange "No data" within ~17 s of silence instead of showing green
  forever. (Channel renewals were verified NOT to be a liveness signal: a
  session-dead client on .83 kept renewing its channel today.)
- Next (bindings/tfc_dart): the same heartbeat-age signal should drive an
  automatic teardown-and-reconnect watchdog, converting every variant of this
  bug into a logged blip. PR #345's list has the isolate-level requirements.

---

## Reproduction campaign (running now on 10.104.60.83)

- Cron `*/15`: `/home/centroid/hmi-debug/cycle.sh` — archives the current boot's
  container logs (gzip, 3-day retention), detects wedges (per-endpoint missing
  heartbeat start, `runIterate failed`, inactivity storm >100/2 min), captures
  `gdb thread apply all bt` (host-side, sudo) + `/proc/net/tcp` on detection,
  then restarts the container. Kill switch: `touch /home/centroid/hmi-debug/DISABLED`.
- `wedges.log` / `endpoint-ages.log` / `cycle.log` in `/home/centroid/hmi-debug/`.
- First cycle already caught the baader zombie: `10.104.60.74(no-heartbeat)
  iterate-death(x1)`.
- Why restarts: every observed failure initiates at connect/renewal boundaries;
  each restart is another roll of those dice, with full evidence retained.
- Jon's field observation: freezes appear more often in Flutter **release**
  builds. Consistent with a timing race (all four paths above are
  ordering-sensitive), not yet tied to a specific mechanism.

## Alias map (log forensics, .83)

`st101=.71  st201=.72  st301=.73  baader=.74  speedbatcher1-3=10.104.29.91-93`.
Key names in app logs (`ST201.section.*`) name the *key's* server; interleaved
open62541 lines (`info/client`, `warn/client`) carry **no endpoint** — never
attribute them by adjacency. The Dart-side lines with `[opc.tcp://…]` prefixes
are the trustworthy ones.
