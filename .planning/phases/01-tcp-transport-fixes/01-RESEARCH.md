# Phase 1: TCP Transport Fixes - Research

**Researched:** 2026-03-06
**Domain:** Modbus TCP protocol library fixes (Dart, modbus_client_tcp fork)
**Confidence:** HIGH

## Summary

Phase 1 fixes five specific bugs/gaps in the centroid-is fork of `modbus_client_tcp` (Dart package). The fork lives at `https://github.com/centroid-is/modbus_client_tcp.git` on the `add-keepalive` branch, currently at commit `182e071`. The source file is a single `lib/src/modbus_client_tcp.dart` (~310 lines) containing `ModbusClientTcp` and its private `_TcpResponse` helper class. The existing test file is empty (placeholder only).

All five fixes are well-understood, localized changes to a single file. The bugs are verifiable from the source code and the Modbus TCP specification (MBAP header structure). The test infrastructure needs to be built from scratch, but the project has an excellent reference pattern in `packages/jbtm/test/msocket_test.dart` and `test_tcp_server.dart` for TCP-level testing.

**Primary recommendation:** Fork the modbus_client_tcp code into the project (e.g., `packages/modbus_client_tcp/`) rather than patching in the pub cache. This enables proper version control, testing, and CI integration. All five fixes touch `lib/src/modbus_client_tcp.dart` and `test/modbus_client_tcp_test.dart`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TCPFIX-01 | Frame length check accounts for 6-byte MBAP header (fix off-by-6 bug) | Bug identified at line 304: `_data.length >= _resDataLen!` should be `_data.length >= _resDataLen! + 6`. See Architecture Patterns > Bug Analysis for details. |
| TCPFIX-02 | Concurrent requests via transaction ID map (replace single `_currentResponse`) | Current `_currentResponse` is single field; must become `Map<int, _TcpResponse>`. Lock must be removed from send() to allow concurrency. See Architecture Patterns > Concurrency Fix. |
| TCPFIX-03 | MBAP length field validated (1-254 range, reject malformed) | No validation exists; add after line 301 where `_resDataLen` is set. Per Modbus spec, valid range is 1-254 (unit ID byte + max 253-byte PDU). |
| TCPFIX-04 | TCP_NODELAY enabled after socket connect | Missing entirely. Add `socket.setOption(SocketOption.tcpNoDelay, true)` after connect, same as MSocket does at line 83. |
| TCPFIX-05 | Keepalive values match MSocket (5s idle, 2s interval, 3 probes) | Already partially done in the `add-keepalive` branch but with wrong values: uses `keepAliveInterval` (default 10s) for both idle AND interval. Must change to 5s idle, 2s interval, 3 probes to match MSocket. |
| TEST-01 | Unit tests covering frame parsing, concurrent transactions, length validation, and keepalive | Empty test file exists. Must build test suite using `TestTcpServer` pattern from jbtm. TDD: tests first. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client_tcp | 1.2.3 (centroid fork, add-keepalive branch) | Modbus TCP client with MBAP framing | The fork we are fixing. Integrates with modbus_client's request/response pattern. |
| modbus_client | 1.4.4 (pub.dev) | Base Modbus protocol types and request classes | Provides `ModbusRequest`, `ModbusResponseCode`, function codes, register types. Not modified in this phase. |
| synchronized | 3.4.0 | Async mutex/lock for Dart | Used by modbus_client_tcp for serialized send(). Will be modified (lock scope change) for concurrent request support. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| test | ^1.25.0 | Dart test framework | All unit tests for this phase |
| dart:io | (SDK) | TCP sockets, platform detection | Socket options (TCP_NODELAY, SO_KEEPALIVE), raw socket options |
| dart:typed_data | (SDK) | Uint8List, ByteData for binary protocol parsing | MBAP header construction and parsing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Forking into project | Patching pub cache | Pub cache patches are lost on `dart pub get`. Fork into project for proper version control. |
| synchronized Lock | Dart Completer-based concurrency | Lock is already in the codebase; modify its scope rather than replacing. |

**Installation (for project-local fork):**
```bash
# Copy from pub cache to project
cp -r ~/.pub-cache/git/modbus_client_tcp-182e071d464abd42dba1e5f543f99f4f94883c2c packages/modbus_client_tcp

# Update pubspec.yaml in packages/tfc_dart to use path dependency
# modbus_client_tcp:
#   path: ../modbus_client_tcp
```

## Architecture Patterns

### Project Structure for the Fork
```
packages/modbus_client_tcp/
├── lib/
│   ├── modbus_client_tcp.dart          # Barrel export
│   └── src/
│       └── modbus_client_tcp.dart      # Main implementation (fix target)
├── test/
│   ├── modbus_client_tcp_test.dart     # All unit tests (currently empty)
│   └── test_helpers.dart               # Mock Modbus server for tests
├── pubspec.yaml
└── CHANGELOG.md
```

### Bug Analysis: TCPFIX-01 (Frame Length Off-by-6)

**What:** The MBAP (Modbus Application Protocol) header is 7 bytes:
- Bytes 0-1: Transaction ID (2 bytes)
- Bytes 2-3: Protocol ID (2 bytes, always 0x0000)
- Bytes 4-5: Length field (2 bytes) -- counts bytes AFTER this field (unit ID + PDU)
- Byte 6: Unit ID (1 byte)

The length field value does NOT include the 6 bytes before it (transaction ID + protocol ID + length field itself). So total frame size = length field value + 6.

**The bug (line 304):**
```dart
// CURRENT (WRONG):
if (_resDataLen != null && _data.length >= _resDataLen!) {
// _resDataLen is set from MBAP length field (bytes 4-5)
// _data.length is TOTAL received bytes including the 6-byte header prefix
// This triggers too early -- declares "got all data" when _data has only
// received (length field) bytes, but actually needs (length field + 6) bytes.

// CORRECT:
if (_resDataLen != null && _data.length >= _resDataLen! + 6) {
```

**Example:** A response with 3 registers (6 data bytes):
- MBAP length field = 9 (1 unit ID + 1 function code + 1 byte count + 6 data bytes)
- Total frame = 9 + 6 = 15 bytes
- Bug triggers at 9 bytes received (missing the last 6 bytes of actual data)

**Why it sometimes works:** For small responses where all data arrives in a single TCP segment, `_data.length` is already the full frame. The bug manifests when responses are split across multiple TCP segments or when the payload is large.

### Bug Analysis: TCPFIX-02 (Concurrent Requests)

**What:** The current implementation uses a `Lock` around the entire `send()` method, serializing all requests. Additionally, `_currentResponse` is a single field, meaning only one response handler exists at a time.

**Current flow:**
1. `send()` acquires `_lock`
2. Creates `_currentResponse = _TcpResponse(...)` with transaction ID
3. Writes request to socket
4. Awaits `request.responseCode` (which completes when `_TcpResponse.addResponseData` finishes)
5. Releases `_lock`

**Problem:** The lock means request B cannot start until request A fully completes (including waiting for response). This prevents pipelining multiple requests to the same device.

**Fix approach:**
1. Replace `_TcpResponse? _currentResponse` with `Map<int, _TcpResponse> _pendingResponses = {}`
2. Narrow the lock scope to protect only socket write (not the response wait)
3. In `_onSocketData`, parse the transaction ID from incoming data and route to the correct `_TcpResponse`
4. Handle the case where a response arrives for an unknown transaction ID (log warning, discard)

**Critical subtlety:** The `_onSocketData` callback receives raw TCP data that may contain multiple Modbus responses concatenated, or partial responses. The current code handles partial responses (buffering until complete) but assumes a single stream. With concurrent requests, partial data routing becomes more complex. **Recommendation:** Keep the Lock to serialize request sends (maintaining ordering guarantees) but allow the response wait to happen outside the lock. This is simpler and still enables pipelining at the TCP level since the Modbus device can process requests while we are waiting for previous responses.

**Simpler concurrent approach:**
```dart
Future<ModbusResponseCode> send(ModbusRequest request) async {
  // Only lock around the socket write, not the response wait
  var transactionId = await _lock.synchronized(() async {
    // connect if needed...
    var tid = _getNextTransactionId();
    var response = _TcpResponse(request, transactionId: tid, timeout: ...);
    _pendingResponses[tid] = response;
    // write to socket...
    _socket!.add(header);
    return tid;
  });
  // Wait for response OUTSIDE the lock
  var res = await request.responseCode;
  _pendingResponses.remove(transactionId);
  return res;
}
```

### Bug Analysis: TCPFIX-03 (Length Field Validation)

**What:** No validation on the MBAP length field. Per the Modbus TCP specification:
- Minimum: 1 (just a unit ID byte with no PDU -- invalid but some devices send this)
- Practical minimum: 2 (unit ID + exception function code)
- Maximum: 254 (1 unit ID + 253 max PDU bytes)
- Value of 0: Invalid (no unit ID)
- Value > 254: Exceeds max Modbus ADU size

**Where to add (after current line 301):**
```dart
_resDataLen = resView.getUint16(4);
// Validate MBAP length field
if (_resDataLen! < 1 || _resDataLen! > 254) {
  ModbusAppLogger.warning(
      "Invalid MBAP length", "${_resDataLen} not in range 1-254");
  _timeout.complete();
  request.setResponseCode(ModbusResponseCode.requestRxFailed);
  return;
}
```

**Note:** The requirement says "1-256 range" but the Modbus spec says max PDU is 253 bytes, so max length field is 254. Using 254 is more correct. However, to be defensive, we could use 260 (allowing slightly over-spec devices). **Recommendation:** Use 254 as the upper bound per spec, but document the reasoning.

### Bug Analysis: TCPFIX-04 (TCP_NODELAY)

**What:** The Nagle algorithm buffers small TCP writes, introducing up to 200ms latency. Modbus requests are small (typically 12 bytes) and latency-sensitive.

**Fix:** Add one line after socket connect in `connect()`:
```dart
_socket = await Socket.connect(serverAddress, serverPort, timeout: connectionTimeout);
_socket!.setOption(SocketOption.tcpNoDelay, true);  // ADD THIS
_enableKeepAlive(_socket!);
```

**Reference:** MSocket already does this at line 83:
```dart
_socket!.setOption(SocketOption.tcpNoDelay, true);
```

### Bug Analysis: TCPFIX-05 (Keepalive Values)

**What:** The `add-keepalive` branch already added `_enableKeepAlive()` but with wrong values. It uses the constructor parameter `keepAliveInterval` (default 10 seconds) for BOTH the idle time AND the probe interval. MSocket uses:
- Idle: 5 seconds (time before first probe)
- Interval: 2 seconds (time between probes)
- Count: 3 probes (before declaring dead)
- Detection time: ~11 seconds (5 + 2*3)

The current fork uses:
- Idle: `intervalSeconds` (default 10s)
- Interval: `intervalSeconds` (default 10s)
- Count: `count` (default 3)
- Detection time: ~40 seconds (10 + 10*3)

**Fix approach:** Change constructor defaults and separate idle from interval:
```dart
ModbusClientTcp(this.serverAddress, {
  // ...
  this.keepAliveIdle = const Duration(seconds: 5),
  this.keepAliveInterval = const Duration(seconds: 2),
  this.keepAliveCount = 3,
  // ...
});
```

Then update `_enableKeepAlive()` to use separate idle/interval values. The platform-specific socket constants are already correct in the fork (matching MSocket's approach).

### Anti-Patterns to Avoid

- **Testing against real Modbus devices:** Tests must use a mock TCP server that speaks raw bytes. Never depend on network hardware for unit tests.
- **Modifying pub cache directly:** Changes are lost on `dart pub get`. Fork into the project.
- **Removing the Lock entirely for TCPFIX-02:** The lock protects socket writes from interleaving. Keep it for write serialization, just don't hold it during response wait.
- **Using `RawSocket` instead of `Socket`:** `ModbusClientTcp` uses `Socket` (which is an `IOSink`). Switching to `RawSocket` would require rewriting the entire class. Not worth it for these fixes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MBAP frame parsing | Custom TCP protocol parser | Fix the existing `_TcpResponse.addResponseData()` | The existing code handles partial TCP segments correctly; just fix the length check |
| Keepalive socket options | Custom heartbeat/ping mechanism | OS-level SO_KEEPALIVE via `setRawOption()` | Kernel-level keepalive is more reliable and doesn't require application-level timers |
| Test TCP server | Complex mock framework | Simple `ServerSocket.bind` + raw byte responses | Same pattern as `TestTcpServer` in jbtm. Modbus responses are just byte arrays. |
| Transaction ID generation | UUID or complex ID scheme | Simple uint16 counter with rollover (already exists) | MBAP transaction ID is 2 bytes (0-65535). Sequential counter is standard. |

**Key insight:** All five fixes are surgical changes to existing code, not new systems. The hardest part is TCPFIX-02 (concurrency) because it changes the data flow, but even that is well-bounded.

## Common Pitfalls

### Pitfall 1: Partial TCP Segments in Tests
**What goes wrong:** Tests send a complete Modbus response as a single byte array, which always works. But real TCP can split a response into multiple segments.
**Why it happens:** `Socket.listen` delivers data as received from the OS, which may split or concatenate TCP segments arbitrarily.
**How to avoid:** Write tests that deliberately split responses at various byte boundaries (mid-header, mid-PDU, one byte at a time).
**Warning signs:** Tests pass but production fails with large payloads or high-latency networks.

### Pitfall 2: Concatenated TCP Segments
**What goes wrong:** Two Modbus responses arrive in a single `_onSocketData` callback. Without proper handling, the second response is lost.
**Why it happens:** TCP is a stream protocol. When the device responds quickly to back-to-back requests, the OS may deliver both responses in one read.
**How to avoid:** After completing one response, check if there are remaining bytes in the buffer that belong to the next response. This is especially important for TCPFIX-02 (concurrent requests).
**Warning signs:** Second concurrent request times out even though the device responded.

### Pitfall 3: Lock Scope in Concurrent Fix
**What goes wrong:** Removing the lock entirely causes interleaved socket writes (request A's header followed by request B's header before A's PDU).
**Why it happens:** `_socket!.add(header)` is not atomic at the TCP level for large writes.
**How to avoid:** Keep the lock around socket write operations. Only release it before awaiting the response.
**Warning signs:** Garbled responses from the device, intermittent failures under concurrent load.

### Pitfall 4: Completer Double-Complete
**What goes wrong:** `setResponseCode` is called on a request whose completer is already completed, throwing a `StateError`.
**Why it happens:** Timeout fires after response is already received, or response arrives after timeout.
**How to avoid:** The base `ModbusRequest.setResponseCode` already checks `_responseCompleter.isCompleted`. The `_TcpResponse` class uses a separate `_timeout` Completer with `_timeout.isCompleted` guard. Maintain both guards.
**Warning signs:** `StateError: Future already completed` in logs.

### Pitfall 5: Platform-Specific Socket Option Constants
**What goes wrong:** Using Linux socket option constants on macOS or vice versa causes `SocketException`.
**Why it happens:** SO_KEEPALIVE is 0x0009 on Linux but 0x0008 on macOS. TCP_KEEPIDLE is 4 on Linux but TCP_KEEPALIVE is 0x10 on macOS.
**How to avoid:** The existing `_enableKeepAlive()` already has correct platform branching. Preserve this structure, just fix the values.
**Warning signs:** Tests pass on developer's Mac but fail on Linux CI, or vice versa.

## Code Examples

Verified patterns from the actual codebase:

### MBAP Header Construction (from `send()` method)
```dart
// Source: modbus_client_tcp.dart lines 113-121
int pduLen = request.protocolDataUnit.length;
var header = Uint8List(pduLen + 7);
ByteData.view(header.buffer)
  ..setUint16(0, transactionId)       // Transaction ID (2 bytes)
  ..setUint16(2, 0)                   // Protocol ID = 0 (2 bytes)
  ..setUint16(4, pduLen + 1)          // Length = PDU + 1 (unit ID byte)
  ..setUint8(6, getUnitId(request));  // Unit ID (1 byte)
header.setAll(7, request.protocolDataUnit);
```

### MBAP Response Parsing Fix (TCPFIX-01 corrected code)
```dart
// Source: modbus_client_tcp.dart _TcpResponse.addResponseData, corrected
_resDataLen = resView.getUint16(4);  // MBAP length field

// TCPFIX-03: Validate length field range
if (_resDataLen! < 1 || _resDataLen! > 254) {
  _timeout.complete();
  request.setResponseCode(ModbusResponseCode.requestRxFailed);
  return;
}

// TCPFIX-01: Total frame = MBAP header prefix (6 bytes) + length field value
if (_resDataLen != null && _data.length >= _resDataLen! + 6) {
  _timeout.complete();
  request.setFromPduResponse(Uint8List.fromList(_data.sublist(7)));
}
```

### TCP_NODELAY (from MSocket reference)
```dart
// Source: packages/jbtm/lib/src/msocket.dart line 83
_socket!.setOption(SocketOption.tcpNoDelay, true);
```

### Keepalive Configuration (MSocket reference values)
```dart
// Source: packages/jbtm/lib/src/msocket.dart lines 127-158
// Values: idle=5s, interval=2s, count=3 (~11s detection)
if (Platform.isMacOS || Platform.isIOS) {
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelSocket, 0x0008, 1));  // SO_KEEPALIVE
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, 0x10, 5));       // TCP_KEEPALIVE (idle)
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, 0x101, 2));      // TCP_KEEPINTVL
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, 0x102, 3));      // TCP_KEEPCNT
} else if (Platform.isLinux || Platform.isAndroid) {
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelSocket, 0x0009, 1));  // SO_KEEPALIVE
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, 4, 5));          // TCP_KEEPIDLE
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, 5, 2));          // TCP_KEEPINTVL
  socket.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, 6, 3));          // TCP_KEEPCNT
}
```

### Test TCP Server Pattern (from jbtm)
```dart
// Source: packages/jbtm/lib/src/test_tcp_server.dart
// Bind to loopback on OS-assigned port, track clients, send raw bytes
final server = TestTcpServer();
final port = await server.start();
// ... test code connects to localhost:port ...
server.sendToAll([0x00, 0x01, 0x00, 0x00, 0x00, 0x05, 0x01, 0x03, 0x02, 0xAB, 0xCD]);
// ... assert response parsed correctly ...
await server.shutdown();
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single response handler | Transaction ID map for concurrent requests | This phase (TCPFIX-02) | Enables pipelining multiple Modbus requests |
| No TCP_NODELAY | TCP_NODELAY after connect | This phase (TCPFIX-04) | Eliminates 200ms Nagle buffering delay |
| 10s keepalive interval | 5s idle / 2s interval / 3 probes | This phase (TCPFIX-05) | Dead connection detected in ~11s instead of ~40s |
| Dart `Socket.setOption` for keepalive | `Socket.setRawOption` with platform constants | Already in fork | Fine-grained control over keepalive parameters |

**Deprecated/outdated:**
- `Socket.setOption(SocketOption.tcpNoDelay, true)` is the current/correct API. The older `TCP_NODELAY` constant style is deprecated in favor of `SocketOption.tcpNoDelay`.

## Open Questions

1. **Should the fork live at `packages/modbus_client_tcp/` or remain a git dependency?**
   - What we know: The modbus-test branch used a git dependency (`ref: add-keepalive`). But we need to make code changes, write tests, and iterate.
   - What's unclear: Whether the team prefers to push fixes to the centroid-is fork and reference by commit, or keep a local copy.
   - Recommendation: Copy into `packages/modbus_client_tcp/` for this phase (enables TDD workflow). Push upstream after fixes are validated. Reference as `path: ../modbus_client_tcp` in tfc_dart's pubspec.

2. **Should TCPFIX-02 (concurrency) handle concatenated responses in a single TCP segment?**
   - What we know: With concurrent requests, the device may send two responses back-to-back in one TCP read.
   - What's unclear: How common this is in practice with typical Modbus devices.
   - Recommendation: Yes, handle it. After completing one response, check for remaining bytes and route to the next pending response. This is critical for correctness.

3. **MBAP length field upper bound: 254 (per spec) or 256 (per requirement)?**
   - What we know: Modbus spec says max PDU is 253 bytes, so max MBAP length is 254 (1 unit ID + 253 PDU). The requirement says ">256".
   - What's unclear: Whether some devices send slightly over-spec responses.
   - Recommendation: Use 254 as the strict upper bound per spec. This is safer; any device sending >254 is non-compliant and the response would be unparseable anyway.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Dart `test` package ^1.25.0 |
| Config file | None -- will use defaults (see Wave 0) |
| Quick run command | `cd packages/modbus_client_tcp && dart test` |
| Full suite command | `cd packages/modbus_client_tcp && dart test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TCPFIX-01 | Frame length check includes 6-byte MBAP header | unit | `cd packages/modbus_client_tcp && dart test test/modbus_client_tcp_test.dart -n "frame length"` | No -- Wave 0 |
| TCPFIX-02 | Concurrent requests resolved via transaction ID | unit | `cd packages/modbus_client_tcp && dart test test/modbus_client_tcp_test.dart -n "concurrent"` | No -- Wave 0 |
| TCPFIX-03 | MBAP length field validated (reject 0 and >254) | unit | `cd packages/modbus_client_tcp && dart test test/modbus_client_tcp_test.dart -n "length validation"` | No -- Wave 0 |
| TCPFIX-04 | TCP_NODELAY enabled on connections | unit | `cd packages/modbus_client_tcp && dart test test/modbus_client_tcp_test.dart -n "TCP_NODELAY"` | No -- Wave 0 |
| TCPFIX-05 | Keepalive values match MSocket (5s idle, 2s interval, 3 probes) | unit | `cd packages/modbus_client_tcp && dart test test/modbus_client_tcp_test.dart -n "keepalive"` | No -- Wave 0 |
| TEST-01 | All fix areas have unit test coverage | meta | All above tests pass | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `cd packages/modbus_client_tcp && dart test`
- **Per wave merge:** `cd packages/modbus_client_tcp && dart test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `packages/modbus_client_tcp/` -- copy fork from pub cache into project as local package
- [ ] `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart` -- all test groups (frame parsing, concurrency, validation, socket options)
- [ ] `packages/modbus_client_tcp/test/modbus_test_server.dart` -- mock Modbus TCP server that sends crafted MBAP responses (raw bytes)
- [ ] `packages/modbus_client_tcp/pubspec.yaml` -- add `test: ^1.25.0` to dev_dependencies (already present)

## Sources

### Primary (HIGH confidence)
- **Actual source code:** `/Users/jonb/.pub-cache/git/modbus_client_tcp-182e071d464abd42dba1e5f543f99f4f94883c2c/lib/src/modbus_client_tcp.dart` -- all bug analysis derived from reading this file
- **MSocket reference:** `/Users/jonb/Projects/tfc-hmi/packages/jbtm/lib/src/msocket.dart` -- keepalive values (5s/2s/3), TCP_NODELAY pattern
- **MSocket tests:** `/Users/jonb/Projects/tfc-hmi/packages/jbtm/test/msocket_test.dart` -- test structure pattern with TestTcpServer
- **TestTcpServer:** `/Users/jonb/Projects/tfc-hmi/packages/jbtm/lib/src/test_tcp_server.dart` -- reusable test server pattern
- **modbus_client base:** `/Users/jonb/.pub-cache/hosted/pub.dev/modbus_client-1.4.4/lib/src/modbus_request.dart` -- ModbusRequest API

### Secondary (MEDIUM confidence)
- [Modbus TCP MBAP header specification](https://ipc2u.com/articles/knowledge-base/detailed-description-of-the-modbus-tcp-protocol-with-command-examples/) -- MBAP header structure, PDU size limits
- [Modbus Wikipedia](https://en.wikipedia.org/wiki/Modbus) -- Max PDU 253 bytes, max ADU 260 bytes for TCP
- [Dart SocketOption.tcpNoDelay API](https://api.flutter.dev/flutter/dart-io/SocketOption/tcpNoDelay-constant.html) -- Official Dart API for TCP_NODELAY
- [Dart RawSocketOption API](https://api.dart.dev/stable/2.19.2/dart-io/RawSocketOption-class.html) -- Platform-specific socket options

### Tertiary (LOW confidence)
- None -- all findings verified from source code and official documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- directly reading the source code; no ambiguity about what exists
- Architecture: HIGH -- all five bugs are precisely identified with line numbers and fix approaches
- Pitfalls: HIGH -- derived from real TCP protocol behavior and verified against existing test patterns
- Test infrastructure: HIGH -- excellent reference implementation exists in jbtm/test/

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable -- upstream library unlikely to change)
