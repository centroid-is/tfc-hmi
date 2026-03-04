# Roadmap: jbtm

## Overview

This roadmap delivers industrial device data acquisition from M2400 weighing/grading devices into the TFC state management system. The build follows a strict dependency chain: extract DynamicValue serialization from open62541_dart, build a reusable TCP socket layer, implement the M2400 ASCII protocol parser with TDD infrastructure, convert parsed data to DynamicValue streams, integrate into state_man following established ClientWrapper patterns, add configuration and multi-device support, then build UI for server configuration and key mapping. Each phase delivers a verifiable, testable capability that unblocks the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: DynamicValue Extraction** - Decouple binarize/serialize from OPC UA in open62541_dart
- [ ] **Phase 2: msocket TCP Layer** - Reusable TCP socket with keepalive, reconnect, and status
- [x] **Phase 3: M2400 Framing** - STX/ETX frame parser and tab-separated record extraction (completed 2026-03-04)
- [x] **Phase 4: M2400 Stub Server** - Programmable test server for TDD of all downstream work (completed 2026-03-04)
- [x] **Phase 5: M2400 Field Catalog** - Field enums, type-specific parsing, status enums, LUA records (completed 2026-03-04)
- [x] **Phase 6: DynamicValue Conversion** - M2400 parsed records to DynamicValue objects (completed 2026-03-04)
- [ ] **Phase 7: state_man Integration** - M2400ClientWrapper, subscribe, named keys, connection status
- [ ] **Phase 8: Connection Resilience** - Proxy-based flaky connection testing and health metrics
- [ ] **Phase 9: Configuration & Multi-device** - Server config, key mapping CRUD, multi-device, collector
- [ ] **Phase 10: UI** - Server config page, key repository picker, REC/FLD option lists

## Phase Details

### Phase 1: DynamicValue Extraction
**Goal**: DynamicValue type is decoupled from OPC UA-specific serialization, enabling protocol-dependent binarize strategies
**Depends on**: Nothing (first phase)
**Requirements**: DV-01
**Success Criteria** (what must be TRUE):
  1. DynamicValue can be instantiated and used without importing any OPC UA serialization code
  2. Existing OPC UA serialization continues to work identically (no regression)
  3. A new serialization strategy can be registered for a non-OPC-UA protocol
  4. The make-dynamicvalue-more-generic branch changes are merged and tests pass in open62541_dart
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Create OpcUaDynamicValueSerializer and strip DynamicValue of PayloadType
- [x] 01-02-PLAN.md — Update call sites, tests, and verify no regression

### Phase 2: msocket TCP Layer
**Goal**: A reusable, protocol-agnostic TCP socket that reliably connects, detects disconnects quickly, and auto-reconnects
**Depends on**: Nothing (independent of Phase 1; can be parallelized)
**Requirements**: TCP-01, TCP-02, TCP-03, TCP-04
**Success Criteria** (what must be TRUE):
  1. msocket connects to a TCP server given host and port, and exposes a raw byte stream
  2. msocket detects a dead connection within ~11 seconds via SO_KEEPALIVE (idle 5s, interval 2s, count 3)
  3. msocket auto-reconnects with bounded exponential backoff after disconnect (500ms initial, 5s max)
  4. msocket exposes a connection status stream that emits connected/connecting/disconnected states accurately
  5. All behavior verified with unit tests using local TCP servers
**Plans**: 2 plans

Plans:
- [ ] 02-01-PLAN.md — Package scaffolding, TestTcpServer helper, MSocket core (connect, data, status, keepalive)
- [ ] 02-02-PLAN.md — Auto-reconnect with exponential backoff, dispose lifecycle, edge-case tests

### Phase 3: M2400 Framing
**Goal**: Raw TCP byte streams are reliably parsed into complete, structured M2400 records
**Depends on**: Phase 2 (uses msocket byte stream interface, but can be tested with in-memory streams)
**Requirements**: M24-01, M24-02, M24-03, M24-10
**Success Criteria** (what must be TRUE):
  1. STX/ETX frame parser correctly extracts complete frames from arbitrary TCP chunk boundaries (partial reads, split frames, multiple frames in one chunk)
  2. Tab-separated key-value pairs are extracted from framed records into structured data
  3. Record type is discriminated via enum (REC_WGT, REC_LUA, REC_INTRO, REC_STAT)
  4. Unknown/unexpected fields are logged as warnings without crashing the parser
**Plans**: 2 plans

Plans:
- [ ] 03-01-PLAN.md — M2400FrameParser StreamTransformer, M2400Record/RecordType types, parseM2400Frame function (TDD)
- [ ] 03-02-PLAN.md — Barrel export, end-to-end integration tests with TestTcpServer + MSocket pipeline

### Phase 4: M2400 Stub Server
**Goal**: A programmable test server that speaks M2400 protocol, enabling TDD for all downstream integration work
**Depends on**: Phase 3 (uses M2400 framing/record format)
**Requirements**: M24-09
**Success Criteria** (what must be TRUE):
  1. Stub server binds to an OS-assigned port and accepts TCP connections
  2. Stub server sends programmable sequences of valid M2400 records (STX-framed, tab-separated)
  3. Stub server can simulate device behavior: push records on demand, push at intervals, push on connect
  4. An msocket client can connect to the stub server and receive parsed M2400 records end-to-end
**Plans**: 1 plan

Plans:
- [x] 04-01-PLAN.md — M2400StubServer with record factories, auto-INTRO, push scheduling, malformed helpers, and tests

### Phase 5: M2400 Field Catalog
**Goal**: Every M2400 field type is enumerated and parsed to its correct Dart type with full protocol coverage
**Depends on**: Phase 3 (extends the parser with field-level detail)
**Requirements**: M24-04, M24-05, M24-06, M24-07, M24-08
**Success Criteria** (what must be TRUE):
  1. All documented field enums (FLD_WEIGHT through FLD_THROUGHPUT, 50+ fields) are defined and parseable
  2. Type-specific parsing produces correct Dart types: Decimal for weights, int for IDs, percentage for belt usage, DateTime for timestamps
  3. Weigher status enum (WST_BAD through WST_BAD_OVER) is defined and parsed from FLD_STATUS values
  4. LUA records (REC_LUA=87) are parsed with dynamic/unknown field handling
  5. Device timestamps are correctly extracted and combined from FLD_DATE, FLD_TIME, and FLD_TIME_MS
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md — M2400Field/FieldType/WeigherStatus enums, parseTypedRecord, M2400ParsedRecord, field parsing tests (TDD)
- [x] 05-02-PLAN.md — Stub server factory alignment to real field IDs, barrel exports, round-trip integration tests

### Phase 6: DynamicValue Conversion
**Goal**: Parsed M2400 records are representable as DynamicValue objects for state_man consumption
**Depends on**: Phase 1 (extracted binarize), Phase 5 (parsed M2400 records with typed fields)
**Requirements**: DV-02
**Success Criteria** (what must be TRUE):
  1. A full M2400 parsed record converts to a DynamicValue containing all fields as a structured object
  2. Individual typed field values (Decimal weight, int ID, DateTime timestamp) convert to appropriate DynamicValue representations
  3. Conversion round-trips correctly: M2400 record -> DynamicValue -> field access produces original typed values
**Plans**: 1 plan

Plans:
- [x] 06-01-PLAN.md — convertRecordToDynamicValue function with TDD, barrel export, pipeline round-trip tests

### Phase 7: state_man Integration
**Goal**: Device data flows through state_man as subscribable DynamicValue streams using named keys
**Depends on**: Phase 6 (DynamicValue conversion), Phase 4 (stub server for integration tests)
**Requirements**: SM-01, SM-02, SM-03, SM-04
**Success Criteria** (what must be TRUE):
  1. M2400ClientWrapper follows ClientWrapper pattern: connect, disconnect, status stream
  2. state_man subscribe returns a Stream of DynamicValue for M2400 keys
  3. Named key addressing works: WGT returns full record DynamicValue, WGT.WEIGHT returns individual field value
  4. Connection status from msocket is integrated into state_man status reporting
  5. End-to-end test: stub server pushes record -> state_man subscriber receives correct DynamicValue
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md — M2400ClientWrapper with pipeline, stream routing, subscribe API, and dot-notation field access
- [ ] 07-02-PLAN.md — StateMan integration wiring, connection status mapping, end-to-end tests with M2400StubServer

### Phase 8: Connection Resilience
**Goal**: Connection reliability is proven under adverse network conditions with observable health metrics
**Depends on**: Phase 7 (working state_man integration to test end-to-end)
**Requirements**: TCP-05, SM-07
**Success Criteria** (what must be TRUE):
  1. proxy.dart tests verify msocket survives cable pull simulation (proxy kill + restart)
  2. proxy.dart tests verify msocket survives switch reboot simulation (delayed proxy restart)
  3. Data flow resumes correctly after reconnection with no duplicate or lost records at the state_man level
  4. Connection health metrics (uptime, reconnect count, records/second) are available per device
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md — ConnectionHealthMetrics class, TcpProxy test utility, proxy-based MSocket resilience tests
- [ ] 08-02-PLAN.md — End-to-end M2400 pipeline resilience tests (StubServer -> Proxy -> MSocket -> FrameParser)

### Phase 9: Configuration & Multi-device
**Goal**: M2400 devices are fully configurable, support multiple simultaneous connections, and integrate with data collection
**Depends on**: Phase 7 (working state_man integration)
**Requirements**: CFG-01, CFG-02, CFG-03, SM-05, SM-06
**Success Criteria** (what must be TRUE):
  1. Server config (host, port 52211/52212, alias) is JSON-serializable and persists to Preferences
  2. JBTM server config section is separate from OPC UA section in StateManConfig
  3. Key mapping CRUD works: create, read, update, delete key mappings for M2400 devices
  4. Multiple M2400 devices connect simultaneously with independent configs and independent data streams
  5. Weight events are auto-stored to timeseries database via Collector integration
**Plans**: 2 plans

Plans:
- [ ] 09-01-PLAN.md — M2400Config, M2400NodeConfig, extend StateManConfig and KeyMappingEntry with JBTM support
- [ ] 09-02-PLAN.md — Multi-device M2400ClientWrapper lifecycle in StateMan, Collector integration for BATCH records

### Phase 10: UI
**Goal**: Users can configure M2400 device connections and key mappings through the application interface
**Depends on**: Phase 9 (configuration and multi-device support)
**Requirements**: UI-01, UI-02, UI-03, UI-04
**Success Criteria** (what must be TRUE):
  1. Server configuration page has a distinct JBTM section separate from OPC UA
  2. Key repository server picker distinguishes M2400 devices from OPC UA devices by type
  3. When configuring an M2400 key, user can select a REC type from a dropdown
  4. When configuring an M2400 key, user can select a FLD from a dropdown filtered by selected REC type
**Plans**: 2 plans

Plans:
- [ ] 10-01-PLAN.md — JBTM servers section on server config page (add/edit/remove M2400 devices)
- [ ] 10-02-PLAN.md — M2400 device type distinction in key repository, REC/FLD dropdown selection

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10
Note: Phases 1 and 2 can be parallelized (no dependency between them).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. DynamicValue Extraction | 1/2 | In Progress|  |
| 2. msocket TCP Layer | 0/2 | Not started | - |
| 3. M2400 Framing | 0/2 | Complete    | 2026-03-04 |
| 4. M2400 Stub Server | 1/1 | Complete    | 2026-03-04 |
| 5. M2400 Field Catalog | 2/2 | Complete    | 2026-03-04 |
| 6. DynamicValue Conversion | 1/1 | Complete    | 2026-03-04 |
| 7. state_man Integration | 1/2 | In Progress | - |
| 8. Connection Resilience | 0/2 | Not started | - |
| 9. Configuration & Multi-device | 0/2 | Not started | - |
| 10. UI | 0/2 | Not started | - |
