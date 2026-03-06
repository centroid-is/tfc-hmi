---
phase: 2
slug: fc15-coil-write-fix
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `test` ^1.21.0 (already in modbus_client dev_deps) |
| **Config file** | none — default test discovery |
| **Quick run command** | `cd packages/modbus_client && dart test` |
| **Full suite command** | `cd packages/modbus_client && dart test && cd ../modbus_client_tcp && dart test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/modbus_client && dart test`
- **After every plan wave:** Run `cd packages/modbus_client && dart test && cd ../modbus_client_tcp && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 0 | LIBFIX-01 | setup | `cd packages/modbus_client && dart test test/modbus_endianness_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 0 | TEST-02 | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | LIBFIX-01 | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "FC15"` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 1 | LIBFIX-01 | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "regression"` | ❌ W0 | ⬜ pending |
| 02-01-05 | 01 | 1 | TEST-02 | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "response"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `packages/modbus_client/` — fork from pub cache (`cp -r ~/.pub-cache/hosted/pub.dev/modbus_client-1.4.4 packages/modbus_client`)
- [ ] `packages/modbus_client/test/modbus_fc15_test.dart` — FC15 test stubs for LIBFIX-01, TEST-02
- [ ] `packages/modbus_client_tcp/pubspec.yaml` — update dep to `modbus_client: path: ../modbus_client`

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
