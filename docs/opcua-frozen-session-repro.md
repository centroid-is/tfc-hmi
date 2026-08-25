# Repro notes: OPC UA sessions freeze on live sockets, values stop updating

**Status:** reproduced twice on the plant test station (SVN-NES-OT-CL02),
2026-08-25. Not fixed. These notes are for reproducing it elsewhere and for
aiming the upcoming robustness work in the open62541 bindings.

## Symptom

Values from some OPC UA servers freeze in the HMI while the process keeps
running. Per server, not global: in the second occurrence ST301's server kept
updating while ST201's was frozen, both with healthy-looking connections.
A restart of the app clears it (until it happens again).

## Hard evidence, second occurrence (app pid 16420, started 08:16:13)

- `Get-NetTCPConnection` for the process at 08:18: sockets to 10.104.60.71,
  .72, .73 and 10.104.29.91, .92, .93 all **Established** -- and
  10.104.60.74 **absent** from the table entirely.
- The ONLY channel transition in the log this run:

      [opc.tcp://10.104.60.74:4840] SecureChannel state:
        UA_SECURECHANNELSTATE_OPEN -> UA_SECURECHANNELSTATE_CLOSING
        (session: UA_SESSIONSTATE_CREATE_REQUEST)

- No "Failed to connect", no "run iterate error", no disconnect lines. The
  reconnect machinery never fired because nothing ever surfaced as an error.
- Freeze landed ~2 minutes after start. `secureChannelLifeTime` is pinned to
  **1 minute** (state_man.dart, with the comment
  `TODO can I reproduce the problem more often`), so the first renewal
  boundary is at ~60s. The first occurrence (app started 07:57) froze the
  whole 10.104.60.7x group the same way: sockets Established, zero log lines
  for those endpoints, no retries, for over an hour.

So: **TCP up, session dead, no error surfaced, no reconnect.** Frozen values
on live sockets.

## Where the code lets this happen

`packages/tfc_dart/lib/core/state_man.dart`, isolate branch of the per-client
loop:

```dart
while (_shouldRun) {
  try {
    clientref.connect(wrapper.config.endpoint).onError((e, st) =>
        logger.e('Failed to connect ...'));   // fired, NOT awaited
    await clientref.runIterate();             // parks forever while "healthy"
  } catch (error) { ... disconnect, 1s, retry ... }
}
```

`open62541_dart/lib/src/isolate.dart`, `RunIterateMessage` handler:

```dart
iterateTimer = Timer.periodic(message.timeout, (timer) {
  if (!client.runIterate(message.timeout)) {
    iterateTimer?.cancel();
    sendPort.send(IsolateResponse.error(...));  // the ONLY completion path
  }
});
```

Two consequences:

1. `runIterate()`'s future completes **only if `client.runIterate` returns
   false**. Any failure mode where iteration keeps returning true against a
   dead session -- e.g. a channel renewal that wedges, or a session that dies
   while the channel stays formally open -- never completes the future, never
   throws, never reaches the reconnect path. The caller waits forever and the
   UI shows the last values.
2. `connect()` is not awaited, so a connect that stalls inside the isolate
   (open62541's connect is blocking FFI there) leaves the iterate timer
   running against a client that never finished connecting -- same silence.

The `.74` log line is the smoking gun for a third shape: channel went
OPEN -> CLOSING **while the session was still in CREATE_REQUEST**, i.e. the
1-minute channel lifetime expired mid-session-creation and nothing retried.

## Reproducing

1. Config with several OPC UA servers (the plant has 7; more clients = more
   renewal races per minute).
2. `secureChannelLifeTime` already at 1 minute -- leave it; that is the
   provocation.
3. Run, wait 1-3 renewal boundaries (1-3 minutes), watch for a server whose
   values stop while `Get-NetTCPConnection` still shows Established:

   ```powershell
   $p = Get-Process centroidx | Select-Object -First 1
   Get-NetTCPConnection -OwningProcess $p.Id | ? RemotePort -eq 4840 |
     Sort-Object RemoteAddress | % { "$($_.RemoteAddress) $($_.State)" }
   ```

4. The tell: frozen station + Established socket + **no** error/disconnect
   lines in `%LOCALAPPDATA%\centroid-hmi\logs\hmi.log` for that endpoint.
   (Log capture on console-less launches works as of #337.)

Both occurrences here were on the MSIX build launched from the Start menu, but
nothing in the mechanism is packaging-specific; yesterday's portable run from
a shell went a full day without it, which may just be renewal-race luck.

## What the robustness work in the bindings should cover

- `runIterate()` must be able to fail for a *dead session*, not only a dead
  iterate: watch the session state (or channel renewals) inside the isolate
  and complete the future with an error when the session leaves ACTIVATED and
  does not come back within a bound.
- `connect()` should be awaited (or bounded): the caller's loop must not park
  on `runIterate()` before a connection exists.
- A channel expiring while the session is still CREATE_REQUEST (the `.74`
  line) needs an explicit retry rather than silence.
- Watchdog worth having regardless of the root cause: per client, if no
  monitored-item update AND no successful keepalive for N seconds while the
  socket is Established, tear down and reconnect. That converts any variant of
  this bug from "frozen until an operator notices" into a logged blip.

## REPRODUCED from source, 2026-08-25 08:32

Release build of main (937979c0) built on the station, launched via Explorer
(the plant condition: no console, no inherited handles). The permanent-dead-
client shape reproduced **1.9 seconds after startup**, first try:

    08:32:30.241  [.74] SecureChannel OPN_SENT -> OPEN     (+0.87s)
    08:32:30.242  [.74] Channel opened
    08:32:31.227  [.74] SecureChannel OPEN -> CLOSING, session UA_SESSIONSTATE_CREATE_REQUEST  (+1.86s)
    -- and .74 never appears in the log again. No retry, no reconnect.

So this shape is NOT the 1-minute renewal: the channel died 0.98s after
opening, during session creation, and the client is permanently dead from
t=+2s with zero further log lines. The reconnect loop never fires, exactly
as predicted from the code: `client.runIterate` keeps returning true for a
session-less client, so the `runIterate()` future never completes and the
caller never reaches its catch/retry.

Launch-mode sensitivity, observed twice: the same binary launched from a
shell (inherited stdout handles) held .74 Established; launched via Explorer
it lost .74 both times. Something about the plant launch mode changes the
odds of losing the session-create race -- worth keeping the Explorer launch
as the repro condition.

The second shape -- a client with an Established socket freezing later (the
ST201 case) -- has not yet been caught under instrumentation; the watch is
socket table + channel/session log lines every 15s. The .74 capture already
demonstrates the core defect the bindings work must fix: a client failure
that never completes `runIterate()` is invisible and permanent.

### Second shape captured, same run, 08:39 (+7 min)

Operator report: ST101 frozen. Socket table at that moment:

    10.104.60.71  Established     <- the reported-frozen station's server
    10.104.60.72  CloseWait       <- server sent FIN; client never closed its side
    10.104.60.73  CloseWait       <- same
    .91/.92/.93   Established

`CloseWait` is the tell: the SERVER closed the connection, and the client has
sat on the half-closed socket since -- no close, no log line, no reconnect.
Across the entire run there is not a single log line for .71/.72/.73: no
channel transitions, no errors. Only .74's two lines exist.

So both shapes are one defect: nothing surfaces "session/connection died" to
the reconnect loop. Dies at session-create (+2s, the .74 case) or the server
hangs up later (CloseWait case) -- either way `client.runIterate` keeps
returning true, the `runIterate()` future never completes, and the retry path
never runs. The UI shows the last values indefinitely.

Repro reliability so far: one Explorer launch of a from-source release build
produced BOTH shapes within 7 minutes, against live plant servers.
Log snapshot at the freeze: `repro/hmi-at-st101-freeze.log` on the station.

## Artifacts

On the test station, session scratchpad `log-backup-081006/` (first
occurrence: logs + connection table) and `log-backup-frozen-081910/`
(second occurrence, caught live: hmi.log at freeze + connections showing
Established sockets and the missing .74).
