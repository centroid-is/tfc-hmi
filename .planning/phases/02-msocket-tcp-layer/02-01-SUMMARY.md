---
phase: 02-msocket-tcp-layer
plan: 01
subsystem: infra
tags: [tcp, socket, keepalive, rxdart, behaviorsubject, dart-io]

# Dependency graph
requires: []
provides:
  - "MSocket class: TCP client with connect, dataStream, statusStream, dispose"
  - "ConnectionStatus enum: connected, connecting, disconnected"
  - "TestTcpServer helper: reusable test TCP server for unit tests"
  - "jbtm package scaffolding: pubspec, analysis_options, barrel export"
affects: [03-m2400-framing, 04-stub-server, 07-state-man-integration, 08-resilience]

# Tech tracking
tech-stack:
  added: [rxdart ^0.28.0, logger ^2.4.0, test ^1.25.0, lints ^5.0.0]
  patterns: [BehaviorSubject status stream, connect-listen-reconnect loop, Completer-based socket done tracking, platform-specific SO_KEEPALIVE]

key-files:
  created:
    - packages/jbtm/pubspec.yaml
    - packages/jbtm/analysis_options.yaml
    - packages/jbtm/lib/jbtm.dart
    - packages/jbtm/lib/src/msocket.dart
    - packages/jbtm/test/test_tcp_server.dart
    - packages/jbtm/test/msocket_test.dart
  modified: []

key-decisions:
  - "Used Completer instead of asFuture() for socket done tracking -- asFuture() replaces onError handler and can leak SocketExceptions to test zones"
  - "Used BehaviorSubject for status stream replay semantics (consistent with tfc_dart codebase patterns)"
  - "Used RawSocketOption.levelSocket and RawSocketOption.levelTcp constants from dart:io instead of hardcoded SOL_SOCKET/IPPROTO_TCP values"
  - "TestTcpServer uses socket.done.catchError to suppress RST errors from client-side disconnects"

patterns-established:
  - "MSocket connect-listen-reconnect loop: async while loop with bounded exponential backoff"
  - "BehaviorSubject<ConnectionStatus> for status stream with synchronous .value getter"
  - "TestTcpServer pattern: bind loopback port 0, waitForClient() completer, sendToAll(), disconnectAll()"
  - "Platform-branching SO_KEEPALIVE via RawSocketOption.fromInt with verified constants"

requirements-completed: [TCP-01, TCP-02, TCP-04]

# Metrics
duration: 14min
completed: 2026-03-04
---

# Phase 2 Plan 01: MSocket TCP Layer Summary

**MSocket TCP client with SO_KEEPALIVE (idle=5s, interval=2s, count=3), BehaviorSubject status stream, raw byte passthrough, and 12 passing unit tests**

## Performance

- **Duration:** 14 min
- **Started:** 2026-03-04T11:46:34Z
- **Completed:** 2026-03-04T12:01:18Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- jbtm package scaffolding with rxdart, logger, test, lints dependencies
- MSocket class: TCP connect, raw byte streaming as Stream<Uint8List>, BehaviorSubject status stream
- Platform-specific SO_KEEPALIVE configuration (macOS/iOS + Linux/Android) using verified system header constants
- TestTcpServer reusable test helper with start, sendToAll, waitForClient, disconnectAll, shutdown
- 12 comprehensive unit tests covering connect, data passthrough, status transitions, replay semantics, keepalive, server disconnect detection, and dispose cleanup

## Task Commits

Each task was committed atomically:

1. **Task 1: Package scaffolding and TestTcpServer helper** - `1c856cb` (chore)
2. **Task 2 RED: Failing tests for MSocket** - `86a9cf4` (test)
3. **Task 2 GREEN: MSocket implementation** - `c5520c4` (feat)

_TDD task had two commits (test then feat). No refactor phase needed._

## Files Created/Modified
- `packages/jbtm/pubspec.yaml` - Package definition with rxdart, logger, test, lints
- `packages/jbtm/analysis_options.yaml` - Recommended lints
- `packages/jbtm/lib/jbtm.dart` - Barrel export for MSocket and ConnectionStatus
- `packages/jbtm/lib/src/msocket.dart` - MSocket class with ConnectionStatus enum (160 lines)
- `packages/jbtm/test/test_tcp_server.dart` - Reusable test TCP server helper (66 lines)
- `packages/jbtm/test/msocket_test.dart` - 12 unit tests for MSocket behavior (282 lines)

## Decisions Made
- **Completer over asFuture():** Used a Completer<void> to track when the socket stream ends instead of StreamSubscription.asFuture(). The asFuture() approach replaces onDone/onError handlers and can leak SocketExceptions to test framework zones when dispose() destroys the socket mid-listen. The Completer pattern handles both onDone and onError explicitly.
- **BehaviorSubject for status:** Consistent with tfc_dart codebase patterns (state_man.dart, alarm.dart). Provides .value for synchronous access and automatic replay on subscribe.
- **dart:io level constants:** Used RawSocketOption.levelSocket and RawSocketOption.levelTcp from dart:io instead of hardcoding SOL_SOCKET (0xffff/1) and IPPROTO_TCP (6) values directly.
- **TestTcpServer waitForClient():** Added Completer-based waitForClient() to handle race condition where MSocket connects before ServerSocket.listen callback fires (especially in multi-test scenarios).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed asFuture() SocketException leak in test zones**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** Using .asFuture() on socket subscription leaked SocketExceptions to dart test framework's error zone when dispose() destroyed the socket mid-listen, causing unrelated test failures
- **Fix:** Replaced asFuture() with Completer<void> that explicitly handles both onDone and onError callbacks
- **Files modified:** packages/jbtm/lib/src/msocket.dart
- **Verification:** All 12 tests pass consistently across 3 consecutive runs
- **Committed in:** c5520c4 (Task 2 GREEN commit)

**2. [Rule 1 - Bug] Fixed race condition in server disconnect test**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** server.disconnectAll() was called before ServerSocket.listen callback fired (server had 0 clients), so nothing was actually disconnected. Race condition manifested only when preceded by certain other tests
- **Fix:** Added await server.waitForClient() before disconnectAll() to ensure server has registered the client
- **Files modified:** packages/jbtm/test/msocket_test.dart
- **Verification:** Test passes consistently when run with all other tests
- **Committed in:** c5520c4 (Task 2 GREEN commit)

**3. [Rule 1 - Bug] Fixed unhandled async SocketException from server-side socket.done**
- **Found during:** Task 2 (GREEN phase)
- **Issue:** When MSocket.dispose() destroys the client socket, the server-side socket.done future rejects with SocketException: Connection reset by peer. Without catchError, this surfaced as an unhandled async error in the test zone
- **Fix:** Added catchError((_) {}) on socket.done in TestTcpServer to suppress RST errors
- **Files modified:** packages/jbtm/test/test_tcp_server.dart
- **Verification:** "no events after dispose" test passes without unhandled exceptions
- **Committed in:** c5520c4 (Task 2 GREEN commit)

---

**Total deviations:** 3 auto-fixed (3 bugs)
**Impact on plan:** All auto-fixes were necessary for test reliability. The asFuture() pitfall and race condition are common Dart TCP testing challenges. No scope creep.

## Issues Encountered
- TCP socket error handling in dart test framework zones requires careful suppression of SocketExceptions on both client and server sides. Errors from socket.done futures, asFuture() rejections, and server.sendToAll() to destroyed sockets all need explicit handling.
- ServerSocket.listen callback fires asynchronously after Socket.connect() returns, creating a timing window where the server has no clients even though the TCP handshake completed. This is a fundamental dart:io behavior, not a bug.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- MSocket is ready for Plan 02 (auto-reconnect with exponential backoff testing)
- TestTcpServer is ready for reuse in Phase 3 (M2400 framing) and Phase 4 (stub server) tests
- Connection loop structure already supports reconnect (while loop with backoff), Plan 02 adds comprehensive reconnect-specific tests

## Self-Check: PASSED

All 7 created files exist. All 3 commits verified in git log.

---
*Phase: 02-msocket-tcp-layer*
*Completed: 2026-03-04*
