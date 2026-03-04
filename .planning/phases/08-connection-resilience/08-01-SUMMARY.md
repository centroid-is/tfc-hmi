---
phase: 08-connection-resilience
plan: 01
subsystem: jbtm
tags: [connection-health, tcp-proxy, resilience, msocket, reconnect]
dependency_graph:
  requires:
    - "Phase 2: MSocket TCP layer (auto-reconnect, SO_KEEPALIVE)"
  provides:
    - "ConnectionHealthMetrics: per-device uptime, reconnectCount, recordsPerSecond"
    - "TcpProxy test utility for network failure simulation"
    - "Proxy-based MSocket resilience test patterns"
  affects:
    - "Phase 8 Plan 02: pipeline resilience tests (uses TcpProxy and ConnectionHealthMetrics)"
    - "Phase 10: UI (health metrics for connection status display)"
tech_stack:
  added: []
  patterns: ["Rolling 1-second window for throughput calculation", "TcpProxy shutdown+restart on fixed port for cable pull simulation", "First-connect vs reconnect distinction via boolean flag"]
key_files:
  created:
    - packages/jbtm/lib/src/connection_health.dart
    - packages/jbtm/test/tcp_proxy.dart
    - packages/jbtm/test/connection_health_test.dart
    - packages/jbtm/test/connection_resilience_test.dart
  modified:
    - packages/jbtm/lib/jbtm.dart
decisions:
  - "TcpProxy copied verbatim from tfc_dart/test/proxy.dart (self-contained, no cross-package dependency)"
  - "ConnectionHealthMetrics tracks first connect via boolean flag; only subsequent connects count as reconnections"
  - "Rolling 1-second window for recordsPerSecond uses List<DateTime> with pruning on access"
  - "Cable pull simulation uses proxy shutdown + restart on captured fixed port (not reject/un-reject)"
metrics:
  duration: "6min"
  completed: "2026-03-04"
  tasks_completed: 2
  tasks_total: 2
  tests_added: 16
  tests_total: 224
---

# Phase 8 Plan 01: Connection Health Metrics and Resilience Tests Summary

ConnectionHealthMetrics tracks per-device uptime, reconnect count, and records/second via MSocket statusStream subscription; TcpProxy enables cable pull and switch reboot simulation proving MSocket survives real-world network failures.

## What Was Built

### ConnectionHealthMetrics (`packages/jbtm/lib/src/connection_health.dart`)

Per-device health tracking class that subscribes to an MSocket's statusStream:

- `Duration get uptime` -- time since last connected (Duration.zero when disconnected)
- `int get reconnectCount` -- incremented on each reconnection after the first connect
- `double get recordsPerSecond` -- rolling 1-second window of record timestamps
- `void notifyRecord()` -- called by pipeline consumers to track throughput
- `void dispose()` -- cancels status subscription

### TcpProxy Test Utility (`packages/jbtm/test/tcp_proxy.dart`)

Copied verbatim from `packages/tfc_dart/test/proxy.dart`. Self-contained TCP proxy with:
- `start()` / `shutdown()` -- lifecycle management
- `reject()` -- destroy connections, reject new ones (RST)
- `bufferServerToClient` / `flush()` -- buffer server responses
- Port 0 (OS-assigned) for conflict-free testing

### Key Design Decisions

1. **TcpProxy verbatim copy**: The proxy is self-contained (dart:async + dart:io only). Copying avoids cross-package test dependencies per CONTEXT.md guidance.

2. **First-connect boolean flag**: `_firstConnected` tracks whether the initial connection has occurred. Only subsequent connected transitions increment `_reconnectCount`.

3. **Rolling window throughput**: `recordsPerSecond` uses a `List<DateTime>` of receipt timestamps, pruned to entries within the last 1 second on each access. Simple, no timers needed.

4. **Cable pull via shutdown+restart**: TcpProxy.reject() doesn't have an "un-reject" method, so cable pull simulation uses `proxy.shutdown()` followed by creating a new TcpProxy on the same captured port.

## Tests

### Connection Health Unit Tests (9 tests)

- Starts with 0 reconnects and 0 records/second
- Uptime is Duration.zero when disconnected
- Uptime > Duration.zero after connect
- reconnectCount is 0 after first connect (not a reconnect)
- reconnectCount is 1 after disconnect + reconnect
- reconnectCount is 2 after two cycles
- notifyRecord() correctly updates recordsPerSecond
- recordsPerSecond drops old entries after 1 second
- dispose() stops tracking

### Connection Resilience Tests (7 tests)

- **Cable pull** (3): MSocket reconnects, data resumes, no stale data
- **Switch reboot** (2): MSocket reconnects after 2s delay, data resumes
- **Health metrics** (2): reconnectCount increments on each recovery, uptime resets after reconnection

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Data tests failing due to missing waitForClient sync**
- **Found during:** Task 2
- **Issue:** Tests sent data before the proxy-to-server connection was established on the TestTcpServer side. `server.sendToAll()` had no clients to send to.
- **Fix:** Added `await server.waitForClient()` and small delay after connect before sending data in data-verification tests.
- **Files modified:** packages/jbtm/test/connection_resilience_test.dart
- **Commit:** 43ee845

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 976ce44 | test | Add failing tests for ConnectionHealthMetrics (TDD RED) |
| 3cde51d | feat | Implement ConnectionHealthMetrics (TDD GREEN) |
| 43ee845 | test | Add proxy-based MSocket resilience tests |

## Verification

- `dart test test/connection_health_test.dart` -- 9/9 pass
- `dart test test/connection_resilience_test.dart` -- 7/7 pass
- `dart test test/connection_health_test.dart test/connection_resilience_test.dart` -- 16/16 pass
- `dart test` -- 224/224 pass (no regressions)
- `grep 'connection_health' packages/jbtm/lib/jbtm.dart` -- export present

## Self-Check: PASSED

- [x] packages/jbtm/lib/src/connection_health.dart -- FOUND
- [x] packages/jbtm/test/tcp_proxy.dart -- FOUND
- [x] packages/jbtm/test/connection_health_test.dart -- FOUND
- [x] packages/jbtm/test/connection_resilience_test.dart -- FOUND
- [x] Commit 976ce44 -- FOUND
- [x] Commit 3cde51d -- FOUND
- [x] Commit 43ee845 -- FOUND
