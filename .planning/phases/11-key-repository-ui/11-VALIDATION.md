---
phase: 11
slug: key-repository-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK) |
| **Config file** | none (uses default `flutter test`) |
| **Quick run command** | `flutter test test/pages/key_repository_test.dart --reporter compact` |
| **Full suite command** | `flutter test test/pages/ --reporter compact` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/pages/key_repository_test.dart --reporter compact`
- **After every plan wave:** Run `flutter test test/pages/ --reporter compact`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | UIKY-01 | widget | `flutter test test/pages/key_repository_test.dart --name "protocol switching"` | Will extend existing | ⬜ pending |
| 11-01-02 | 01 | 1 | UIKY-02 | widget | `flutter test test/pages/key_repository_test.dart --name "server alias"` | Will extend existing | ⬜ pending |
| 11-01-03 | 01 | 1 | UIKY-03 | widget | `flutter test test/pages/key_repository_test.dart --name "register type"` | Will extend existing | ⬜ pending |
| 11-01-04 | 01 | 1 | UIKY-04 | widget | `flutter test test/pages/key_repository_test.dart --name "register address"` | Will extend existing | ⬜ pending |
| 11-01-05 | 01 | 1 | UIKY-05 | widget | `flutter test test/pages/key_repository_test.dart --name "data type"` | Will extend existing | ⬜ pending |
| 11-01-06 | 01 | 1 | UIKY-06 | widget | `flutter test test/pages/key_repository_test.dart --name "poll group"` | Will extend existing | ⬜ pending |
| 11-01-07 | 01 | 1 | TEST-07 | widget | `flutter test test/pages/key_repository_test.dart --reporter compact` | Will extend existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/helpers/test_helpers.dart` — add `sampleModbusKeyMappings()` and `sampleStateManConfigWithModbus()` helpers (if not already present)
- [ ] `test/pages/key_repository_test.dart` — add Modbus protocol switching, config section, auto-lock, and search filter test groups

*Existing infrastructure covers test framework requirements. Only new test helpers and test cases needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Configured Modbus keys display live values | UIKY (Success Criteria 4) | Requires live Modbus device connection | Connect to Modbus simulator, configure key, verify value updates in UI |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
