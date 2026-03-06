---
phase: 4
slug: modbusclientwrapper-connection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test ^1.25.0 |
| **Config file** | packages/tfc_dart/dart_test.yaml (if exists) or none |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` |
| **Full suite command** | `cd packages/tfc_dart && dart test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | CONN-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "connects with host port unitId"` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | CONN-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "status"` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | CONN-02 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "reconnect"` | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | CONN-05 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "multiple"` | ❌ W0 | ⬜ pending |
| 04-01-05 | 01 | 1 | TEST-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` — test stubs for CONN-01, CONN-02, CONN-03, CONN-05, TEST-03
- [ ] Mock factory helper for `ModbusClientTcp` — controllable `connect()` / `isConnected` behavior without real TCP

*Note: `ModbusTestServer` lives in `packages/modbus_client_tcp/test/` and cannot be imported from tfc_dart tests. Phase 4 uses mock factory injection instead. Real TCP integration tests deferred to Phase 5.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
