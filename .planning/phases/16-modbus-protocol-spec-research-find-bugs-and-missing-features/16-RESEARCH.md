# Phase 16: Modbus Protocol Spec Research -- Find Bugs and Missing Features

**Researched:** 2026-03-09
**Domain:** Modbus TCP protocol specification compliance audit
**Confidence:** HIGH

## Summary

This research audits the existing Modbus TCP implementation (forked modbus_client + modbus_client_tcp libraries plus the ModbusClientWrapper/ModbusDeviceClientAdapter layers) against the official Modbus Application Protocol Specification v1.1b and the Modbus Messaging on TCP/IP Implementation Guide. The goal is to identify protocol compliance gaps, bugs, and missing features that could cause interoperability issues with real devices.

The implementation is fundamentally sound -- the core function codes (FC01-FC06, FC15, FC16) work correctly, MBAP header parsing handles edge cases (concatenated/split frames, concurrent transactions), and the wrapper/adapter layers provide clean SCADA-safe APIs. However, the audit found 5 bugs/compliance gaps, 4 missing validations, and 3 missing features that should be addressed before the system is deployed to production with diverse Modbus devices.

**Primary recommendation:** Fix the identified bugs (especially address validation, response byte count validation, and write quantity overflow), add missing spec validations, and consider byte order configuration as a near-term enhancement since it's the most commonly needed interoperability feature.

## Findings: Bugs and Compliance Gaps

### BUG-01: No address range validation (Severity: MEDIUM)
**What:** Register addresses in `ModbusNodeConfig` and `ModbusRegisterSpec` accept any integer value. The Modbus spec limits addresses to 0-65535 (0x0000-0xFFFF). Negative addresses or addresses >65535 will produce malformed PDU requests (the address field is a uint16 in the MBAP frame).
**Where:** `key_repository.dart` line 1482 (`int.tryParse(_addressController.text) ?? 0` -- no clamp), `ModbusNodeConfig` class in `state_man.dart` (no validation), `_createElement` in `modbus_client_wrapper.dart` (passes address directly to element constructor).
**Spec reference:** All function codes use a 16-bit starting address field (0x0000-0xFFFF).
**Fix:** Clamp address to 0-65535 in UI, add assertion in `ModbusRegisterSpec` constructor.
**Confidence:** HIGH

### BUG-02: Response byte count not validated (Severity: LOW)
**What:** `ModbusElementRequest.internalSetFromPduResponse` skips byte 1 of read responses (the byte count field) without validating it matches the expected size. Per spec, for FC03/FC04, byte count = 2 * N (N = number of registers read). A malformed response with wrong byte count could cause silent data corruption or RangeError.
**Where:** `modbus_request.dart` line 80 (`pdu.sublist(2)` skips byte count without checking).
**Spec reference:** Modbus spec says response PDU byte[1] = N*2 for register reads, N = ceil(coils/8) for coil reads.
**Impact:** Low in practice (well-behaved devices echo correct byte counts), but violates defense-in-depth principle.
**Confidence:** HIGH

### BUG-03: Unit ID not validated in response (Severity: LOW)
**What:** `_TcpResponse.addResponseData` validates transaction ID and protocol ID from the MBAP header but does NOT check that the unit ID (byte 6) in the response matches the unit ID that was sent in the request. Per Modbus TCP spec, the server must echo back the same unit ID.
**Where:** `modbus_client_tcp.dart` line 386-413 (_TcpResponse validates bytes 0-5 but not byte 6).
**Spec reference:** Modbus TCP Implementation Guide: "The MODBUS server must use the same unit identifier in the response."
**Impact:** Low -- in practice devices echo the correct unit ID. Could matter with gateways routing to multiple downstream devices.
**Confidence:** HIGH

### BUG-04: Response function code not validated against request (Severity: LOW)
**What:** `ModbusRequest.setFromPduResponse` checks if bit 7 is set (exception response) but does not verify that the function code in the response matches the function code of the request. A response with the wrong function code would be silently accepted.
**Where:** `modbus_request.dart` line 55-62.
**Spec reference:** Modbus spec: "The function code in the response of a normal response is an echo of the function code in the request."
**Impact:** Very low -- transaction ID routing already ensures correct pairing in TCP mode. More relevant for serial (RTU) mode.
**Confidence:** HIGH

### BUG-05: FC15/FC16 byte count field overflow for large writes (Severity: LOW)
**What:** `getMultipleWriteRequest` encodes the byte count as `setUint8(5, bytes.length)`. This is a single byte (0-255). For FC15, max 1968 coils = 246 bytes -- fits. For FC16, max 123 registers = 246 bytes -- fits. So this is NOT actually a bug for spec-compliant quantities. However, the code does not validate that the quantity/bytes stay within spec limits. If someone calls `writeMultiple` with >123 registers (>246 bytes), the byte count field will overflow silently.
**Where:** `modbus_element.dart` line 120 (`setUint8(5, bytes.length)`).
**Spec reference:** FC16 max quantity = 123 registers (246 bytes), FC15 max quantity = 1968 coils (246 bytes).
**Fix:** Add assertions: FC16 quantity <= 123, FC15 quantity <= 1968, bytes.length <= 246.
**Confidence:** HIGH

## Findings: Missing Validations

### VAL-01: No quantity range validation on read requests
**What:** The read request construction does not validate that the quantity field (number of registers/coils) is within the spec-allowed range. The `ModbusElementsGroup` limits to 125 registers / 2000 coils (matching spec), but individual element reads don't enforce minimum (must be >= 1).
**Where:** `modbus_element.dart` line 56 (quantity = `byteCount > 1 ? byteCount ~/ 2 : 1`). This is always >= 1 for valid elements, so not a real bug -- but there's no explicit assertion.
**Impact:** Very low, more of a spec-completeness issue.
**Confidence:** HIGH

### VAL-02: FC05 write value validation
**What:** Per Modbus spec, FC05 (Write Single Coil) accepts only two values: 0x0000 (OFF) and 0xFF00 (ON). Any other value should be rejected. The library's `ModbusBitElement._getRawValue` correctly maps bool/int to 0x0000 or 0xFF00, so this is handled correctly in practice. No bug here.
**Where:** `modbus_element_bit.dart` line 37-43.
**Status:** CORRECTLY IMPLEMENTED. No action needed.
**Confidence:** HIGH

### VAL-03: Unit ID range in ModbusConfig
**What:** The UI clamps unit ID to 1-247, which is correct for Modbus serial addressing but slightly restrictive for Modbus TCP. In TCP mode, unit ID 0 is used for broadcast and unit ID 255 is commonly used for direct IP-addressed devices. The current range may prevent connecting to some TCP-only devices that use unit ID 0 or 255.
**Where:** `server_config.dart` line 1618 (`.clamp(1, 247)`).
**Spec reference:** Modbus TCP Implementation Guide recommends unit ID 255 for TCP queries when no gateway routing is needed. Unit ID 0 is broadcast (no response expected).
**Fix:** Expand to 0-255 for TCP connections. Consider warning for unit ID 0 (broadcast, no response) and 248-254 (reserved in serial spec, but valid in TCP).
**Confidence:** HIGH

### VAL-04: Protocol ID not validated in router-level buffer processing
**What:** `_processIncomingBuffer` validates transaction ID and MBAP length but does not check protocol ID (bytes 2-3 must be 0x0000 for Modbus). The `_TcpResponse` defense-in-depth layer does check protocol ID. This is low risk but inconsistent.
**Where:** `modbus_client_tcp.dart` line 210-264 (router loop).
**Impact:** Very low -- _TcpResponse catches it as defense-in-depth.
**Confidence:** HIGH

## Findings: Missing Features

### FEAT-01: Byte/word order configuration (HIGH priority)
**What:** The `modbus_client` library supports four endianness modes (ABCD, CDAB, BADC, DCBA) but the wrapper layer (`ModbusClientWrapper._createElement`) always uses the default ABCD (big-endian) mode. Multi-register data types (int32, uint32, float32, int64, uint64, float64) frequently require non-standard byte ordering depending on the device manufacturer. This is the single most common Modbus interoperability issue in the field.
**Where:** `modbus_client_wrapper.dart` line 698-733 (`_createElement` does not set endianness on any element).
**Status:** Listed as ADV-01 in v2 requirements. Recommend promoting to v1 based on real-world impact.
**Config change needed:** Add `endianness` field to `ModbusConfig` (per-device) or `ModbusNodeConfig` (per-register). Per-device is more common (all registers on a device typically use the same byte order).
**Confidence:** HIGH

### FEAT-02: Diagnostics function code FC08 (LOW priority)
**What:** The Modbus spec defines FC08 (Diagnostics) with sub-function 0x0000 (Return Query Data) as a standard way to test device responsiveness. This is more robust than the current heartbeat approach (reading holding register 0, which may not exist on all devices). However, the current heartbeat approach works fine for devices that support FC03.
**Where:** Not implemented. Would be useful as an alternative heartbeat mechanism.
**Impact:** Low -- current heartbeat works for most devices. FC08 could be a fallback option.
**Confidence:** MEDIUM

### FEAT-03: Exception detail surfacing (MEDIUM priority)
**What:** When write operations fail, the error message is `Write failed: ${result.name}` where `result.name` is the enum name (e.g., `illegalDataAddress`, `deviceFailure`). The wrapper does not distinguish between Modbus protocol exceptions (which carry device-specific information) and transport errors. More informative error reporting would help operators diagnose issues.
**Where:** `modbus_client_wrapper.dart` lines 378-379, 404-405.
**Fix:** Include the exception code value and a human-readable description. Distinguish between spec-defined exceptions (0x01-0x0B) and library-internal codes (0xF0-0xFF).
**Confidence:** HIGH

## Spec Compliance Summary Table

| Spec Requirement | Status | Notes |
|-----------------|--------|-------|
| FC01 Read Coils (max 2000) | PASS | ModbusElementsGroup.maxCoilsRange = 2000 |
| FC02 Read Discrete Inputs (max 2000) | PASS | Same as FC01 |
| FC03 Read Holding Registers (max 125) | PASS | ModbusElementsGroup.maxRegistersRange = 125 |
| FC04 Read Input Registers (max 125) | PASS | Same as FC03 |
| FC05 Write Single Coil (0x0000/0xFF00) | PASS | _getRawValue maps correctly |
| FC06 Write Single Register | PASS | |
| FC15 Write Multiple Coils (max 1968) | NO VALIDATION | Works but no quantity limit check |
| FC16 Write Multiple Registers (max 123) | NO VALIDATION | Works but no quantity limit check |
| MBAP header: Transaction ID matching | PASS | Router + _TcpResponse both check |
| MBAP header: Protocol ID = 0 | PARTIAL | _TcpResponse checks, router does not |
| MBAP header: Length field 1-254 (or 65535 for FC90) | PASS | Both layers validate |
| MBAP header: Unit ID echo | MISSING | Not validated in response |
| PDU max size: 253 bytes | IMPLICIT | Element sizes enforce practical limits |
| Address range: 0-65535 | MISSING | No validation in wrapper or UI |
| Response function code echo | MISSING | Not validated against request |
| Response byte count validation | MISSING | Skipped in read response parsing |
| Error responses (FC + 0x80) | PASS | Correctly detected and mapped |
| Exception codes (0x01-0x0B) | PASS | All standard codes defined in enum |
| TCP_NODELAY | PASS | Set after connect |
| TCP keepalive (cross-platform) | PASS | Platform-specific socket options |
| Multi-register endianness | MISSING | Library supports, wrapper does not expose |
| Concurrent transactions | PASS | Transaction ID map with lock-narrowed write |
| Partial/concatenated frame handling | PASS | BytesBuilder incoming buffer with while-loop parser |

## Architecture Patterns

### Current Implementation Stack

```
Flutter UI (server_config.dart, key_repository.dart)
    |
    v
StateMan (state_man.dart) -- route by protocol
    |
    v
ModbusDeviceClientAdapter (modbus_device_client.dart) -- DeviceClient interface
    |
    v
ModbusClientWrapper (modbus_client_wrapper.dart) -- connection, polling, reading, writing
    |
    v
ModbusClientTcp (modbus_client_tcp.dart) -- MBAP framing, TCP transport, keepalive
    |
    v
modbus_client library -- element types, request/response PDU, function codes
```

### Where Fixes Should Go

| Finding | Fix Layer | Files Affected |
|---------|-----------|----------------|
| BUG-01 address validation | UI + config + wrapper | key_repository.dart, state_man.dart, modbus_client_wrapper.dart |
| BUG-02 response byte count | Library (modbus_client) | modbus_request.dart |
| BUG-03 unit ID validation | Library (modbus_client_tcp) | modbus_client_tcp.dart |
| BUG-04 function code echo | Library (modbus_client) | modbus_request.dart |
| BUG-05 write quantity limits | Library (modbus_client) | modbus_element.dart |
| VAL-03 unit ID range | UI | server_config.dart |
| FEAT-01 byte order | Config + wrapper | state_man.dart, modbus_client_wrapper.dart, server_config.dart, key_repository.dart |
| FEAT-03 error detail | Wrapper | modbus_client_wrapper.dart |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Byte order handling | Custom byte swapping | modbus_client's ModbusEndianness enum (ABCD/CDAB/BADC/DCBA) | Already implemented and tested in library, just needs wiring through wrapper |
| MBAP frame parsing | New frame parser | Existing _processIncomingBuffer + _TcpResponse | Already handles all edge cases (concatenated, split, partial frames) |
| Exception code mapping | Custom error codes | ModbusResponseCode enum | All standard Modbus exception codes already defined |

## Common Pitfalls

### Pitfall 1: Byte order confusion between device and library
**What goes wrong:** Device documentation says "word swap" but library uses CDAB/BADC/ABCD/DCBA terminology. The mapping is: ABCD = big-endian (Modbus standard), CDAB = word swap, BADC = byte swap, DCBA = word+byte swap.
**Why it happens:** Different device vendors use different terminology for the same byte ordering.
**How to avoid:** Provide clear labels in the UI that show both the vendor-neutral name (ABCD etc.) and the common name (Big-Endian, Word Swap, etc.).
**Warning signs:** Multi-register values (float32, int32) read as garbage or very large/small numbers.

### Pitfall 2: Address numbering confusion (0-based vs 1-based)
**What goes wrong:** Device documentation says "Holding Register 40001" but the Modbus protocol uses 0-based addressing. Register 40001 is actually address 0 in FC03.
**Why it happens:** The "4xxxx" notation is a legacy Modicon convention where the leading digit indicates the register type (4 = holding register, 3 = input register, 0 = coil, 1 = discrete input) and the remaining digits are 1-based.
**How to avoid:** The current implementation uses 0-based addressing (consistent with protocol). Document this clearly in the UI. Consider adding a "Use 1-based addressing" toggle or showing both formats.
**Warning signs:** All values are shifted by one register position.

### Pitfall 3: Register boundary crossing in batch reads
**What goes wrong:** A batch read includes registers at addresses that are not implemented on the device. The device responds with exception code 0x02 (Illegal Data Address), and the entire batch fails.
**Why it happens:** Batch coalescing with gap filling reads "holes" between subscribed registers that may not exist on the device.
**How to avoid:** The existing gap threshold limits wasteful reads. If a device has sparse register maps, users should configure separate poll groups or the gap threshold should be configurable.
**Warning signs:** Batch reads that worked for contiguous registers start failing when non-contiguous registers are added.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dart test (test package) |
| Config file | packages/tfc_dart/pubspec.yaml (dev_dependencies: test) |
| Quick run command | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact` |
| Full suite command | `cd packages/tfc_dart && dart test test/core/ --reporter compact` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BUG-01 | Address clamped to 0-65535 | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart -x` | Existing file, new tests needed |
| BUG-02 | Response byte count validated | unit | `cd packages/modbus_client_tcp && dart test` | Existing file, new tests needed |
| BUG-03 | Unit ID validated in response | unit | `cd packages/modbus_client_tcp && dart test` | Existing file, new tests needed |
| BUG-05 | Write quantity limits enforced | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart -x` | Existing file, new tests needed |
| VAL-03 | Unit ID 0-255 accepted | widget | Widget test in centroid-hmi/test/ | Depends on scope decision |
| FEAT-01 | Byte order passes through to element | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart -x` | New tests needed |

### Sampling Rate
- **Per task commit:** `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --reporter compact`
- **Per wave merge:** `cd packages/tfc_dart && dart test test/core/ --reporter compact && cd packages/modbus_client_tcp && dart test --reporter compact`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. Test files exist, new test cases need to be added within them.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single _currentResponse | Transaction ID map with concurrent support | Phase 1 (TCPFIX-02) | Enables parallel requests |
| Individual element reads | Batch coalesced group reads | Phase 5 (Plan 02) | Dramatically reduces TCP round-trips |
| No keepalive | Platform-specific SO_KEEPALIVE | Phase 1 (TCPFIX-05) | ~11s dead connection detection |
| App-level heartbeat only | Heartbeat + TCP keepalive | Phase 15 | Dual detection mechanism |

## Open Questions

1. **Should FEAT-01 (byte order) be promoted from v2 to this phase?**
   - What we know: It is listed as ADV-01 in v2 requirements. The library already supports it. Only wiring is needed.
   - What's unclear: Whether the user wants this in this research/fix phase or deferred.
   - Recommendation: Include it as an optional plan. It is the most impactful missing feature for real-world device compatibility.

2. **Should BUG-02/BUG-03/BUG-04 (response validation) be fixed?**
   - What we know: These are spec compliance gaps, not production bugs. They are LOW severity.
   - What's unclear: Whether the user wants library-level fixes for theoretical issues.
   - Recommendation: Fix BUG-02 and BUG-03 (they affect robustness). Skip BUG-04 (function code validation is redundant with transaction ID routing in TCP mode).

3. **Gap threshold configurability**
   - What we know: Current thresholds (10 registers, 100 coils) are hardcoded. Some devices have sparse register maps that fail with gap filling.
   - What's unclear: Whether this is a real problem in the current deployment.
   - Recommendation: Defer unless real-world testing in Phase 13 reveals issues.

## Priority Ranking for Fixes

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| 1 | BUG-01: Address validation 0-65535 | Small | Prevents malformed PDU |
| 2 | BUG-05: Write quantity limits | Small | Prevents protocol violation |
| 3 | VAL-03: Unit ID range 0-255 | Small | Enables more device types |
| 4 | FEAT-01: Byte order config | Medium | Enables most common interop need |
| 5 | FEAT-03: Exception detail surfacing | Small | Better operator diagnostics |
| 6 | BUG-02: Response byte count validation | Small | Defense-in-depth |
| 7 | BUG-03: Unit ID response validation | Small | Spec compliance |
| 8 | BUG-04: Function code echo validation | Tiny | Completeness only |

## Sources

### Primary (HIGH confidence)
- Modbus Application Protocol Specification v1.1b (modbus.org) -- function code limits, PDU structure, exception codes
- [Fernhill Software Modbus Protocol Reference](https://www.fernhillsoftware.com/help/drivers/modbus/modbus-protocol.html) -- function code details, quantity limits
- [Modbus Wikipedia](https://en.wikipedia.org/wiki/Modbus) -- protocol overview, MBAP header format
- Codebase audit: packages/modbus_client/, packages/modbus_client_tcp/, packages/tfc_dart/lib/core/ -- direct code inspection

### Secondary (MEDIUM confidence)
- [Wingpath ModTest Manual -- Message Limits](https://wingpath.co.uk/docs/modtest/message_limits.html) -- FC15 coil limit evolution (800 -> 1968)
- [IPC2U Modbus TCP Description](https://ipc2u.com/articles/knowledge-base/detailed-description-of-the-modbus-tcp-protocol-with-command-examples/) -- MBAP header layout

### Tertiary (LOW confidence)
- None -- all findings verified against code and official spec documentation

## Metadata

**Confidence breakdown:**
- Bug findings: HIGH -- directly verified against code and Modbus spec
- Missing validations: HIGH -- spec requirements compared against implementation
- Missing features: HIGH (existence) / MEDIUM (priority assessment)
- Spec compliance table: HIGH -- systematic function-code-by-function-code audit

**Research date:** 2026-03-09
**Valid until:** Indefinite (Modbus spec is stable, last updated 2012)
