# Phase 2: FC15 Coil Write Fix - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the Write Multiple Coils (FC15) quantity bug in the `modbus_client` base package so that writing 16 or more coils in a single request reports the correct quantity. The bug is in `getMultipleWriteRequest` at `modbus_element.dart:109` where `bytes.length ~/ 2` is used for the quantity field — correct for FC16 (registers) but wrong for FC15 (coils), where quantity = number of coils.

</domain>

<decisions>
## Implementation Decisions

### Bug diagnosis
- Skip diagnosis — the code is clearly wrong for coils (`bytes.length ~/ 2` ≠ coil count when coils > 15)
- Go straight to fix + test (TDD: write failing test first)

### Fork strategy
- Fork entire `modbus_client` package (v1.4.4) from pub cache into `packages/modbus_client/`
- Same pattern as Phase 1's `modbus_client_tcp` fork — enables TDD, version control, CI
- Update `modbus_client_tcp/pubspec.yaml` to use `path: ../modbus_client` (local dep chain)
- Fork the full package, not a minimal subset — future phases (especially Phase 6: Writing) will need more of it

### Fix approach
- Claude's discretion on whether to add a quantity parameter to `getMultipleWriteRequest` or override in `ModbusBitElement`
- Just fix FC15 quantity — do NOT implement group write (`ModbusWriteGroupRequest` is out of scope, that's a separate capability)

### Testing
- Full round-trip: test PDU encoding AND mock server response parsing
- Test boundary cases: 1-15 coils (regression) AND 16, 17, 32, 64 coils (the broken cases)
- Claude's discretion on test depth and validation assertions

### Claude's Discretion
- Fix architecture: type-aware quantity parameter vs override in subclass
- Whether to add byte count validation (assert `bytes.length == ceil(quantity / 8)` for coils)
- Test infrastructure details
- Upstream coordination (not important right now)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `packages/modbus_client_tcp/test/modbus_test_server.dart`: Mock TCP server pattern from Phase 1 — can be adapted for testing FC15 response parsing
- `packages/modbus_client_tcp/test/modbus_client_tcp_test.dart`: Test structure pattern with mock server setup/teardown

### Established Patterns
- Local fork in `packages/` with path dependency: proven in Phase 1 with `modbus_client_tcp`
- TDD red/green/refactor cycle: established workflow

### Integration Points
- `modbus_client_tcp/pubspec.yaml` currently depends on `modbus_client: ^1.4.2` from pub.dev — must update to `path: ../modbus_client`
- `packages/tfc_dart/pubspec.yaml` may need transitive dependency update
- `getMultipleWriteRequest` in `modbus_element.dart:95-115` — the fix target
- `ModbusBitElement` in `element_type/modbus_element_bit.dart` — coil type that inherits the broken method
- `ModbusWriteRequest` in `modbus_request.dart:176-204` — response handling for write operations

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- Group write capability (`ModbusWriteGroupRequest`) — commented out in `modbus_element_group.dart`, could be its own phase or part of Phase 6
- Upstream contribution to `modbus_client` pub.dev package — fix locally first, consider PR later

</deferred>

---

*Phase: 02-fc15-coil-write-fix*
*Context gathered: 2026-03-06*
