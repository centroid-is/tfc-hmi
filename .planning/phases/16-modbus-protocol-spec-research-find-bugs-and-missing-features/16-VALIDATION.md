---
phase: 16
slug: modbus-protocol-spec-research-find-bugs-and-missing-features
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test (test package) |
| **Config file** | packages/tfc_dart/pubspec.yaml (dev_dependencies: test) |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` |
| **Full suite command** | `cd packages/tfc_dart && dart test test/core/ --reporter compact` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test test/core/ --reporter compact`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | BUG-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |
| 16-01-02 | 01 | 1 | BUG-05 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |
| 16-01-03 | 01 | 1 | VAL-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |
| 16-01-04 | 01 | 1 | BUG-02 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |
| 16-01-05 | 01 | 1 | BUG-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |
| 16-02-01 | 02 | 2 | FEAT-01 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |
| 16-02-02 | 02 | 2 | FEAT-03 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` | Existing file, new tests needed | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. Test files exist, new test cases need to be added within them.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| UI address field clamps to 0-65535 | BUG-01 | Widget test needed for UI clamp | Enter address >65535 in key_repository UI, verify clamp |
| Unit ID field accepts 0-255 for TCP | VAL-03 | Widget test needed for UI range | Configure TCP connection, set unit ID to 0 and 255, verify accepted |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
