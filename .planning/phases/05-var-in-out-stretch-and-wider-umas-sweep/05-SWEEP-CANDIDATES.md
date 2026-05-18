# SWEEP-01 candidate discovery

8 candidates surfaced. Triage in `05-SWEEP-TRIAGE.md`.

---

## C-01 — UMAS error messages lack sub-function context

**Failure mode.** Every error site builds messages like `"UMAS init
failed: ..."`, `"UMAS writeVariable failed: ..."`, but
`_checkStatus()` reports only `"UMAS readDataTypes error: 0x..."`.
The `_checkStatus(pdu, 'writeVariable')` style only includes the
op-name when the call site passes one. Several sites pass terse
operation names ("readDD02(blockNo=0x...)", "readDataTypes") while
others use the generic "init failed". Operator-facing logs cannot
always tell which path the error came from.

**Evidence (code).** `packages/tfc_dart/lib/core/umas_client.dart`
lines 317-336 (`_checkStatus`); error sites at 351-353, 413-414,
649-651, 700-702, 810-812, 917-918, 1010-1011, 1044-1045, 1100-1107,
1132-1138, 1238-1240, 1344-1348, 1402-1410, 1432-1440.

**Effort.** S — one line per call site to ensure each
`UmasException` message includes a stable operation token.

**Risk if not fixed.** Triage time on operator-reported errors grows
unbounded; we can't search logs by sub-function.

**Recommendation.** ACCEPT v1.1 as **SWEEP-03**.

---

## C-02 — `_handleSessionError` does not clear `_projectCrc`

**Failure mode.** On a PLC reboot, the pairing key is invalidated and
`_handleSessionError()` clears `_pairingKey`, `_hardwareId`,
`_index`, `maxFrameSize`, `_previousCrcs`, `_hasReservation`,
`_useMonitorPlc`, and `_monitorTable`. It does NOT clear
`_projectCrc`. If the PLC is reprogrammed during the reboot (common
in dev / commissioning), the next `readVariable`/`writeVariable`
will send a stale `_projectCrc` which then either succeeds against
the wrong project (silent data corruption risk) or returns an error
that we attribute to the wrong cause.

**Evidence (code).** `umas_client.dart:1165-1176` clears 8 fields
but `_projectCrc` is set elsewhere (lines 1217-1218, 1330-1331,
`_readProjectInfo` path) and is not in the reset list. Search:
```
$ grep -n "_projectCrc" packages/tfc_dart/lib/core/umas_client.dart
```
Found 4 read sites, 1-2 write sites, **zero** clear sites.

**Effort.** S — one line: `_projectCrc = null;` in
`_handleSessionError`.

**Risk if not fixed.** Latent — but the *commissioning* scenario
(reboot during programming changes) is the most common dev
environment. Real-customer data-corruption probability is low (PLC
rejects with CRC mismatch in practice), but the noise on dev/CI
sessions is high.

**Recommendation.** ACCEPT v1.1 as **SWEEP-04**.

---

## C-03 — `_maxWriteVariableRefs = 255` cap silently drops trailing refs

**Failure mode.** Caller submits 300 writes in one batch:
`writeVariable()` sublist-truncates to 255 (`umas_client.dart:1321-1323`)
and proceeds without a warning. The caller's Future resolves
successfully even though writes 256-300 never reached the PLC.

**Evidence (code).** `umas_client.dart:1300-1323`:
```dart
final cappedRefs = refs.length > _maxWriteVariableRefs
    ? refs.sublist(0, _maxWriteVariableRefs)
    : refs;
```
No log, no exception, no error return. Same anti-pattern in read
(line 1212).

**Effort.** S — emit `_log.w()` when truncation happens. Optionally
throw `UmasException` with a clear message.

**Risk if not fixed.** Silent data loss in batch-write scenarios.
Trivial to hit when iterating a tree of FB members.

**Recommendation.** ACCEPT v1.1 as **SWEEP-05**.

---

## C-04 — MonitorPlc 0x50 vs ReadAll 0x22 STRING divergence

**Failure mode.** STRING reads through 0x50 (MonitorPlc) fail with
the underflow bug fixed in Phase 1. STRING reads through 0x22
(ReadVariable, single ref) use the DSI=3 clamp at
`umas_types.dart:411-414` and succeed. The two paths have different
size-handling code that has drifted.

**Evidence (code).** `umas_types.dart:411-414` (0x22 clamp wide
types to 4 bytes via DSI=3); `umas_types.dart:1232-1237` (0x50
advances offset by full declared byte size — the underflow bug).
Phase 1 plans to add the clamp to the 0x50 path, restoring parity.

**Effort.** S — already in Phase 1's scope.

**Risk if not fixed.** Already addressed by Phase 1.

**Recommendation.** Already covered by Phase 1; no new SWEEP-XX
needed.

---

## C-05 — Monitor-job lifecycle under PLC reboot

**Failure mode.** When the PLC reboots mid-monitor, the pairing key
is invalidated. `_handleSessionError` correctly calls
`_monitorTable.reset()`, but the user-facing layer (e.g.
`ModbusDeviceClientAdapter`) does NOT re-register the variables
after the session re-pairs. The monitor stays empty until a fresh
`monitorRegisterAndRead` call. Symptom: tag values appear "frozen"
in the HMI for some recovery window.

**Evidence (code).** `umas_client.dart:1173-1174` resets
`_monitorTable`, but the adapter at
`modbus_device_client.dart` (not inspected in depth in this phase)
needs to listen for state transitions back to `paired` and
re-register. No such listener observed in a `grep` for
`UmasSessionState` consumers outside `umas_client.dart`.

**Effort.** M — adapter-side recovery wiring + test fixture for
"PLC reboot mid-monitor".

**Risk if not fixed.** Visible to operators; recovery window varies
with read cadence. NOT a data-loss issue (next register cycle
recovers).

**Recommendation.** DEFER to v2. Days-timeline + cross-layer change
+ stable workaround (force a re-register on session-state listener)
is enough for v1.1.

---

## C-06 — Retry-queue saturation (database layer, not UMAS)

**Failure mode.** Documented in
`.planning/codebase/CONCERNS.md:243-248` — when DB is down and
writes arrive faster than 100/flush-cycle, oldest entries are
dropped with a `logger.w()`. No UI surfacing.

**Evidence (code).** `packages/tfc_dart/lib/core/database.dart:427`
(`_retryQueue` cap of 100), 658-662 (drop-with-warn).

**Effort.** M — needs UI signal (toast/badge) when drops happen.

**Risk if not fixed.** Operator unaware of data loss during DB
outages.

**Recommendation.** DEFER to v2. Not UMAS-protocol-related, despite
the sweep brief mentioning retry-queue. Outside v1.1's UMAS-hardening
core.

---

## C-07 — Type-variant handling: BYTE_STRING, WSTRING, multi-dim arrays

**Failure mode.** The DSI=3 clamp covers types > 4 bytes generically
but only STRING is tested. BYTE_STRING (Schneider EDT 0x12 in some
firmware variants), WSTRING (UTF-16, 2 bytes per char), and >1-D
arrays may have analogous size-mismatch bugs in
`parseReadAllResponse` and `parseVariableValues`. Live PLC has none
of these declared (only BOOL / INT / DINT / REAL / WORD / STRING
observed), so we have no live evidence either way.

**Evidence (code).** `umas_types.dart:360-414`
(`UmasDataTypes.builtIn` table + `dataSizeIndexFromByteSize`). No
test coverage for BYTE_STRING / WSTRING in
`packages/tfc_dart/test/umas_*_test.dart`. Multi-dim arrays parsed
by `UmasArrayTypeDefinition` (`umas_types.dart:180-203`) — code
supports N dimensions, but the only tested case is 1-D
(`umas_e2e_test.dart:277`).

**Effort.** M — fixture-based tests (would synthesise wire data
without a real PLC), no production code change unless a bug is
found.

**Risk if not fixed.** Unknown — no live evidence. Defensive
coverage only.

**Recommendation.** DEFER to v2. Live PLC does not exercise these
types; cost of test fixtures outweighs benefit within hard
timeline.

---

## C-08 — `_maxReadVariableRefs = 255` cap silently truncates

**Failure mode.** Same anti-pattern as C-03 but on the read path
(`umas_client.dart:1211-1214`). Less impactful (callers see fewer
returned values than requested and can detect), but still silent.

**Evidence (code).** `umas_client.dart:1211-1214`:
```dart
final cappedRefs = refs.length > _maxReadVariableRefs
    ? refs.sublist(0, _maxReadVariableRefs)
    : refs;
```

**Effort.** S — same `_log.w()` pattern as C-03.

**Risk if not fixed.** Detectable by caller (return-value length
mismatch). Lower priority than C-03 (write).

**Recommendation.** Fold into **SWEEP-05** (same fix as C-03 — log
when either cap hits).

---

## Summary table

| # | Title | Effort | Decision | New REQ-ID |
|---|---|---|---|---|
| C-01 | Error messages lack sub-function context | S | Accept v1.1 | SWEEP-03 |
| C-02 | `_handleSessionError` doesn't clear `_projectCrc` | S | Accept v1.1 | SWEEP-04 |
| C-03 | `_maxWriteVariableRefs` silently caps | S | Accept v1.1 | SWEEP-05 |
| C-04 | 0x50 vs 0x22 STRING divergence | S | Already in Phase 1 | — |
| C-05 | Monitor lifecycle under reboot | M | Defer to v2 | — |
| C-06 | Retry-queue saturation (DB) | M | Defer to v2 | — |
| C-07 | BYTE_STRING / WSTRING / multi-dim arrays | M | Defer to v2 | — |
| C-08 | `_maxReadVariableRefs` silently caps | S | Fold into SWEEP-05 | (same) |

**Surfaced:** 8. **Accepted v1.1:** 3 (SWEEP-03, SWEEP-04, SWEEP-05).
**Deferred to v2:** 4. **Folded into Phase 1 / SWEEP-05:** 2 (C-04,
C-08).
