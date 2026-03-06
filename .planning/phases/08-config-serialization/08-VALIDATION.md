---
phase: 8
slug: config-serialization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test ^1.25.0 |
| **Config file** | packages/tfc_dart/dart_test.yaml (if exists) or default |
| **Quick run command** | `cd packages/tfc_dart && dart test test/state_man_config_test.dart` |
| **Full suite command** | `cd packages/tfc_dart && dart test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/state_man_config_test.dart`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | INTG-06 | unit | `cd packages/tfc_dart && dart test test/state_man_config_test.dart --name "ModbusConfig"` | Partially (file exists, tests TBD) | ⬜ pending |
| 08-01-02 | 01 | 1 | INTG-07 | unit | `cd packages/tfc_dart && dart test test/state_man_config_test.dart --name "ModbusNodeConfig"` | Partially (file exists, tests TBD) | ⬜ pending |
| 08-01-03 | 01 | 1 | TEST-06 | unit | `cd packages/tfc_dart && dart test test/state_man_config_test.dart` | Partially (file exists, tests TBD) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.* `state_man_config_test.dart` already has 21 serialization tests for M2400 config — new Modbus groups will be added to this file following the same pattern.

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
