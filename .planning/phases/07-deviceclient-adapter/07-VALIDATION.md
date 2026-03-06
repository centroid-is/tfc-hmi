---
phase: 7
slug: deviceclient-adapter
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | package:test v1.25.0 |
| **Config file** | none (standard dart test runner) |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart` |
| **Full suite command** | `cd packages/tfc_dart && dart test test/core/` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test test/core/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | INTG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart --name "subscribableKeys"` | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | INTG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart --name "canSubscribe"` | ❌ W0 | ⬜ pending |
| 07-01-03 | 01 | 1 | INTG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart --name "subscribe"` | ❌ W0 | ⬜ pending |
| 07-01-04 | 01 | 1 | INTG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart --name "read"` | ❌ W0 | ⬜ pending |
| 07-01-05 | 01 | 1 | INTG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart --name "write"` | ❌ W0 | ⬜ pending |
| 07-01-06 | 01 | 1 | INTG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart --name "connection"` | ❌ W0 | ⬜ pending |
| 07-01-07 | 01 | 1 | TEST-04 | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `packages/tfc_dart/test/core/modbus_device_client_test.dart` — new test file for adapter contract tests
- No framework install needed — `package:test` already in dev_dependencies
- MockModbusClient already exists in `modbus_client_wrapper_test.dart` — can be reused or extracted

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
