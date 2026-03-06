---
phase: 5
slug: modbusclientwrapper-reading
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test ^1.25.0 |
| **Config file** | packages/tfc_dart/dart_test.yaml (concurrency: 1) |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` |
| **Full suite command** | `cd packages/tfc_dart && dart test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | TEST | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` | ✅ extends | ⬜ pending |
| 05-01-02 | 01 | 1 | READ-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "coil" -r compact` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 1 | READ-02 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "discrete" -r compact` | ❌ W0 | ⬜ pending |
| 05-01-04 | 01 | 1 | READ-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "holding" -r compact` | ❌ W0 | ⬜ pending |
| 05-01-05 | 01 | 1 | READ-04 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "input register" -r compact` | ❌ W0 | ⬜ pending |
| 05-01-06 | 01 | 1 | READ-05 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "data type" -r compact` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 1 | READ-07 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "poll group" -r compact` | ❌ W0 | ⬜ pending |
| 05-02-02 | 02 | 1 | READ-06 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "coalesce" -r compact` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Extend `MockModbusClient` in test file with `send()` override and configurable response handler
- [ ] Add test group stubs for READ-01 through READ-07 in existing `modbus_client_wrapper_test.dart`
- [ ] No new test infrastructure files needed -- all tests extend existing file and mock

*Existing infrastructure covers framework and config. Wave 0 extends mock and adds test stubs.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
