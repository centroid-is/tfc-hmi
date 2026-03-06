---
phase: 6
slug: modbusclientwrapper-writing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test ^1.25.x |
| **Config file** | packages/tfc_dart/dart_test.yaml (if exists) or none |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` |
| **Full suite command** | `cd packages/tfc_dart && dart test` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | WRIT-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "coil write"` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | WRIT-02 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "holding register write"` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | WRIT-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "multi-register write"` | ❌ W0 | ⬜ pending |
| 06-01-04 | 01 | 1 | WRIT-04 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "multi-coil write"` | ❌ W0 | ⬜ pending |
| 06-01-05 | 01 | 1 | WRIT-05 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "read-only"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements:
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` — already has MockModbusClient, createWrapperWithMock helper, connection/read test groups
- Write test groups will be added to existing file following same patterns
- No new test infrastructure needed

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
