#!/usr/bin/env python3
"""Tests for tools/hmi_profiler.py.

    python3 -m unittest discover -s tools -p 'test_*.py'

The websocket client is hand-rolled, so it gets an end-to-end test against a
real loopback server that speaks enough of RFC 6455 to answer it — including
the fragmentation and >64 KiB payloads that a CPU-sample response actually
hits in practice.
"""

import base64
import hashlib
import json
import os
import socket
import struct
import sys
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hmi_profiler as hp  # noqa: E402


# --------------------------------------------------------------------------
# A server that speaks just enough websocket to answer our client.
# --------------------------------------------------------------------------


class FakeVmServer(threading.Thread):
    """Serves one connection; replies to JSON-RPC from a canned script."""

    def __init__(self, handler, fragment=False):
        super().__init__(daemon=True)
        self._handler = handler
        self._fragment = fragment
        self._listener = socket.socket()
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen(1)
        self.port = self._listener.getsockname()[1]
        self.error = None
        self.conn = None

    @property
    def url(self):
        return f"ws://127.0.0.1:{self.port}/ws"

    def run(self):
        try:
            self.conn, _ = self._listener.accept()
            self._handshake()
            self._handler(self)
        except Exception as exc:  # surfaced by the test through self.error
            self.error = exc
        finally:
            if self.conn:
                self.conn.close()
            self._listener.close()

    def _handshake(self):
        request = b""
        while b"\r\n\r\n" not in request:
            chunk = self.conn.recv(4096)
            if not chunk:
                raise AssertionError("client hung up during handshake")
            request += chunk
        key = ""
        for line in request.decode("latin-1").split("\r\n"):
            name, _, value = line.partition(":")
            if name.strip().lower() == "sec-websocket-key":
                key = value.strip()
        accept = base64.b64encode(
            hashlib.sha1((key + hp._WS_GUID).encode()).digest()
        ).decode()
        self.conn.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode()
        )

    # -- framing ----------------------------------------------------------

    def _recv_exactly(self, count):
        buf = b""
        while len(buf) < count:
            chunk = self.conn.recv(count - len(buf))
            if not chunk:
                raise AssertionError("client hung up")
            buf += chunk
        return buf

    def recv_json(self):
        while True:
            first = self._recv_exactly(1)[0]
            opcode = first & 0x0F
            second = self._recv_exactly(1)[0]
            length = second & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv_exactly(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv_exactly(8))[0]
            mask = self._recv_exactly(4) if second & 0x80 else None
            payload = self._recv_exactly(length) if length else b""
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x1:
                return json.loads(payload)
            if opcode == 0x8:
                raise AssertionError("client closed")

    def _frame(self, opcode, payload, fin=True):
        header = bytearray([(0x80 if fin else 0x00) | opcode])
        length = len(payload)
        if length < 126:
            header.append(length)
        elif length < 1 << 16:
            header.append(126)
            header += struct.pack(">H", length)
        else:
            header.append(127)
            header += struct.pack(">Q", length)
        return bytes(header) + payload

    def send_json(self, message):
        payload = json.dumps(message).encode()
        if self._fragment and len(payload) > 8:
            half = len(payload) // 2
            self.conn.sendall(self._frame(0x1, payload[:half], fin=False))
            self.conn.sendall(self._frame(0x0, payload[half:], fin=True))
        else:
            self.conn.sendall(self._frame(0x1, payload))

    def send_ping(self):
        self.conn.sendall(self._frame(0x9, b"hi"))


def serve(handler, fragment=False):
    server = FakeVmServer(handler, fragment=fragment)
    server.start()
    return server


# --------------------------------------------------------------------------


class WebSocketTransportTest(unittest.TestCase):
    def test_round_trip(self):
        def handler(server):
            request = server.recv_json()
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {"major": 4}})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            self.assertEqual(service.call("getVersion"), {"major": 4})
        finally:
            service.close()
        server.join(5)
        self.assertIsNone(server.error)

    def test_fragmented_and_large_messages(self):
        payload = {"blob": "x" * 200_000}

        def handler(server):
            request = server.recv_json()
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": payload})

        server = serve(handler, fragment=True)
        service = hp.VmService.connect(server.url)
        try:
            self.assertEqual(service.call("getVM"), payload)
        finally:
            service.close()
        server.join(5)
        self.assertIsNone(server.error)

    def test_answers_ping_while_waiting(self):
        def handler(server):
            request = server.recv_json()
            server.send_ping()
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {"ok": True}})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            self.assertEqual(service.call("getVersion"), {"ok": True})
        finally:
            service.close()
        server.join(5)
        self.assertIsNone(server.error)

    def test_events_arriving_before_the_response_are_kept(self):
        def handler(server):
            request = server.recv_json()
            server.send_json(
                {
                    "jsonrpc": "2.0",
                    "method": "streamNotify",
                    "params": {
                        "streamId": "Extension",
                        "event": {"extensionKind": "Flutter.Frame", "extensionData": {"build": 1}},
                    },
                }
            )
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            service.call("getVersion")
            self.assertEqual(len(service.events), 1)
            self.assertEqual(service.events[0]["extensionKind"], "Flutter.Frame")
        finally:
            service.close()
        server.join(5)

    def test_error_response_raises_but_try_call_swallows_it(self):
        def handler(server):
            for _ in range(2):
                request = server.recv_json()
                server.send_json(
                    {
                        "jsonrpc": "2.0",
                        "id": request["id"],
                        "error": {"code": 112, "message": "Cannot get CPU samples"},
                    }
                )

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            with self.assertRaises(hp.VmServiceError):
                service.call("getCpuSamples")
            self.assertIsNone(service.try_call("getCpuSamples"))
        finally:
            service.close()
        server.join(5)

    def test_connect_failure_is_a_profiler_error(self):
        # Port 1 on loopback refuses connections; no wait, so it gives up at once.
        with self.assertRaises(hp.ProfilerError):
            hp.VmService.connect("ws://127.0.0.1:1/ws")

    def test_reconnect_replaces_the_socket_in_place(self):
        def handler(server):
            request = server.recv_json()
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {"ok": 1}})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            service.call("getVersion")
            # Nothing is listening on port 1, so reconnect gives up cleanly
            # instead of leaving a half-open service behind.
            with self.assertRaises(hp.ProfilerError):
                service.reconnect("ws://127.0.0.1:1/ws")
        finally:
            service.close()

    def test_rejects_a_non_websocket_url(self):
        with self.assertRaises(hp.ProfilerError):
            hp.WebSocket("http://127.0.0.1:1/")


class CollectFramesTest(unittest.TestCase):
    def test_subscribes_collects_and_unsubscribes(self):
        seen = []

        def handler(server):
            request = server.recv_json()  # streamListen
            seen.append(request["method"])
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {}})
            for build in (2000, 40000):
                server.send_json(
                    {
                        "jsonrpc": "2.0",
                        "method": "streamNotify",
                        "params": {
                            "streamId": "Extension",
                            "event": {
                                "extensionKind": "Flutter.Frame",
                                "extensionData": {"build": build, "raster": 1000},
                            },
                        },
                    }
                )
            # An unrelated extension event must not be counted as a frame.
            server.send_json(
                {
                    "jsonrpc": "2.0",
                    "method": "streamNotify",
                    "params": {
                        "streamId": "Extension",
                        "event": {"extensionKind": "Flutter.Navigation", "extensionData": {}},
                    },
                }
            )
            request = server.recv_json()  # streamCancel
            seen.append(request["method"])
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            frames = hp.collect_frames(service, 0.3)
        finally:
            service.close()
        server.join(5)
        self.assertIsNone(server.error)
        self.assertEqual(seen, ["streamListen", "streamCancel"])
        self.assertEqual([f["build"] for f in frames], [2000, 40000])
        self.assertEqual(hp.frame_stats(frames)["janky"], 1)


class GatherTest(unittest.TestCase):
    class _Args:
        pass

    def test_one_unavailable_section_does_not_lose_the_others(self):
        calls = []

        def failing():
            calls.append("cpu")
            raise hp.VmServiceError("getCpuSamples", {"message": "Feature is disabled"})

        def working():
            calls.append("memory")

        problems = []

        # Exercised through the same shape gather() uses.
        def attempt(section, work):
            try:
                work()
            except hp.ConnectionClosed:
                raise
            except (hp.ProfilerError, TimeoutError) as exc:
                problems.append(f"{section}: {exc}")

        attempt("cpu", failing)
        attempt("memory", working)
        self.assertEqual(calls, ["cpu", "memory"])
        self.assertEqual(len(problems), 1)
        self.assertIn("Feature is disabled", problems[0])

    def test_gather_reports_a_dead_section_and_keeps_going(self):
        def handler(server):
            while True:
                request = server.recv_json()
                method = request["method"]
                if method == "getVM":
                    result = {"isolates": [{"id": "isolates/1", "name": "main"}]}
                elif method == "getVersion":
                    result = {"major": 4, "minor": 20}
                elif method in ("clearCpuSamples", "getCpuSamples"):
                    server.send_json(
                        {
                            "jsonrpc": "2.0",
                            "id": request["id"],
                            "error": {"code": 100, "message": "Feature is disabled"},
                        }
                    )
                    continue
                elif method == "getMemoryUsage":
                    result = {"heapUsage": 1_000_000, "heapCapacity": 2_000_000}
                elif method == "getAllocationProfile":
                    result = {
                        "members": [{"class": {"name": "Foo"}, "bytesCurrent": 10, "instancesCurrent": 1}]
                    }
                else:
                    result = {"type": "Success"}
                server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": result})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            data = hp.gather(service, 0.0, 5, want=("cpu", "memory"))
        finally:
            service.close()
        self.assertEqual(data["cpu"]["samples"], 0)
        self.assertEqual(data["memory_classes"][0]["name"], "Foo")
        self.assertEqual(len(data["problems"]), 1)
        self.assertIn("cpu:", data["problems"][0])

    def test_a_dropped_connection_stops_the_whole_window(self):
        def handler(server):
            request = server.recv_json()  # getVM
            server.send_json(
                {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {"isolates": [{"id": "isolates/1", "name": "main"}]},
                }
            )
            request = server.recv_json()  # getVersion
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {}})
            server.conn.close()  # the app goes away mid-window

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            with self.assertRaises(hp.ConnectionClosed):
                hp.gather(service, 0.0, 5, want=("cpu", "memory"))
        finally:
            service.close()


class MainIsolateTest(unittest.TestCase):
    def test_prefers_the_isolate_named_main(self):
        def handler(server):
            request = server.recv_json()
            server.send_json(
                {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "isolates": [
                            {"id": "isolates/7", "name": "worker"},
                            {"id": "isolates/1", "name": "main"},
                        ]
                    },
                }
            )

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            self.assertEqual(service.main_isolate(), "isolates/1")
        finally:
            service.close()

    def test_no_isolates_is_an_error(self):
        def handler(server):
            request = server.recv_json()
            server.send_json({"jsonrpc": "2.0", "id": request["id"], "result": {"isolates": []}})

        server = serve(handler)
        service = hp.VmService.connect(server.url)
        try:
            with self.assertRaises(hp.ProfilerError):
                service.main_isolate()
        finally:
            service.close()


# --------------------------------------------------------------------------
# Analysis
# --------------------------------------------------------------------------


SAMPLE_FUNCTIONS = [
    {
        "resolvedUrl": "package:tfc/page_creator/assets/conveyor.dart",
        "function": {"name": "paint", "owner": {"type": "@Class", "name": "ConveyorPainter"}},
    },
    {
        "resolvedUrl": "package:flutter/src/rendering/object.dart",
        "function": {"name": "_paintWithContext", "owner": {"type": "@Class", "name": "RenderObject"}},
    },
    {"resolvedUrl": "", "function": {"name": "memcpy"}},
]


class FunctionLabelTest(unittest.TestCase):
    def test_qualifies_with_the_owning_class(self):
        self.assertEqual(
            hp.function_label(SAMPLE_FUNCTIONS, 0), "ConveyorPainter.paint [conveyor.dart]"
        )

    def test_unresolved_url_reads_as_native(self):
        self.assertEqual(hp.function_label(SAMPLE_FUNCTIONS, 2), "memcpy [native]")

    def test_out_of_range_index_does_not_raise(self):
        self.assertEqual(hp.function_label(SAMPLE_FUNCTIONS, 99), "???")
        self.assertEqual(hp.function_label(SAMPLE_FUNCTIONS, None), "???")

    def test_package_grouping(self):
        self.assertEqual(hp.package_of(SAMPLE_FUNCTIONS, 0), "tfc")
        self.assertEqual(hp.package_of(SAMPLE_FUNCTIONS, 1), "flutter")
        self.assertEqual(hp.package_of(SAMPLE_FUNCTIONS, 2), "native")


class FoldCpuSamplesTest(unittest.TestCase):
    def payload(self, stacks):
        return {
            "samplePeriod": 250,
            "timeExtentMicros": 1_000_000,
            "functions": SAMPLE_FUNCTIONS,
            "samples": [{"stack": stack} for stack in stacks],
        }

    def test_self_time_counts_only_the_leaf(self):
        folded = hp.fold_cpu_samples(self.payload([[0, 1], [0, 1], [1]]))
        self_by_name = {row["name"]: row["samples"] for row in folded["self"]}
        self.assertEqual(self_by_name["ConveyorPainter.paint [conveyor.dart]"], 2)
        self.assertEqual(self_by_name["RenderObject._paintWithContext [object.dart]"], 1)

    def test_inclusive_time_counts_a_recursive_frame_once(self):
        folded = hp.fold_cpu_samples(self.payload([[1, 1, 1, 0]]))
        inclusive = {row["name"]: row["samples"] for row in folded["inclusive"]}
        self.assertEqual(inclusive["RenderObject._paintWithContext [object.dart]"], 1)

    def test_empty_stacks_are_skipped_and_do_not_divide_by_zero(self):
        folded = hp.fold_cpu_samples(self.payload([[], []]))
        self.assertEqual(folded["samples"], 0)
        self.assertEqual(folded["self"], [])

    def test_missing_payload_is_tolerated(self):
        folded = hp.fold_cpu_samples({})
        self.assertEqual(folded["samples"], 0)

    def test_percentages_are_relative_to_counted_samples(self):
        folded = hp.fold_cpu_samples(self.payload([[0], [0], [1], []]))
        top = folded["self"][0]
        self.assertEqual(top["name"], "ConveyorPainter.paint [conveyor.dart]")
        self.assertAlmostEqual(top["percent"], 200 / 3.0)

    def test_top_limits_rows(self):
        folded = hp.fold_cpu_samples(self.payload([[0], [1], [2]]), top=1)
        self.assertEqual(len(folded["self"]), 1)


class PercentileTest(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(hp.percentile([], 0.9), 0)

    def test_nearest_rank(self):
        values = list(range(1, 101))
        self.assertEqual(hp.percentile(values, 0.0), 1)
        self.assertEqual(hp.percentile(values, 1.0), 100)
        self.assertEqual(hp.percentile(values, 0.5), 51)

    def test_single_value(self):
        self.assertEqual(hp.percentile([7], 0.99), 7)


class FrameStatsTest(unittest.TestCase):
    def frames(self, pairs):
        return [
            {"build": build, "raster": raster, "elapsed": build + raster, "number": i}
            for i, (build, raster) in enumerate(pairs)
        ]

    def test_counts_frames_over_budget(self):
        stats = hp.frame_stats(self.frames([(2000, 3000), (20000, 3000), (2000, 90000)]))
        self.assertEqual(stats["frames"], 3)
        self.assertEqual(stats["janky"], 2)
        self.assertEqual(stats["severe"], 1)
        self.assertAlmostEqual(stats["janky_percent"], 200 / 3.0)

    def test_a_frame_exactly_on_budget_is_not_jank(self):
        stats = hp.frame_stats(self.frames([(hp.FRAME_BUDGET_US, 1000)]))
        self.assertEqual(stats["janky"], 0)

    def test_blames_the_slower_thread(self):
        raster_bound = hp.frame_stats(self.frames([(1000, 30000)] * 10))
        self.assertEqual(raster_bound["bottleneck"], "raster")
        build_bound = hp.frame_stats(self.frames([(30000, 1000)] * 10))
        self.assertEqual(build_bound["bottleneck"], "build")

    def test_no_frames(self):
        stats = hp.frame_stats([])
        self.assertEqual(stats["frames"], 0)
        self.assertEqual(stats["bottleneck"], "unknown")
        self.assertIsNone(stats["worst_frame"])
        self.assertEqual(stats["janky_percent"], 0.0)

    def test_worst_frame_is_the_longest(self):
        stats = hp.frame_stats(self.frames([(1000, 1000), (1000, 40000)]))
        self.assertEqual(stats["worst_frame"]["number"], 1)

    def test_missing_keys_default_to_zero(self):
        stats = hp.frame_stats([{"number": 1}])
        self.assertEqual(stats["build_us"]["max"], 0)


class TimelineSummaryTest(unittest.TestCase):
    def test_pairs_begin_and_end_events(self):
        # This is what the Dart VM actually writes for Timeline.startSync,
        # which is how the framework marks BUILD / LAYOUT / PAINT.
        payload = {
            "traceEvents": [
                {"ph": "B", "name": "BUILD", "ts": 1000, "pid": 1, "tid": 7},
                {"ph": "B", "name": "PAINT", "ts": 1100, "pid": 1, "tid": 7},
                {"ph": "E", "name": "PAINT", "ts": 1400, "pid": 1, "tid": 7},
                {"ph": "E", "name": "BUILD", "ts": 1900, "pid": 1, "tid": 7},
            ]
        }
        rows = {row["name"]: row for row in hp.summarise_timeline(payload)}
        self.assertEqual(rows["BUILD"]["total_us"], 900)
        self.assertEqual(rows["PAINT"]["total_us"], 300)

    def test_threads_do_not_pair_with_each_other(self):
        payload = {
            "traceEvents": [
                {"ph": "B", "name": "UI", "ts": 0, "pid": 1, "tid": 1},
                {"ph": "B", "name": "RASTER", "ts": 10, "pid": 1, "tid": 2},
                {"ph": "E", "name": "RASTER", "ts": 60, "pid": 1, "tid": 2},
                {"ph": "E", "name": "UI", "ts": 100, "pid": 1, "tid": 1},
            ]
        }
        rows = {row["name"]: row for row in hp.summarise_timeline(payload)}
        self.assertEqual(rows["UI"]["total_us"], 100)
        self.assertEqual(rows["RASTER"]["total_us"], 50)

    def test_unmatched_events_are_dropped_not_guessed(self):
        payload = {
            "traceEvents": [
                {"ph": "E", "name": "OPENED_BEFORE_THE_BUFFER", "ts": 5, "pid": 1, "tid": 1},
                {"ph": "B", "name": "STILL_RUNNING", "ts": 10, "pid": 1, "tid": 1},
            ]
        }
        self.assertEqual(hp.summarise_timeline(payload), [])

    def test_aggregates_complete_events_only(self):
        payload = {
            "traceEvents": [
                {"ph": "X", "name": "PAINT", "dur": 100},
                {"ph": "X", "name": "PAINT", "dur": 300},
                {"ph": "B", "name": "PAINT", "dur": 9999},
                {"ph": "X", "name": "LAYOUT", "dur": 50},
            ]
        }
        rows = hp.summarise_timeline(payload)
        by_name = {row["name"]: row for row in rows}
        self.assertEqual(by_name["PAINT"]["count"], 2)
        self.assertEqual(by_name["PAINT"]["total_us"], 400)
        self.assertEqual(by_name["PAINT"]["mean_us"], 200)
        self.assertEqual(by_name["PAINT"]["max_us"], 300)
        self.assertEqual(rows[0]["name"], "PAINT")  # ordered by total time

    def test_empty_payload(self):
        self.assertEqual(hp.summarise_timeline({}), [])


class AllocationSummaryTest(unittest.TestCase):
    def test_reads_the_flat_class_heap_stats_current_vms_send(self):
        payload = {
            "members": [
                {
                    "class": {"name": "_List"},
                    "bytesCurrent": 774_000_000,
                    "instancesCurrent": 20715,
                },
                {"class": {"name": "Function"}, "bytesCurrent": 872_704, "instancesCurrent": 6818},
            ]
        }
        rows = hp.summarise_allocations(payload)
        self.assertEqual([row["name"] for row in rows], ["_List", "Function"])
        self.assertEqual(rows[0]["instances"], 20715)

    def test_sums_both_spaces_and_sorts_by_size(self):
        payload = {
            "members": [
                {
                    "class": {"name": "Uint8List"},
                    "oldSpace": {"bytesCurrent": 1000, "instancesCurrent": 2},
                    "newSpace": {"bytesCurrent": 500, "instancesCurrent": 1},
                },
                {
                    "class": {"name": "Widget"},
                    "oldSpace": {"bytesCurrent": 4000, "instancesCurrent": 40},
                    "newSpace": {},
                },
                {"class": {"name": "Empty"}, "oldSpace": {}, "newSpace": {}},
            ]
        }
        rows = hp.summarise_allocations(payload)
        self.assertEqual([row["name"] for row in rows], ["Widget", "Uint8List"])
        self.assertEqual(rows[1]["bytes"], 1500)
        self.assertEqual(rows[1]["instances"], 3)

    def test_empty_payload(self):
        self.assertEqual(hp.summarise_allocations({}), [])


class RenderTest(unittest.TestCase):
    def test_idle_app_says_so_rather_than_printing_an_empty_table(self):
        text = hp.render_frames(hp.frame_stats([]))
        self.assertIn("No `Flutter.Frame` events", text)

    def test_report_renders_every_section(self):
        data = {
            "collected_at": "2026-08-28 10:00:00 +0000",
            "url": "ws://flutter:8181/ws",
            "isolate": "isolates/1",
            "seconds": 15,
            "vm_version": "4.19",
            "frames": hp.frame_stats([{"build": 20000, "raster": 1000, "elapsed": 21000}]),
            "cpu": hp.fold_cpu_samples(
                {"functions": SAMPLE_FUNCTIONS, "samples": [{"stack": [0, 1]}]}
            ),
            "timeline": hp.summarise_timeline({"traceEvents": [{"ph": "X", "name": "BUILD", "dur": 5}]}),
            "memory_usage": {"heapUsage": 12_000_000, "heapCapacity": 20_000_000},
            "memory_classes": hp.summarise_allocations(
                {"members": [{"class": {"name": "Foo"}, "oldSpace": {"bytesCurrent": 9}}]}
            ),
        }
        report = hp.render_report(data)
        for heading in ("### Frames", "### CPU", "### Timeline", "### Memory"):
            self.assertIn(heading, report)
        self.assertIn("ConveyorPainter.paint", report)
        self.assertIn("BUILD", report)

    def test_table_escapes_nothing_but_still_lines_up(self):
        table = hp.render_table(["a", "b"], [[1, 2], [3, 4]])
        self.assertEqual(table.splitlines()[0], "| a | b |")
        self.assertEqual(table.splitlines()[1], "|---|---|")

    def test_empty_table(self):
        self.assertIn("nothing recorded", hp.render_table(["a"], []))


class ParserTest(unittest.TestCase):
    def test_defaults(self):
        args = hp.build_parser().parse_args(["report"])
        self.assertEqual(args.command, "report")
        self.assertEqual(args.seconds, 15.0)
        self.assertEqual(args.url, hp.DEFAULT_URL)

    def test_every_command_is_wired_up(self):
        for name in hp.COMMANDS:
            self.assertEqual(hp.build_parser().parse_args([name]).command, name)


if __name__ == "__main__":
    unittest.main()
