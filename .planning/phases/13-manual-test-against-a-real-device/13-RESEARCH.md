# Phase 13: Manual Test Against a Real Device - Research

**Researched:** 2026-03-07
**Domain:** End-to-end Modbus TCP integration validation with physical hardware
**Confidence:** HIGH

## Summary

Phase 13 is an end-to-end validation phase, not a code-writing phase. All Modbus TCP integration code is already complete (Phases 1-11). The purpose of this phase is to exercise the full stack -- from UI configuration through StateMan routing to actual Modbus TCP wire communication -- against a real PLC at `10.50.10.10` on the production network. This validates that the code works beyond unit/widget test mocks.

The project has a known deployment target: Flutter UI runs on `10.50.10.11` (centroid@ via SSH) inside a Docker container named `flutter` (image: `ghcr.io/centroid-is/centroid-hmi`), communicating with a PLC at `10.50.10.10`. The docker-compose stack includes weston (Wayland compositor), timescaledb, and watchtower for auto-updates. The current keymappings.json has ~6000 lines of OPC UA key configurations but zero Modbus entries -- Modbus keys must be configured through the UI for the first time.

The critical testing areas are: (1) connection establishment and status display, (2) reading register values that match known PLC state, (3) writing values and observing PLC-side changes, (4) reconnection after cable pull / power cycle, and (5) coexistence with existing OPC UA subscriptions.

**Primary recommendation:** Create a structured manual test checklist document that the user executes step-by-step, with specific register addresses to read/write, expected behaviors, and pass/fail criteria. The planner should produce a checklist-based plan, not code tasks.

## Standard Stack

This phase does not introduce new libraries or code. It exercises the existing stack:

### Core (already integrated)
| Library | Version | Purpose | Phase Built |
|---------|---------|---------|-------------|
| modbus_client (fork) | packages/modbus_client | Modbus protocol elements, FC01-FC16 | Phase 2 |
| modbus_client_tcp (fork) | packages/modbus_client_tcp | TCP transport with MBAP framing | Phase 1 |
| ModbusClientWrapper | tfc_dart/lib/core | Connection lifecycle, polling, read/write | Phases 4-6 |
| ModbusDeviceClientAdapter | tfc_dart/lib/core | DeviceClient interface adapter | Phase 7 |
| ModbusConfig / ModbusNodeConfig | state_man.dart | JSON serialization | Phase 8 |
| StateMan Modbus routing | state_man.dart | subscribe/read/write dispatch | Phase 9 |
| Server Config UI | lib/pages/server_config.dart | Modbus server CRUD + status | Phase 10 |
| Key Repository UI | lib/pages/key_repository.dart | Protocol switching + Modbus fields | Phase 11 |

### Supporting (deployment)
| Tool | Purpose |
|------|---------|
| SSH (`ssh centroid@10.50.10.11`) | Access to production device |
| Docker (`docker logs flutter`) | View application logs |
| VNC (port 5900 on 10.50.10.11) | View Flutter UI remotely |
| Docker Compose | Manage flutter/weston/timescaledb stack |

## Architecture Patterns

### Full Data Flow Under Test

```
User (VNC/direct) -> Flutter UI (server_config.dart / key_repository.dart)
    -> StateManConfig.toPrefs() -> stateManProvider invalidation
    -> StateMan.create() -> buildModbusDeviceClients()
    -> ModbusClientWrapper.connect() -> ModbusClientTcp -> TCP to PLC:502
    -> PLC responds -> poll group timer reads -> BehaviorSubject update
    -> StateMan.subscribe() stream -> UI widget rebuild -> user sees value
```

### Configuration Flow

1. **Server config page**: Add Modbus server (host: 10.50.10.10, port: 502, unitId: 1, alias: "plc1")
2. **Server config page**: Configure poll group (name: "default", interval: 1000ms)
3. **Save**: Triggers `ref.invalidate(stateManProvider)` which re-creates connections
4. **Key repository page**: Switch a key to Modbus protocol, select server alias "plc1"
5. **Key repository page**: Set register type (e.g., holdingRegister), address, data type
6. **Key repository page**: Save key mappings
7. **StateMan picks up new config**: Modbus adapter subscribes to register, poll group starts reading

### What Must Be Verified on Real Hardware

| Category | What | Why Not Tested Yet |
|----------|------|--------------------|
| TCP connection | Socket connects to PLC:502 | All unit tests use MockModbusClient or ModbusTestServer on localhost |
| MBAP framing | Real PLC responses parse correctly | Test server returns synthetic responses |
| Keepalive | Dead connection detected within ~11s | Cannot simulate network failure in unit tests |
| Auto-reconnect | Connection recovers after PLC reboot | MockModbusClient.shouldFailConnect is artificial |
| Register reads | FC01/FC02/FC03/FC04 return correct values | Mock onSend returns synthetic data |
| Register writes | FC05/FC06/FC15/FC16 change PLC state | Mock accepts all writes |
| Poll timing | Values update at configured interval | Timer.periodic works in tests but real latency varies |
| Multi-protocol | OPC UA keys unaffected by Modbus | StateMan tests use mock DeviceClients |
| Config persistence | Config survives app restart | Widget tests override prefs provider |
| UI status display | Green/red/orange status chips update live | Tests only verify grey "Not active" |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Modbus test slave | Custom PLC simulator script | Real PLC at 10.50.10.10 | Phase 13 is specifically about real hardware validation |
| Automated E2E test framework | Flutter integration_test driver | Manual checklist execution | Manual testing catches visual/UX issues automation misses; real hardware is not CI-available |
| Log analysis tool | Custom log parser | `docker logs flutter 2>&1 \| grep -i modbus` | Simple grep on container logs is sufficient |

## Common Pitfalls

### Pitfall 1: Testing Without Known-Good Register Values
**What goes wrong:** Tester reads registers but has no reference to verify correctness. "Got value 42" -- is that right?
**Why it happens:** PLC register maps are device-specific. Without a register map document or independent tool to cross-verify, results are uninterpretable.
**How to avoid:** Before testing, identify at least 2-3 registers with known, verifiable values (e.g., a status register that is always 0 when stopped, a counter that increments, a temperature that can be cross-checked with a display). Alternatively, use a third-party Modbus tool (e.g., `modpoll` CLI, QModMaster GUI, or Python `pymodbus` REPL) to read the same registers independently.
**Warning signs:** "I see values but I don't know if they're correct."

### Pitfall 2: Config Not Persisting Across Restart
**What goes wrong:** Modbus server config is added in UI, but after Docker container restart the config is gone.
**Why it happens:** SharedPreferences in Docker requires the `local-share` volume mount (`./local-share:/home/centroid/.local/share/`). If this mount is missing or permissions are wrong, preferences are lost on restart.
**How to avoid:** Verify the volume mount exists in docker-compose.yml (it does -- line 58). After configuring, restart container and verify config survives.
**Warning signs:** Config present before restart, gone after.

### Pitfall 3: Firewall or Network Isolation Blocking Port 502
**What goes wrong:** Connection status stays "Connecting..." forever, never reaches "Connected."
**Why it happens:** Modbus TCP uses port 502 (privileged port). Firewalls, Docker network mode, or VLAN isolation may block it.
**How to avoid:** Before testing the Flutter app, verify raw TCP connectivity: `nc -zv 10.50.10.10 502` from inside the Docker container (`docker exec -it flutter bash`), or from the host machine.
**Warning signs:** Status chip stuck on orange "Connecting..." with exponential backoff logs in `docker logs flutter`.

### Pitfall 4: Wrong Unit ID
**What goes wrong:** Connection succeeds (TCP level) but all reads return errors or wrong data.
**Why it happens:** Modbus unit ID defaults to 1, but the PLC may be configured with a different unit ID (common with multi-drop setups or gateways).
**How to avoid:** Verify the PLC's unit ID before testing. Common values: 1 (most PLCs), 0 or 255 (broadcast/any), or a configured value for gateway setups.
**Warning signs:** Connected status shows green, but all register reads return null/error.

### Pitfall 5: Data Type Mismatch for Multi-Register Values
**What goes wrong:** Reading a 32-bit float shows garbage value (e.g., 1.14e+24 instead of 25.5).
**Why it happens:** Byte order (endianness) varies between PLC manufacturers. The Modbus spec defines big-endian for 16-bit registers, but 32-bit and 64-bit multi-register types have no standard byte order. Some PLCs use AB CD (big-endian), others use CD AB (word-swapped), BA DC, or DC BA.
**How to avoid:** Start testing with uint16 single-register reads (unambiguous). Only after verifying those, move to 32-bit types. If float32 reads produce garbage, it's likely a byte order issue -- this is explicitly deferred to v2 (ADV-01) but should be documented as a known limitation.
**Warning signs:** uint16 reads correct, but float32/int32 reads produce nonsensical values.

### Pitfall 6: OPC UA Disruption During Modbus Config Changes
**What goes wrong:** Adding Modbus config triggers `ref.invalidate(stateManProvider)`, which restarts ALL protocol connections including OPC UA.
**Why it happens:** StateMan re-creation is a full restart of the connection provider. This is by design (same behavior when editing OPC UA config) but could cause brief data gaps.
**How to avoid:** This is expected behavior, not a bug. Document that saving Modbus config causes a brief reconnection cycle for all protocols. Verify that OPC UA reconnects successfully after the invalidation.
**Warning signs:** OPC UA values freeze briefly after saving Modbus config, then resume. This is normal.

## Code Examples

No new code is produced in this phase. The relevant code paths to observe in logs:

### Expected Log Output on Successful Modbus Connection
```
Starting DataAcquisition isolate "modbus" (opcua: 0, m2400: 0, modbus: 1)
[ModbusClientWrapper] Connecting to 10.50.10.10:502 (unitId: 1)
[ModbusClientWrapper] Connected to 10.50.10.10:502
```

### Expected Log Output on Connection Failure
```
[ModbusClientWrapper] Connecting to 10.50.10.10:502 (unitId: 1)
[ModbusClientWrapper] Connection failed, retrying in 500ms
[ModbusClientWrapper] Connection failed, retrying in 1000ms
[ModbusClientWrapper] Connection failed, retrying in 2000ms
```

### Verifying Config JSON Structure
```json
{
  "opcua": [...existing...],
  "jbtm": [...existing...],
  "modbus": [
    {
      "host": "10.50.10.10",
      "port": 502,
      "unit_id": 1,
      "server_alias": "plc1",
      "poll_groups": [
        {"name": "default", "interval_ms": 1000}
      ]
    }
  ]
}
```

### Verifying Key Mapping JSON Structure
```json
{
  "nodes": {
    "TestKey": {
      "opcua_node": null,
      "m2400_node": null,
      "modbus_node": {
        "server_alias": "plc1",
        "register_type": "holdingRegister",
        "address": 0,
        "data_type": "uint16",
        "poll_group": "default"
      },
      "collect": null
    }
  }
}
```

## Test Checklist Structure

The planner should organize the phase into these test areas:

### Area 1: Prerequisites and Network Verification
- Verify network connectivity to PLC (TCP port 502 reachable)
- Identify test registers with known/verifiable values
- Have independent Modbus tool available for cross-verification
- Ensure Docker container is running with correct volume mounts

### Area 2: Server Configuration
- Add Modbus server via UI (host, port, unit ID, alias)
- Configure poll group(s)
- Save config
- Observe connection status chip transitions (Connecting -> Connected)
- Verify config persists across container restart

### Area 3: Key Configuration and Reading
- Add a test key with Modbus protocol via key repository UI
- Configure register type, address, data type
- Observe live value updates on the main HMI page
- Cross-verify values with independent Modbus tool
- Test each register type: coil (FC01), discrete input (FC02), holding register (FC03), input register (FC04)

### Area 4: Writing
- Write to a coil (FC05) via StateMan.write() or UI interaction
- Write to a holding register (FC06)
- Verify PLC-side change (cross-check with independent tool or physical observation)
- Attempt write to input register -- verify clear error (not crash)

### Area 5: Resilience
- Disconnect PLC (power cycle or cable pull)
- Observe status transition to Disconnected
- Reconnect PLC
- Verify auto-reconnect and value resume
- Verify reconnect time is reasonable (not 2+ hours)

### Area 6: Coexistence
- While Modbus is active, verify OPC UA keys still update normally
- Add/remove Modbus keys while OPC UA is running
- Verify no cross-protocol interference

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| modbus-test branch (3300 lines, broke OPC UA) | DeviceClient pattern (clean adapter) | Phase 7, 2026-03-06 | Modbus coexists with OPC UA without interference |
| Single _currentResponse in modbus_client_tcp | Transaction ID map for concurrent requests | Phase 1, 2026-03-06 | Multiple in-flight requests supported |
| No keepalive on Modbus TCP | SO_KEEPALIVE (5s/2s/3) | Phase 1, 2026-03-06 | Dead connections detected in ~11s |

## Open Questions

1. **Which specific registers are available on the PLC at 10.50.10.10?**
   - What we know: The PLC exists and has OPC UA (namespace 4, GVL_BatchLines). Modbus capability is assumed but unverified.
   - What's unclear: Does this PLC expose Modbus TCP on port 502? What registers are available? What unit ID?
   - Recommendation: User must verify PLC has Modbus TCP enabled before testing. If not, a separate Modbus device or simulator (e.g., `diagslave` on another machine) is needed.

2. **Is the production PLC safe to write to during testing?**
   - What we know: The PLC controls batch lines with motors and speed batchers.
   - What's unclear: Are there safe registers to write for testing without affecting production operation?
   - Recommendation: Identify safe test registers (e.g., spare/unused holding registers) or test during planned downtime. Never write to motor control registers during production.

3. **How will the tester deploy the current branch to the remote device?**
   - What we know: Production runs `ghcr.io/centroid-is/centroid-hmi:latest` with watchtower auto-update. Current Modbus code is on `feat/modbus-tcp-integration` branch.
   - What's unclear: Is there a CI/CD pipeline to build and push this branch as a Docker image? Or will the tester build locally and scp/load?
   - Recommendation: The planner should include a deployment step. Options: (a) merge to main and let watchtower pull, (b) build image locally with `docker build` and push to ghcr, (c) build Flutter elinux binary and copy to device.

4. **Byte order for multi-register types (32-bit, 64-bit)?**
   - What we know: ADV-01 (byte order configuration) is deferred to v2. Current implementation uses default library byte order (big-endian).
   - What's unclear: Whether the target PLC uses standard big-endian for 32-bit types.
   - Recommendation: Test with uint16 first (always unambiguous). Document any byte order issues as known limitations for v2.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual execution (human tester with checklist) |
| Config file | None -- manual test plan document |
| Quick run command | N/A (manual) |
| Full suite command | N/A (manual) |

### Phase Requirements -> Test Map

Phase 13 has no formal requirement IDs assigned. It cross-validates requirements from all previous phases against real hardware:

| Source Req | Behavior | Test Type | How Verified |
|-----------|----------|-----------|-------------|
| CONN-01 | Connect to Modbus TCP device | manual | Status chip shows "Connected" |
| CONN-02 | Auto-reconnect with backoff | manual | Disconnect/reconnect PLC, observe recovery |
| CONN-03 | Connection status streams to UI | manual | Status chip color changes in real-time |
| READ-01 | Read coils (FC01) | manual | Cross-verify with independent tool |
| READ-02 | Read discrete inputs (FC02) | manual | Cross-verify with independent tool |
| READ-03 | Read holding registers (FC03) | manual | Cross-verify with independent tool |
| READ-04 | Read input registers (FC04) | manual | Cross-verify with independent tool |
| WRIT-01 | Write single coil (FC05) | manual | Verify PLC-side change |
| WRIT-02 | Write single register (FC06) | manual | Verify PLC-side change |
| INTG-05 | Modbus keys coexist with OPC UA | manual | OPC UA values still update while Modbus active |
| UISV-01 | Add Modbus server via UI | manual | Server card appears, connection initiates |
| UISV-04 | Live connection status per server | manual | Green/red/orange chip updates |
| UIKY-01 | Switch key between protocols | manual | Protocol switch persists, value streams |

### Sampling Rate
- **Per test step:** Human verifies pass/fail against criteria
- **Per area:** Complete all steps in area before moving to next
- **Phase gate:** All critical test steps pass (warnings acceptable)

### Wave 0 Gaps
None -- no test infrastructure to create. This phase uses manual verification against the running application.

## Sources

### Primary (HIGH confidence)
- Project codebase analysis: `packages/tfc_dart/lib/core/modbus_client_wrapper.dart`, `modbus_device_client.dart`, `state_man.dart`
- Project memory (MEMORY.md): Deployment details (10.50.10.11, Docker container flutter, PLC at 10.50.10.10)
- Phase verification reports: `10-VERIFICATION.md` (identifies human-verification items for real device testing)
- Phase summaries: All 15 SUMMARY.md files across phases 1-11

### Secondary (MEDIUM confidence)
- Docker-compose.yml: Container configuration, volume mounts, environment variables
- keymappings.json: Current production config (6000 lines, all OPC UA, zero Modbus entries)
- config.json: Current page layout configuration (no Modbus data)

## Metadata

**Confidence breakdown:**
- Test structure: HIGH - comprehensive understanding of what needs manual verification from all phase verification reports
- Deployment: HIGH - docker-compose.yml and MEMORY.md provide complete deployment details
- PLC availability: MEDIUM - PLC exists (referenced in Phase 10 verification) but Modbus TCP capability unverified
- Register map: LOW - no register documentation found; user must provide specific addresses

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- no external dependencies to go stale)
