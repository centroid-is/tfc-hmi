# Technology Stack: Modbus TCP Integration

**Project:** TFC-HMI Modbus TCP Client
**Researched:** 2026-03-06
**Overall Confidence:** HIGH (existing fork already chosen; research confirms it is the right choice)

## Recommended Stack

### Core Modbus Libraries

| Technology | Version | Source | Purpose | Why |
|------------|---------|--------|---------|-----|
| `modbus_client` | ^1.4.4 | pub.dev (upstream) | Base Modbus protocol: element types, function codes, request/response framing | Best-in-class for Dart. Rich type system (int16/32/64, uint16/32/64, float, double, bit, coil, enum, status, bitmask). Actively maintained by cabella.net. 160 pub points, 1050 weekly downloads. No fork needed -- upstream is sufficient after PROJECT.md review clarified the FC15 bug is in quantity calculation, not in the base package architecture. |
| `modbus_client_tcp` | git: centroid-is fork, `add-keepalive` branch | GitHub fork of cabbi/modbus_client_tcp | TCP transport layer with keepalive | Fork is required. Upstream (v1.2.3, last updated Apr 2025) has no keepalive, no TCP_NODELAY, single `_currentResponse` (no concurrent requests), and a frame length check bug. The centroid-is fork on `add-keepalive` branch addresses keepalive. Remaining fixes (frame length off-by-6, transaction ID map, length validation, TCP_NODELAY) are scoped in PROJECT.md requirements. |

### Supporting Libraries (Already in Project)

| Library | Version | Purpose | Relevance to Modbus |
|---------|---------|---------|---------------------|
| `rxdart` | ^0.28.0 | BehaviorSubject streams | ModbusClientWrapper uses BehaviorSubject for polled values, same pattern as OPC UA/M2400 |
| `logger` | ^2.4.0 | Structured logging | Connection lifecycle, poll group timing, error reporting |
| `json_annotation` + `json_serializable` | ^4.9.0 / ^6.9.4 | Config serialization | ModbusConfig, ModbusNodeConfig, ModbusPollGroup need JSON round-tripping for config.json |
| `open62541` | git: centroid-is | DynamicValue type only | Modbus values convert to/from DynamicValue for StateMan compatibility (not for OPC UA protocol) |

### Infrastructure (Already in Project)

| Technology | Version | Purpose | Modbus Impact |
|------------|---------|---------|---------------|
| MSocket (jbtm package) | local | TCP keepalive reference | NOT used for Modbus transport. modbus_client_tcp has its own socket. But MSocket's keepalive constants (macOS: 0x10/0x101/0x102, Linux: 4/5/6) are the reference for what the fork needs. Windows constants (3/17/16) need adding to MSocket too. |
| drift + drift_postgres | ^2.28.0 / ^1.3.1 | TimescaleDB storage | Modbus polled values flow through StateMan into the same database pipeline as OPC UA |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| **Base protocol** | `modbus_client` (cabbi) | `dart_modbus` v1.0.1 | New package (4 months old), 2 likes, 34 downloads, unverified publisher. Pure Dart is nice but modbus_client has 3 years of production use, richer type system, and the old modbus-test branch already has 3300 lines built on it. Switching would mean rewriting ModbusClientWrapper. |
| **Base protocol** | `modbus_client` (cabbi) | `modbus` (hacker-cb) v0.2.0 | Abandoned. Last update 3 years ago (Sep 2022). Stuck on Dart SDK 2.12. No coil/discrete input types. Dead project. |
| **Base protocol** | `modbus_client` (cabbi) | `modbus_master` v2.1.4 | Single-element operations only (no bulk read/write). 59 weekly downloads. No register grouping. Would require building all the batching/grouping logic that modbus_client provides for free. |
| **TCP transport** | centroid-is fork of `modbus_client_tcp` | Upstream `modbus_client_tcp` v1.2.3 | Missing keepalive, TCP_NODELAY, concurrent request support, and has frame length bug. These are not optional for industrial HMI -- stale connections cause operator confusion, Nagle latency is unacceptable for real-time display, and the frame bug causes data corruption. |
| **TCP transport** | centroid-is fork of `modbus_client_tcp` | Raw MSocket + custom framing | MSocket is battle-tested for raw TCP but has no Modbus MBAP framing. Would mean reimplementing the entire Modbus TCP protocol layer (transaction IDs, unit IDs, PDU length parsing, response matching). 10x more work than fixing the fork's bugs. |
| **TCP transport** | centroid-is fork of `modbus_client_tcp` | `dart_modbus` TCP client | Same concerns as base protocol alternative. Unknown quality of TCP handling. No keepalive support evident. |

## Ecosystem Assessment

The Dart Modbus ecosystem is small but adequate. There are effectively two viable options:

1. **cabbi/modbus_client + modbus_client_tcp** -- The clear leader. Verified publisher (cabella.net). Modular design (separate TCP/UDP/Serial packages). Rich type system covering all standard Modbus data representations. Active maintenance (v1.4.4 released ~Oct 2025). This is what the project already uses via centroid-is forks.

2. **Everything else** -- Either abandoned (`modbus` v0.2.0), too new/unproven (`dart_modbus` v1.0.1), or too limited (`modbus_master` -- single-element only).

The decision to fork `modbus_client_tcp` rather than replace it is sound. The upstream package handles the complex parts (MBAP header construction, response parsing, connection management) correctly for the common case. The bugs are in edge cases (16+ coils, concurrent requests, frame length validation) that are fixable without architectural changes.

## Bugs to Fix in Dependencies

These are already documented in PROJECT.md but included here for stack completeness:

### modbus_client (upstream, pub.dev v1.4.4)

| Bug | Severity | Fix Location | Notes |
|-----|----------|------------|-------|
| FC15 quantity bug for 16+ coils | HIGH | Fork or PR upstream | Issue #19 on cabbi/modbus_client confirms the problem. Quantity is hardcoded to 1 regardless of actual coil count. Need to fork modbus_client too, or submit a PR. |
| No ModbusWriteGroupRequest | MEDIUM | Fork or custom code | Group writes need implementing. modbus_client has ModbusElementsGroup for reads but not for writes. |

### modbus_client_tcp (centroid-is fork, add-keepalive branch)

| Bug | Severity | Fix Location | Notes |
|-----|----------|------------|-------|
| Frame length check off by 6 bytes | HIGH | Line ~297 in fork | MBAP header is 7 bytes (not 6). PDU length field doesn't include the 6-byte header prefix. The check is comparing wrong values. |
| Single `_currentResponse` (no concurrent requests) | HIGH | Replace with transaction ID map | Modbus TCP protocol uses transaction IDs specifically to support pipelining. The upstream design serializes all requests through a lock, which works but kills throughput for multi-poll-group scenarios. |
| No length field validation | MEDIUM | Add 1-256 range check | Malformed responses with length=0 or length>256 should be rejected, not parsed. |
| No TCP_NODELAY | MEDIUM | Add after connect() | Nagle's algorithm adds up to 200ms latency. Unacceptable for HMI polling at 100ms-1s intervals. |
| Keepalive values need matching MSocket | LOW | Already partially done in fork | Verify values match MSocket: 5s idle, 2s interval, 3 probes. |

### MSocket (jbtm package)

| Bug | Severity | Fix Location | Notes |
|-----|----------|------------|-------|
| No Windows keepalive support | MEDIUM | `_configureKeepalive()` | Add `Platform.isWindows` branch with constants: SIO_KEEPALIVE_VALS=3, TCP_KEEPIDLE=17, TCP_KEEPINTVL=16. Reference: centroid-is/postgresql-dart add-keepalive-test branch. Benefits M2400 protocol too. |

## Fork Strategy Recommendation

**Use upstream `modbus_client` v1.4.4 from pub.dev unless FC15 fix requires a fork.** Check if the FC15 bug can be worked around by using ModbusCoil elements correctly (per maintainer's response in issue #19). If not, fork to centroid-is/modbus_client.

**Use centroid-is/modbus_client_tcp fork (add-keepalive branch) with additional fixes.** This is already the plan. The fork is necessary -- upstream hasn't been updated since Apr 2025 and shows no intent to add keepalive or concurrent request support.

## Installation

```yaml
# In packages/tfc_dart/pubspec.yaml
dependencies:
  # Modbus - base protocol (try upstream first; fork if FC15 fix needed)
  modbus_client: ^1.4.4
  # OR if fork needed:
  # modbus_client:
  #   git:
  #     url: https://github.com/centroid-is/modbus_client.git
  #     ref: main

  # Modbus - TCP transport (fork required for keepalive + bug fixes)
  modbus_client_tcp:
    git:
      url: https://github.com/centroid-is/modbus_client_tcp.git
      ref: add-keepalive
```

## Key Version Constraints

| Package | Min Dart SDK | Notes |
|---------|-------------|-------|
| modbus_client 1.4.4 | 2.17 | Project uses ^3.5.1, no conflict |
| modbus_client_tcp 1.2.3 (upstream base) | 2.17 | No conflict |
| Project SDK | ^3.5.1 | Well above all minimums |

## Sources

- [modbus_client on pub.dev](https://pub.dev/packages/modbus_client) -- v1.4.4, verified publisher cabella.net, 160 pub points, 1050 weekly downloads (HIGH confidence)
- [modbus_client_tcp on pub.dev](https://pub.dev/packages/modbus_client_tcp) -- v1.2.3, verified publisher cabella.net, 160 pub points, 844 weekly downloads (HIGH confidence)
- [cabbi/modbus_client GitHub](https://github.com/cabbi/modbus_client) -- 16 stars, 7 forks, 2 open issues including FC15 (#19) (HIGH confidence)
- [cabbi/modbus_client_tcp GitHub](https://github.com/cabbi/modbus_client_tcp) -- 8 stars, 4 forks, 1 open issue, upstream source for centroid-is fork (HIGH confidence)
- [FC15 issue #19](https://github.com/cabbi/modbus_client/issues/19) -- Confirmed: FC15 quantity bug when writing 16+ coils (HIGH confidence)
- [centroid-is/modbus_client_tcp GitHub](https://github.com/centroid-is/modbus_client_tcp) -- Fork with add-keepalive branch, 20 commits (MEDIUM confidence -- could not fully inspect branch diff)
- [modbus on pub.dev](https://pub.dev/packages/modbus) -- v0.2.0, abandoned 3 years ago (HIGH confidence -- confirmed dead)
- [modbus_master on pub.dev](https://pub.dev/packages/modbus_master) -- v2.1.4, single-element only (HIGH confidence)
- [dart_modbus on pub.dev](https://pub.dev/packages/dart_modbus) -- v1.0.1, too new, 34 downloads (HIGH confidence)
- modbus-test branch in tfc-hmi repo -- 3300 lines of existing work, uses modbus_client + modbus_client_tcp (HIGH confidence -- directly inspected)
- MSocket source in packages/jbtm/lib/src/msocket.dart -- keepalive constants for macOS/Linux, no Windows (HIGH confidence -- directly inspected)
