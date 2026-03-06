# Phase 4: ModbusClientWrapper -- Connection - Research

**Researched:** 2026-03-06
**Domain:** Dart connection lifecycle management wrapping ModbusClientTcp
**Confidence:** HIGH

## Summary

This phase builds a `ModbusClientWrapper` that wraps the forked `ModbusClientTcp` (in `packages/modbus_client_tcp/`) with connection lifecycle management: auto-reconnect with exponential backoff, `BehaviorSubject<ConnectionStatus>` status streaming, connect/disconnect/dispose lifecycle, and factory injection for testability. The project already has two production-proven reference implementations of this exact pattern: `MSocket` (raw TCP with reconnect) and `M2400ClientWrapper` (wraps MSocket with protocol-specific routing). The wrapper must NOT manage reading, writing, or polling -- those are Phases 5-6. It must NOT implement the `DeviceClient` adapter -- that is Phase 7.

The key design challenge is that `ModbusClientTcp` was designed as a stateless connect-on-demand client (with `autoConnectAndKeepConnected` mode), not a persistent-connection client with status streaming. It exposes `connect() -> Future<bool>` and `disconnect() -> Future<void>` but has no connection status stream, no reconnect loop, and no event when the underlying socket drops. The wrapper must build its own connection loop (like MSocket's `_connectionLoop()`) around `ModbusClientTcp`, using `doNotConnect` mode and managing the connection state externally.

**Primary recommendation:** Follow the MSocket connection loop pattern exactly, wrapping `ModbusClientTcp` with `connectionMode: ModbusConnectionMode.doNotConnect`. Manage the connection loop, backoff, and status streaming in the wrapper. Use factory injection for `ModbusClientTcp` creation to enable test injection with `ModbusTestServer`.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Connection status uses existing `ConnectionStatus` enum (connected, connecting, disconnected) -- match MSocket and OPC UA
- Match MSocket backoff: 500ms initial, 5s max, immediate reset on successful reconnect
- Retry forever -- never give up. HMI should always try to reconnect. Operator removes device if permanently gone.
- Phase 4 is wrapper only -- DeviceClient adapter is Phase 7, no stub
- Provide both disconnect() and dispose() -- disconnect() stops reconnect loop but allows later reconnect, dispose() is terminal (closes streams, can't reuse)
- Factory injection for ModbusClientTcp -- constructor accepts optional factory for test injection, matching M2400ClientWrapper's socketFactory pattern

### Claude's Discretion
- Health monitoring approach (TCP keepalive vs app-level heartbeat read)
- Error handling strategy (pass-through vs wrapper exceptions)
- Disconnect detection timing (immediate vs probe-first)
- Reconnect logging verbosity
- File location within packages/
- Constructor parameter style (raw vs config object)
- Connection loop management (own loop vs built-in auto-connect)
- connect() return type semantics

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONN-01 | User can connect to a Modbus TCP device by specifying host, port, and unit ID | Constructor takes host, port, unitId; connect() initiates connection loop via ModbusClientTcp factory |
| CONN-02 | Connection auto-recovers with exponential backoff after loss | MSocket _connectionLoop() pattern: 500ms initial, 5s max, reset on success, retry forever |
| CONN-03 | Connection status streams to UI (connected, connecting, disconnected) | BehaviorSubject<ConnectionStatus>.seeded(disconnected) with dual API (sync getter + stream) |
| CONN-05 | User can connect to multiple independent Modbus devices simultaneously | Each wrapper instance is fully independent (own client, own status subject, own loop) |
| TEST-03 | ModbusClientWrapper has unit tests for connection lifecycle, polling, read/write, and reconnect behavior | Phase 4 scope: connection lifecycle and reconnect tests only. Use ModbusTestServer for mock TCP. TDD: tests first. |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client_tcp (fork) | 1.2.3 (local) | TCP transport with MBAP framing, keepalive | Already forked and fixed in Phases 1-3 |
| modbus_client (fork) | local | Base ModbusClient class, connection modes, response codes | Dependency of modbus_client_tcp |
| rxdart | ^0.28.0 | BehaviorSubject for status streaming with replay | Already used by MSocket, M2400ClientWrapper, state_man |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| test | ^1.25.0 | Unit testing framework | All tests -- already in dev_dependencies |
| logger | ^2.4.0 | Structured logging | Connection events, reconnect attempts |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Own connection loop | ModbusClientTcp autoConnectAndKeepConnected | Built-in mode has no status stream, no backoff control, no reconnect events -- unsuitable for HMI status display |
| BehaviorSubject | StreamController.broadcast | Loses replay semantics -- new subscribers wouldn't get current status |
| Factory injection | Mockito/Mocktail mocks | Factory injection is simpler, already proven in M2400ClientWrapper, and ModbusTestServer provides real TCP testing |

## Architecture Patterns

### Recommended Project Structure

The wrapper should live in `packages/tfc_dart/lib/core/` alongside `state_man.dart`, since:
1. `tfc_dart` already depends on `modbus_client_tcp` (in pubspec.yaml)
2. `tfc_dart` already depends on `rxdart` (for BehaviorSubject)
3. The Phase 7 `ModbusDeviceClientAdapter` will live in `state_man.dart` (like `M2400DeviceClientAdapter`), and needs to import the wrapper
4. No new package dependency is needed

```
packages/tfc_dart/lib/core/
  modbus_client_wrapper.dart     # Phase 4: connection lifecycle wrapper
  state_man.dart                 # Existing -- has ConnectionStatus enum, DeviceClient interface
```

Test file:
```
packages/tfc_dart/test/core/
  modbus_client_wrapper_test.dart  # Phase 4 tests
```

### Pattern 1: Connection Loop (from MSocket)

**What:** A `while (!_disposed)` loop that manages connect/disconnect/backoff cycles, emitting status transitions via BehaviorSubject.
**When to use:** Any persistent-connection wrapper where the underlying transport doesn't provide reconnect.
**Example:**

```dart
// Source: packages/jbtm/lib/src/msocket.dart (production code, adapted)
Future<void> _connectionLoop() async {
  while (!_stopped) {
    if (!_status.isClosed) _status.add(ConnectionStatus.connecting);
    try {
      final connected = await _client.connect();
      if (_stopped) {
        await _client.disconnect();
        break;
      }
      if (!connected) throw StateError('connect() returned false');
      if (!_status.isClosed) _status.add(ConnectionStatus.connected);
      _backoff = _initialBackoff;

      // Block until connection drops
      await _awaitDisconnect();
    } catch (e) {
      _logger.e('Connection error to $_host:$_port: $e');
    }

    // Socket is gone -- clean up
    await _client.disconnect();
    if (!_stopped && !_status.isClosed) {
      _status.add(ConnectionStatus.disconnected);
    }
    if (_stopped) break;
    await Future.delayed(_backoff);
    if (_stopped) break;
    _backoff = _clampDuration(_backoff * 2, Duration.zero, _maxBackoff);
  }
}
```

### Pattern 2: Factory Injection (from M2400ClientWrapper)

**What:** Constructor accepts an optional factory function that creates the underlying transport client. Default factory creates the real client; tests inject a factory that returns a client pointing at ModbusTestServer.
**When to use:** Any wrapper that needs testability without mock frameworks.
**Example:**

```dart
// Source: packages/jbtm/lib/src/m2400_client_wrapper.dart (production pattern)
class ModbusClientWrapper {
  final ModbusClientTcp Function(String host, int port, int unitId) _clientFactory;

  ModbusClientWrapper(
    this._host, this._port, this._unitId, {
    ModbusClientTcp Function(String, int, int)? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultFactory;

  static ModbusClientTcp _defaultFactory(String host, int port, int unitId) {
    return ModbusClientTcp(
      host,
      serverPort: port,
      unitId: unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 3),
    );
  }
}
```

### Pattern 3: Dual Lifecycle API (from M2400ClientWrapper)

**What:** `disconnect()` stops the reconnect loop but keeps streams alive for reuse. `dispose()` is terminal -- closes all streams, no reuse possible.
**When to use:** When the wrapper must survive configuration changes or user-initiated disconnect without losing subscribers.
**Example:**

```dart
// Source: packages/jbtm/lib/src/m2400_client_wrapper.dart (production pattern)
void disconnect() {
  _stopped = true;
  _cleanupClient();
  // Status subject stays open -- can call connect() again
}

void dispose() {
  _stopped = true;
  _cleanupClient();
  _status.close(); // Terminal -- BehaviorSubject is closed
}
```

### Pattern 4: Disconnect Detection via Periodic Health Probe

**What:** After successful connect, periodically send a lightweight Modbus read to detect application-level hangs (where TCP keepalive sees the connection as alive but the PLC is unresponsive).
**When to use:** When TCP keepalive alone is insufficient (e.g., PLC firmware hang, network equipment buffering).
**Recommendation for this phase:** Rely on TCP keepalive only (already configured in ModbusClientTcp with 5s/2s/3 = ~11s detection). ModbusClientTcp's socket listener `onDone` callback calls `disconnect()` when the socket closes, which the wrapper can detect. Add health probing later if needed -- same approach as OPC UA's `ns=0;i=2258` read.

**Rationale:** TCP keepalive is already configured properly in ModbusClientTcp (Phase 1/3 work). The OPC UA TCP half-open problem was specific to `open62541_dart`'s kernel-level buffering where `send()` succeeded despite dead connection. ModbusClientTcp's socket listener `onDone` will fire when keepalive detects the dead connection, which is sufficient for Phase 4.

### Anti-Patterns to Avoid

- **Using autoConnectAndKeepConnected mode:** This mode auto-connects on `send()` but provides no status stream, no reconnect events, and no backoff control. The wrapper would have no way to emit `connecting` status or control retry timing.
- **Sharing ConnectionStatus enum between packages:** MSocket defines its own `ConnectionStatus` in jbtm, state_man defines its own in tfc_dart. The wrapper should use tfc_dart's `ConnectionStatus` (from `state_man.dart`) since that is what the DeviceClient adapter (Phase 7) will expose. This avoids the jbtm-style mapping layer.
- **Creating ModbusClientTcp in the constructor:** The client must be created fresh on each reconnect attempt because `disconnect()` destroys the socket and clears state. Create a new client instance in each iteration of the connection loop.
- **Blocking connect() until first connection succeeds:** MSocket's `connect()` is fire-and-forget (returns void, starts loop asynchronously). This is the correct pattern for an HMI -- the UI should show "connecting" immediately, not block.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Connection status streaming with replay | Custom StreamController + cached value | BehaviorSubject from rxdart | Automatic replay to new subscribers, thread-safe, well-tested |
| Exponential backoff | Custom timer logic | MSocket's 3-line pattern: `_backoff = clamp(_backoff * 2, Duration.zero, _maxBackoff)` | Proven in production, simple, handles edge cases |
| TCP keepalive configuration | SO_KEEPALIVE setup in wrapper | ModbusClientTcp._enableKeepAlive() (already built in Phase 1/3) | Cross-platform (macOS, Linux, Windows), already tested |
| Mock TCP server for tests | Mockito mocks of ModbusClientTcp | ModbusTestServer from packages/modbus_client_tcp/test/ | Real TCP testing, already handles MBAP framing, proven in Phase 1 tests |
| Duration clamping | Inline math | MSocket._clampDuration() static helper (copy or extract) | Clean, tested |

**Key insight:** The wrapper is fundamentally a connection loop + status streaming + factory injection. All three patterns exist verbatim in MSocket and M2400ClientWrapper. The implementation is assembly of proven parts, not invention.

## Common Pitfalls

### Pitfall 1: ModbusClientTcp disconnect() does not notify
**What goes wrong:** You call `connect()` on ModbusClientTcp, the PLC drops, and ModbusClientTcp calls its own `disconnect()` internally (from the socket `onDone` callback) -- but there is no notification mechanism. The wrapper has no event to unblock on.
**Why it happens:** ModbusClientTcp is a stateless client. It has `isConnected` (bool) but no status stream or callback.
**How to avoid:** After successful `connect()`, the wrapper must poll `_client.isConnected` periodically or attempt a lightweight operation and catch failure. Alternatively, the wrapper can manage the socket listener directly by using `connectionMode: doNotConnect` and calling `connect()`/checking `isConnected` in a loop.
**Warning signs:** Tests that connect and then never detect disconnect.

**Recommended approach:** Use a periodic `isConnected` check in a tight loop (e.g., every 500ms) after connection succeeds. When `isConnected` returns false, the connection loop continues to the backoff/reconnect phase. This is simpler than trying to hook into ModbusClientTcp's internal socket listener.

### Pitfall 2: ModbusClientTcp does not recreate socket state cleanly
**What goes wrong:** After `disconnect()`, calling `connect()` again on the same ModbusClientTcp instance works (it creates a new socket). However, the internal `_pendingResponses` map and `_incomingBuffer` are cleared in `disconnect()`, and `_lastTransactionId` continues incrementing, which is correct.
**Why it matters:** Unlike MSocket (which gets destroyed and recreated), ModbusClientTcp can be reused across connect/disconnect cycles. The wrapper can either reuse the same instance or create a new one each cycle.
**How to avoid:** Reuse the same ModbusClientTcp instance across reconnect cycles -- it handles cleanup in `disconnect()`. Only create a new instance if the factory parameters (host, port, unitId) change.

### Pitfall 3: Race condition between connect() and disconnect()
**What goes wrong:** If `disconnect()` is called while `connect()` is awaiting `Socket.connect()`, the new socket is created after the disconnect request.
**Why it happens:** `connect()` is async. Between the await and the socket assignment, external state can change.
**How to avoid:** Use a `_stopped` flag (like MSocket's `_disposed`). Check it immediately after `await connect()` returns, and if true, call `disconnect()` and break out of the loop.
**Warning signs:** Status stream showing `connected` after `disconnect()` was called.

### Pitfall 4: BehaviorSubject operations after close
**What goes wrong:** Adding to a closed BehaviorSubject throws. If `dispose()` closes the subject but the connection loop is still running, it crashes.
**Why it happens:** The connection loop runs asynchronously. `dispose()` may be called while the loop is in `Future.delayed()`.
**How to avoid:** Always check `!_status.isClosed` before adding to the subject (MSocket does this). Set `_stopped = true` before closing, and check `_stopped` at every loop iteration and after every await.
**Warning signs:** Unhandled exception: "Cannot add event after closing."

### Pitfall 5: Test server port conflicts
**What goes wrong:** Tests using hardcoded ports fail intermittently due to port-in-use conflicts.
**Why it happens:** Previous test didn't clean up, or OS hasn't freed the port yet.
**How to avoid:** Always use port 0 (`ServerSocket.bind(InternetAddress.loopbackIPv4, 0)`) for OS-assigned ephemeral ports. Both `TestTcpServer` and `ModbusTestServer` already do this.
**Warning signs:** Flaky tests with "Address already in use" errors.

## Code Examples

### Creating ModbusClientTcp with doNotConnect mode

```dart
// Source: packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart (constructor)
final client = ModbusClientTcp(
  '10.50.10.10',
  serverPort: 502,
  unitId: 1,
  connectionMode: ModbusConnectionMode.doNotConnect,
  connectionTimeout: const Duration(seconds: 3),
  responseTimeout: const Duration(seconds: 3),
  // Keepalive defaults: 5s idle, 2s interval, 3 probes (from Phase 1)
);

// Manual connect
final success = await client.connect(); // Returns Future<bool>
if (success) {
  // client.isConnected == true
  // Socket listener is active, keepalive configured
}

// Manual disconnect
await client.disconnect(); // Returns Future<void>
// client.isConnected == false
// _pendingResponses cleared, _incomingBuffer cleared
```

### Using ModbusTestServer for wrapper tests

```dart
// Source: packages/modbus_client_tcp/test/modbus_test_server.dart (adapted)
late ModbusTestServer server;

setUp(() async {
  server = ModbusTestServer();
  final port = await server.start();
  // Create wrapper with factory that points to test server
  wrapper = ModbusClientWrapper('127.0.0.1', port, 1,
    clientFactory: (host, port, unitId) => ModbusClientTcp(
      host,
      serverPort: port,
      unitId: unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 1),
    ),
  );
});

tearDown(() async {
  wrapper.dispose();
  await server.shutdown();
});

test('auto-reconnects after server disconnect', () async {
  wrapper.connect();
  await wrapper.statusStream
      .firstWhere((s) => s == ConnectionStatus.connected);
  await server.waitForClient();

  // Simulate device failure
  server.disconnectAll();

  // Should auto-reconnect
  await wrapper.statusStream
      .firstWhere((s) => s == ConnectionStatus.disconnected);
  await wrapper.statusStream
      .firstWhere((s) => s == ConnectionStatus.connected)
      .timeout(const Duration(seconds: 5));
});
```

### BehaviorSubject status pattern

```dart
// Source: packages/jbtm/lib/src/msocket.dart lines 34-36 (exact production code)
final _status =
    BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.disconnected);

// Sync getter
ConnectionStatus get connectionStatus => _status.value;

// Async stream (replays current value to new listeners)
Stream<ConnectionStatus> get connectionStream => _status.stream;
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ModbusClientTcp autoConnect | Wrapper with own loop + doNotConnect | Phase 4 (new) | Full control over reconnect timing and status streaming |
| Single ConnectionStatus enum | Per-package enum with mapping | Existing | M2400 adapter maps jbtm.ConnectionStatus to state_man.ConnectionStatus; Modbus wrapper should use state_man.ConnectionStatus directly |

**ModbusClientTcp internals relevant to wrapper:**
- `connect()` -> `Future<bool>`: Creates socket, sets TCP_NODELAY, enables keepalive, starts listening. Returns true on success, false on failure.
- `disconnect()` -> `Future<void>`: Destroys socket, clears pending responses and buffer. Sets `_socket = null`.
- `isConnected` -> `bool`: Returns `_socket != null`.
- Socket `onDone` callback: Calls `disconnect()` when socket stream ends (e.g., remote close, keepalive timeout).
- Socket `onError` callback: Logs error, calls `disconnect()`.
- Socket `cancelOnError: true`: Socket listener cancels on first error.

## Open Questions

1. **Disconnect detection mechanism**
   - What we know: ModbusClientTcp calls `disconnect()` internally when the socket closes (onDone/onError callbacks). After this, `isConnected` returns false.
   - What's unclear: The exact timing between socket close and `isConnected` becoming false. There may be a brief window where the socket is destroyed but `_socket` hasn't been nulled yet.
   - Recommendation: Poll `isConnected` every 500ms in the connection loop. When it returns false, the loop proceeds to reconnect. The 500ms granularity is acceptable for HMI status display. Alternative: use a Completer that completes when a test send fails, but this adds unnecessary complexity for Phase 4 (send/read is Phase 5).

2. **Constructor style for Phase 8 compatibility**
   - What we know: Phase 8 will serialize/deserialize ModbusConfig from JSON. The wrapper constructor needs host, port, and unitId at minimum.
   - What's unclear: Whether Phase 8 will construct wrappers directly or through a factory function.
   - Recommendation: Use raw parameters (host, port, unitId) for the constructor. A config object can be introduced in Phase 8 if needed -- adding a `ModbusClientWrapper.fromConfig()` factory is non-breaking.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dart test ^1.25.0 |
| Config file | packages/tfc_dart/dart_test.yaml (if exists) or none |
| Quick run command | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` |
| Full suite command | `cd packages/tfc_dart && dart test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONN-01 | Connect to Modbus device given host, port, unit ID | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "connects with host port unitId" -x` | Wave 0 |
| CONN-02 | Auto-reconnect with exponential backoff | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "reconnect" -x` | Wave 0 |
| CONN-03 | Status streams via BehaviorSubject | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "status" -x` | Wave 0 |
| CONN-05 | Multiple independent wrapper instances | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "multiple" -x` | Wave 0 |
| TEST-03 | Unit tests for connection lifecycle and reconnect | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart`
- **Per wave merge:** `cd packages/tfc_dart && dart test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` -- covers CONN-01, CONN-02, CONN-03, CONN-05, TEST-03
- [ ] Need to verify `ModbusTestServer` is importable from tfc_dart tests (it lives in `packages/modbus_client_tcp/test/`). If not, either copy it or make it a `lib/testing/` export. Alternative: create a simpler test helper that just tracks connect/disconnect calls without real TCP.

**Test infrastructure note:** The existing `ModbusTestServer` in `packages/modbus_client_tcp/test/` cannot be imported from `packages/tfc_dart/test/` because it is in a `test/` directory (not exported from `lib/`). Options:
1. Move `ModbusTestServer` to `packages/modbus_client_tcp/lib/testing/modbus_test_server.dart` and export it
2. Copy the server to `packages/tfc_dart/test/helpers/`
3. Create a minimal mock that doesn't need real TCP (just tracks connect/disconnect calls via factory injection)

**Recommendation:** Option 3 for Phase 4 -- the wrapper's connection lifecycle can be fully tested by injecting a mock `ModbusClientTcp` factory that returns a fake client with controllable `connect()` / `isConnected` behavior. Real TCP testing with `ModbusTestServer` is better suited for Phase 5 (reading) where MBAP framing matters. However, if integration confidence is desired, option 2 (copy) is the simplest path.

## Discretion Recommendations

Based on research of existing patterns and ModbusClientTcp internals:

### Connection loop management: Own loop (not built-in auto-connect)
**Rationale:** ModbusClientTcp's `autoConnectAndKeepConnected` only auto-connects on `send()`, has no status stream, no backoff control, and no reconnect events. The wrapper must own the loop.

### connect() return type: void (fire-and-forget)
**Rationale:** MSocket.connect() returns void and starts the loop asynchronously. M2400ClientWrapper.connect() returns void. This is the established pattern. Status is observed via `connectionStream`, not the return value.

### Health monitoring: TCP keepalive only (no app-level heartbeat)
**Rationale:** ModbusClientTcp has properly configured keepalive (5s/2s/3 probes = ~11s detection) from Phase 1/3 work. The socket `onDone` handler fires when keepalive detects dead connection. App-level health reads add complexity (which register to read? what if device has no readable registers?) and can be added later if TCP keepalive proves insufficient.

### Error handling: Log + transition status (no wrapper-specific exceptions)
**Rationale:** Connection errors are handled by the loop (catch, log, backoff, retry). The wrapper's public API communicates via `connectionStream`, not exceptions. This matches MSocket and M2400ClientWrapper patterns.

### File location: `packages/tfc_dart/lib/core/modbus_client_wrapper.dart`
**Rationale:** tfc_dart already depends on modbus_client_tcp and rxdart. state_man.dart (which has DeviceClient and ConnectionStatus) is in the same directory. No new package dependency needed.

### Constructor style: Raw parameters (host, port, unitId)
**Rationale:** Simple, matches MSocket(host, port) and M2400ClientWrapper(host, port) patterns. Phase 8 can add a fromConfig() factory later without breaking changes.

### ConnectionStatus enum: Use state_man.dart's ConnectionStatus
**Rationale:** The wrapper lives in tfc_dart alongside state_man.dart. Using the same enum avoids the jbtm-style mapping layer that M2400DeviceClientAdapter needs. The wrapper can import ConnectionStatus directly from state_man.dart (or it could be extracted to its own file to avoid a heavy import, but state_man.dart is already a core dependency).

### Disconnect detection: Poll isConnected every 250-500ms
**Rationale:** After a successful `connect()`, the wrapper needs to know when the connection drops. ModbusClientTcp's socket listener calls `disconnect()` internally, setting `_socket = null` and making `isConnected` return false. A periodic check is simple and reliable. The alternative (trying to listen on ModbusClientTcp's socket directly) breaks encapsulation.

## Sources

### Primary (HIGH confidence)
- `packages/jbtm/lib/src/msocket.dart` -- MSocket connection loop, backoff, status streaming (production reference)
- `packages/jbtm/lib/src/m2400_client_wrapper.dart` -- Factory injection, dual lifecycle, status piping (production reference)
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart` -- ModbusClientTcp API, connect/disconnect/isConnected, socket management
- `packages/modbus_client/lib/modbus_client.dart` -- ModbusConnectionMode enum, ModbusClient base class
- `packages/modbus_client/lib/src/modbus_client.dart` -- ModbusClient abstract class API
- `packages/tfc_dart/lib/core/state_man.dart` -- ConnectionStatus enum, DeviceClient interface, M2400DeviceClientAdapter
- `packages/modbus_client_tcp/test/modbus_test_server.dart` -- Test server for TCP-level testing
- `packages/jbtm/test/msocket_test.dart` -- MSocket test patterns (TDD reference)
- `packages/jbtm/test/m2400_client_wrapper_test.dart` -- M2400ClientWrapper test patterns (TDD reference)

### Secondary (MEDIUM confidence)
- ModbusClientTcp socket lifecycle behavior (inferred from source code analysis, not separately documented)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries are already in use in the project, versions confirmed from pubspec.yaml
- Architecture: HIGH -- patterns are directly copied from production MSocket and M2400ClientWrapper code in the same project
- Pitfalls: HIGH -- identified from source code analysis of ModbusClientTcp internals and existing test patterns

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable -- all dependencies are local forks under project control)
