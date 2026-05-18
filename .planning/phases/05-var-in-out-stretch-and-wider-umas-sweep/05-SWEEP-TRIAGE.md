# SWEEP-01 triage

8 candidates → 3 new REQ-IDs accepted into v1.1, 4 deferred to v2, 1
folded into Phase 1's STRING-clamp scope.

The orchestrator will fold the accepted REQ-IDs into
`.planning/REQUIREMENTS.md` Active section during merge.

---

## v1.1 — new requirements

### SWEEP-03 (NEW v1.1 REQ-ID): UMAS error messages include sub-function name

- **Statement.** Every `UmasException` thrown from `umas_client.dart`
  includes a stable operation token (e.g. `"writeVariable"`,
  `"readVariable"`, `"readDD02(blockNo=...)"`) in the message so
  operator logs can be grepped by sub-function.
- **Verified by.** Unit test that hits each public method with a
  fixture that returns a known UMAS error and asserts the message
  contains the operation name.
- **Source.** C-01 in `05-SWEEP-CANDIDATES.md`.
- **Phase.** 5 (this plan).

### SWEEP-04 (NEW v1.1 REQ-ID): Clear `_projectCrc` on session error

- **Statement.** `UmasClient._handleSessionError()` also clears
  `_projectCrc` so a PLC reboot mid-session does not carry a stale
  project CRC into the post-reboot session.
- **Verified by.** Unit test that sets `_projectCrc` via the
  `_readProjectInfo` path, triggers `_handleSessionError`, and
  asserts `_projectCrc` is null.
- **Source.** C-02 in `05-SWEEP-CANDIDATES.md`.
- **Phase.** 5 (this plan).

### SWEEP-05 (NEW v1.1 REQ-ID): Warn on `_maxReadVariableRefs` / `_maxWriteVariableRefs` cap

- **Statement.** When the write-batch (255 refs) or read-batch (255
  refs) cap truncates a request, `UmasClient` logs at warn level
  with the number of dropped refs so operators can detect silent
  truncation.
- **Verified by.** Unit test using a captured `_log` Logger that
  asserts the warning fires when 256+ refs are submitted, and does
  NOT fire at 255.
- **Source.** C-03 + C-08 in `05-SWEEP-CANDIDATES.md`.
- **Phase.** 5 (this plan).

---

## v2 — deferred

### Monitor-job lifecycle under PLC reboot (C-05)

- **Failure mode.** Adapter does not re-register monitor entries
  after `_handleSessionError` resets the table; tag values appear
  frozen until the next deliberate `monitorRegisterAndRead`.
- **Defer rationale.** Cross-layer change (adapter, not just
  driver); v1 has a workaround (force re-register on session-state
  flip); not a data-loss bug; M effort against hard timeline.
- **v2 entry.** `MON-01`: monitor-table recovery after PLC reboot —
  adapter listens for `UmasSessionState.paired` → `uninitialized`
  → `paired` transitions and replays the last-known monitor list.

### Retry-queue saturation UI signal (C-06)

- **Failure mode.** Database-layer drops at 100-entry cap with only
  a `logger.w()` — operator does not see the data loss.
- **Defer rationale.** Not UMAS-protocol-related; UI signal is a
  feature ask, not a hardening fix.
- **v2 entry.** `RETRY-01`: surface retry-queue saturation as a
  UI badge / toast.

### Type-variant handling: BYTE_STRING / WSTRING / multi-dim (C-07)

- **Failure mode.** No evidence of breakage on live PLC (none of
  these declared); defensive coverage gap.
- **Defer rationale.** Live evidence absent; cost of synthesising
  wire-fixtures outweighs benefit within timeline. Open the door for
  v2 once a customer PLC declares these types.
- **v2 entry.** `TYPE-01`: extend `UmasDataTypes` test coverage to
  BYTE_STRING, WSTRING, 2D+ arrays once a customer PLC declares
  them.

---

## Folded into existing scope

### 0x50 vs 0x22 STRING divergence (C-04)

Phase 1 (BUG-01 / BUG-02) already covers this — adding the DSI=3
clamp to `parseReadAllResponse` restores parity with 0x22's
`dataSizeIndexFromByteSize` at `umas_types.dart:411-414`. No new
REQ-ID needed.

---

## Live-PLC pass-rate impact (acceptance for SWEEP-01 sub-criterion 4)

After SWEEP-03/04/05 implementation:

- Baseline before: `35 ok / 0 fail` (this worktree's HEAD = `f9c6df19`).
- After SWEEP-03/04/05: SAME — none of these touch the scalar read
  path, so the live `check 192.168.112.159` pass rate is unchanged.

Verified post-implementation by `dart run packages/tfc_dart/tool/umas_cli.dart check 192.168.112.159 --json`.
