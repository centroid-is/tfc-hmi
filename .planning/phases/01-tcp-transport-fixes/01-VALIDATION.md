---
phase: 1
slug: tcp-transport-fixes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `test` ^1.25.0 |
| **Config file** | none — Wave 0 installs |
| **Quick run command** | `cd packages/modbus_client_tcp && dart test` |
| **Full suite command** | `cd packages/modbus_client_tcp && dart test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/modbus_client_tcp && dart test`
- **After every plan wave:** Run `cd packages/modbus_client_tcp && dart test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 0 | TEST-01 | setup | `cd packages/modbus_client_tcp && dart test` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | TCPFIX-01 | unit | `dart test test/modbus_client_tcp_test.dart -n "frame length"` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | TCPFIX-03 | unit | `dart test test/modbus_client_tcp_test.dart -n "length validation"` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | TCPFIX-04 | unit | `dart test test/modbus_client_tcp_test.dart -n "TCP_NODELAY"` | ❌ W0 | ⬜ pending |
| 01-02-04 | 02 | 1 | TCPFIX-05 | unit | `dart test test/modbus_client_tcp_test.dart -n "keepalive"` | ❌ W0 | ⬜ pending |
| 01-02-05 | 02 | 1 | TCPFIX-02 | unit | `dart test test/modbus_client_tcp_test.dart -n "concurrent"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `packages/modbus_client_tcp/` — copy fork from pub cache into project as local package
- [ ] `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart` — test stubs for all TCPFIX requirements
- [ ] `packages/modbus_client_tcp/test/modbus_test_server.dart` — mock Modbus TCP server (raw byte responses)
- [ ] `packages/tfc_dart/pubspec.yaml` — update to path dependency `../modbus_client_tcp`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Keepalive probes on macOS vs Linux | TCPFIX-05 | Platform-specific raw socket options differ | Run tests on both macOS and Linux; verify socket options set without SocketException |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
