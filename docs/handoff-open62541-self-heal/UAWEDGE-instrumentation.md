# UAWEDGE instrumentation — reproduce the setup

State as of 2026-08-25 evening. The wedge hunt narrowed hard today; this is
how to run the instrumented build that will name the culprit the next time it
fires, and what is already ruled out.

## Ruled out, with evidence

- NOT the sync service path: 45s+ of healthy 7-server operation produced ZERO
  `svc-wait` lines -- the bindings drive open62541 entirely through the async
  service path. (Also: sendRequest defaults timeoutHint from config.timeout at
  ua_client.c:407, so the 0->unlimited branch cannot fire for our calls.)
- NOT PR 86's send loop: two dumps (pre- and post-PR86) block at the SAME
  select() offsets under UA_Client_run_iterate.
- NOT the eventloop math: pollFDs clamps listenTimeout to the run() budget
  (eventloop_posix.c ~370: dateNext capped by maxDate). A long select means a
  long budget was HANDED IN -- the instrumentation prints it.
- Environment factors already removed on this branch: 1-minute channel
  lifetime (was 10x renewal provocation), and the teardown-reconnect loop's
  connection leak is understood (20+ zombie sockets exhaust the PLC's pool
  and manufacture the "sick server" state; plain Client with 2-3 cycles never
  triggered it).

## The instrumented setup (already wired in this worktree)

1. Both pubspecs depend on `path: C:/Users/Centroid/ob62` (local open62541_dart
   checkout, branch local/instrumented = PR 86).
2. The hook's cached C sources are patched in place under
   `centroid-hmi/.dart_tool/hooks_runner/shared/open62541/build/dl/src`:
   - `src/client/ua_client.c`: `UAWEDGE svc-wait start/end` around the
     synchronous service wait (type id, budget, status, waited ms).
   - `arch/posix/eventloop_posix.c`: `UAWEDGE select long listenTimeout=Nms`
     whenever a select is asked to sleep > 2s.
   - both files gained `#include <stdio.h>`; all lines fflush(stderr).
   The hook reuses this source dir, so `flutter build windows --release`
   recompiles the patches. Verify with:
   `grep -c UAWEDGE build/windows/x64/runner/Release/open62541.dll` (expect 3).
3. LAUNCH WITH STDERR CAPTURED -- native stderr is lost on console-less
   launches (the #337 gap), so Explorer launches swallow the evidence:
   `Start-Process cmd -WorkingDirectory $rel -ArgumentList '/c', "$rel\centroidx.exe 2> C:\Users\Centroid\wt0\repro\uawedge.log"`

## Reading the verdict at the next wedge

- `UAWEDGE select long listenTimeout=N` lines -> the native eventloop was
  handed an N-ms budget; walk up from el->run(timeout) callers with that
  number in hand.
- Wedge with ZERO UAWEDGE lines -> the native layer is innocent; the
  starvation lives in the Dart isolate's own message/timer handling
  (lib/src/isolate.dart) -- profile the isolate handler next.
- Either way, procdump + the WinDbg-package cdb are on the station
  (`repro/procdump.exe`, WinDbg appx) -- dump while wedged, `~*k`, look for
  the select site's neighbours.

## Also banked

- Dumps: `repro/wedged-20816.dmp` (pre-PR86), `repro/wedged-pr86-21652.dmp`,
  stacks in `repro/stacks*.txt`.
- 3.5h healthy no-isolate control run: scratchpad `no-isolate-3.5h-run.log`.
- Escape hatch for the wall: `CENTROID_OPCUA_NO_ISOLATE=1` (plain Clients,
  proven stable, UI jank during handshakes).
