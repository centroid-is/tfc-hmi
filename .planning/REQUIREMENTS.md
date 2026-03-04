# Requirements: jbtm

**Defined:** 2026-03-04
**Core Value:** Reliable, real-time acquisition of device data into state_man -- if the device pushes a record, the system captures it and makes it available as a DynamicValue stream.

## v1 Requirements

### TCP Transport (msocket)

- [x] **TCP-01**: msocket provides TCP connection with configurable host and port
- [x] **TCP-02**: msocket configures SO_KEEPALIVE with low timeouts for disconnect detection
- [x] **TCP-03**: msocket auto-reconnects with exponential backoff on disconnect
- [x] **TCP-04**: msocket exposes connection status stream (connected/connecting/disconnected)
- [ ] **TCP-05**: msocket connection resilience verified via proxy.dart (cable pull, switch reboot simulation)

### M2400 Protocol

- [x] **M24-01**: Parser handles STX/ETX frame delimiting from TCP byte stream (partial reads, split frames)
- [x] **M24-02**: Parser extracts tab-separated key-value pairs from framed records
- [x] **M24-03**: Record type discrimination via enum (REC_WGT=3, REC_LUA=87, REC_INTRO=5, REC_STAT=14)
- [x] **M24-04**: Field enums cover full catalog (FLD_WEIGHT, FLD_STATUS, FLD_DEVID, FLD_UNIT, FLD_SIWEIGHT, FLD_OUTPUT, FLD_MATERIAL, FLD_WQUALITY, FLD_WCOUNT, FLD_LENGTH, FLD_BATCHID, FLD_PIECES, FLD_MSGID, FLD_REGCMD, FLD_KEY, FLD_DEVTYPE, FLD_DEVPROG, FLD_EXID, FLD_POSITION, FLD_ERRTEXT, FLD_BUTTONID, FLD_IDFAMILY, FLD_TARE, FLD_BARCODE, FLD_SADDLES, FLD_NOMINAL, FLD_TARGET, FLD_FGIVEAWAY, FLD_VGIVEAWAY, FLD_TARETYPE, FLD_SERIAL_NUMBER, FLD_STDDEVA, FLD_RESULT_CODE, FLD_DATE, FLD_TIME, FLD_TIME_MS, FLD_SCALE_RANGE, FLD_WEIGHING_STATUS, FLD_PROGRAMID, FLD_PROGRAMNAME, FLD_MINWEIGHT, FLD_MAXWEIGHT, FLD_ALIBI, FLD_DIVISION, FLD_ID, FLD_REJECT_REASON, FLD_ORIGIN_LABEL, FLD_TARE_DEVICE, FLD_TARE_ALIBI, FLD_PACK_ID, FLD_CHECKSUM, FLD_ALIBI_TEXT, FLD_BELT_USAGE, FLD_EVENT_NO, FLD_DELTATIME, FLD_DELTAWEIGHT, FLD_THROUGHPUT)
- [x] **M24-05**: Type-specific value parsing per field (Decimal for weights, int for IDs, percentage for belt usage, date/time parsing)
- [x] **M24-06**: Weigher status enum (WST_BAD=0, WST_R1=1, WST_R2=2, WST_BAD_DENY=10, WST_BAD_STDDEV=11, WST_BAD_ALIBI=12, WST_BAD_UNEXPECT=13, WST_BAD_UNDER=14, WST_BAD_OVER=15)
- [x] **M24-07**: LUA record support (REC_LUA=87) with dynamic/unknown fields
- [x] **M24-08**: Device timestamp extraction from FLD_DATE/FLD_TIME/FLD_TIME_MS when present
- [x] **M24-09**: Stub server speaks M2400 protocol with programmable record sequences for TDD
- [x] **M24-10**: Unknown fields logged as warnings, do not crash parser

### DynamicValue Integration

- [x] **DV-01**: Extract binarize from DynamicValue in open62541_dart (make-dynamicvalue-more-generic branch)
- [x] **DV-02**: M2400 parsed records convert to DynamicValue (full record as object, fields as typed values)

### state_man Integration

- [x] **SM-01**: M2400ClientWrapper follows ClientWrapper pattern (connect, disconnect, status stream)
- [ ] **SM-02**: state_man subscribe returns Stream<DynamicValue> for M2400 keys
- [x] **SM-03**: Named key addressing -- WGT for full record DynamicValue, WGT.WEIGHT for individual field
- [x] **SM-04**: Connection status integrated into state_man status reporting
- [ ] **SM-05**: Multi-device support -- N simultaneous M2400 connections with independent configs
- [ ] **SM-06**: Collector integration -- weight events auto-stored to timeseries database
- [ ] **SM-07**: Connection health metrics -- uptime, reconnect count, records/second per device

### Configuration

- [ ] **CFG-01**: Server config with host, port (52211/52212), and alias -- JSON-serializable
- [ ] **CFG-02**: JBTM server config section separate from OPC UA section in StateManConfig
- [ ] **CFG-03**: Key mapping CRUD -- create, read, update, delete key mappings for M2400 devices

### UI

- [ ] **UI-01**: Server configuration page with JBTM section distinct from OPC UA section
- [ ] **UI-02**: Server picker in key repository distinguishes M2400 vs OPC UA device types
- [ ] **UI-03**: Option lists to select REC type when configuring M2400 key
- [ ] **UI-04**: Option lists to select FLD when configuring M2400 key (filtered by context)

## v2 Requirements

### Future Protocols

- **FP-01**: M3000 protocol support (XML-based) reusing msocket
- **FP-02**: Pluto protocol support reusing msocket
- **FP-03**: Innova protocol support reusing msocket

### Advanced Features

- **ADV-01**: Write/command to M2400 device (bidirectional)
- **ADV-02**: Historical data replay from device memory

## Out of Scope

| Feature | Reason |
|---------|--------|
| Write/command to device | Read-only for v1; doubles complexity, not needed yet |
| Generic protocol framework | Build M2400 concrete first; let abstraction emerge when M3000 arrives |
| Polling mechanism | M2400 pushes records; polling fights the device design |
| Checksum/CRC validation | TCP handles integrity; M2400 ASCII protocol has no checksums |
| Multi-dimensional array fields | M2400 fields are flat key-value pairs |
| In-package UI | Package is data layer; UI lives in main app |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TCP-01 | Phase 2 | Complete |
| TCP-02 | Phase 2 | Complete |
| TCP-03 | Phase 2 | Complete |
| TCP-04 | Phase 2 | Complete |
| TCP-05 | Phase 8 | Pending |
| M24-01 | Phase 3 | Complete |
| M24-02 | Phase 3 | Complete |
| M24-03 | Phase 3 | Complete |
| M24-04 | Phase 5 | Complete |
| M24-05 | Phase 5 | Complete |
| M24-06 | Phase 5 | Complete |
| M24-07 | Phase 5 | Complete |
| M24-08 | Phase 5 | Complete |
| M24-09 | Phase 4 | Complete |
| M24-10 | Phase 3 | Complete |
| DV-01 | Phase 1 | Complete |
| DV-02 | Phase 6 | Complete |
| SM-01 | Phase 7 | Complete |
| SM-02 | Phase 7 | Pending |
| SM-03 | Phase 7 | Complete |
| SM-04 | Phase 7 | Complete |
| SM-05 | Phase 9 | Pending |
| SM-06 | Phase 9 | Pending |
| SM-07 | Phase 8 | Pending |
| CFG-01 | Phase 9 | Pending |
| CFG-02 | Phase 9 | Pending |
| CFG-03 | Phase 9 | Pending |
| UI-01 | Phase 10 | Pending |
| UI-02 | Phase 10 | Pending |
| UI-03 | Phase 10 | Pending |
| UI-04 | Phase 10 | Pending |

**Coverage:**
- v1 requirements: 31 total
- Mapped to phases: 31
- Unmapped: 0

---
*Requirements defined: 2026-03-04*
*Last updated: 2026-03-04 after roadmap creation*
