# Handoff: open62541_dart ClientIsolate self-heal

For whoever has push rights on centroid-is/open62541_dart -- the plant PC's
token got 403. Everything needed is in this folder.

## Confirmed root cause (clean-channel evidence, bench 2026-08-25 ~12:39)

Side-channel probe (immune to the hmi.log corruption) on a from-source build:

    [WD st301] age=530.4 sub=2242791693 s=null c=null

- s/c null = `ClientIsolate.state` timing out (5s bound) on EVERY poll: the
  isolate stopped answering messages entirely.
- age 530s = no data or heartbeat for ~9 minutes (the freeze the operator sees).
- tfc's watchdog null-path did `continue` forever -- and could not do better:
  even `disconnect` is a message the wedged isolate never processes. NOTHING
  that works through the isolate can recover it.
- Only secured (SignAndEncrypt + user/pass) servers wedge; the three anonymous
  speedbatchers never have. The wedge is almost certainly a blocking native
  call on the dead secured socket.
- Cadence detail that hid this for three diagnostic rounds: the vitals probe
  printed every 120 polls; healthy polls take 250ms (30s cadence), timed-out
  polls take 5s (~10 MINUTES cadence), so dead servers all but vanished from
  the logs.

## The fix (bindings): abandon-and-respawn

`isolate_self_heal_test.dart` in this folder is a ready failing test -- drop it
into open62541_dart/test/ (it uses test/common.dart's addBasicVariables and
intNodeId). It drives this API:

- `keepConnected(url, ..., {Duration? unresponsiveTimeout})` -- when set, the
  supervisor pings the isolate (a trivial PingMessage answered immediately in
  the isolate's message loop). ~3 consecutive missed pings within the timeout
  window => respawn.
- Respawn semantics:
  - Old isolate: `receivePort.close()`, `Isolate.kill(priority: immediate)`
    BEST EFFORT -- an isolate blocked in a native call only dies when that
    call returns. Do not wait for it; abandon it (leaks one thread per
    occurrence, which beats a frozen plant).
  - All `_pendingRequests` complete with a new
    `ClientIsolateRespawnedException` (callers retry).
  - Monitored-item stream controllers get that error and close: their native
    subscriptions died with the old isolate; the error is what makes tfc's
    resubscribe ladder fire.
  - STATE streams survive as objects: tfc listens once at construction and
    never again. Track which streamController ids are state streams; after the
    new isolate is up, re-send `StateStreamMessage(id)` for each so the same
    controllers keep emitting.
  - Re-arm keepConnected on the new isolate with the stored url/params -- the
    session then reconnects and tfc's Session-lost machinery resubscribes keys.
- `debugWedgeIsolate(Duration)` @visibleForTesting -- sends a message whose
  handler busy-blocks the isolate event loop (`while (DateTime.now()...)`),
  simulating the native wedge; killable in tests, unlike real FFI.
- Plumbing this requires: `_isolate/_sendPort/_receivePort/_initCompleter`
  become reassignable (they are `late final` today); the spawn parameters get
  stored (e.g. a `_IsolateData Function(SendPort)` closure) so respawn can
  reuse them; `_handleMessage`'s SendPort branch must tolerate re-init
  (`if (!_initCompleter.isCompleted) complete()`).

Production default: leave unresponsiveTimeout null (opt-in) OR default ~15s;
tfc will pass its supervision config either way.

## Already in flight elsewhere

- tfc side (this branch): a cloud agent is building
  `agent/watchdog-null-escalation` -- WatchdogUnresponsiveTracker so the
  null-poll state is loudly reported + time-based vitals cadence. Review and
  merge into this branch when it lands.
- After the bindings release: bump the pin in centroid-hmi/pubspec.yaml +
  packages/tfc_dart/pubspec.yaml, and pass `unresponsiveTimeout` from
  StateMan's supervision config in the keepConnected call
  (packages/tfc_dart/lib/core/state_man.dart, ClientIsolate branch).
- Bench verification recipe: build release, launch VIA EXPLORER (shell
  launches mask the bug), plant FIN wave hits secured servers at ~+7 min;
  success = values resume on their own. The plant PC can run this on request.

## Separate issue discovered, do not lose

`%LOCALAPPDATA%\centroid-hmi\logs\hmi.log` has TWO writers on console-less
launches since #337 (the C++ append handle AND the Dart writer) and they
clobber each other's lines -- absence of a line proves nothing, which cost
three diagnostic rounds today. Needs its own fix (single owner, or both
handles atomic-append with no buffered rewrites).
