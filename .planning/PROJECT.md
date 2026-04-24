# UMAS Real-World Verification & Hardening

## What This Is

A comprehensive verification and hardening effort for the UMAS (Unified Messaging Application Services) protocol implementation in the TFC HMI. The goal is to prove the UMAS subsystem works against a real Schneider PLC at 10.50.10.12, expand test coverage to all UMAS sub-functions, harden error handling for production use, and verify the browse UI works with real PLC data.

## Core Value

The UMAS protocol client reliably communicates with real Schneider PLCs — browsing variables, reading/writing values, and handling all sub-functions — so operators can discover and interact with PLC data through the HMI.

## Requirements

### Validated

- ✓ FC90 request/response framing (UmasRequest class) — existing
- ✓ ReadPlcId (0x02) sub-function — existing
- ✓ Init (0x01) sub-function — existing
- ✓ ReadDataDictionary (0x26) sub-function — existing
- ✓ Python stub server for offline testing — existing
- ✓ Wire format correction (status/subFunc byte order) — existing
- ✓ UmasVariable and data type mapping — existing
- ✓ UMAS Browse UI widget — existing

### Active

- [ ] All UMAS sub-functions implemented and tested against real PLC at 10.50.10.12
- [ ] Python stub server expanded to cover all UMAS sub-functions
- [ ] Live hardware tests passing against 10.50.10.12
- [ ] Browse UI displays real PLC variable tree
- [ ] Error handling hardened for production (timeouts, reconnection, malformed responses)
- [ ] Read/write variable values to/from real PLC
- [ ] PLC status, memory operations, and diagnostics sub-functions
- [ ] Ship-ready quality — robust enough for operator use

### Out of Scope

- New UI features beyond the existing UMAS browse panel — this is about making what exists work reliably
- Support for non-Schneider PLCs — UMAS is Schneider-specific
- PLC firmware configuration — the PLC at 10.50.10.12 is assumed to be properly configured

## Context

- Previous live testing against 10.50.10.123 returned UMAS status 0x83 for all sub-functions, likely because that PLC didn't have UMAS/FC90 enabled. The new PLC at 10.50.10.12 is expected to support UMAS properly.
- The current UmasClient implements ReadPlcId (0x02), Init (0x01), and ReadDataDictionary (0x26). Additional UMAS sub-functions (ReadProjectInfo 0x03, memory read/write, diagnostics) need research and implementation.
- The Python stub server handles basic sub-functions but needs expansion to match real PLC behavior observed during live testing.
- The UMAS browse UI (`lib/widgets/umas_browse.dart`) exists but hasn't been verified against real PLC data.
- Wire format was corrected based on real PLC observations: pdu[2] = SubFuncEcho, pdu[3] = Status (differs from initial research assumptions).

## Constraints

- **Hardware**: Real PLC at 10.50.10.12:502 required for live testing
- **Protocol**: UMAS over Modbus TCP FC90 — Schneider proprietary, limited public documentation
- **Network**: PLC must be reachable from development machine
- **Tech stack**: Dart/Flutter, existing `umas_client.dart` in `packages/tfc_dart`

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Research UMAS protocol thoroughly before testing | Limited public docs — need to understand all sub-functions before implementing | — Pending |
| Expand stub server alongside live testing | Keep offline tests in sync with real PLC behavior | — Pending |
| Test all UMAS sub-functions, not just browse | Complete protocol coverage needed for ship-ready quality | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-24 after initialization*
