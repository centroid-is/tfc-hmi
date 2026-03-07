#!/usr/bin/env python3
"""Stub UMAS/Modbus TCP server for integration testing.

Responds to FC90 (0x5A) UMAS requests over Modbus TCP MBAP framing.
Supports: Init (0x01), ReadDataDictionary (0x26) with record types 0xDD02/0xDD03.

Usage: python3 test/umas_stub_server.py [port]
"""

import struct
import socketserver
import sys
import signal
import os

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
    # typeId, name, byteSize
    (100, "MY_STRUCT", 16),
    (101, "ALARM_TYPE", 8),
]


def build_variable_names_payload():
    """Build 0xDD02 response: variable name records."""
    buf = bytearray()
    for name, block_no, offset, data_type_id in VARIABLES:
        name_bytes = name.encode("utf-8")
        buf += struct.pack("<H", len(name_bytes))
        buf += name_bytes
        buf += struct.pack("<HHH", block_no, offset, data_type_id)
    return bytes(buf)


def build_data_types_payload():
    """Build 0xDD03 response: data type reference records."""
    buf = bytearray()
    for type_id, name, byte_size in DATA_TYPES:
        name_bytes = name.encode("utf-8")
        buf += struct.pack("<HH", type_id, len(name_bytes))
        buf += name_bytes
        buf += struct.pack("<H", byte_size)
    return bytes(buf)


def build_success_response(sub_func, payload, pairing_key=0x00):
    """Build FC90 success PDU: [0x5A, pairingKey, 0xFE, subFunc, ...payload]."""
    pdu = bytearray([0x5A, pairing_key, 0xFE, sub_func])
    pdu += payload
    return bytes(pdu)


def build_error_response(error_code, pairing_key=0x00):
    """Build FC90 error PDU: [0x5A, pairingKey, 0xFD, errorCode]."""
    return bytes([0x5A, pairing_key, 0xFD, error_code])


def wrap_mbap(transaction_id, unit_id, pdu):
    """Wrap PDU in MBAP header."""
    length = 1 + len(pdu)  # unit_id + pdu
    header = struct.pack(">HHH", transaction_id, 0, length)
    return header + bytes([unit_id]) + pdu


class UmasHandler(socketserver.BaseRequestHandler):
    def handle(self):
        print(f"[STUB] Connection from {self.client_address}")
        buf = bytearray()

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
            return build_error_response(0x01)

        fc = pdu[0]
        if fc != 0x5A:
            print(f"[STUB] Non-FC90 request (FC={fc:#x}), ignoring")
            return None

        pairing_key = pdu[1]
        sub_func = pdu[2]
        payload = pdu[3:]

        print(f"[STUB] FC90 subFunc={sub_func:#04x} pairingKey={pairing_key:#04x} payloadLen={len(payload)}")

        if sub_func == 0x01:
            # Init: return max frame size = 1024
            resp_payload = struct.pack("<H", 1024)
            return build_success_response(sub_func, resp_payload, pairing_key)

        elif sub_func == 0x26:
            # ReadDataDictionary
            if len(payload) < 2:
                return build_error_response(0x02, pairing_key)

            record_type = struct.unpack("<H", payload[:2])[0]
            print(f"[STUB]   recordType={record_type:#06x}")

            if record_type == 0xDD02:
                data = build_variable_names_payload()
                return build_success_response(sub_func, data, pairing_key)
            elif record_type == 0xDD03:
                data = build_data_types_payload()
                return build_success_response(sub_func, data, pairing_key)
            else:
                return build_error_response(0x03, pairing_key)

        else:
            print(f"[STUB] Unknown subFunc {sub_func:#04x}")
            return build_error_response(0x04, pairing_key)


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


def main():
    server = ReusableTCPServer(("0.0.0.0", PORT), UmasHandler)
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
