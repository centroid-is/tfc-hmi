---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in_progress
stopped_at: Phase 8 Plan 02 complete
last_updated: "2026-03-04T14:54:00.000Z"
last_activity: 2026-03-04 -- Completed 08-02 (Pipeline resilience tests, 224 total tests)
progress:
  total_phases: 10
  completed_phases: 8
  total_plans: 18
  completed_plans: 14
  percent: 78
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-04)

**Core value:** Reliable, real-time acquisition of device data into state_man -- if the device pushes a record, the system captures it and makes it available as a DynamicValue stream.
**Current focus:** Phase 8 complete - Connection Resilience. Phase 9 next (Configuration & Multi-Device).

## Current Position

Phase: 8 of 10 (Connection Resilience) -- COMPLETE
Plan: 2 of 2 in current phase -- COMPLETE
Status: Phase 8 Complete, Phase 9 Next
Last activity: 2026-03-04 -- Completed 08-02 (Pipeline resilience tests, 23 new tests, 224 total)

Progress: [████████--] 78%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | 3min | 2 tasks | 3 files |
| Phase 01 P02 | 7min | 2 tasks | 4 files |
| Phase 02 P01 | 14min | 2 tasks | 7 files |
| Phase 02 P02 | 3min | 1 task | 2 files |
| Phase 03 P01 | 4min | 2 tasks | 3 files |
| Phase 03 P02 | 3min | 1 task | 1 file |
| Phase 04 P01 | 7min | 1 task | 7 files |
| Phase 05 P01 | 5min | 2 tasks | 4 files |
| Phase 05 P02 | 3min | 1 task | 3 files |
| Phase 06 P01 | -- | 1 task | 3 files |
| Phase 07 P01 | 4min | 1 task | 3 files |
| Phase 07 P02 | 6min | 2 tasks | 3 files |
| Phase 08 P01 | 3min | 2 tasks | 5 files |
| Phase 08 P02 | 3min | 1 task | 1 file |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Phases 1 and 2 can be parallelized (DV extraction and msocket have no dependency)
- Roadmap: DynamicValue extraction is Phase 1 because it is a cross-repo blocker (open62541_dart)
- Roadmap: Stub server is its own phase (Phase 4) to establish TDD infrastructure before field catalog
- [Phase 01]: Used static methods on OpcUaDynamicValueSerializer (not extension methods) for explicit OPC UA dependency and future protocol extensibility
- [Phase 01]: autoDeduceType made private static on serializer (only used internally by serialize)
- [Phase 01]: common.dart uses barrel import for OpcUaDynamicValueSerializer (no separate import needed)
- [Phase 01]: Phase 1 complete -- DynamicValue is fully protocol-agnostic, make-dynamicvalue-more-generic branch ready for merge
- [Phase 02]: Used Completer instead of asFuture() for socket done tracking (asFuture leaks SocketExceptions to test zones)
- [Phase 02]: BehaviorSubject for status stream replay (consistent with tfc_dart patterns)
- [Phase 02]: Used RawSocketOption.levelSocket/levelTcp constants from dart:io (not hardcoded integers)
- [Phase 02]: Plan 01 implementation already contained full reconnect logic; Plan 02 focused on comprehensive test coverage (9 reconnect tests)
- [Phase 03]: recordTypeFieldKey defined as 'REC' top-level constant -- needs validation against protocol docs/device captures
- [Phase 03]: Silent discard for inter-frame garbage bytes (no logging to avoid log flood)
- [Phase 03]: 64KB max frame size (65536 bytes) for oversized frame protection
- [Phase 03]: StreamTransformer pattern for frame parser, pure function for record parser
- [Phase 03]: Completer-based test sync for broadcast stream pipelines (stream.first creates cold subscription that misses events)
- [Phase 03]: Phase 3 complete -- M2400 framing validated end-to-end with 51 tests (unit + integration)
- [Phase 04]: TestTcpServer moved from test/ to lib/src/ for importability by external packages
- [Phase 04]: onConnect callback on TestTcpServer enables per-client INTRO writes without broadcast
- [Phase 04]: utf8.encode used instead of .codeUnits in buildM2400Frame for non-ASCII correctness
- [Phase 04]: M2400StubServer uses composition (wraps TestTcpServer) not inheritance
- [Phase 04]: Phase 4 complete -- M2400StubServer with 22 tests, TDD infrastructure ready for phases 5-8
- [Phase 05]: Weight values parsed to double directly (no Decimal package) -- resolves STATE.md blocker
- [Phase 05]: Field 77 (SI Weight) classified as FieldType.string -- display-ready, no suffix stripping
- [Phase 05]: Unknown field IDs logged at debug level (not warning) for discovery without production noise
- [Phase 05]: Enum value 'id' renamed to 'recordId' to avoid shadowing M2400Field.id getter
- [Phase 05]: Stub server factories import M2400Field enum directly as single source of truth for field IDs
- [Phase 05]: INTRO record field IDs kept as string keys (not confirmed from device data)
- [Phase 05]: Phase 5 complete -- 54 M2400Field values, typed parsing, 160 tests (67 new)
- [Phase 06]: convertRecordToDynamicValue maps M2400ParsedRecord to DynamicValue object tree with typed children and enum metadata
- [Phase 06]: Phase 6 complete -- DynamicValue conversion with 13 tests, pipeline round-trip verified
- [Phase 07]: Wrapper-owned BehaviorSubject for status (not delegating to MSocket) to survive connect/disconnect cycles
- [Phase 07]: Route by DynamicValue.name (set to M2400RecordType.name by converter) rather than carrying record type separately
- [Phase 07]: STAT/INTRO use BehaviorSubject (replay last); BATCH/LUA use broadcast StreamController (event-only)
- [Phase 07]: Dot-notation uses DynamicValue[] operator to traverse child hierarchy
- [Phase 07]: DeviceClient interface in tfc_dart (not jbtm depending on tfc_dart) to avoid wrong-direction dependency
- [Phase 07]: jbtm does NOT depend on tfc_dart -- adapter wrapping M2400ClientWrapper as DeviceClient lives at app layer
- [Phase 07]: StateMan.subscribe() checks DeviceClient.canSubscribe() first, falls through to OPC UA _monitor()
- [Phase 07]: Phase 7 complete -- DeviceClient interface, StateMan routing, 17 new tests (6 routing + 11 integration), 207 total
- [Phase 08]: TcpProxy copied verbatim from tfc_dart/test/proxy.dart (self-contained, no cross-package dependency)
- [Phase 08]: ConnectionHealthMetrics tracks first connect via boolean flag; only subsequent connects count as reconnections
- [Phase 08]: Rolling 1-second window for recordsPerSecond (List<DateTime> with pruning on access)
- [Phase 08]: Cable pull simulation uses proxy shutdown + restart on captured fixed port
- [Phase 08]: Pipeline resilience tests verify through M2400ClientWrapper.subscribe() (real integration path)
- [Phase 08]: Phase 8 complete -- ConnectionHealthMetrics, TcpProxy, 23 new resilience tests, 224 total

### Pending Todos

None yet.

### Blockers/Concerns

- ~~Phase 1: make-dynamicvalue-more-generic branch status in open62541_dart is unknown~~ RESOLVED: Branch has 4 clean commits, all tests pass
- ~~Phase 5: Decimal handling strategy (Decimal package vs string preservation) needs decision before parser implementation~~ RESOLVED: Using double directly -- DynamicValue uses double, M2400 values have 2-3 decimal places max, no arithmetic in jbtm
- ~~Phase 2: Platform-specific SO_KEEPALIVE constants (macOS vs Linux) need verification on deployment target~~ RESOLVED: Constants verified from macOS system headers and centroid-is/postgresql-dart reference implementation. All tests pass on macOS.

## Session Continuity

Last session: 2026-03-04T14:54:00.000Z
Stopped at: Phase 8 Plan 02 complete
Resume file: .planning/phases/08-connection-resilience/08-02-SUMMARY.md
