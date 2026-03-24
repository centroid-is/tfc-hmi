#!/usr/bin/env python3
"""Stub UMAS/Modbus TCP server for integration testing.

Responds to FC90 (0x5A) UMAS requests over Modbus TCP MBAP framing.
Supports: ReadPlcId (0x02), Init (0x01), ReadDataDictionary (0x26)
with record types 0xDD02/0xDD03 in corrected PLC4X mspec format.

Usage: python3 test/umas_stub_server.py [port]
"""

import struct
import socketserver
import sys
import signal

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5020

# --- Sample data: realistic Schneider PLC variable tree ---

VARIABLES = [
    # name, blockNo, offset, dataTypeId
    ("Application.GVL.temperature", 1, 0, 5),    # REAL
    ("Application.GVL.pressure", 1, 4, 5),        # REAL
    ("Application.GVL.motor_running", 1, 8, 6),   # BOOL
    ("Application.GVL.setpoint", 1, 9, 1),        # INT
    ("Application.GVL.error_code", 1, 11, 2),     # UINT
    ("Application.Motor.speed", 2, 0, 5),          # REAL
    ("Application.Motor.torque", 2, 4, 5),         # REAL
    ("Application.Motor.enabled", 2, 8, 6),        # BOOL
    ("Application.Counters.production", 3, 0, 4),  # UDINT
    ("Application.Counters.runtime_ms", 3, 4, 8),  # TIME
]

DATA_TYPES = [
    # typeId, name, byteSize, classIdentifier, dataType
    (100, "MY_STRUCT", 16, 2, 0),
    (101, "ALARM_TYPE", 8, 0, 5),
]

# PLC identification values
HARDWARE_ID = 0x12345678
MEMORY_BLOCK_INDEX = 0
NUM_MEMORY_BANKS = 1


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
    """Build 0xDD02 response in corrected PLC4X mspec format.

    Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
    Records: dataType(2 LE) + block(2 LE) + offset(2 LE) + unknown4(2 LE) +
             stringLength(2 LE) + name(N bytes, null-terminated)
    """
    buf = bytearray()
    # Header
    buf += struct.pack("B", 0x00)                      # range
    buf += struct.pack("<H", next_address)              # nextAddress
    buf += struct.pack("<H", 0x0000)                    # unknown1
    buf += struct.pack("<H", len(variables))            # noOfRecords

    # Records
    for name, block_no, offset, data_type_id in variables:
        name_bytes = name.encode("utf-8") + b"\x00"    # null-terminated
        buf += struct.pack("<H", data_type_id)          # dataType
        buf += struct.pack("<H", block_no)              # block
        buf += struct.pack("<H", offset)                # offset
        buf += struct.pack("<H", 0x0000)                # unknown4
        buf += struct.pack("<H", len(name_bytes))       # stringLength (incl null)
        buf += name_bytes                               # name
    return bytes(buf)


def build_data_types_payload(data_types, next_address=0x0000):
    """Build 0xDD03 response in corrected PLC4X mspec format.

    Header: range(1) + nextAddress(2 LE) + unknown1(1) + noOfRecords(2 LE)
    Records: dataSize(2 LE) + unknown1(2 LE) + classIdentifier(1) +
             dataType(1) + stringLength(1) + name(N bytes, null-terminated)
    """
    buf = bytearray()
    # Header
    buf += struct.pack("B", 0x00)                      # range
    buf += struct.pack("<H", next_address)              # nextAddress
    buf += struct.pack("B", 0x00)                       # unknown1
    buf += struct.pack("<H", len(data_types))           # noOfRecords

    # Records
    for type_id, name, byte_size, class_id, data_type in data_types:
        name_bytes = name.encode("utf-8") + b"\x00"    # null-terminated
        buf += struct.pack("<H", byte_size)             # dataSize
        buf += struct.pack("<H", 0x0000)                # unknown1
        buf += struct.pack("B", class_id)               # classIdentifier
        buf += struct.pack("B", data_type)              # dataType
        buf += struct.pack("B", len(name_bytes))        # stringLength (incl null)
        buf += name_bytes                               # name
    return bytes(buf)


def build_success_response(sub_func, payload, pairing_key=0x00):
    """Build FC90 success PDU: [0x5A, pairingKey, subFunc, 0xFE, ...payload].

    Real Schneider PLC format: FC + pairingKey + subFuncEcho + status + payload.
    """
    pdu = bytearray([0x5A, pairing_key, sub_func, 0xFE])
    pdu += payload
    return bytes(pdu)


def build_error_response(error_code, pairing_key=0x00, sub_func=0x00):
    """Build FC90 error PDU: [0x5A, pairingKey, subFunc, 0xFD, errorCode].

    Real Schneider PLC format: FC + pairingKey + subFuncEcho + status + errorCode.
    """
    return bytes([0x5A, pairing_key, sub_func, 0xFD, error_code])


def wrap_mbap(transaction_id, unit_id, pdu):
    """Wrap PDU in MBAP header."""
    length = 1 + len(pdu)  # unit_id + pdu
    header = struct.pack(">HHH", transaction_id, 0, length)
    return header + bytes([unit_id]) + pdu


class UmasHandler(socketserver.BaseRequestHandler):
    def handle(self):
        print(f"[STUB] Connection from {self.client_address}")
        buf = bytearray()
        self.pairing_key = 0x00

        # Pagination state per connection
        self._dd02_offset = 0
        self._dd03_offset = 0

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

    def handle_pdu(self, pdu):
        if len(pdu) < 3:
            return build_error_response(0x01, sub_func=0x00)

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
            return build_success_response(sub_func, resp_payload, self.pairing_key)

        elif sub_func == 0x01:
            # Init: return max frame size = 1024, store pairing key
            self.pairing_key = pairing_key
            resp_payload = struct.pack("<H", 1024)
            return build_success_response(sub_func, resp_payload, pairing_key)

        elif sub_func == 0x26:
            # ReadDataDictionary -- accept full 13-byte payload
            if len(payload) < 2:
                return build_error_response(0x02, self.pairing_key, sub_func)

            record_type = struct.unpack("<H", payload[:2])[0]
            print(f"[STUB]   recordType={record_type:#06x} payloadLen={len(payload)}")

            if len(payload) >= 13:
                # Parse full payload fields for logging
                index = payload[2]
                hw_id = struct.unpack("<I", payload[3:7])[0]
                block_no = struct.unpack("<H", payload[7:9])[0]
                offset = struct.unpack("<H", payload[9:11])[0]
                blank = struct.unpack("<H", payload[11:13])[0]
                print(f"[STUB]   index={index} hwId={hw_id:#010x} blockNo={block_no:#06x} offset={offset:#06x} blank={blank:#06x}")

            if record_type == 0xDD02:
                # Return all variables in single page
                data = build_variable_names_payload(VARIABLES, next_address=0x0000)
                return build_success_response(sub_func, data, self.pairing_key)
            elif record_type == 0xDD03:
                # Return all data types in single page
                data = build_data_types_payload(DATA_TYPES, next_address=0x0000)
                return build_success_response(sub_func, data, self.pairing_key)
            else:
                return build_error_response(0x03, self.pairing_key, sub_func)

        else:
            print(f"[STUB] Unknown subFunc {sub_func:#04x}")
            return build_error_response(0x04, self.pairing_key, sub_func)


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


def main():
    server = ReusableTCPServer(("0.0.0.0", PORT), UmasHandler)
    if hasattr(signal, 'SIGTERM'):
        signal.signal(signal.SIGTERM, lambda *_: (server.shutdown(), sys.exit(0)))
    print(f"[STUB] UMAS stub server listening on port {PORT}", flush=True)
    print(f"[STUB] Variables: {len(VARIABLES)}, Custom types: {len(DATA_TYPES)}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
