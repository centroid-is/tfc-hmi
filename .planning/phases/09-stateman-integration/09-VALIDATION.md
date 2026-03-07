---
phase: 9
slug: stateman-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | package:test v1.25.0 |
| **Config file** | none (standard dart test runner) |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/modbus_stateman_routing_test.dart` |
| **Full suite command** | `cd packages/tfc_dart && dart test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/modbus_stateman_routing_test.dart`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 0 | INTG-02 | unit | `cd packages/tfc_dart && dart test test/core/modbus_stateman_routing_test.dart` | ❌ W0 | ⬜ pending |
| 09-01-02 | 01 | 0 | INTG-03 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-03 | 01 | 0 | INTG-04 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-04 | 01 | 0 | INTG-05 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-05 | 01 | 0 | INTG-08 | unit | same | ❌ W0 | ⬜ pending |
| 09-01-06 | 01 | 0 | TEST-05 | unit | same | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `packages/tfc_dart/test/core/modbus_stateman_routing_test.dart` — stubs for INTG-02 through INTG-08, TEST-05
- [ ] Reuse MockModbusClient and createWrapperWithMock from `modbus_device_client_test.dart`
- [ ] No framework install needed — `package:test` already in dev_dependencies

*Existing infrastructure covers framework requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live Modbus device polling at correct interval | INTG-02 | Requires physical Modbus device or simulator | 1. Connect to Modbus simulator 2. Configure poll group at 2s 3. Verify stream emits values at ~2s intervals |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
