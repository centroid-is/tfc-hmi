#!/usr/bin/env python3
"""
Modbus TCP test server for tfc-hmi integration tests.

Uses pymodbus to provide a configurable Modbus TCP server with pre-populated
test data. Supports runtime commands via stdin to modify datastore values.

Usage:
    python modbus_server.py [--port PORT]
"""

import argparse
import asyncio
import struct
import sys
import threading

from pymodbus.datastore import (
    ModbusSequentialDataBlock,
    ModbusDeviceContext,
    ModbusServerContext,
)
from pymodbus.server import StartAsyncTcpServer


def encode_float32(value: float) -> list[int]:
    """Encode a float32 into two big-endian uint16 values."""
    packed = struct.pack(">f", value)
    high, low = struct.unpack(">HH", packed)
    return [high, low]


def encode_float64(value: float) -> list[int]:
    """Encode a float64 into four big-endian uint16 values."""
    packed = struct.pack(">d", value)
    a, b, c, d = struct.unpack(">HHHH", packed)
    return [a, b, c, d]


def encode_uint32(value: int) -> list[int]:
    """Encode a uint32 into two big-endian uint16 values."""
    packed = struct.pack(">I", value)
    high, low = struct.unpack(">HH", packed)
    return [high, low]


def encode_int64(value: int) -> list[int]:
    """Encode an int64 into four big-endian uint16 values."""
    packed = struct.pack(">q", value)
    a, b, c, d = struct.unpack(">HHHH", packed)
    return [a, b, c, d]


def build_server_context() -> ModbusServerContext:
    """Build and return a ModbusServerContext with pre-populated test data.

    IMPORTANT: pymodbus 3.12 ModbusDeviceContext applies an internal +1 address
    offset (the old zero_mode parameter was removed). To ensure consistency, we
    pre-populate data through the context's setValues() method, which applies the
    same offset as client reads and stdin commands.
    """
    # Initialize data blocks with 1001 entries (extra slot for context offset).
    coils = ModbusSequentialDataBlock(0, [False] * 1001)
    discrete_inputs = ModbusSequentialDataBlock(0, [False] * 1001)
    holding_registers = ModbusSequentialDataBlock(0, [0] * 1001)
    input_registers = ModbusSequentialDataBlock(0, [0] * 1001)

    device_context = ModbusDeviceContext(
        di=discrete_inputs,
        co=coils,
        hr=holding_registers,
        ir=input_registers,
    )
    server_context = ModbusServerContext(devices=device_context, single=True)
    slave = server_context[0]

    # Pre-populate through context API (applies same address offset as client).
    # FC 3 = holding registers
    slave.setValues(3, 0, [12345])
    slave.setValues(3, 1, [0x8000])
    slave.setValues(3, 10, encode_float32(3.14))
    slave.setValues(3, 20, encode_float64(2.718281828))
    slave.setValues(3, 30, encode_uint32(100000))
    slave.setValues(3, 40, encode_int64(-1000000))

    # FC 4 = input registers
    slave.setValues(4, 0, [54321])

    # FC 1 = coils
    slave.setValues(1, 0, [True])
    slave.setValues(1, 1, [False])

    # FC 2 = discrete inputs
    slave.setValues(2, 0, [True])
    slave.setValues(2, 1, [False])

    return server_context


def _stdin_reader_thread(queue: "asyncio.Queue[str | None]", loop: asyncio.AbstractEventLoop) -> None:
    """Read lines from stdin in a dedicated thread, post them to an async queue.

    Uses readline() instead of iteration to avoid Python's internal read-ahead
    buffering that delays line delivery when stdin is a pipe.
    """
    try:
        while True:
            line = sys.stdin.readline()
            if not line:
                break  # EOF
            loop.call_soon_threadsafe(queue.put_nowait, line.strip())
    except Exception:
        pass
    # Signal EOF
    loop.call_soon_threadsafe(queue.put_nowait, None)


async def stdin_command_handler(context: ModbusServerContext, shutdown_event: asyncio.Event) -> None:
    """Process commands from stdin via a thread-safe async queue."""
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[str | None] = asyncio.Queue()

    # Start a thread to read stdin (avoids event loop contention with TCP server)
    reader_thread = threading.Thread(
        target=_stdin_reader_thread, args=(queue, loop), daemon=True
    )
    reader_thread.start()

    slave = context[0]  # Unit ID 0 (single slave).

    while True:
        try:
            command = await queue.get()
            if command is None:
                # EOF on stdin - parent process closed the pipe.
                break
            if not command:
                continue

            parts = command.split()
            if len(parts) == 0:
                continue

            action = parts[0].upper()

            if action == "STOP":
                print("STOPPING", flush=True)
                shutdown_event.set()
                return

            if action == "SET" and len(parts) >= 4:
                register_type = parts[1].upper()
                addr = int(parts[2])
                value = int(parts[3])

                if register_type == "HR":
                    slave.setValues(3, addr, [value])
                    print(f"OK SET HR {addr} {value}", flush=True)
                elif register_type == "IR":
                    slave.setValues(4, addr, [value])
                    print(f"OK SET IR {addr} {value}", flush=True)
                elif register_type == "CO":
                    slave.setValues(1, addr, [bool(value)])
                    print(f"OK SET CO {addr} {value}", flush=True)
                elif register_type == "DI":
                    slave.setValues(2, addr, [bool(value)])
                    print(f"OK SET DI {addr} {value}", flush=True)
                else:
                    print(f"ERROR unknown register type: {register_type}", flush=True)

            elif action == "GET" and len(parts) >= 3:
                register_type = parts[1].upper()
                addr = int(parts[2])

                if register_type == "HR":
                    values = slave.getValues(3, addr, 1)
                    print(f"{values[0]}", flush=True)
                elif register_type == "IR":
                    values = slave.getValues(4, addr, 1)
                    print(f"{values[0]}", flush=True)
                elif register_type == "CO":
                    values = slave.getValues(1, addr, 1)
                    print(f"{1 if values[0] else 0}", flush=True)
                elif register_type == "DI":
                    values = slave.getValues(2, addr, 1)
                    print(f"{1 if values[0] else 0}", flush=True)
                else:
                    print(f"ERROR unknown register type: {register_type}", flush=True)

            else:
                print(f"ERROR unknown command: {command}", flush=True)

        except Exception as e:
            print(f"ERROR {e}", flush=True)


async def run_server(port: int) -> None:
    """Start the Modbus TCP server and stdin command handler."""
    from pymodbus.server import ModbusTcpServer, ServerAsyncStop

    server_context = build_server_context()
    shutdown_event = asyncio.Event()

    # Create and start the TCP server manually so we can print READY after bind.
    server = ModbusTcpServer(context=server_context, address=("0.0.0.0", port))
    try:
        await server.listen()
    except Exception as e:
        print(f"FAIL {e}", flush=True)
        return

    # Start the stdin command handler as a background task.
    asyncio.create_task(stdin_command_handler(server_context, shutdown_event))

    # Now we are actually listening on the port.
    print("READY", flush=True)

    # Wait for shutdown signal. The server is already serving after listen().
    await shutdown_event.wait()

    # Clean up
    try:
        await ServerAsyncStop()
    except Exception:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Modbus TCP test server")
    parser.add_argument(
        "--port",
        type=int,
        default=5020,
        help="TCP port to listen on (default: 5020)",
    )
    args = parser.parse_args()

    asyncio.run(run_server(args.port))


if __name__ == "__main__":
    main()
