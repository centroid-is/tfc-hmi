---
phase: 10
slug: server-config-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK) |
| **Config file** | none — standard Flutter test setup |
| **Quick run command** | `flutter test test/pages/server_config_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/pages/server_config_test.dart`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 0 | TEST-08 | widget | `flutter test test/pages/server_config_test.dart` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | UISV-01 | widget | `flutter test test/pages/server_config_test.dart --name "add server"` | ❌ W0 | ⬜ pending |
| 10-01-03 | 01 | 1 | UISV-02 | widget | `flutter test test/pages/server_config_test.dart --name "edit server"` | ❌ W0 | ⬜ pending |
| 10-01-04 | 01 | 1 | UISV-03 | widget | `flutter test test/pages/server_config_test.dart --name "remove server"` | ❌ W0 | ⬜ pending |
| 10-01-05 | 01 | 1 | UISV-04 | widget | `flutter test test/pages/server_config_test.dart --name "connection status"` | ❌ W0 | ⬜ pending |
| 10-01-06 | 01 | 1 | UISV-05 | widget | `flutter test test/pages/server_config_test.dart --name "poll group"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/pages/server_config_test.dart` — Modbus section widget test stubs for UISV-01 through UISV-05
- [ ] `test/helpers/test_helpers.dart` — extend with `sampleModbusStateManConfig()` helper

*Existing infrastructure covers framework installation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Grey dot when StateMan not initialized | UISV-04 | Requires real app state timing | 1. Launch app without config 2. Navigate to server config 3. Verify grey dot shown |
| Auto-reconnect on save | UISV-01 | Requires real Modbus server | 1. Configure server 2. Save 3. Verify stateManProvider invalidation triggers reconnect |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
