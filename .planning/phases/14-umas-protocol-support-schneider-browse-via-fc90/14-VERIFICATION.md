---
phase: 14-umas-protocol-support-schneider-browse-via-fc90
verified: 2026-03-07T20:57:41Z
status: passed
score: 8/8 must-haves verified
human_verification:
  - test: "Browse against real Schneider PLC with Data Dictionary enabled"
    expected: "UMAS browse dialog opens, variable tree populates with PLC variable hierarchy, selecting a variable fills in register address and data type in key config"
    why_human: "Requires real hardware running Schneider firmware with Data Dictionary enabled -- cannot emulate in unit tests"
  - test: "OPC UA browse dialog visual parity after extraction to generic BrowsePanel"
    expected: "OPC UA browse dialog looks and behaves identically to pre-phase-14 version (layout, colors, icons, expand/collapse, detail strip, breadcrumb)"
    why_human: "Visual regression requires human comparison -- automated tests verify behavior but not pixel-accurate appearance"
  - test: "UMAS browse error when Modbus not connected"
    expected: "Tapping Browse when Modbus TCP is disconnected shows snackbar 'Modbus not connected. Connect first, then browse.'"
    why_human: "Requires running app with a disconnected Modbus server to trigger the null-client code path"
---

# Phase 14: UMAS Protocol Support Verification Report

**Phase Goal:** Schneider PLC variables can be browsed by name via UMAS protocol through a shared protocol-agnostic browse dialog, with UMAS toggle in Modbus server config and Browse button in key repository
**Verified:** 2026-03-07T20:57:41Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | UmasClient sends FC90 frames through existing ModbusClientTcp transport and parses UMAS responses | VERIFIED | `umas_client.dart:10-53` — UmasRequest extends ModbusRequest with FC=0x5A PDU; send function injection wires to ModbusClientTcp.send; 8 unit tests pass |
| 2 | Data dictionary variable names and data types can be read from a Schneider PLC with Data Dictionary enabled | VERIFIED | `umas_client.dart:104-231` — readVariableNames() sends 0x26/0xDD02, readDataTypes() sends 0x26/0xDD03; LE parsing; unit tests with canned responses pass |
| 3 | Variable tree is built from flat dictionary data using dot-separated name hierarchy | VERIFIED | `umas_client.dart:235-306` — _TreeBuilder splits on '.', buildVariableTree/browse() methods; unit test for dot-separated hierarchy passes |
| 4 | OPC UA browse dialog is extracted into a protocol-agnostic BrowsePanel widget | VERIFIED | `lib/widgets/browse_panel.dart` — 785 lines; BrowseNode, BrowseDataSource, BrowsePanel, showBrowseDialog all present; 16 widget tests pass |
| 5 | OPC UA browse works identically through the new adapter layer (no visual or behavioral changes) | VERIFIED (automated) / ? HUMAN NEEDED (visual) | `lib/widgets/opcua_browse.dart` — OpcUaBrowseDataSource implements BrowseDataSource; browseOpcUaNode() returns BrowseResultItem; 27 adapter tests pass; visual parity needs human check |
| 6 | UMAS checkbox appears in Modbus server config card | VERIFIED | `lib/pages/server_config.dart:2097` — CheckboxListTile with title 'Schneider UMAS'; toggling updates _umasEnabled; 2 widget tests pass |
| 7 | Browse button appears in key repository Modbus config section when UMAS is enabled | VERIFIED | `lib/pages/key_repository.dart:1526` — conditional `if (_isUmasEnabled)` TextButton.icon 'Browse'; 3 key_repository tests verify visible/hidden states |
| 8 | Selecting a UMAS variable populates register address and data type in key config | VERIFIED (code path) / ? HUMAN NEEDED (E2E) | `lib/pages/key_repository.dart:1419-1453` — browseUmasNode result mapped to address (blockNo+offset), register type (holdingRegister), _mapUmasDataType(); requires real hardware for full E2E |

**Score:** 8/8 truths verified (3 additionally flagged for human verification)

### Required Artifacts

#### Plan 01 Artifacts

| Artifact | Min Lines | Actual Lines | Status | Details |
|----------|-----------|--------------|--------|---------|
| `packages/tfc_dart/lib/core/umas_types.dart` | 60 | 125 | VERIFIED | UmasSubFunction, UmasVariable, UmasDataTypeRef, UmasVariableTreeNode, UmasException, UmasInitResult, UmasDataTypes all present |
| `packages/tfc_dart/lib/core/umas_client.dart` | 120 | 307 | VERIFIED | UmasClient, UmasRequest, _TreeBuilder all present; browse(), init(), readVariableNames(), readDataTypes() implemented |
| `packages/tfc_dart/test/core/umas_client_test.dart` | 100 | 261 | VERIFIED | 8 tests all passing (GREEN) |

#### Plan 02 Artifacts

| Artifact | Min Lines | Actual Lines | Status | Details |
|----------|-----------|--------------|--------|---------|
| `lib/widgets/browse_panel.dart` | 200 | 785 | VERIFIED | BrowseNode, BrowseNodeType, BrowseDataSource, BrowsePanel, showBrowseDialog, BrowseNodeTile, VariableDetailStrip all exported |
| `lib/widgets/opcua_browse.dart` | 50 | 197 | VERIFIED | OpcUaBrowseDataSource implements BrowseDataSource; browseOpcUaNode() preserved |
| `test/widgets/browse_panel_test.dart` | 80 | ~280 (16 tests) | VERIFIED | All 16 widget tests pass |

#### Plan 03 Artifacts

| Artifact | Min Lines | Actual Lines | Status | Details |
|----------|-----------|--------------|--------|---------|
| `lib/widgets/umas_browse.dart` | 60 | 127 | VERIFIED | UmasBrowseDataSource implements BrowseDataSource; browseUmasNode() present; null-checks wrapper.client |
| `lib/pages/server_config.dart` | contains "umasEnabled" | line 2097 | VERIFIED | CheckboxListTile 'Schneider UMAS' present; _umasEnabled state field wired |
| `lib/pages/key_repository.dart` | contains "browseUmasNode" | line 1419 | VERIFIED | browseUmasNode called in _openUmasBrowseDialog; Browse button conditionally rendered |
| `packages/tfc_dart/lib/core/state_man.dart` | contains "umasEnabled" | lines 266-267 | VERIFIED | @JsonKey(name: 'umas_enabled', defaultValue: false) bool umasEnabled; regenerated .g.dart at line 145/155 |

### Key Link Verification

#### Plan 01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `umas_client.dart` | `modbus_client_tcp.dart` | `ModbusClientTcp.send(UmasRequest)` | VERIFIED | UmasClient accepts `Future<ModbusResponseCode> Function(ModbusRequest)` sendFn; wired to tcpClient.send in browseUmasNode |
| `umas_client.dart` | `umas_types.dart` | import | VERIFIED | `import 'package:tfc_dart/core/umas_types.dart'` at line 5 |
| `modbus_client_tcp.dart` | FC90 large response exemption | 0x5A/functionCode 90 check | VERIFIED | Lines 218-224: `(functionCode == 0x5A) ? 65535 : 254`; lines 400-404: `(request.functionCode.code == 0x5A) ? 65535 : 254` |

#### Plan 02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `browse_panel.dart` | `opcua_browse.dart` | BrowseDataSource interface implemented by OpcUaBrowseDataSource | VERIFIED | `class OpcUaBrowseDataSource implements BrowseDataSource` at line 53 of opcua_browse.dart |
| `opcua_browse.dart` | `browse_panel.dart` | import | VERIFIED | `import 'browse_panel.dart'` at line 6 of opcua_browse.dart |
| `lib/pages/key_repository.dart` | `opcua_browse.dart` | browseOpcUaNode still called | VERIFIED | browseOpcUaNode preserved; key_repository.dart still calls it for OPC UA |

#### Plan 03 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `umas_browse.dart` | `umas_client.dart` | UmasClient.browse() called from UmasBrowseDataSource | VERIFIED | `UmasClient(sendFn: tcpClient.send)` at line 119; `_client.browse()` called in fetchRoots |
| `umas_browse.dart` | `browse_panel.dart` | implements BrowseDataSource | VERIFIED | `class UmasBrowseDataSource implements BrowseDataSource` at line 13 |
| `key_repository.dart` | `umas_browse.dart` | browseUmasNode called when Browse button tapped | VERIFIED | `browseUmasNode(...)` at line 1419; triggered by `_openUmasBrowseDialog` |
| `server_config.dart` | `state_man.dart` | ModbusConfig.umasEnabled field | VERIFIED | umasEnabled set in _buildConfig; serialized in state_man.g.dart |

### Requirements Coverage

The requirement IDs UMAS-01 through UMAS-08 and TEST-10 through TEST-12 are declared in both the ROADMAP.md (Phase 14 entry) and in the plan frontmatter, but **are NOT present in `.planning/REQUIREMENTS.md`**. REQUIREMENTS.md covers the Modbus TCP integration requirements (v1 ends at TEST-09) and has no UMAS entries. This is a documentation gap — the UMAS requirements exist in ROADMAP.md as Success Criteria but were never formally added to REQUIREMENTS.md.

Mapping requirement IDs from plan frontmatter against ROADMAP.md Success Criteria (the authoritative source):

| Requirement | Source Plan | ROADMAP Success Criterion | Status | Evidence |
|-------------|------------|--------------------------|--------|----------|
| UMAS-01 | 14-01 | UmasClient sends FC90 frames through ModbusClientTcp | SATISFIED | UmasRequest + UmasClient + 8 passing tests |
| UMAS-02 | 14-01 | Data dictionary variable names readable (0xDD02) | SATISFIED | readVariableNames() + unit tests |
| UMAS-03 | 14-01 | Data dictionary data types readable (0xDD03) | SATISFIED | readDataTypes() + unit tests |
| UMAS-04 | 14-01 | Hierarchical variable tree from dot-separated paths | SATISFIED | buildVariableTree() + _TreeBuilder + unit tests |
| UMAS-05 | 14-02 | Protocol-agnostic BrowsePanel widget extracted | SATISFIED | browse_panel.dart 785 lines + 16 widget tests |
| UMAS-06 | 14-02 | OPC UA browse works identically through adapter | SATISFIED (code) / HUMAN (visual) | OpcUaBrowseDataSource + 27 adapter tests; visual parity needs human |
| UMAS-07 | 14-03 | UMAS checkbox in Modbus server config + umasEnabled persists | SATISFIED | CheckboxListTile + state_man.g.dart JSON round-trip |
| UMAS-08 | 14-03 | Browse button + variable selection populates key config | SATISFIED (code) / HUMAN (E2E) | browseUmasNode + _mapUmasDataType + 3 key_repository tests |
| TEST-10 | 14-01 | UMAS unit tests (FC90 PDU + parsing + tree + errors) | SATISFIED | 8 umas_client_test.dart + 4 MBAP FC90 exemption tests |
| TEST-11 | 14-02 | Generic browse panel widget tests | SATISFIED | 16 browse_panel_test.dart + 27 opcua_browse_test.dart |
| TEST-12 | 14-03 | UMAS browse adapter + UI wiring tests | SATISFIED | 10 umas_browse_test.dart + server_config UMAS group + 3 key_repository UMAS tests |

**Note on ORPHANED requirements:** REQUIREMENTS.md does not contain UMAS-01 through UMAS-08 or TEST-10 through TEST-12. These requirements exist only in ROADMAP.md (as Success Criteria) and plan frontmatter. The traceability table in REQUIREMENTS.md ends at TEST-09 with no Phase 14 entries. This is a documentation gap but does not indicate missing implementation — all criteria are implemented and tested.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/pages/server_config.dart` | 26 | `// TODO not the best place but cross platform` | Info | Pre-existing TODO unrelated to phase 14 |
| `packages/tfc_dart/lib/core/state_man.dart` | 987, 998 | `// TODO can I reproduce the problem more often` | Info | Pre-existing TODO unrelated to phase 14; in health check timing code |

No blocker or warning anti-patterns found in phase 14 code. The null returns in umas_browse.dart (lines 28, 64, 71, etc.) are correct defensive programming (null client check, not-found node, not-mounted context guards) — not stubs.

### Human Verification Required

#### 1. Real Schneider PLC Browse

**Test:** Add a Modbus server pointing to a Schneider PLC with host/port. Enable the "Schneider UMAS" checkbox. Save. Open the key repository, create or select a Modbus key, choose the UMAS-enabled server, and click Browse.
**Expected:** Browse dialog opens showing the PLC variable hierarchy (folder nodes matching PLC application structure, leaf nodes with REAL/INT/BOOL etc. data types). Selecting a leaf variable and clicking Select should populate the register address field (blockNo + offset) and auto-select the correct data type.
**Why human:** Requires real Schneider PLC hardware running firmware with Data Dictionary enabled (FC90/0x26/0xDD02 responses). Unit tests use canned byte sequences and cannot validate against actual PLC responses.

#### 2. OPC UA Browse Visual Parity

**Test:** Open the OPC UA browse dialog before and after this phase. Compare layout, colors, icons (folder icon for objects, tag icon for variables), detail strip, breadcrumb, expand/collapse behavior, and select/cancel buttons.
**Expected:** Identical appearance and behavior to pre-phase-14 OPC UA browse panel. Breadcrumb now shows "Root" instead of "Objects" as the root label (intentional protocol-neutral change documented in 14-02-SUMMARY).
**Why human:** Visual regression detection. Automated tests verify behavioral correctness (expand, select, error states) but not pixel-accurate appearance parity.

#### 3. UMAS Browse Error State (Modbus Not Connected)

**Test:** Configure a Modbus server with UMAS enabled, but do not connect it. Open key repository, select that server, click Browse.
**Expected:** Snackbar appears: "Modbus not connected. Connect first, then browse." Dialog does not open.
**Why human:** Requires running app with a Modbus server that fails to connect. The null-check code path at `lib/widgets/umas_browse.dart:107-116` is correct but untested by automated tests.

---

## Test Suite Summary

| Test Suite | Tests | Result |
|-----------|-------|--------|
| `packages/tfc_dart/test/core/umas_client_test.dart` | 8 | All passed |
| `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart` | 17 (4 FC90-specific) | All passed |
| `test/widgets/browse_panel_test.dart` | 16 | All passed |
| `test/widgets/opcua_browse_test.dart` | 27 | All passed |
| `test/widgets/umas_browse_test.dart` | 10 | All passed |
| `test/pages/server_config_test.dart` | includes 2 UMAS | All passed |
| `test/pages/key_repository_test.dart` | includes 3 UMAS | All passed |

**Total new tests:** 12 (Plan 01) + 43 (Plan 02) + 15 (Plan 03) = ~70 new/modified tests, all green.

---

_Verified: 2026-03-07T20:57:41Z_
_Verifier: Claude (gsd-verifier)_
