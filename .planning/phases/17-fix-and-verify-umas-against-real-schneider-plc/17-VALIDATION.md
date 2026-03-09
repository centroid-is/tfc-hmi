---
phase: 17
slug: fix-and-verify-umas-against-real-schneider-plc
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dart test (pure Dart, NOT flutter_test) |
| **Config file** | packages/tfc_dart/pubspec.yaml (dev_dependencies: test) |
| **Quick run command** | `cd packages/tfc_dart && dart test test/core/umas_client_test.dart --reporter compact` |
| **Full suite command** | `cd packages/tfc_dart && dart test --reporter compact` |
| **Live test command** | `cd packages/tfc_dart && dart test test/umas_live_test.dart --run-skipped --reporter compact` |
| **Estimated runtime** | ~10 seconds (unit), ~30 seconds (live) |

---

## Sampling Rate

- **After every task commit:** Run `cd packages/tfc_dart && dart test test/core/umas_client_test.dart --reporter compact`
- **After every plan wave:** Run `cd packages/tfc_dart && dart test --reporter compact`
- **Before `/gsd:verify-work`:** Full suite green + live tests pass with `--run-skipped`
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | FIX-01, FIX-02, FIX-03, FIX-04, FIX-05, FIX-06 | unit | `cd packages/tfc_dart && dart test test/core/umas_client_test.dart --reporter compact` | Existing, update needed | pending |
| 17-02-01 | 02 | 2 | VER-01, VER-02 | live (skip) | `cd packages/tfc_dart && dart test test/umas_live_test.dart --run-skipped --reporter compact` | Existing, update needed | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] Update `packages/tfc_dart/test/core/umas_client_test.dart` — update tests to match corrected wire format
- [ ] Update `test/umas_stub_server.py` — match corrected protocol format
- [ ] Update `packages/tfc_dart/test/umas_live_test.dart` — live hardware integration tests (pure Dart)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Browse dialog shows real PLC variables | VER-03 | Requires running Flutter UI against real PLC | Open UMAS browse dialog for server at 10.50.10.123, verify variable tree appears |
| Selecting UMAS variable fills correct address/type | VER-04 | Requires UI interaction | Select a variable from browse, verify address and type populate in key config |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
