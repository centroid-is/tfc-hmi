---
phase: 16-modbus-protocol-spec-research-find-bugs-and-missing-features
verified: 2026-03-09T13:33:36Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 16: Modbus Protocol Spec Research Verification Report

**Phase Goal:** All Modbus protocol compliance gaps identified in the spec audit are fixed (address validation, response byte count checking, unit ID response validation, write quantity limits), unit ID range expanded to 0-255 for TCP, write errors surface detailed exception information, and byte order is configurable per device for multi-register interoperability

**Verified:** 2026-03-09T13:33:36Z
**Status:** PASSED
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| #   | Truth                                                                                           | Status     | Evidence                                                                                                                                      |
| --- | ----------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Register addresses are validated to 0-65535 at spec, config, and UI layers                      | VERIFIED   | `ModbusRegisterSpec` has `assert(address >= 0 && address <= 65535)` (wrapper.dart:47-48); `ModbusNodeConfig` clamps at construction (state_man.dart:311); UI clamps at save (key_repository.dart:1482) |
| 2   | Response byte count is validated against expected size for read responses                       | VERIFIED   | `ModbusReadRequest.expectedResponseByteCount` returns `element.byteCount`; `ModbusElementRequest.internalSetFromPduResponse` rejects mismatch with `requestRxFailed` (modbus_request.dart:81-94); 4 passing tests in modbus_client_tcp_test.dart |
| 3   | Unit ID in MBAP response header is validated against request unit ID                            | VERIFIED   | `_TcpResponse` stores `unitId` field (modbus_client_tcp.dart:366) and validates byte 6 against it at line 423-425; 2 passing tests (BUG-03 group) |
| 4   | FC15/FC16 write quantity limits are enforced per spec (max 1968 coils, 123 registers)           | VERIFIED   | `getMultipleWriteRequest` has asserts: `bytes.length <= 246`, FC16 `regCount <= 123`, FC15 `coilCount <= 1968` (modbus_element.dart:114-127); 5 passing tests in modbus_write_limits_test.dart |
| 5   | Unit ID field accepts 0-255 for TCP connections (was 1-247)                                     | VERIFIED   | `server_config.dart:1621` changed from `.clamp(1, 247)` to `.clamp(0, 255)`; `ModbusConfig` constructor: `unitId = unitId.clamp(0, 255)` (state_man.dart:279); 5 passing wrapper tests (VAL-03 group) |
| 6   | Write failure messages include exception code number and human-readable description             | VERIFIED   | Both `write()` and `writeMultiple()` throw with format `"${result.name} (0x${hex}) -- ${_describeException(result)}"` (modbus_client_wrapper.dart:383, 410); `_describeException` covers codes 0x01-0x0B plus transport errors (line 784); 2 passing tests (FEAT-03 group) |
| 7   | Byte order (ABCD/CDAB/BADC/DCBA) is configurable per Modbus server                             | VERIFIED   | `DropdownButtonFormField<ModbusEndianness>` with 4 options in Modbus server config card (server_config.dart:1878-1924); vendor guidance tooltip present; 5 widget tests all pass |
| 8   | Endianness from config flows through wrapper to modbus_client element constructors              | VERIFIED   | `ModbusConfig.endianness` field with JSON serialization via `state_man.g.dart:146-159`; `buildSpecsFromKeyMappings` accepts `endianness` param passed as `config.endianness` (modbus_device_client.dart:153-155); `_createElement` passes `spec.endianness` to all 6 multi-register constructors (modbus_client_wrapper.dart:725-735); 6 passing tests (endianness group) |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact                                                                    | Provides                                                              | Status     | Details                                                                         |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------- |
| `packages/modbus_client/lib/src/modbus_request.dart`                        | Response byte count validation in `internalSetFromPduResponse`        | VERIFIED   | Contains `expectedResponseByteCount` getter pattern; byte count check at lines 85-94 |
| `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart`                 | Unit ID validation in `_TcpResponse.addResponseData`                 | VERIFIED   | `unitId` field on `_TcpResponse` (line 366); comparison at lines 423-425        |
| `packages/modbus_client/lib/src/modbus_element.dart`                        | Write quantity limit assertions in `getMultipleWriteRequest`          | VERIFIED   | Three asserts at lines 114-127 covering byte limit, FC16 register limit, FC15 coil limit |
| `packages/modbus_client/test/modbus_write_limits_test.dart`                 | Tests for BUG-05 write limits                                         | VERIFIED   | 5 tests in 3 groups (FC16, FC15, byte count); all pass                          |
| `packages/tfc_dart/lib/core/modbus_client_wrapper.dart`                     | Address assertion in `ModbusRegisterSpec`, rich write errors, endianness on spec | VERIFIED   | `assert` at line 47; `_describeException` at line 784; `endianness` field at line 38 |
| `packages/tfc_dart/lib/core/state_man.dart`                                 | Address clamp, unit ID clamp, endianness field on `ModbusConfig`      | VERIFIED   | Address clamp line 311; unit ID clamp line 279; `endianness` field line 269    |
| `packages/tfc_dart/lib/core/state_man.g.dart`                               | JSON serialization for `ModbusEndianness`                             | VERIFIED   | `$enumDecodeNullable` with `_$ModbusEndiannessEnumMap` and ABCD default at lines 146-159 |
| `packages/tfc_dart/lib/core/modbus_device_client.dart`                      | `buildSpecsFromKeyMappings` propagates endianness                     | VERIFIED   | `endianness` param with ABCD default (line 121); passed to `ModbusRegisterSpec` (line 134); `config.endianness` at line 155 |
| `lib/pages/server_config.dart`                                              | Unit ID clamp 0-255, byte order dropdown with vendor tooltip          | VERIFIED   | `clamp(0, 255)` at line 1621; `DropdownButtonFormField<ModbusEndianness>` at line 1878 |
| `lib/pages/key_repository.dart`                                             | Address clamped to 0-65535 in UI                                      | VERIFIED   | `.clamp(0, 65535)` at line 1482                                                 |
| `test/pages/server_config_byte_order_test.dart`                             | Widget tests for byte order dropdown                                  | VERIFIED   | 5 tests: renders 4 options, selection updates config, default ABCD, pre-configured CDAB, info icon |
| `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart`               | Tests for BUG-01, FEAT-03, VAL-03, FEAT-01                           | VERIFIED   | Groups: Address validation (4), Rich write error (2), Unit ID range (5), endianness (6); all 17 new tests pass |
| `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart`               | Tests for BUG-02, BUG-03                                              | VERIFIED   | Groups: response byte count (4), unit ID validation (2); all 6 new tests pass |

### Key Link Verification

| From                                     | To                                   | Via                                                     | Status  | Details                                                                                        |
| ---------------------------------------- | ------------------------------------ | ------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------- |
| `modbus_request.dart`                    | `ModbusElementRequest.internalSetFromPduResponse` | byte count check before `pdu.sublist(2)`       | WIRED   | Pattern `pdu[1]` at line 87; `return ModbusResponseCode.requestRxFailed` at line 92           |
| `modbus_client_tcp.dart`                 | `_TcpResponse.addResponseData`       | unit ID byte 6 comparison                               | WIRED   | `responseUnitId != unitId` at line 423; `unitId` field stored at construction (line 376)      |
| `key_repository.dart`                    | `ModbusNodeConfig`                   | address clamping before config save                     | WIRED   | `.clamp(0, 65535)` at line 1482 in `_notifyChanged`                                           |
| `modbus_client_wrapper.dart`             | `ModbusResponseCode`                 | exception detail in error message                       | WIRED   | `result.name`, `result.code.toRadixString(16)`, `_describeException(result)` at lines 383, 410 |
| `state_man.dart` (`ModbusConfig`)        | `ModbusConfig`                       | endianness field with JSON key and ModbusEndianness enum | WIRED   | `@JsonKey(name: 'endianness')` present; `state_man.g.dart` has `_$ModbusEndiannessEnumMap`   |
| `modbus_client_wrapper.dart`             | `ModbusElement` constructors         | endianness parameter passed in `_createElement`         | WIRED   | `endianness: spec.endianness` on 6 multi-register constructors at lines 725-735               |
| `server_config.dart`                     | `ModbusConfig.endianness`            | dropdown selection stored in config                     | WIRED   | `DropdownButtonFormField<ModbusEndianness>` at line 1878; `setState(() => _endianness = value)` at line 1924 |

### Requirements Coverage

Phase 16 uses internal audit IDs (BUG-*/VAL-*/FEAT-*) defined in 16-RESEARCH.md, mapped to ROADMAP.md Success Criteria. These are separate from the main v1 REQUIREMENTS.md IDs.

| Requirement ID | Source Plan | Description                                              | Status    | Evidence                                                                                     |
| -------------- | ----------- | -------------------------------------------------------- | --------- | -------------------------------------------------------------------------------------------- |
| BUG-01         | 16-02       | Register address validation to 0-65535                   | SATISFIED | Assert in `ModbusRegisterSpec`; clamp in `ModbusNodeConfig`; clamp in key_repository UI     |
| BUG-02         | 16-01       | Response byte count not validated in read responses      | SATISFIED | `expectedResponseByteCount` getter; byte count check in `internalSetFromPduResponse`        |
| BUG-03         | 16-01       | Unit ID not validated in MBAP response                   | SATISFIED | `_TcpResponse.unitId` field; comparison against response byte 6                             |
| BUG-05         | 16-01       | FC15/FC16 write quantity overflow not guarded            | SATISFIED | Three asserts in `getMultipleWriteRequest`: byte count, FC16 register count, FC15 coil count |
| VAL-03         | 16-02       | Unit ID range restricted to 1-247 (should be 0-255 TCP) | SATISFIED | `server_config.dart` changed to `.clamp(0, 255)`; `ModbusConfig` constructor clamps 0-255  |
| FEAT-01        | 16-03       | Byte/word order config per device for multi-register types (promoted from ADV-01 in v2 requirements) | SATISFIED | Per-server `endianness` on `ModbusConfig`; flows through `buildSpecsFromKeyMappings` -> `ModbusRegisterSpec` -> `_createElement` -> 6 element constructors; UI dropdown with all 4 options |
| FEAT-03        | 16-02       | Write errors don't surface Modbus exception detail       | SATISFIED | `_describeException` helper; error format includes enum name, hex code, and human-readable text |

**Orphaned requirements check:** No orphaned requirements. All 7 IDs claimed by plans are accounted for.

**REQUIREMENTS.md cross-reference note:** BUG-*, VAL-*, FEAT-* IDs are internal Phase 16 audit IDs defined in 16-RESEARCH.md. FEAT-01 corresponds to ADV-01 in v2 requirements (byte/word order config), which was promoted to Phase 16. No v1 requirements (CONN-*, READ-*, WRIT-*, etc.) were assigned to Phase 16.

### Anti-Patterns Found

| File                                               | Line | Pattern                         | Severity | Impact                                                                                 |
| -------------------------------------------------- | ---- | ------------------------------- | -------- | -------------------------------------------------------------------------------------- |
| `packages/modbus_client/lib/src/modbus_request.dart` | 228  | `/* TODO: define multiple write "strategy"! */` | Info | Pre-existing commented-out class stub; unrelated to Phase 16 work                     |
| `packages/tfc_dart/lib/core/state_man.dart`         | 990, 1001 | `// TODO can I reproduce the problem more often` | Info | Pre-existing debug note in heartbeat timer code; unrelated to Phase 16 work      |
| `lib/pages/server_config.dart`                      | 28   | `// TODO not the best place but cross platform` | Info | Pre-existing comment about import placement; unrelated to Phase 16 work               |

All TODOs are pre-existing (not introduced by Phase 16 changes) and none block the phase goal.

### Human Verification Required

#### 1. Byte order round-trip with real device

**Test:** Connect a Modbus device that uses CDAB (word swap) byte order (e.g., Schneider Modicon). Configure byte order as "CDAB (Word Swap)" in server config. Read a float32 or int32 register.
**Expected:** Value reads correctly (not garbage). When byte order is set to ABCD, the same register reads as a large/garbage number.
**Why human:** Cannot verify correct byte interpretation without a physical device providing known float32/int32 values.

#### 2. Write error message usability

**Test:** Attempt to write to a read-only register or an address that doesn't exist on a device. Observe the error message shown to the user.
**Expected:** Error message includes the Modbus exception code (e.g., `illegalDataAddress (0x02) -- Register address does not exist on device`), giving the operator actionable diagnostic information.
**Why human:** Cannot observe UI error display flow without a device returning exception responses. Unit tests verify the string format but not user-facing presentation.

### Gaps Summary

No gaps. All 8 success criteria from ROADMAP.md are verified against the actual codebase.

All tests pass:
- `packages/modbus_client`: 35 tests passing (including 5 new BUG-05 tests)
- `packages/modbus_client_tcp`: 23 tests passing (including 6 new BUG-02 + BUG-03 tests)
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart`: 109 tests passing (including 17 new Phase 16 tests)
- `test/pages/server_config_byte_order_test.dart`: 5 widget tests passing

All 12 task commits verified in git history: `6cfb85d`, `ea1626f`, `749dac0`, `0fb4c1c`, `bacaa6c`, `2e8deda`, `07da85a`, `554bd2d`, `fa3456f`, `7eec5c0`, `ec13471`, `d9d8d90`.

---

_Verified: 2026-03-09T13:33:36Z_
_Verifier: Claude (gsd-verifier)_
