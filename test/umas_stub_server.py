#!/usr/bin/env python3
"""Stub UMAS/Modbus TCP server for integration testing.

Responds to FC90 (0x5A) UMAS requests over Modbus TCP MBAP framing.
Supports: ReadPlcId (0x02), Init (0x01), ReadDataDictionary (0x26),
PlcStatus (0x04), ProjectInfo (0x03), Echo (0x0A),
KeepAlive (0x12), TakePlcReservation (0x10), ReleasePlcReservation (0x11),
ReadVariable (0x22), WriteVariable (0x23),
ReadCoilsRegisters (0x24), WriteCoilsRegisters (0x25), MonitorPlc (0x50),
ReadCardInfo (0x06), ReadMemoryBlock (0x20), ReadEthMasterData (0x39),
CheckPlc (0x58), ReadIoObject (0x70), GetStatusModule (0x73)
with record types 0xDD02/0xDD03 in corrected PLC4X mspec format.

Uses 3-byte response header matching real PLC: FC(0x5A) + pairingKey + status.

Usage: python3 test/umas_stub_server.py [--port PORT]
       python3 test/umas_stub_server.py [PORT]  (legacy positional)

When --port 0 (the default), the OS assigns a free port and the actual
port is printed as "PORT=<N>" on stdout for the test harness to parse.
"""

import argparse
import struct
import socketserver
import sys
import signal

# --- Sample data: realistic Schneider PLC variable tree ---

VARIABLES = [
    # name, blockNo, offset, dataTypeId
    # dataTypeId values come from PLC4X UmasDataType enum (the IDs the
    # Schneider PLC actually uses on the wire). 1=BOOL, 4=INT, 5=UINT,
    # 6=DINT, 7=UDINT, 8=REAL, 10=TIME, 21=BYTE, 22=WORD, 23=DWORD.
    ("Application.GVL.temperature", 1, 0, 8),    # REAL
    ("Application.GVL.pressure", 1, 4, 8),        # REAL
    ("Application.GVL.motor_running", 1, 8, 1),   # BOOL
    ("Application.GVL.setpoint", 1, 9, 4),        # INT
    ("Application.GVL.error_code", 1, 11, 5),     # UINT
    ("Application.Motor.speed", 2, 0, 8),          # REAL
    ("Application.Motor.torque", 2, 4, 8),         # REAL
    ("Application.Motor.enabled", 2, 8, 1),        # BOOL
    ("Application.Counters.production", 3, 0, 7),  # UDINT
    ("Application.Counters.runtime_ms", 3, 4, 10), # TIME
    # Array variable referencing the custom array type below (id=120).
    # Type 120 is "ARRAY[1..4] OF UINT" (4 elements * 2 bytes = 8 bytes).
    ("Application.GVL.colors", 1, 16, 120),
]

DATA_TYPES = [
    # typeId, name, byteSize, classIdentifier, dataType
    # `dataType` is the PLC-assigned numeric type id used by DD02 records to
    # reference this entry. Real PLCs allocate custom type ids starting at
    # 27+ to avoid collisions with the built-in scalar ids (1-14).
    (100, "MY_STRUCT", 16, 2, 27),
    (101, "ALARM_TYPE", 8, 0, 28),
    # Array type: ARRAY[1..4] OF UINT.
    # classIdentifier=4 (array). The DD03 record's `dataType` byte for an
    # array type is the array's own custom id (matches real-PLC observation
    # — the element type is recovered via a follow-up DD02 query that
    # returns a UmasArrayTypeDefinition, not from this byte).
    (120, "ARRAY[1..4] OF UINT", 8, 4, 120),
]

# Array-type definitions returned by DD02 queries keyed on a custom array
# type id. Each entry describes the array's element type and dimension
# bounds per PLC4X UmasArrayTypeDefinition: classId(1) + elementTypeId(2 LE)
# + numberOfDimensions(1) + dimensions[N] (8 bytes each: startIndex(4 LE)
# + upperBound(4 LE)).
#
#   typeId -> (elementTypeId, [(startIndex, upperBound), ...])
ARRAY_TYPES = {
    120: (5, [(1, 4)]),  # ARRAY[1..4] OF UINT
}

# PLC identification values
HARDWARE_ID = 0x12345678
MEMORY_BLOCK_INDEX = 0
NUM_MEMORY_BANKS = 1

# Deterministic CRC values for PlcStatus (6 blocks, matching real PLC observation)
CRC_VALUES = [
    0xAABBCCDD,
    0x11223344,
    0x55667788,
    0x99AABBCC,
    0xDDEEFF00,
    0x12345678,
]


# Data type ID to byte size mapping — matches PLC4X UmasDataType enum.
DATA_TYPE_SIZES = {
    1: 1,    # BOOL
    4: 2,    # INT
    5: 2,    # UINT
    6: 4,    # DINT
    7: 4,    # UDINT
    8: 4,    # REAL
    10: 4,   # TIME
    21: 1,   # BYTE
    22: 2,   # WORD
    23: 4,   # DWORD
    25: 1,   # EBOOL
}


def _init_variable_store():
    """Create initial variable store with realistic values.

    Key = (block, offset), value = raw bytes packed LE.
    """
    store = {}
    initial_values = {
        (1, 0): struct.pack("<f", 22.5),        # temperature REAL
        (1, 4): struct.pack("<f", 1.013),        # pressure REAL
        (1, 8): struct.pack("B", 1),             # motor_running BOOL
        (1, 9): struct.pack("<h", 100),           # setpoint INT
        (1, 11): struct.pack("<H", 0),            # error_code UINT
        # colors: ARRAY[1..4] OF UINT — 4 LE uint16 values starting at offset 16.
        (1, 16): struct.pack("<H", 100),           # colors[1]
        (1, 18): struct.pack("<H", 200),           # colors[2]
        (1, 20): struct.pack("<H", 300),           # colors[3]
        (1, 22): struct.pack("<H", 400),           # colors[4]
        (2, 0): struct.pack("<f", 1450.0),        # speed REAL
        (2, 4): struct.pack("<f", 85.5),          # torque REAL
        (2, 8): struct.pack("B", 1),              # enabled BOOL
        (3, 0): struct.pack("<I", 12345),         # production UDINT
        (3, 4): struct.pack("<I", 3600000),       # runtime_ms TIME
    }
    store.update(initial_values)
    return store


# Module-level initial store (reset per connection for test isolation)
VARIABLE_STORE = _init_variable_store()

# Register store for direct register access (0x24/0x25).
# Key = (area_code, start_address), value = raw bytes.
# Initialized empty; populated by 0x25 writes.
REGISTER_STORE = {}


def build_plc_ident_payload():
    """Build 0x02 (Read PLC Identification) response payload.

    Format: range(2 LE) + hardwareId(4 LE) + numberOfMemoryBanks(1) +
            PlcMemoryBlockIdent[]: address(2 LE) + blockType(1) + unknown(2 LE) + memoryLength(4 LE)
    """
    buf = bytearray()
    buf += struct.pack("<H", 0x0001)               # range
    buf += struct.pack("<I", HARDWARE_ID)           # hardwareId / ident
    buf += struct.pack("B", NUM_MEMORY_BANKS)       # numberOfMemoryBanks
    # Memory block entries
    for i in range(NUM_MEMORY_BANKS):
        buf += struct.pack("<H", MEMORY_BLOCK_INDEX + i)  # address (used as index)
        buf += struct.pack("B", 0x01)                     # blockType
        buf += struct.pack("<H", 0x0000)                  # unknown
        buf += struct.pack("<I", 0x00010000)              # memoryLength
    return bytes(buf)


def build_variable_names_payload(variables, next_address=0x0000):
    """Build 0xDD02 top-level response in PLC4X mspec format.

    Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
    Top-level records (10-byte header):
      dataType(2 LE) + block(2 LE) + offset(4 LE) + flags(1) + unknown4(1)
      + null-terminated UTF-8 name
    """
    buf = bytearray()
    buf += struct.pack("B", 0x00)
    buf += struct.pack("<H", next_address)
    buf += struct.pack("<H", 0x0000)  # unknown1
    buf += struct.pack("<H", len(variables))

    for name, block_no, offset, data_type_id in variables:
        name_bytes = name.encode("utf-8") + b"\x00"
        buf += struct.pack("<H", data_type_id)
        buf += struct.pack("<H", block_no)
        buf += struct.pack("<I", offset)  # uint32
        buf += struct.pack("B", 0xFF)     # flags (non-zero -> top-level format)
        buf += struct.pack("B", 0x01)     # unknown4
        buf += name_bytes
    return bytes(buf)


def build_data_types_payload(data_types, next_address=0x0000):
    """Build 0xDD03 response in PLC4X mspec format.

    Header: range(1) + unknown1(4) + noOfRecords(2 LE)  -- 7 bytes
    Per record (UmasDatatypeReference):
      dataSize(2 LE) + unknown1(2 LE) + classIdentifier(1) + dataType(1)
      + reserved 0x00(1) + null-terminated UTF-8 name

    DD03 does not paginate; legacy `next_address` is preserved in the low
    16 bits of unknown1 so existing tests that pass it still build
    parseable payloads.
    """
    buf = bytearray()
    buf += struct.pack("B", 0x00)
    buf += struct.pack("<H", next_address)
    buf += struct.pack("<H", 0x0000)
    buf += struct.pack("<H", len(data_types))

    for type_id, name, byte_size, class_id, data_type in data_types:
        name_bytes = name.encode("utf-8") + b"\x00"
        buf += struct.pack("<H", byte_size)
        buf += struct.pack("<H", 0x0000)
        buf += struct.pack("B", class_id)
        buf += struct.pack("B", data_type)
        buf += struct.pack("B", 0x00)  # reserved
        buf += name_bytes
    return bytes(buf)


def build_plc_status_payload():
    """Build PlcStatus (0x04) response payload.

    Format: statusByte(1) + notUsed2(2) + numberOfBlocks(1) + blocks[6 x uint32 LE]
    Total: 1 + 2 + 1 + 24 = 28 bytes
    """
    buf = bytearray()
    buf += struct.pack("B", 0x03)                      # statusByte (running)
    buf += struct.pack("<H", 0x0000)                    # notUsed2
    buf += struct.pack("B", len(CRC_VALUES))           # numberOfBlocks
    for crc in CRC_VALUES:
        buf += struct.pack("<I", crc)                  # CRC block (uint32 LE)
    return bytes(buf)


def build_project_info_payload():
    """Build ProjectInfo (0x03) response payload.

    Returns opaque bytes containing project name, padded to ~50 bytes
    to match observed real PLC response size.
    """
    buf = bytearray()
    # Some header bytes (opaque, mimicking real PLC)
    buf += b"\x00" * 10
    # Project name as ASCII
    project_name = b"StubProject"
    buf += project_name
    # Pad to ~50 bytes total
    remaining = 50 - len(buf)
    if remaining > 0:
        buf += b"\x00" * remaining
    return bytes(buf)


def build_success_response(payload, pairing_key=0x00):
    """Build FC90 success PDU: [0x5A, pairingKey, 0xFE, ...payload].

    Real Schneider PLC 3-byte header: FC + pairingKey + status (no sub-function echo).
    """
    pdu = bytearray([0x5A, pairing_key, 0xFE])
    pdu += payload
    return bytes(pdu)


def build_error_response(error_code, pairing_key=0x00):
    """Build FC90 error PDU: [0x5A, pairingKey, 0xFD, errorCode].

    Real Schneider PLC 3-byte header: FC + pairingKey + status (no sub-function echo).
    """
    return bytes([0x5A, pairing_key, 0xFD, error_code])


def wrap_mbap(transaction_id, unit_id, pdu):
    """Wrap PDU in MBAP header."""
    length = 1 + len(pdu)  # unit_id + pdu
    header = struct.pack(">HHH", transaction_id, 0, length)
    return header + bytes([unit_id]) + pdu


class UmasHandler(socketserver.BaseRequestHandler):
    def handle(self):
        global VARIABLE_STORE
        VARIABLE_STORE = _init_variable_store()  # Reset per connection for test isolation
        global REGISTER_STORE
        REGISTER_STORE = {}  # Reset register store per connection
        print(f"[STUB] Connection from {self.client_address}")
        buf = bytearray()
        self.pairing_key = 0x00
        self.has_session = False
        self.has_reservation = False
        self._m580_mode = getattr(self.server, '_m580_mode', False)

        # Pagination state per connection
        self._dd02_offset = 0
        self._dd03_offset = 0

        # MonitorPlc (0x50) registration table: variableIndex -> (block, offset)
        self._monitor_registrations = {}

        while True:
            try:
                data = self.request.recv(4096)
            except (ConnectionResetError, BrokenPipeError):
                break
            if not data:
                break

            buf += data

            # Process all complete MBAP frames in buffer
            while len(buf) >= 7:
                # Parse MBAP header
                tx_id, proto_id, length = struct.unpack(">HHH", buf[:6])
                unit_id = buf[6]
                total_len = 6 + length  # header + length field contents

                if len(buf) < total_len:
                    break  # wait for more data

                frame = buf[:total_len]
                buf = buf[total_len:]

                pdu = frame[7:]  # everything after unit_id
                response_pdu = self.handle_pdu(pdu)

                if response_pdu:
                    response = wrap_mbap(tx_id, unit_id, response_pdu)
                    try:
                        self.request.sendall(response)
                    except (ConnectionResetError, BrokenPipeError):
                        return

        print(f"[STUB] Disconnected {self.client_address}")

    def handle_read_variable(self, payload):
        """Handle ReadVariable (0x22) request.

        Request: crc(4 LE) + variableCount(1) + [variableRef]*
        VariableRef: isArray:4bits+dataSizeIndex:4bits(1) + block(2 LE) + 0x01(1) + baseOffset(2 LE) + offset(1) [+ arrayLength(2 LE) if isArray]
        Response: concatenated raw bytes of requested variable values.

        In M580 mode (--m580 flag), returns 0xA1 error to simulate M580 PLC
        behavior where ReadVariable is not supported.
        """
        if self._m580_mode:
            print("[STUB] M580 mode: rejecting ReadVariable (0x22) with 0xA1 error")
            return build_error_response(0xA1, self.pairing_key)

        global VARIABLE_STORE
        if len(payload) < 5:
            return build_error_response(0x02, self.pairing_key)

        # crc = payload[0:4]  -- validated in real PLC, ignored in stub
        count = payload[4]
        pos = 5
        result = bytearray()

        for _ in range(count):
            if pos >= len(payload):
                return build_error_response(0x02, self.pairing_key)

            byte0 = payload[pos]
            is_array = (byte0 >> 4) & 0x0F
            data_size_index = byte0 & 0x0F
            data_size = 1 << (data_size_index - 1) if data_size_index > 0 else 1

            block = struct.unpack("<H", payload[pos+1:pos+3])[0]
            # skip 0x01 byte at pos+3
            base_offset = struct.unpack("<H", payload[pos+4:pos+6])[0]
            # Schneider paged byte addressing: baseOffset is a 256-byte page
            # index, offset is the low byte. address = baseOffset*256 + offset.
            offset_byte = payload[pos+6]
            address = (base_offset * 256) + offset_byte
            ref_size = 7

            array_length = 1
            if is_array:
                array_length = struct.unpack("<H", payload[pos+7:pos+9])[0]
                ref_size += 2

            pos += ref_size

            key = (block, address)
            if key not in VARIABLE_STORE:
                print(f"[STUB] ReadVariable: variable not found at block={block} offset={base_offset}")
                return build_error_response(0x03, self.pairing_key)

            var_bytes = VARIABLE_STORE[key]
            # For arrays, repeat or slice; for scalars, return stored bytes
            total_bytes = data_size * array_length
            # Pad or truncate to requested size
            if len(var_bytes) >= total_bytes:
                result += var_bytes[:total_bytes]
            else:
                result += var_bytes + b"\x00" * (total_bytes - len(var_bytes))

        return build_success_response(bytes(result), self.pairing_key)

    def handle_write_variable(self, payload):
        """Handle WriteVariable (0x23) request.

        Request: crc(4 LE) + variableCount(1) + [writeRef]*
        WriteRef: isArray:4bits+dataSizeIndex:4bits(1) + block(2 LE) + baseOffset(2 LE) + offset(2 LE) [+ arrayLength(2 LE) if isArray] + data[dataSize]
        Response: success (empty payload).
        """
        global VARIABLE_STORE
        if len(payload) < 5:
            return build_error_response(0x02, self.pairing_key)

        # crc = payload[0:4]  -- ignored in stub
        count = payload[4]
        pos = 5

        for _ in range(count):
            if pos >= len(payload):
                return build_error_response(0x02, self.pairing_key)

            byte0 = payload[pos]
            is_array = (byte0 >> 4) & 0x0F
            data_size_index = byte0 & 0x0F
            data_size = 1 << (data_size_index - 1) if data_size_index > 0 else 1

            block = struct.unpack("<H", payload[pos+1:pos+3])[0]
            base_offset = struct.unpack("<H", payload[pos+3:pos+5])[0]
            # Schneider paged addressing for write: baseOffset is the
            # 256-byte page index, the 2-byte offset field is the in-page
            # byte address.
            offset_word = struct.unpack("<H", payload[pos+5:pos+7])[0]
            address = (base_offset * 256) + offset_word
            header_size = 7

            array_length = 1
            if is_array:
                array_length = struct.unpack("<H", payload[pos+7:pos+9])[0]
                header_size += 2

            total_data_size = data_size * array_length
            data_start = pos + header_size
            data_end = data_start + total_data_size

            if data_end > len(payload):
                return build_error_response(0x02, self.pairing_key)

            new_data = payload[data_start:data_end]
            key = (block, address)
            VARIABLE_STORE[key] = bytes(new_data)
            print(f"[STUB] WriteVariable: block={block} offset={base_offset} size={total_data_size} bytes={new_data.hex()}")

            pos = data_end

        return build_success_response(b"", self.pairing_key)

    def handle_monitor_plc(self, payload):
        """Handle MonitorPlc (0x50) request.

        Request: subCommand(1) + unknown(1) + numberOfSubOps(1) + [subOperation]*
        Per PLC4X mspec, every sub-operation in the array begins with its own
        operationType discriminator byte (which equals the outer subCommand).
        Sub-operations:
          Register (0x05): opType(0x05) + variableIndex(1) + block(2 LE) + offset(2 LE) + action(1)  -- 7 bytes
          ReadAll (0x07): no per-sub-op payload
          RegisterAndRead (0x09): opType(0x09) + variableIndex(1) + block(2 LE) + offset(2 LE)  -- 6 bytes
          Reset (0x0B): no per-sub-op payload
        """
        global VARIABLE_STORE
        if len(payload) < 1:
            return build_error_response(0x02, self.pairing_key)

        sub_command = payload[0]

        if sub_command == 0x05:
            # Register / Deregister -- each sub-op is 7 bytes:
            #   opType(0x05) + variableIndex(1) + block(2 LE) + offset(2 LE) + action(1)
            if len(payload) < 3:
                return build_error_response(0x02, self.pairing_key)
            # unknown = payload[1]
            num_sub_ops = payload[2]
            pos = 3
            for _ in range(num_sub_ops):
                if pos + 7 > len(payload):
                    return build_error_response(0x02, self.pairing_key)
                if payload[pos] != 0x05:
                    return build_error_response(0x02, self.pairing_key)
                var_index = payload[pos+1]
                block = struct.unpack("<H", payload[pos+2:pos+4])[0]
                offset = struct.unpack("<H", payload[pos+4:pos+6])[0]
                action = payload[pos+6]
                pos += 7
                if action == 0x02:
                    self._monitor_registrations[var_index] = (block, offset)
                    print(f"[STUB] MonitorPlc: registered idx={var_index} block={block} offset={offset}")
                elif action == 0x01:
                    self._monitor_registrations.pop(var_index, None)
                    print(f"[STUB] MonitorPlc: deregistered idx={var_index}")
            return build_success_response(b"", self.pairing_key)

        elif sub_command == 0x07:
            # ReadAll: read all registered variables, concatenate raw bytes
            result = bytearray()
            for var_index in sorted(self._monitor_registrations.keys()):
                block, offset = self._monitor_registrations[var_index]
                key = (block, offset)
                if key in VARIABLE_STORE:
                    result += VARIABLE_STORE[key]
                else:
                    print(f"[STUB] MonitorPlc ReadAll: no data for block={block} offset={offset}")
            return build_success_response(bytes(result), self.pairing_key)

        elif sub_command == 0x09:
            # RegisterAndRead: register + immediate read -- each sub-op is 6 bytes:
            #   opType(0x09) + variableIndex(1) + block(2 LE) + offset(2 LE)
            if len(payload) < 3:
                return build_error_response(0x02, self.pairing_key)
            # unknown = payload[1]
            num_sub_ops = payload[2]
            pos = 3
            result = bytearray()
            for _ in range(num_sub_ops):
                if pos + 6 > len(payload):
                    return build_error_response(0x02, self.pairing_key)
                if payload[pos] != 0x09:
                    return build_error_response(0x02, self.pairing_key)
                var_index = payload[pos+1]
                block = struct.unpack("<H", payload[pos+2:pos+4])[0]
                offset = struct.unpack("<H", payload[pos+4:pos+6])[0]
                pos += 6
                self._monitor_registrations[var_index] = (block, offset)
                key = (block, offset)
                if key in VARIABLE_STORE:
                    result += VARIABLE_STORE[key]
                print(f"[STUB] MonitorPlc: register+read idx={var_index} block={block} offset={offset}")
            return build_success_response(bytes(result), self.pairing_key)

        elif sub_command == 0x0B:
            # Reset: clear all registrations
            self._monitor_registrations.clear()
            print("[STUB] MonitorPlc: reset all registrations")
            return build_success_response(b"", self.pairing_key)

        else:
            print(f"[STUB] MonitorPlc: unknown subCommand {sub_command:#04x}")
            return build_error_response(0x04, self.pairing_key)

    def handle_read_coils_registers(self, payload):
        """Handle ReadCoilsRegisters (0x24) request.

        Request: memoryArea(1) + startAddress(2 LE) + quantity(2 LE)
        Response: raw data bytes (words: quantity*2, coils: ceil(quantity/8)).
        """
        global REGISTER_STORE
        if len(payload) < 5:
            return build_error_response(0x02, self.pairing_key)

        area = payload[0]
        start_addr = struct.unpack("<H", payload[1:3])[0]
        quantity = struct.unpack("<H", payload[3:5])[0]

        print(f"[STUB] ReadCoilsRegisters: area={area:#04x} addr={start_addr} qty={quantity}")

        # Determine response size based on area type
        if area in (0x00, 0x06):
            # Coils / system bits: bit-packed
            num_bytes = (quantity + 7) // 8
        else:
            # Words: quantity * 2 bytes
            num_bytes = quantity * 2

        # Check if data was previously written to this address
        key = (area, start_addr)
        if key in REGISTER_STORE:
            stored = REGISTER_STORE[key]
            if len(stored) >= num_bytes:
                result = stored[:num_bytes]
            else:
                result = stored + b"\x00" * (num_bytes - len(stored))
        else:
            # Return zero-initialized data
            result = b"\x00" * num_bytes

        return build_success_response(bytes(result), self.pairing_key)

    def handle_write_coils_registers(self, payload):
        """Handle WriteCoilsRegisters (0x25) request.

        Request: memoryArea(1) + startAddress(2 LE) + quantity(2 LE) + data[N]
        Response: success status only.
        """
        global REGISTER_STORE
        if len(payload) < 5:
            return build_error_response(0x02, self.pairing_key)

        area = payload[0]
        start_addr = struct.unpack("<H", payload[1:3])[0]
        quantity = struct.unpack("<H", payload[3:5])[0]

        # Determine expected data size
        if area in (0x00, 0x06):
            num_bytes = (quantity + 7) // 8
        else:
            num_bytes = quantity * 2

        data_start = 5
        data_end = data_start + num_bytes

        if data_end > len(payload):
            print(f"[STUB] WriteCoilsRegisters: payload too short, need {data_end} got {len(payload)}")
            return build_error_response(0x02, self.pairing_key)

        data = payload[data_start:data_end]
        key = (area, start_addr)
        REGISTER_STORE[key] = bytes(data)

        print(f"[STUB] WriteCoilsRegisters: area={area:#04x} addr={start_addr} qty={quantity} bytes={data.hex()}")

        return build_success_response(b"", self.pairing_key)

    def handle_pdu(self, pdu):
        if len(pdu) < 3:
            return build_error_response(0x01)

        fc = pdu[0]
        if fc != 0x5A:
            print(f"[STUB] Non-FC90 request (FC={fc:#x}), ignoring")
            return None

        pairing_key = pdu[1]
        sub_func = pdu[2]
        payload = pdu[3:]

        print(f"[STUB] FC90 subFunc={sub_func:#04x} pairingKey={pairing_key:#04x} payloadLen={len(payload)}")

        if sub_func == 0x02:
            # Read PLC Identification
            resp_payload = build_plc_ident_payload()
            return build_success_response(resp_payload, self.pairing_key)

        elif sub_func == 0x01:
            # Init: return max frame size = 1021 (0x03FD LE), store pairing key
            self.pairing_key = pairing_key
            self.has_session = True
            resp_payload = struct.pack("<H", 1021)
            return build_success_response(resp_payload, pairing_key)

        elif sub_func == 0x04:
            # PlcStatus: return status byte + 6 CRC blocks
            resp_payload = build_plc_status_payload()
            return build_success_response(resp_payload, self.pairing_key)

        elif sub_func == 0x03:
            # ProjectInfo: return opaque project data
            resp_payload = build_project_info_payload()
            return build_success_response(resp_payload, self.pairing_key)

        elif sub_func == 0x0A:
            # Echo: return the request payload unchanged
            return build_success_response(bytes(payload), self.pairing_key)

        elif sub_func == 0x12:
            # KeepAlive: success if session active, error if not
            if self.has_session:
                return build_success_response(b"", self.pairing_key)
            else:
                return build_error_response(0x05, self.pairing_key)

        elif sub_func == 0x10:
            # TakePlcReservation: set reservation flag
            self.has_reservation = True
            return build_success_response(b"", self.pairing_key)

        elif sub_func == 0x11:
            # ReleasePlcReservation: clear reservation flag
            self.has_reservation = False
            return build_success_response(b"", self.pairing_key)

        elif sub_func == 0x22:
            # ReadVariable
            return self.handle_read_variable(payload)

        elif sub_func == 0x23:
            # WriteVariable
            return self.handle_write_variable(payload)

        elif sub_func == 0x24:
            # ReadCoilsRegisters
            return self.handle_read_coils_registers(payload)

        elif sub_func == 0x25:
            # WriteCoilsRegisters
            return self.handle_write_coils_registers(payload)

        elif sub_func == 0x50:
            # MonitorPlc
            return self.handle_monitor_plc(payload)

        elif sub_func == 0x26:
            # ReadDataDictionary -- accept full 13-byte payload
            if len(payload) < 2:
                return build_error_response(0x02, self.pairing_key)

            record_type = struct.unpack("<H", payload[:2])[0]
            print(f"[STUB]   recordType={record_type:#06x} payloadLen={len(payload)}")

            if len(payload) >= 11:
                # DD03 = 11 bytes (no trailing blank), DD02 = 13 bytes (with blank)
                index = payload[2]
                hw_id = struct.unpack("<I", payload[3:7])[0]
                block_no = struct.unpack("<H", payload[7:9])[0]
                offset = struct.unpack("<H", payload[9:11])[0]
                blank_str = ""
                if len(payload) >= 13:
                    blank = struct.unpack("<H", payload[11:13])[0]
                    blank_str = f" blank={blank:#06x}"
                print(f"[STUB]   index={index} hwId={hw_id:#010x} blockNo={block_no:#06x} offset={offset:#06x}{blank_str}")

            if record_type == 0xDD02:
                # If the request keys on a custom array type, return that
                # type's UmasArrayTypeDefinition payload (per PLC4X mspec).
                # Otherwise fall through to the variable-name table.
                if block_no in ARRAY_TYPES:
                    element_type_id, dims = ARRAY_TYPES[block_no]
                    body = bytearray()
                    body += struct.pack("B", 0x04)              # classId
                    body += struct.pack("<H", element_type_id)  # elementTypeId
                    body += struct.pack("B", len(dims))         # numberOfDimensions
                    for start_idx, upper in dims:
                        body += struct.pack("<I", start_idx)    # startIndex
                        body += struct.pack("<I", upper)        # upperBound
                    return build_success_response(bytes(body), self.pairing_key)
                # Return all variables in single page
                data = build_variable_names_payload(VARIABLES, next_address=0x0000)
                return build_success_response(data, self.pairing_key)
            elif record_type == 0xDD03:
                # Return all data types in single page
                data = build_data_types_payload(DATA_TYPES, next_address=0x0000)
                return build_success_response(data, self.pairing_key)
            else:
                return build_error_response(0x03, self.pairing_key)

        elif sub_func == 0x06:
            # ReadCardInfo: return 16 bytes of simulated card info
            # Format: cardPresent(1) + reserved(3) + capacity(4 LE) + freeSpace(4 LE) + reserved(4)
            card_info = struct.pack("<BBBBIIII",
                0x01,       # card present
                0x00, 0x00, 0x00,  # reserved
                0x01000000, # capacity: ~16MB
                0x00800000, # free space: ~8MB
                0x00000000, # reserved
                0x00000000, # reserved
            )
            return build_success_response(card_info[:16], self.pairing_key)

        elif sub_func == 0x20:
            # ReadMemoryBlock: range(1) + blockNumber(2 LE) + offset(2 LE) + unknownObj(2 LE) + numberOfBytes(2 LE)
            if len(payload) < 9:
                return build_error_response(0x02, self.pairing_key)
            range_byte = payload[0]
            # block_number = struct.unpack("<H", payload[1:3])[0]
            # mem_offset = struct.unpack("<H", payload[3:5])[0]
            # unknown_obj = struct.unpack("<H", payload[5:7])[0]
            num_bytes = struct.unpack("<H", payload[7:9])[0]
            # Response: range(1) + numberOfBytes(2 LE) + data[numberOfBytes]
            resp = bytearray()
            resp += struct.pack("B", range_byte)
            resp += struct.pack("<H", num_bytes)
            resp += b"\x00" * num_bytes  # zero-filled data
            return build_success_response(bytes(resp), self.pairing_key)

        elif sub_func == 0x39:
            # ReadEthMasterData: return 32 bytes of simulated network topology
            eth_data = bytearray(32)
            eth_data[0] = 0x01   # number of modules
            eth_data[1] = 0x02   # module type (Ethernet)
            eth_data[4:8] = bytes([192, 168, 1, 1])  # simulated IP
            return build_success_response(bytes(eth_data), self.pairing_key)

        elif sub_func == 0x58:
            # CheckPlc: return 8 bytes (all zeros = healthy)
            return build_success_response(b"\x00" * 8, self.pairing_key)

        elif sub_func == 0x70:
            # ReadIoObject: return 16 bytes of simulated I/O data
            io_data = bytearray(16)
            io_data[0] = 0x01  # module count
            io_data[1] = 0x00  # status OK
            return build_success_response(bytes(io_data), self.pairing_key)

        elif sub_func == 0x73:
            # GetStatusModule: return 12 bytes of simulated module status
            module_status = bytearray(12)
            module_status[0] = 0x01  # module count
            module_status[1] = 0x00  # all OK
            module_status[2] = 0x03  # running state
            return build_success_response(bytes(module_status), self.pairing_key)

        else:
            print(f"[STUB] Unknown subFunc {sub_func:#04x}")
            return build_error_response(0x04, self.pairing_key)


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description="Stub UMAS/Modbus TCP server")
    parser.add_argument("port_positional", nargs="?", type=int, default=None,
                        help="Port (positional, legacy). Use --port instead.")
    parser.add_argument("--port", type=int, default=None,
                        help="Port to bind (0 = OS-assigned, default: 0)")
    parser.add_argument("--m580", action="store_true", default=False,
                        help="Simulate M580 PLC: reject ReadVariable (0x22) with 0xA1 error")
    args = parser.parse_args()

    # --port flag takes precedence, then positional, then default 0
    port = args.port if args.port is not None else (args.port_positional if args.port_positional is not None else 0)

    server = ReusableTCPServer(("127.0.0.1", port), UmasHandler)
    server._m580_mode = args.m580
    actual_port = server.server_address[1]
    if hasattr(signal, 'SIGTERM'):
        signal.signal(signal.SIGTERM, lambda *_: (server.shutdown(), sys.exit(0)))
    # The "PORT=<N>" token is parsed by the Dart test to discover the bound port.
    print(f"[STUB] UMAS stub server listening on PORT={actual_port}", flush=True)
    print(f"[STUB] Variables: {len(VARIABLES)}, Custom types: {len(DATA_TYPES)}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
