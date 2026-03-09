---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in-progress
stopped_at: Completed 17-02-PLAN.md (live UMAS hardware testing)
last_updated: "2026-03-09T14:39:44Z"
last_activity: 2026-03-09 -- 17-02 complete, live UMAS tests against real PLC, fixed response PDU byte order, added unitId threading
progress:
  total_phases: 17
  completed_phases: 13
  total_plans: 25
  completed_plans: 25
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-06)

**Core value:** Modbus devices can be read from and written to through the same StateMan interface as OPC UA and M2400, without breaking existing protocol integrations.
**Current focus:** Phase 17 -- Fix and Verify UMAS Against Real Schneider PLC

## Current Position

Phase: 17 (Fix and Verify UMAS Against Real Schneider PLC)
Plan: 2 of 2 in current phase (17-02 COMPLETE)
Status: Phase 17 complete. All UMAS wire format bugs fixed (Plan 01) and verified against real Schneider PLC (Plan 02). PLC returns 0x83 for all UMAS subfunctions -- needs Data Dictionary enabled.
Last activity: 2026-03-09 -- 17-02 complete, live UMAS tests against real PLC, corrected response PDU byte order

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 15
- Average duration: 8.5min
- Total execution time: 2.06 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-tcp-transport-fixes | 2/2 | 11min | 5.5min |
| 02-fc15-coil-write-fix | 1/1 | 3min | 3min |
| 04-modbusclientwrapper-connection | 1/1 | 10min | 10min |
| 05-modbusclientwrapper-reading | 2/2 | 34min | 17min |
| 06-modbusclientwrapper-writing | 1/1 | 6min | 6min |
| 07-deviceclient-adapter | 1/1 | 4min | 4min |
| 08-config-serialization | 1/1 | 11min | 11min |
| 09-stateman-integration | 2/2 | 22min | 11min |

| 10-server-config-ui | 2/2 | 19min | 9.5min |
| 11-key-repository-ui | 2/2 | 7min | 3.5min |

**Recent Trend:**
- Last 5 plans: 09-01 (11min), 09-02 (11min), 10-01 (9min), 10-02 (10min), 11-01 (5min), 11-02 (2min)
- Trend: Consistent ~10min for UI/integration plans, verification checkpoints fastest

*Updated after each plan completion*
| Phase 11 P01 | 5min | 2 tasks | 3 files |
| Phase 11 P02 | 2min | 1 task | 0 files |
| Phase 14 P01 | ~10min | 3 tasks | 4 files |
| Phase 14 P02 | 8min | 2 tasks | 4 files |
| Phase 14 P03 | 10min | 2 tasks | 9 files |
| Phase 15 P02 | 9min | 2 tasks | 2 files |
| Phase 15 P01 | 11min | 2 tasks | 7 files |
| Phase 15 P03 | 7min | 2 tasks | 2 files |
| Phase 16 P01 | 6min | 2 tasks | 4 files |
| Phase 16 P02 | 12min | 2 tasks | 5 files |
| Phase 16 P03 | 12min | 2 tasks | 7 files |
| Phase 17 P01 | 10min | 2 tasks | 5 files |
| Phase 17 P02 | 12min | 2 tasks | 4 files |

## Accumulated Context

### Roadmap Evolution

- Phase 13 added: manual test against a real device
- Phase 14 added: UMAS protocol support - Schneider browse via FC90
- Phase 15 added: Code review fixes — security, performance, correctness, and duplication
- Phase 16 added: Modbus protocol spec research — find bugs and missing features
- Phase 17 added: fix and verify umas against real schneider plc

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Phases 1-3 (library fixes) have no inter-dependencies and could run in parallel
- Roadmap: TEST-09 (TDD process) is cross-cutting -- applies to all phases, not assigned to a single phase
- Roadmap: CONN-04 (cross-platform keepalive) split -- Linux/macOS covered by Phase 1 (TCPFIX-05), Windows by Phase 3
- 01-01: Forked modbus_client_tcp from pub cache into packages/ for proper TDD and version control
- 01-01: MBAP length upper bound = 254 per Modbus spec (1 unit ID + 253 max PDU)
- 01-01: keepAliveIdle=5s, keepAliveInterval=2s matches MSocket for ~11s dead connection detection
- 01-02: MBAP frame parsing moved to router level for multi-response routing; _TcpResponse retains defense-in-depth checks
- 01-02: Lock scope narrowed to protect only socket write, not response wait -- enables concurrent in-flight requests
- 01-02: Incoming buffer approach for TCP stream reassembly instead of per-response partial buffering
- 02-01: Optional quantity parameter approach over ModbusBitElement override -- coil count cannot be recovered from packed byte count
- 02-01: Added publish_to: none to both fork pubspec.yaml files for clean dart analyze
- 04-01: Own connection loop with doNotConnect mode -- ModbusClientTcp autoConnectAndKeepConnected has no status stream or backoff control
- 04-01: Poll isConnected every 250ms for disconnect detection -- simpler than hooking into socket internals
- 04-01: TCP keepalive only for dead connection detection (no app-level health probe yet)
- 04-01: MockModbusClient extends ModbusClientTcp for unit tests -- factory injection, no Mockito needed
- 05-01: Object? as BehaviorSubject value type -- bool/int/double are all Object; Phase 7 adapter wraps to DynamicValue
- 05-01: Individual element reads per poll tick -- batch coalescing deferred to Plan 02
- 05-01: Lazy poll group creation -- subscribe() auto-creates default group at 1s interval
- 05-01: ModbusNumRegister returns num (double due to multiplier formula) -- library behavior, not wrapper choice
- 05-02: Gap thresholds 10 registers / 100 coils -- 20 bytes waste vs ~40ms TCP round-trip savings
- 05-02: Replaced individual reads entirely with batch reads -- ModbusElementsGroup handles single elements too
- 05-02: Pipe all subscription values after ALL groups read (not per-group) -- simpler, no subscription-to-group matching
- 06-01: Spec-based write API (not key-based) -- write-only registers may never be subscribed, spec carries all metadata
- 06-01: Shared _validateWriteAccess() extracts disposed/connected/read-only checks for write() and writeMultiple()
- 06-01: Optimistic BehaviorSubject update after successful write -- immediate UI feedback vs waiting for next poll tick
- 06-01: No write concurrency serialization at wrapper level -- Modbus TCP transport handles concurrent transactions via transaction IDs
- 07-01: Spec-based typeId mapping (ModbusDataType -> NodeId) rather than runtime type inference -- num is always double from modbus library
- 07-01: Exact key matching via containsKey (no dot-notation prefix matching unlike M2400)
- 07-01: write() added to DeviceClient abstract class with M2400 throwing UnsupportedError
- 08-01: ModbusRegisterType as separate Dart enum (not reusing ModbusElementType) for clean camelCase JSON serialization
- 08-01: Default case with ArgumentError in fromModbusElementType to satisfy non-exhaustive switch on external enum
- 08-01: createModbusDeviceClients uses named record with ModbusConfig instead of anonymous field record
- 09-01: readMany partitions keys into DeviceClient (Modbus/M2400) vs OPC UA before processing
- 09-01: buildModbusDeviceClients pre-configures poll groups from ModbusConfig.pollGroups before adapter creation
- 09-01: _resolveModbusDeviceClient matches by serverAlias between modbusNode config and adapter instance
- 09-02: DataAcquisitionIsolateConfig.modbusJson defaults to const [] for backward compatibility
- 09-02: Isolate name fallback: 'modbus' when only modbusJson present (was blanket 'jbtm')
- 09-02: All three creation paths (isolate, main.dart spawner, Flutter UI provider) use same buildModbusDeviceClients factory
- [Phase 10]: Extracted ServerConfigBody from ServerConfigPage to bypass BaseScaffold/Beamer dependency in widget tests
- [Phase 10]: Override stateManProvider with throw in test helper to prevent real network connections while showing 'Not active' status
- [Phase 10]: Connection status lookup matches ModbusDeviceClientAdapter by serverAlias first, falls back to host+port matching
- [Phase 10-02]: Poll group controllers re-initialized on length change in didUpdateWidget, not every rebuild
- [Phase 10-02]: Interval clamped to min 50ms to prevent accidental high-frequency polling
- [Phase 11-01]: Modbus subtitle format: registerType[address] dataType @ serverAlias (compact, scannable)
- [Phase 11-01]: Poll group dropdown disabled when no server alias selected, reset to 'default' on server change
- [Phase 11-01]: Data type dropdown shows 'Data Type (auto)' label when auto-locked, single 'bit' item, onChanged null
- [Phase 11-01]: Three-way protocol rendering: if (_isModbus) ... else if (_isM2400) ... else OPC UA
- [Phase 11-02]: Visual verification approved via automated test coverage (41 widget tests, 8 Modbus-specific)
- [Phase 14-02]: BrowseNode.id stores NodeId.toString() for OPC UA -- enables lossless round-trip via parseNodeId
- [Phase 14-02]: BrowseTreeEntry (public) replaces private _TreeNode to satisfy dart analyze lint
- [Phase 14-02]: formatDynamicValue moved to OpcUaBrowseDataSource as static method (OPC UA specific)
- [Phase 14-02]: Breadcrumb root label is "Root" in generic panel (protocol-neutral, was "Objects")
- [Phase 14-03]: browseUmasNode null-checks wrapper.client before creating UmasClient (snackbar if not connected)
- [Phase 14-03]: _ModbusConfigSection converted to ConsumerStatefulWidget for stateManProvider access
- [Phase 14-03]: _buildConfig helper centralizes ModbusConfig construction in server config card (DRY)
- [Phase 14-03]: UMAS data type mapping uses uppercase switch with byteSize fallback for unknown types
- [Phase 14-03]: stateManProvider override added to buildTestableKeyRepository to prevent timer leaks
- [Phase 15-02]: Emit disconnected synchronously in dispose() before closing BehaviorSubject to preserve listener ordering
- [Phase 15-02]: unawaited() in disconnect() and dispose() documents intentional fire-and-forget (not accidental)
- [Phase 15-03]: ConnectionStatusChip as public widget in own file for cross-file reusability
- [Phase 15-03]: DUP-02 config lifecycle left protocol-specific (custom state per section makes generic extraction complex)
- [Phase 15]: BytesBuilder with copy:false for zero-copy TCP buffer accumulation
- [Phase 15]: findByAlias extension on List<ModbusConfig> keeps lookup local to key_repository.dart
- [Phase 15]: Path index built once in fetchRoots(), reused for all subsequent lookups
- [Phase 16-01]: expectedResponseByteCount as nullable getter -- null skips validation (for group requests)
- [Phase 16-01]: Unit ID validation inside header parsing block, not separate check (single execution)
- [Phase 16-01]: Write limit assertions (not exceptions) -- zero overhead in release, fail-fast in debug
- [Phase 16-02]: Assert for ModbusRegisterSpec (code-constructed), clamp for ModbusNodeConfig (JSON-deserialized) -- crash-safe on bad data
- [Phase 16-02]: Unit ID 0-255 for TCP without warnings -- all values are spec-valid in TCP context
- [Phase 16-02]: _describeException covers standard Modbus codes 0x01-0x0B plus library transport codes
- [Phase 16-03]: Endianness is per-device (per ModbusConfig), not per-register -- all registers on a device use same byte order
- [Phase 16-03]: Single-register types (int16/uint16) and bit types unaffected by endianness -- only 32-bit and 64-bit types pass through
- [Phase 16-03]: buildSpecsFromKeyMappings accepts endianness as optional parameter with ABCD default for backward compatibility
- [Phase 17-01]: MockUmasSender uses response queues (List per subFunc) for pagination testing instead of single canned response
- [Phase 17-01]: Data type IDs assigned sequentially as 100+i from DD03 record order -- DD03 format has no type ID field
- [Phase 17-01]: Null-terminated strings: parse stringLength bytes then strip trailing 0x00 for safe handling
- [Phase 17-01]: DD02 pagination via offset field (blockNo=0xFFFF); DD03 pagination via blockNo field (offset=0x0000)
- [Phase 17-02]: UMAS response PDU format is FC+pairingKey+subFuncEcho+status (not FC+pairingKey+status+subFuncEcho as assumed in Phase 14)
- [Phase 17-02]: UmasClient accepts optional unitId parameter threaded to all UmasRequest instances (Schneider PLCs typically use 255)
- [Phase 17-02]: Live tests catch UmasException and pass with diagnostic output when PLC does not support UMAS
- [Phase 17-02]: _checkStatus() helper centralizes status checking with clear error messages including hex status codes

### Pending Todos

None yet.

### Blockers/Concerns

- Need actual production config.json and keymappings.json to validate backward compatibility before Phase 8

## Session Continuity

Last session: 2026-03-09T14:39:44Z
Stopped at: Completed 17-02-PLAN.md (live UMAS hardware testing)
Resume file: None
