---
phase: 15
slug: code-review-fixes-security-performance-correctness-and-duplication
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test (Dart SDK) + flutter_test |
| **Config file** | packages/tfc_dart/pubspec.yaml (test dependency) |
| **Quick run command** | `cd packages/tfc_dart && dart test --reporter compact` |
| **Full suite command** | `cd packages/tfc_dart && dart test && cd ../../ && flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test --reporter compact`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test && cd ../../ && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | CORR-02 | unit | `dart test test/core/state_man_test.dart` | ✅ | ⬜ pending |
| 15-01-02 | 01 | 1 | CORR-03 | lint | `dart analyze packages/tfc_dart/lib/core/umas_types.dart` | ✅ | ⬜ pending |
| 15-01-03 | 01 | 1 | CORR-04 | unit | `dart test test/core/umas_client_test.dart` | ✅ | ⬜ pending |
| 15-01-04 | 01 | 1 | DUP-06 | unit | `dart test test/core/modbus_device_client_test.dart` | ✅ | ⬜ pending |
| 15-01-05 | 01 | 1 | SEC-02 | unit | `dart test test/core/umas_client_test.dart` | ✅ | ⬜ pending |
| 15-01-06 | 01 | 1 | DUP-07 | lint | `dart analyze lib/pages/key_repository.dart` | ✅ | ⬜ pending |
| 15-01-07 | 01 | 1 | DUP-08 | lint | `dart analyze lib/pages/key_repository.dart` | ✅ | ⬜ pending |
| 15-01-08 | 01 | 1 | PERF-01 | lint | `dart analyze lib/widgets/umas_browse.dart` | ✅ | ⬜ pending |
| 15-01-09 | 01 | 1 | PERF-02 | unit | `cd packages/modbus_client_tcp && dart test` | ✅ | ⬜ pending |
| 15-02-01 | 02 | 1 | CORR-01 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |
| 15-02-02 | 02 | 1 | SEC-01 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |
| 15-02-03 | 02 | 1 | SEC-03 | unit | `dart test test/core/modbus_client_wrapper_test.dart` | ✅ | ⬜ pending |
| 15-02-04 | 02 | 1 | CORR-05 | unit | `dart test test/core/modbus_client_wrapper_test.dart` | ✅ | ⬜ pending |
| 15-03-01 | 03 | 2 | DUP-01 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |
| 15-03-02 | 03 | 2 | DUP-03 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |
| 15-03-03 | 03 | 2 | DUP-04 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |
| 15-03-04 | 03 | 2 | DUP-05 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |
| 15-03-05 | 03 | 2 | DUP-02 | widget | `flutter test test/pages/server_config_test.dart` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing test infrastructure covers most phase requirements
- Changes are refactoring and bug fixes, not new features requiring new test scaffolding
- Existing tests should continue to pass after each change

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Config save/reload cycle | CORR-01 | SharedPreferences race is timing-dependent | Save config, reload page, verify values persist |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
