# Phase 14: UMAS Protocol Support - Schneider Browse via FC90 - Research

**Researched:** 2026-03-07
**Domain:** UMAS (Unity Management and Administration System) protocol over Modbus TCP; Flutter browse UI abstraction
**Confidence:** MEDIUM

## Summary

UMAS is Schneider Electric's proprietary protocol for configuring and monitoring their PLCs (M340, M580, Quantum with Unity firmware). It rides on top of Modbus TCP by using reserved function code 90 (0x5A). Each UMAS message is wrapped in a standard Modbus TCP MBAP frame with FC=0x5A, followed by a pairing key byte, a UMAS sub-function code byte, and a variable-length payload. The protocol is little-endian internally (unlike standard Modbus which is big-endian).

The key capability for this phase is the data dictionary reading via UMAS sub-function code 0x26, which allows querying variable names, data types, and memory locations from the PLC. This requires that the Data Dictionary be enabled on the PLC in Unity Pro / EcoStruxure Control Expert. The Apache PLC4X project has a working Python implementation that reads variable names (record type 0xDD02), data type references (record type 0xDD03), and UDT definitions to construct a complete browsable symbol tree. This provides a reliable reference implementation.

On the UI side, the existing OPC UA browse dialog (`lib/widgets/opcua_browse.dart`) is tightly coupled to `open62541` types (`ClientApi`, `BrowseResultItem`, `NodeId`, `NodeClass`). To share it with UMAS, the UI components need to be extracted into a protocol-agnostic layer. The tree view, node tiles, breadcrumb, detail strip, and selection mechanics are all reusable -- only the data source (OPC UA browse API vs. UMAS data dictionary) differs.

**Primary recommendation:** Build a new `UmasClient` class that sends FC90 raw frames through the existing `ModbusClientTcp` socket (using a custom `ModbusRequest` subclass), implement the data dictionary reading sequence (init -> get project info -> read variable names -> read data types -> read UDT definitions -> build tree), then extract the browse dialog into a protocol-agnostic widget and wire both OPC UA and UMAS as data providers.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client_tcp (fork) | local | TCP transport for FC90 raw frames | Already in project, handles MBAP framing and transaction IDs |
| modbus_client (fork) | local | Base ModbusRequest for custom FC90 | Already supports `FunctionType.custom` and custom `ModbusFunctionCode` |
| flutter | 3.x | UI framework | Already in project |
| flutter_riverpod | 2.x | State management for browse dialog | Already in project |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| font_awesome_flutter | existing | Icons in browse UI | Already used in OPC UA browse |
| dart:typed_data | built-in | ByteData for little-endian UMAS payload parsing | Core Dart library |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom ModbusRequest for FC90 | Raw TCP socket | Would bypass existing MBAP framing, transaction ID management, keepalive -- much more work |
| Extending modbus_client_tcp | Separate UMAS TCP client | Would duplicate connection management, socket handling -- unnecessary |
| Protocol-agnostic browse widget | Two separate browse widgets | Would duplicate 700+ lines of tree view code |

**No new packages needed.** All UMAS communication is built on top of existing Modbus TCP infrastructure.

## Architecture Patterns

### Recommended Project Structure
```
packages/tfc_dart/lib/core/
  umas_client.dart          # UMAS protocol client (FC90 commands)
  umas_types.dart           # UMAS data types, variable references, UDT defs
lib/widgets/
  browse_panel.dart         # Protocol-agnostic browse panel (extracted)
  opcua_browse.dart         # OPC UA-specific browse adapter (thin wrapper)
  umas_browse.dart          # UMAS-specific browse adapter (thin wrapper)
```

### Pattern 1: Custom ModbusRequest for FC90
**What:** Subclass `ModbusRequest` to send FC90 frames with UMAS sub-function payloads through the existing `ModbusClientTcp.send()` pipeline.
**When to use:** For all UMAS communication.
**Example:**
```dart
// UMAS request wraps sub-function code + payload into FC90 PDU
class UmasRequest extends ModbusRequest {
  final int umasSubFunction;
  final int pairingKey;
  final Uint8List umasPayload;

  @override
  FunctionCode get functionCode =>
      const ModbusFunctionCode(0x5A, FunctionType.custom);

  @override
  Uint8List get protocolDataUnit {
    // FC(1) + PairingKey(1) + SubFunction(1) + Payload(N)
    final pdu = Uint8List(3 + umasPayload.length);
    pdu[0] = 0x5A;           // Function code 90
    pdu[1] = pairingKey;      // Session/pairing key
    pdu[2] = umasSubFunction; // UMAS sub-function code
    pdu.setAll(3, umasPayload);
    return pdu;
  }

  @override
  int get responsePduLength => -1; // Variable length, handled by custom parsing

  // Response parsing overrides...
}
```

### Pattern 2: Protocol-Agnostic Browse Tree
**What:** Extract `BrowseNodeTile`, `VariableDetailStrip`, breadcrumb builder, and tree expansion logic into a generic `BrowsePanel` widget. Both OPC UA and UMAS provide data through a common `BrowseDataSource` interface.
**When to use:** When building the shared browse UI.
**Example:**
```dart
/// Protocol-agnostic node representation
class BrowseNode {
  final String id;           // Unique ID (NodeId string for OPC UA, path for UMAS)
  final String displayName;
  final BrowseNodeType type; // folder, variable, method
  final String? dataType;
  final String? description;
  final Map<String, String> metadata; // Protocol-specific info
}

/// Data source interface both OPC UA and UMAS implement
abstract class BrowseDataSource {
  Future<List<BrowseNode>> fetchRoots();
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent);
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node);
}
```

### Pattern 3: UMAS Data Dictionary Reading Sequence
**What:** Multi-step sequence to discover all PLC variables.
**When to use:** When user clicks "Browse" on a UMAS-enabled Modbus server.
**Sequence:**
1. `0x01` - Init communication (get max frame size)
2. `0x02` - Read PLC ID (get firmware version, hardware ID)
3. `0x03` - Read project info (get CRC for cache validation)
4. `0x26` with record_type `0xDD02` - Read unlocated variable names
5. `0x26` with record_type `0xDD03` - Read data type references
6. `0x26` for UDT definitions (for custom/struct types)
7. Build hierarchical variable tree from collected data

### Anti-Patterns to Avoid
- **Modifying ModbusClientTcp internals for FC90:** The existing `send()` pipeline handles MBAP framing, transaction IDs, and response routing correctly. Use `ModbusRequest` subclassing, not socket-level hacking.
- **Byte-order confusion:** UMAS payloads are little-endian but the MBAP header is big-endian. Do NOT apply a blanket endianness setting -- handle each layer correctly.
- **Blocking the UI during dictionary read:** The data dictionary reading involves multiple round-trips. Run in an async method with progress indicators, not synchronously.
- **Assuming all Schneider PLCs have Data Dictionary enabled:** It must be enabled in Unity Pro / Control Expert. Detect the absence gracefully and show a clear error message.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MBAP frame construction | Custom TCP framing | `ModbusClientTcp.send()` with custom `ModbusRequest` | Already handles transaction IDs, response routing, keepalive, reconnection |
| Tree view with expand/collapse | Custom tree widget from scratch | Extract from existing `OpcUaBrowsePanel` | 775 lines of tested, working tree UI code already exists |
| CRC32 calculation | Custom CRC32 implementation | `dart:convert` or `package:crypto` | Standard algorithm, needed for "shifted CRC" in 0x22 requests |
| Variable type resolution | Inline type mapping | Lookup table from PLC4X's `UmasDataType` enum | 14+ data types with specific byte widths |

**Key insight:** The existing Modbus TCP infrastructure (forked `modbus_client_tcp` with transaction ID support) is the perfect transport layer. UMAS is just another "function code" from the TCP client's perspective.

## Common Pitfalls

### Pitfall 1: MBAP Length Validation Rejection
**What goes wrong:** UMAS responses can be larger than standard Modbus responses. The current `_processIncomingBuffer()` validates MBAP length field against range 1-254.
**Why it happens:** UMAS data dictionary responses can contain variable names and type definitions that exceed the 253-byte Modbus PDU limit.
**How to avoid:** Check if UMAS responses actually stay within 254 bytes per frame. PLC4X negotiates a "max frame size" during init (0x01). If responses are chunked by the PLC to fit within Modbus limits, this is fine. If not, the length validation in `_TcpResponse.addResponseData()` needs adjustment for FC90.
**Warning signs:** `requestRxFailed` errors when reading data dictionary from PLCs with many variables.

### Pitfall 2: Little-Endian vs Big-Endian Confusion
**What goes wrong:** UMAS payload bytes are interpreted in wrong byte order.
**Why it happens:** Standard Modbus is big-endian, but UMAS payloads are little-endian. Mixed in the same TCP frame.
**How to avoid:** Use `ByteData` with explicit `Endian.little` for all UMAS payload parsing. The MBAP header (bytes 0-6) stays big-endian per Modbus spec.
**Warning signs:** Garbled variable names, wrong memory addresses, incorrect data type IDs.

### Pitfall 3: Pairing Key / Session Management
**What goes wrong:** Requests after init fail because wrong pairing key is used.
**Why it happens:** The PLC returns a pairing key in the init response (0x01). Subsequent requests must include this key. It's 0x00 for unauthenticated "public" messages.
**How to avoid:** Store the pairing key from the init response and include it in all subsequent requests. For read-only browsing, 0x00 should work (no reservation needed).
**Warning signs:** 0xFD error responses after successful init.

### Pitfall 4: Data Dictionary Not Enabled on PLC
**What goes wrong:** 0x26 requests return errors instead of variable data.
**Why it happens:** The Data Dictionary must be explicitly enabled in Unity Pro / EcoStruxure Control Expert on the PLC project.
**How to avoid:** Detect this failure mode and show a clear user-facing message: "Data Dictionary not enabled on PLC. Enable it in Unity Pro under Project Settings."
**Warning signs:** 0xFD error response to 0x26 sub-function.

### Pitfall 5: OPC UA Type Coupling in Browse Widget
**What goes wrong:** Extracting the browse panel fails because types like `NodeId`, `NodeClass`, `BrowseResultItem` are deeply embedded.
**Why it happens:** The current `OpcUaBrowsePanel` directly uses `open62541` types in its state, rendering, and logic.
**How to avoid:** Create protocol-agnostic types (`BrowseNode`, `BrowseNodeType`) and map OPC UA types to them at the adapter boundary. Keep the generic panel completely free of OPC UA imports.
**Warning signs:** Import cycles, type casts, or "shim" objects that wrap OPC UA types.

## Code Examples

### Existing OPC UA Browse Panel Architecture (from opcua_browse.dart)

The current browse dialog has these key components that need extraction:

```dart
// Current OPC UA-specific types (must be generalized):
class BrowseTreeNode {
  final BrowseResultItem item;  // open62541 type -- must abstract
  final int depth;
  final NodeId parentNodeId;    // open62541 type -- must abstract
}

// OpcUaBrowsePanel key methods that ARE protocol-agnostic:
// - flattenTree() -- builds flat list from expanded tree state
// - _buildBreadcrumb() -- constructs path from root to selection
// - _toggleExpand() -- expand/collapse node
// - _onTapNode() -- select variable or expand folder
// - _prefetchChildren() -- eagerly load next level

// BrowseNodeTile -- fully reusable (only needs generic icon mapping)
// VariableDetailStrip -- fully reusable (shows name, value, dataType)
```

### UMAS Frame Structure (verified from Wireshark dissectors and blog analysis)

```
MBAP Header (big-endian):
  [0-1] Transaction ID (uint16)
  [2-3] Protocol ID = 0x0000 (uint16)
  [4-5] Length = remaining bytes after this field (uint16)
  [6]   Unit ID (uint8)

UMAS Payload (little-endian):
  [7]   Function Code = 0x5A (uint8)
  [8]   Pairing Key (uint8, 0x00 for public)
  [9]   UMAS Sub-Function Code (uint8)
  [10+] Sub-function-specific payload (variable length)

UMAS Response:
  [7]   Function Code = 0x5A (uint8)
  [8]   Pairing Key (uint8)
  [9]   Status: 0xFE=success, 0xFD=error (uint8)
  [10]  Echo of UMAS Sub-Function Code (uint8, only on success)
  [11+] Response payload (variable length)
```

### UMAS Init Communication (0x01)

```dart
// Request: FC=0x5A, PairingKey=0x00, SubFunc=0x01
// No additional payload
//
// Response includes:
// - Max frame size (uint16 LE)
// - Firmware version
// - Hardware ID
// This establishes communication and returns constraints
```

### UMAS Data Dictionary Read (0x26)

```dart
// Request: FC=0x5A, PairingKey=0x00, SubFunc=0x26
// Payload varies by record type:
//   record_type=0xDD02: Read unlocated variable names
//   record_type=0xDD03: Read data type references
//
// Response: List of variable/type records
// May need multiple requests (pagination) for large dictionaries
```

### How Browse Results Map to Key Repository

```dart
// When user selects a UMAS variable in the browse dialog:
// 1. Variable has: name, data_type, block_no, offset
// 2. Must convert to ModbusNodeConfig:
//    - registerType: holdingRegister (UMAS variables live in holding registers)
//    - address: calculated from block_no + offset
//    - dataType: mapped from UMAS data type ID to ModbusDataType
//    - serverAlias: from the Modbus server config
// 3. The key gets a human-readable name from the UMAS variable name
```

### Server Config UI Addition

```dart
// Current ModbusConfig fields: host, port, unitId, serverAlias, pollGroups
// Add: bool umasEnabled (default: false)
//
// In the _ModbusServerConfigCard, add a checkbox:
// [x] Schneider UMAS (enable variable browsing)
//
// When umasEnabled && user is in key repository:
//   Show "Browse" button (like OPC UA) instead of manual register entry
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual register address entry | UMAS data dictionary browsing | PLC4X 0.12+ (2024) | Users can discover variables by name instead of guessing addresses |
| Separate browse UIs per protocol | Protocol-agnostic browse panel | This phase | Reduces UI code duplication, consistent UX |
| Unsigned UMAS messages only | Signed/reserved message support | 2023+ firmware | Newer PLCs may require authentication for some operations |

**Deprecated/outdated:**
- The Liras blog series (2017) documents the core protocol but predates newer function codes (0x27 preload, 0x6E nonces)
- PLC4X UMAS driver is Python-only -- no Dart/Java implementation exists

## Open Questions

1. **MBAP Length Limit for UMAS Responses**
   - What we know: Standard Modbus limits MBAP length to 254 (1 unit ID + 253 PDU). UMAS init negotiates max frame size.
   - What's unclear: Do Schneider PLCs chunk data dictionary responses to fit within 254 bytes, or do they send larger frames? The PLC4X code references "max frame size" from init response which "doesn't include the Modbus header."
   - Recommendation: Test with a real Schneider PLC. If responses exceed 254 bytes, the `_processIncomingBuffer` length validation needs to allow larger frames for FC90 responses. LOW priority -- likely chunked.

2. **Authentication for Data Dictionary Access**
   - What we know: Basic UMAS commands (init, read ID, read variables) work without reservation (pairing key 0x00). The advanced Wireshark dissector documents "reservation nonces exchange" (0x6E) and signed messages.
   - What's unclear: Do some PLC firmware versions require reservation/authentication just to read the data dictionary?
   - Recommendation: Start with unauthenticated (public) access. Add reservation support only if needed. Read-only browsing should not require PLC reservation.

3. **UMAS Variable Address to Modbus Register Mapping**
   - What we know: UMAS variables have block_no + offset addresses. Standard Modbus uses register addresses. PLC4X uses `_sort_tags_based_on_memory_address()` to organize reads.
   - What's unclear: The exact formula to convert UMAS block_no/offset to Modbus holding register addresses for subsequent polling via standard FC03.
   - Recommendation: Investigate during implementation. The PLC4X UmasDevice.py `_read_tag` method likely contains this mapping. Worst case: use UMAS 0x22 (READ_VARIABLES) for ongoing reads instead of standard FC03.

4. **Variable Name Encoding**
   - What we know: PLC4X parses variable names from 0xDD02 responses. Names may be UTF-8 or ASCII.
   - What's unclear: Maximum name length, character encoding, whether hierarchical paths use dots or slashes.
   - Recommendation: Discover during implementation by examining actual PLC responses. The PLC4X code uses standard string parsing.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test + dart test |
| Config file | pubspec.yaml (test dependency) |
| Quick run command | `cd /Users/jonb/Projects/tfc-hmi && flutter test test/widgets/opcua_browse_test.dart` |
| Full suite command | `cd /Users/jonb/Projects/tfc-hmi && flutter test` |

### Phase Requirements -> Test Map

Since no formal requirement IDs are assigned yet, mapping to expected behaviors:

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| UmasRequest builds correct FC90 PDU | unit | `dart test packages/tfc_dart/test/core/umas_client_test.dart` | Wave 0 |
| UmasClient init communication parses response | unit | `dart test packages/tfc_dart/test/core/umas_client_test.dart` | Wave 0 |
| UmasClient reads data dictionary variable names | unit | `dart test packages/tfc_dart/test/core/umas_client_test.dart` | Wave 0 |
| UmasClient reads data type references | unit | `dart test packages/tfc_dart/test/core/umas_client_test.dart` | Wave 0 |
| UmasClient builds variable tree from dictionary | unit | `dart test packages/tfc_dart/test/core/umas_client_test.dart` | Wave 0 |
| Protocol-agnostic BrowsePanel renders tree | widget | `flutter test test/widgets/browse_panel_test.dart` | Wave 0 |
| BrowsePanel expand/collapse works | widget | `flutter test test/widgets/browse_panel_test.dart` | Wave 0 |
| BrowsePanel selection returns result | widget | `flutter test test/widgets/browse_panel_test.dart` | Wave 0 |
| OPC UA adapter produces same behavior as before | widget | `flutter test test/widgets/opcua_browse_test.dart` | Exists (modify) |
| UMAS browse adapter produces tree from dict | widget | `flutter test test/widgets/umas_browse_test.dart` | Wave 0 |
| UMAS checkbox in server config | widget | `flutter test test/pages/server_config_test.dart` | Exists (extend) |
| Key repository "Browse" button for UMAS servers | widget | `flutter test test/pages/key_repository_test.dart` | Exists (extend) |

### Sampling Rate
- **Per task commit:** Quick run on affected test file
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `packages/tfc_dart/test/core/umas_client_test.dart` -- UMAS protocol unit tests
- [ ] `test/widgets/browse_panel_test.dart` -- Protocol-agnostic browse panel tests
- [ ] `test/widgets/umas_browse_test.dart` -- UMAS browse adapter tests

## Sources

### Primary (HIGH confidence)
- Liras en la red blog series (2017) - [Part I](http://lirasenlared.blogspot.com/2017/08/the-unity-umas-protocol-part-i.html), [Part II](http://lirasenlared.blogspot.com/2017/08/the-unity-umas-protocol-part-ii.html), [Part III](http://lirasenlared.blogspot.com/2017/08/the-unity-umas-protocol-part-iii.html), [Part IV](https://lirasenlared.blogspot.com/2017/08/the-unity-umas-protocol-part-iv.html) - Detailed reverse engineering with byte-level packet analysis
- [Apache PLC4X UMAS Driver (Python)](https://github.com/apache/plc4x/tree/develop/plc4py/plc4py/drivers/umas) - Working implementation with data dictionary reading, variable tree building, browse support
- [PLC4X UMAS Documentation](https://plc4x.incubator.apache.org/plc4x/pre-release/users/protocols/umas.html) - Official driver docs confirming data dictionary requirement and supported features
- [Yanissec Wireshark Dissector](https://github.com/yanissec/umas-wireshark-dissector/blob/main/umas.lua) - 33 function codes documented
- [Zaltzman Advanced Wireshark Dissector](https://github.com/zaltzman/UMAS-Wireshark-Dissector) - 24+ function codes including 0x26 DATA_DICTIONARY, 0x27 preload, reserved message handling
- Existing codebase: `lib/widgets/opcua_browse.dart` (775 lines), `lib/pages/key_repository.dart`, `lib/pages/server_config.dart`, `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart`

### Secondary (MEDIUM confidence)
- [Kaspersky ICS CERT Report](https://ics-cert.kaspersky.com/publications/reports/2022/09/29/the-secrets-of-schneider-electrics-umas-protocol/) - Complete function code list, session management, response codes
- [PLC4X commit msg13542](https://www.mail-archive.com/commits@plc4x.apache.org/msg13542.html) - Documents 0x26 with record types 0xDD02/0xDD03 for data dictionary
- [mliras/malmod umas.py](https://github.com/mliras/malmod/blob/master/umas.py) - Python reference implementation confirming message structure

### Tertiary (LOW confidence)
- [Biero Llagas Medium article](https://medium.com/@biero-llagas/reverse-of-a-schneider-network-protocol-1e94980faa57) - Reverse engineering overview (could not fetch full content)
- [Stormshield UMAS IPS docs](https://documentation.stormshield.eu/SNS/v4/en/Content/User_Configuration_Manual_SNS_v4/Protocols/SCADA-UMAS.htm) - Firewall perspective on UMAS function classification

## Metadata

**Confidence breakdown:**
- UMAS protocol structure: HIGH - Multiple independent sources agree on FC90 framing, sub-function codes, little-endian payloads
- Data dictionary mechanism (0x26): MEDIUM - PLC4X has working code but detailed wire format for 0xDD02/0xDD03 requests not fully documented in public sources
- Browse UI extraction: HIGH - Full source code of existing OPC UA browse panel is available and understood
- UMAS-to-Modbus address mapping: LOW - How block_no/offset translates to standard Modbus register addresses needs investigation with real hardware
- Authentication requirements: MEDIUM - Public (unauthenticated) access should work for read-only browsing per PLC4X implementation

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable protocol, low churn)
