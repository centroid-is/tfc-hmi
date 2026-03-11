# Phase 18 Research: Modbus Enhancements

## Feature 1: Register Address Base (0 vs 1)

### Background
Modbus PDU uses 0-based addressing on the wire. The "1-based" convention comes from Modicon's data model (40001 = first holding register). About half the industry uses each convention.

### Vendor Conventions
| Convention | Vendors |
|---|---|
| **0-based** (default) | Siemens S7, ABB AC500, Beckhoff TwinCAT, Wago 750, Omron CJ/NJ, Allen-Bradley, Schneider Quantum |
| **1-based** (subtract 1) | Schneider M340/M580/Premium, Mitsubishi FX/iQ-R, Delta DVP/AS, Unitronics Vision |

### SCADA Tool Naming
Most tools call this "Zero Based Addressing" (KEPServerEX, Ignition). Some say "Address Base" or "PLC Addresses (Base 1)".

### Implementation
- Add `addressBase` field (int, 0 or 1, default 0) to `ModbusConfig`
- Subtract `addressBase` from address when constructing ModbusElement for wire transmission
- UI: Dropdown on server config card ("0 (Protocol)" / "1 (Modicon)") with info tooltip
- JSON key: `address_base`

### Files to Change
- `packages/tfc_dart/lib/core/state_man.dart` — ModbusConfig model
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` — apply offset in element creation
- `lib/pages/server_config.dart` — dropdown UI
- `packages/tfc_dart/lib/core/state_man.g.dart` — regenerate JSON

## Feature 2: Bit Masking (Visual Grid, Read+Write)

### Background
OPC UA has no native bit-level access. Modbus reads whole registers. Both need client-side bit extraction. Common in SCADA (Kepware `.3` notation, Ignition `getBit()`, WebHMI checkbox grid).

### User Choice
- **UI**: Visual bit grid (16 or 32 clickable bits depending on data type)
- **Write**: Full read+write support (read-modify-write pattern)
- **Scope**: Both Modbus AND OPC UA (protocol-agnostic)

### Data Model
Add to `KeyMappingEntry` (protocol-agnostic, not per-protocol node config):
```dart
@JsonKey(name: 'bit_mask')
int? bitMask;        // e.g., 0x00FF for lower 8 bits
@JsonKey(name: 'bit_shift')
int? bitShift;       // right-shift after masking (0 = no shift)
```

### Where to Apply Masking

**Read path** — apply in `ModbusDeviceClientAdapter._toDynamicValue()` and equivalent OPC UA path:
```
raw register value → mask & shift → DynamicValue → stream → UI
```

**Write path** — read-modify-write:
```
read current full value → clear masked bits → set new bits → write full value
```

### Result Types
- Single bit (mask is power of 2) → Boolean
- Multi-bit → unsigned integer

### UI (key_repository.dart)
- Optional expandable section "Bit Mask" below data type
- Visual grid of 16 bits (or 32 for 32-bit types)
- Click to toggle bits on/off
- Show hex mask value and resulting bit range
- Shared widget usable by both Modbus and OPC UA config sections

### Files to Change
- `packages/tfc_dart/lib/core/state_man.dart` — KeyMappingEntry fields
- `packages/tfc_dart/lib/core/modbus_device_client.dart` — apply mask on read
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` — read-modify-write on write
- `packages/tfc_dart/lib/core/state_man.dart` — apply mask on OPC UA read path
- `lib/pages/key_repository.dart` — bit grid widget
- New shared widget: `lib/widgets/bit_mask_grid.dart`

## Feature 3: Multi-Protocol KeyMappingEntryDialog

### Current State
`lib/page_creator/assets/common.dart` lines 813-863: `KeyMappingEntryDialog` only shows OPC UA servers:
```dart
final serverAliases = stateMan.config.opcua
    .map((config) => config.serverAlias ?? "__default")
    .toList();
```

### Required Change
Show servers from ALL protocols with protocol indicator:
```dart
// Gather from all protocols
opcua servers → labeled "(OPC UA)"
modbus servers → labeled "(Modbus)"
m2400 servers → labeled "(M2400)"
```

When user selects a server, determine protocol and show appropriate config fields:
- OPC UA: namespace + identifier (existing)
- Modbus: register type, address, data type, poll group
- M2400: record type, field

### Reference Implementation
`key_repository.dart` already has full multi-protocol support with device type chips (lines 920-972). Pattern can be reused.

### Files to Change
- `lib/page_creator/assets/common.dart` — KeyMappingEntryDialog
