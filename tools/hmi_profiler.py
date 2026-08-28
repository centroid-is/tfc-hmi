#!/usr/bin/env python3
"""Read the Dart VM Service of a running CentroidX and report on performance.

The `latest-release` container image is a Flutter *profile* build: AOT-compiled
like release, but with the Dart VM Service, the sampling CPU profiler and the
`Flutter.Frame` timing events still compiled in. This script talks to that
service and turns it into something a person — or an LLM asked to "find where
the app is slow" — can read without opening DevTools.

No third-party packages. The WebSocket client below is deliberately small so
the script runs anywhere python3 does, including a stock `python:alpine`.

Subcommands
    status     one-shot: version, isolates, heap, uptime.
    frames     collect `Flutter.Frame` events, report jank percentiles.
    cpu        sample the CPU profiler, report hot functions (self/inclusive).
    timeline   aggregate VM timeline events by name (BUILD/LAYOUT/PAINT/GC...).
    memory     heap usage plus the largest classes by retained size.
    report     all of the above, as one markdown document.
    watch      run `report` forever on an interval, writing files to --out-dir.

Examples
    # against a station, from a machine on the same network
    python3 tools/hmi_profiler.py report --url ws://10.50.10.11:8181/ws

    # against `flutter run --profile` on this machine (auth codes are on, so
    # paste the whole URI the tool printed)
    python3 tools/hmi_profiler.py cpu --url ws://127.0.0.1:53309/cbGW2JoeB_M=/ws

    # inside the compose stack
    docker compose run --rm profiler report --seconds 60
"""

from __future__ import annotations

import argparse
import base64
import collections
import errno
import hashlib
import json
import os
import socket
import ssl
import struct
import sys
import time
import urllib.parse

DEFAULT_URL = os.environ.get("HMI_VM_SERVICE_URI", "ws://flutter:8181/ws")

# A frame is "janky" when it misses its budget. 60 Hz is the panel refresh on
# every station we ship, so the budget is 16.67 ms; the engine reports build
# and raster separately and either one blowing it drops the frame.
FRAME_BUDGET_US = 16667
SEVERE_FRAME_BUDGET_US = FRAME_BUDGET_US * 3

_WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class ProfilerError(Exception):
    """Anything that stops us producing a report."""


class ConnectionClosed(ProfilerError):
    pass


class VmServiceError(ProfilerError):
    def __init__(self, method, error):
        self.method = method
        self.error = error
        super().__init__(f"{method}: {error.get('message', error)}")


# --------------------------------------------------------------------------
# Minimal RFC 6455 client. Text frames only, which is all the VM Service uses.
# --------------------------------------------------------------------------


class WebSocket:
    #: Once a frame header has started arriving the rest of it must follow, so
    #: reads after the first byte use this timeout rather than the caller's
    #: deadline — timing out mid-frame would desynchronise the stream.
    body_timeout = 60.0

    def __init__(self, url, connect_timeout=10.0):
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("ws", "wss"):
            raise ProfilerError(f"not a WebSocket URL: {url!r}")
        port = parsed.port or (443 if parsed.scheme == "wss" else 80)
        host = parsed.hostname
        if not host:
            raise ProfilerError(f"no host in URL: {url!r}")
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query

        self._buf = b""
        self._sock = socket.create_connection((host, port), timeout=connect_timeout)
        if parsed.scheme == "wss":
            self._sock = ssl.create_default_context().wrap_socket(
                self._sock, server_hostname=host
            )
        self._handshake(host, port, path)

    def _handshake(self, host, port, path):
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self._sock.sendall(request.encode("ascii"))

        header = b""
        while b"\r\n\r\n" not in header:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise ConnectionClosed("server closed during handshake")
            header += chunk
        head, _, rest = header.partition(b"\r\n\r\n")
        self._buf = rest

        lines = head.decode("latin-1").split("\r\n")
        if "101" not in lines[0]:
            raise ProfilerError(f"handshake refused: {lines[0]}")
        accept = ""
        for line in lines[1:]:
            name, _, value = line.partition(":")
            if name.strip().lower() == "sec-websocket-accept":
                accept = value.strip()
        expected = base64.b64encode(
            hashlib.sha1((key + _WS_GUID).encode("ascii")).digest()
        ).decode()
        if accept != expected:
            raise ProfilerError("handshake accept key mismatch")

    def _recv_exactly(self, count):
        while len(self._buf) < count:
            try:
                chunk = self._sock.recv(max(4096, count - len(self._buf)))
            except socket.timeout as exc:
                raise TimeoutError("timed out reading from the VM service") from exc
            except OSError as exc:
                if exc.errno == errno.EINTR:
                    continue
                raise ConnectionClosed(str(exc)) from exc
            if not chunk:
                raise ConnectionClosed("server closed the connection")
            self._buf += chunk
        out, self._buf = self._buf[:count], self._buf[count:]
        return out

    def _read_frame(self, timeout):
        # Between frames the buffer sits on a frame boundary, so the caller's
        # deadline only has to cover the wait for the first byte.
        self._sock.settimeout(max(timeout, 0.0))
        first = self._recv_exactly(1)[0]
        self._sock.settimeout(self.body_timeout)

        fin = bool(first & 0x80)
        opcode = first & 0x0F
        second = self._recv_exactly(1)[0]
        masked = bool(second & 0x80)
        length = second & 0x7F
        if length == 126:
            length = struct.unpack(">H", self._recv_exactly(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", self._recv_exactly(8))[0]
        mask = self._recv_exactly(4) if masked else None
        payload = self._recv_exactly(length) if length else b""
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return fin, opcode, payload

    def _send_frame(self, opcode, payload):
        header = bytearray()
        header.append(0x80 | opcode)
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 1 << 16:
            header.append(0x80 | 126)
            header += struct.pack(">H", length)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", length)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self._sock.settimeout(self.body_timeout)
        self._sock.sendall(bytes(header) + masked)

    def send_text(self, text):
        self._send_frame(0x1, text.encode("utf-8"))

    def recv_text(self, timeout=30.0):
        """Return the next text message, answering pings while it waits."""
        deadline = time.monotonic() + timeout
        chunks = []
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 and not chunks:
                raise TimeoutError("timed out waiting for a VM service message")
            fin, opcode, payload = self._read_frame(max(remaining, 0.0))
            if opcode == 0x8:
                raise ConnectionClosed("server sent close")
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode in (0x0, 0x1, 0x2):
                chunks.append(payload)
                if fin:
                    return b"".join(chunks).decode("utf-8")
                continue
            raise ProfilerError(f"unexpected websocket opcode {opcode:#x}")

    def close(self):
        try:
            self._send_frame(0x8, b"")
        except OSError:
            pass
        finally:
            self._sock.close()


# --------------------------------------------------------------------------
# VM Service JSON-RPC
# --------------------------------------------------------------------------


class VmService:
    """JSON-RPC over the socket, with stream events buffered out of the way."""

    def __init__(self, ws):
        self._ws = ws
        self._next_id = 0
        self.events = collections.deque()

    @classmethod
    def connect(cls, url, wait=0.0, connect_timeout=10.0):
        """Connect, retrying for `wait` seconds — containers restart."""
        return cls(cls._open(url, wait, connect_timeout))

    @staticmethod
    def _open(url, wait, connect_timeout):
        deadline = time.monotonic() + wait
        attempt = 0
        while True:
            attempt += 1
            try:
                return WebSocket(url, connect_timeout=connect_timeout)
            except (OSError, ProfilerError) as exc:
                if time.monotonic() >= deadline:
                    raise ProfilerError(
                        f"could not reach the VM service at {url} "
                        f"({exc}). Is the container a profile build with "
                        "FLUTTER_ENGINE_SWITCHES set?"
                    ) from exc
                time.sleep(min(2.0 * attempt, 5.0))

    def reconnect(self, url, wait=0.0, connect_timeout=10.0):
        """Swap in a fresh socket, keeping this object identity — callers
        (and `main`'s cleanup) hold on to the service, not the socket."""
        try:
            self._ws.close()
        except OSError:
            pass
        self._ws = self._open(url, wait, connect_timeout)
        self.events.clear()

    def call(self, method, params=None, timeout=60.0):
        self._next_id += 1
        request_id = str(self._next_id)
        self._ws.send_text(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "method": method,
                    "params": params or {},
                }
            )
        )
        deadline = time.monotonic() + timeout
        while True:
            message = json.loads(self._ws.recv_text(max(deadline - time.monotonic(), 0.0)))
            if message.get("id") == request_id:
                if "error" in message:
                    raise VmServiceError(method, message["error"])
                return message.get("result", {})
            self._buffer(message)

    def _buffer(self, message):
        if message.get("method") == "streamNotify":
            event = message.get("params", {}).get("event")
            if event is not None:
                self.events.append(event)

    def try_call(self, method, params=None, timeout=60.0):
        """Like `call`, but `None` instead of raising. For optional extras."""
        try:
            return self.call(method, params, timeout)
        except (VmServiceError, TimeoutError):
            return None

    def listen(self, stream_id):
        try:
            self.call("streamListen", {"streamId": stream_id})
            return True
        except VmServiceError as exc:
            # Already subscribed is fine; anything else means no such stream.
            return "already" in str(exc.error.get("message", "")).lower()

    def cancel(self, stream_id):
        self.try_call("streamCancel", {"streamId": stream_id}, timeout=10.0)

    def collect_events(self, seconds, kinds=None):
        """Drain events for `seconds`, returning the ones we asked for."""
        collected = list(self.events)
        self.events.clear()
        deadline = time.monotonic() + seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                message = json.loads(self._ws.recv_text(remaining))
            except TimeoutError:
                break
            self._buffer(message)
            collected.extend(self.events)
            self.events.clear()
        if kinds is None:
            return collected
        return [e for e in collected if e.get("extensionKind") in kinds or e.get("kind") in kinds]

    def main_isolate(self):
        vm = self.call("getVM")
        isolates = vm.get("isolates", [])
        if not isolates:
            raise ProfilerError("the VM reports no isolates")
        for isolate in isolates:
            if isolate.get("name") == "main":
                return isolate["id"]
        return isolates[0]["id"]

    def close(self):
        self._ws.close()


# --------------------------------------------------------------------------
# Analysis — pure functions over VM Service payloads, so they can be tested
# without a running app.
# --------------------------------------------------------------------------


def percentile(values, fraction):
    """Nearest-rank percentile. `fraction` is 0..1. Empty list -> 0."""
    if not values:
        return 0
    ordered = sorted(values)
    index = int(round(fraction * (len(ordered) - 1)))
    return ordered[index]


def function_label(functions, index):
    """A readable `Class.method [file.dart]` for a profile function index."""
    if not isinstance(index, int) or index < 0 or index >= len(functions):
        return "???"
    entry = functions[index] or {}
    function = entry.get("function")
    if isinstance(function, dict):
        name = function.get("name") or "???"
        owner = function.get("owner")
        if isinstance(owner, dict):
            owner_name = owner.get("name")
            owner_type = owner.get("type", "")
            if owner_name and "Class" in owner_type:
                name = f"{owner_name}.{name}"
    else:
        name = function or "???"
    url = entry.get("resolvedUrl") or ""
    where = url.rsplit("/", 1)[-1] if url else "native"
    return f"{name} [{where}]"


def package_of(functions, index):
    """`package:tfc/...` -> `tfc`; anything else grouped coarsely."""
    if not isinstance(index, int) or index < 0 or index >= len(functions):
        return "unknown"
    url = (functions[index] or {}).get("resolvedUrl") or ""
    if url.startswith("package:"):
        return url.split(":", 1)[1].split("/", 1)[0]
    if "/packages/" in url:
        return url.split("/packages/", 1)[1].split("/", 1)[0]
    if url.startswith("dart:"):
        return url.split("/", 1)[0]
    if not url:
        return "native"
    return "app"


def fold_cpu_samples(payload, top=25):
    """Fold `getCpuSamples` into self/inclusive/per-package tallies."""
    functions = payload.get("functions", []) or []
    samples = payload.get("samples", []) or []
    self_ticks = collections.Counter()
    inclusive_ticks = collections.Counter()
    package_ticks = collections.Counter()
    counted = 0

    for sample in samples:
        stack = sample.get("stack") or []
        if not stack:
            continue
        counted += 1
        self_ticks[function_label(functions, stack[0])] += 1
        package_ticks[package_of(functions, stack[0])] += 1
        # A recursive frame must not count twice towards inclusive time.
        for index in set(stack):
            inclusive_ticks[function_label(functions, index)] += 1

    def as_rows(counter):
        return [
            {"name": name, "samples": count, "percent": 100.0 * count / counted if counted else 0.0}
            for name, count in counter.most_common(top)
        ]

    return {
        "samples": counted,
        "sample_period_us": payload.get("samplePeriod"),
        "time_span_s": (payload.get("timeExtentMicros") or 0) / 1e6,
        "self": as_rows(self_ticks),
        "inclusive": as_rows(inclusive_ticks),
        "packages": as_rows(package_ticks),
    }


def frame_stats(frames):
    """Turn `Flutter.Frame` extensionData payloads into jank statistics."""
    builds = [f.get("build", 0) for f in frames]
    rasters = [f.get("raster", 0) for f in frames]
    elapsed = [f.get("elapsed", 0) for f in frames]
    janky = [
        f
        for f in frames
        if f.get("build", 0) > FRAME_BUDGET_US or f.get("raster", 0) > FRAME_BUDGET_US
    ]
    severe = [
        f
        for f in frames
        if f.get("build", 0) > SEVERE_FRAME_BUDGET_US
        or f.get("raster", 0) > SEVERE_FRAME_BUDGET_US
    ]
    worst = max(frames, key=lambda f: f.get("elapsed", 0)) if frames else None
    return {
        "frames": len(frames),
        "janky": len(janky),
        "janky_percent": 100.0 * len(janky) / len(frames) if frames else 0.0,
        "severe": len(severe),
        "build_us": {
            "p50": percentile(builds, 0.50),
            "p90": percentile(builds, 0.90),
            "p99": percentile(builds, 0.99),
            "max": max(builds) if builds else 0,
        },
        "raster_us": {
            "p50": percentile(rasters, 0.50),
            "p90": percentile(rasters, 0.90),
            "p99": percentile(rasters, 0.99),
            "max": max(rasters) if rasters else 0,
        },
        "elapsed_us": {
            "p50": percentile(elapsed, 0.50),
            "p90": percentile(elapsed, 0.90),
            "p99": percentile(elapsed, 0.99),
            "max": max(elapsed) if elapsed else 0,
        },
        "worst_frame": worst,
        # Which half of the pipeline to blame: UI thread (build) or GPU (raster).
        "bottleneck": (
            "raster"
            if percentile(rasters, 0.90) > percentile(builds, 0.90)
            else "build"
        )
        if frames
        else "unknown",
    }


def summarise_timeline(payload, top=25):
    """Total/mean/max duration per timeline event name.

    The Dart VM writes `Timeline.startSync`/`finishSync` — which is what the
    framework's BUILD, LAYOUT and PAINT blocks are — as separate `B` and `E`
    trace events, one pair per thread. Only the embedder emits pre-durationed
    `X` events. Both are folded here; anything still open when the buffer ends
    is dropped rather than guessed at.
    """
    totals = collections.Counter()
    counts = collections.Counter()
    peaks = {}
    open_blocks = collections.defaultdict(list)

    def record(name, duration):
        totals[name] += duration
        counts[name] += 1
        peaks[name] = max(peaks.get(name, 0), duration)

    for event in payload.get("traceEvents", []) or []:
        phase = event.get("ph")
        if phase == "X":
            record(event.get("name") or "?", event.get("dur") or 0)
        elif phase == "B":
            open_blocks[(event.get("pid"), event.get("tid"))].append(
                (event.get("name") or "?", event.get("ts") or 0)
            )
        elif phase == "E":
            stack = open_blocks[(event.get("pid"), event.get("tid"))]
            if stack:
                name, start = stack.pop()
                record(name, max((event.get("ts") or 0) - start, 0))

    return [
        {
            "name": name,
            "count": counts[name],
            "total_us": total,
            "mean_us": total // counts[name] if counts[name] else 0,
            "max_us": peaks.get(name, 0),
        }
        for name, total in totals.most_common(top)
    ]


def summarise_allocations(payload, top=25):
    """Largest classes on the heap.

    Current VMs report one flat `ClassHeapStats` per class; older ones split
    it into `newSpace`/`oldSpace`. Read whichever is there.
    """
    rows = []
    for member in payload.get("members", []) or []:
        size = member.get("bytesCurrent")
        instances = member.get("instancesCurrent")
        if size is None:
            old = member.get("oldSpace") or {}
            new = member.get("newSpace") or {}
            size = (old.get("bytesCurrent") or 0) + (new.get("bytesCurrent") or 0)
            instances = (old.get("instancesCurrent") or 0) + (new.get("instancesCurrent") or 0)
        if not size:
            continue
        instances = instances or 0
        name = (member.get("class") or {}).get("name") or "?"
        rows.append({"name": name, "bytes": size, "instances": instances})
    rows.sort(key=lambda row: row["bytes"], reverse=True)
    return rows[:top]


# --------------------------------------------------------------------------
# Collection
# --------------------------------------------------------------------------


def collect_frames(service, seconds):
    listening = service.listen("Extension")
    if not listening:
        raise ProfilerError("the VM refused the Extension stream")
    try:
        events = service.collect_events(seconds, kinds={"Flutter.Frame"})
    finally:
        service.cancel("Extension")
    return [e.get("extensionData") or {} for e in events]


def collect_cpu(service, isolate, seconds, period_us=250):
    # 1000 µs is the VM default; 250 µs gives four times the resolution, which
    # matters when a paint pass is only a couple of milliseconds long.
    service.try_call("setFlag", {"name": "profile_period", "value": str(period_us)}, timeout=10.0)
    service.call("clearCpuSamples", {"isolateId": isolate})
    time.sleep(seconds)
    return service.call(
        "getCpuSamples",
        {"isolateId": isolate, "timeOriginMicros": 0, "timeExtentMicros": 10**15},
        timeout=180.0,
    )


def collect_timeline(service, seconds):
    streams = ["Dart", "Embedder", "GC"]
    if service.try_call("setVMTimelineFlags", {"recordedStreams": streams}) is None:
        return None
    service.try_call("clearVMTimeline")
    time.sleep(seconds)
    payload = service.try_call("getVMTimeline", timeout=180.0)
    service.try_call("setVMTimelineFlags", {"recordedStreams": []})
    return payload


def collect_memory(service, isolate):
    usage = service.try_call("getMemoryUsage", {"isolateId": isolate}) or {}
    allocations = service.try_call("getAllocationProfile", {"isolateId": isolate}, timeout=120.0)
    return usage, allocations or {}


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def ms(micros):
    return f"{(micros or 0) / 1000.0:.1f}"


def render_table(headers, rows):
    if not rows:
        return "_(nothing recorded)_\n"
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    for row in rows:
        out.append("| " + " | ".join(str(cell) for cell in row) + " |")
    return "\n".join(out) + "\n"


def render_frames(stats):
    lines = ["### Frames\n"]
    if not stats["frames"]:
        lines.append(
            "No `Flutter.Frame` events arrived. Either the UI is idle (nothing "
            "is animating and no state changed) or this is a release build, "
            "which does not post them.\n"
        )
        return "\n".join(lines)
    lines.append(
        f"{stats['frames']} frames, {stats['janky']} over the 16.7 ms budget "
        f"({stats['janky_percent']:.1f} %), {stats['severe']} over 50 ms. "
        f"Slower half of the pipeline: **{stats['bottleneck']}**.\n"
    )
    lines.append(
        render_table(
            ["phase", "p50 ms", "p90 ms", "p99 ms", "max ms"],
            [
                [
                    phase,
                    ms(stats[key]["p50"]),
                    ms(stats[key]["p90"]),
                    ms(stats[key]["p99"]),
                    ms(stats[key]["max"]),
                ]
                for phase, key in (
                    ("build (UI thread)", "build_us"),
                    ("raster (GPU thread)", "raster_us"),
                    ("total", "elapsed_us"),
                )
            ],
        )
    )
    return "\n".join(lines)


def render_cpu(folded):
    lines = ["### CPU\n"]
    if not folded["samples"]:
        lines.append(
            "No CPU samples. The isolate was idle, or the engine was started "
            "without `--enable-dart-profiling`.\n"
        )
        return "\n".join(lines)
    lines.append(
        f"{folded['samples']} samples at {folded['sample_period_us'] or '?'} µs.\n"
    )
    lines.append("**Self time** — where the CPU actually burns:\n")
    lines.append(
        render_table(
            ["%", "samples", "function"],
            [[f"{r['percent']:.1f}", r["samples"], r["name"]] for r in folded["self"]],
        )
    )
    lines.append("**Inclusive time** — functions that contain the cost:\n")
    lines.append(
        render_table(
            ["%", "samples", "function"],
            [[f"{r['percent']:.1f}", r["samples"], r["name"]] for r in folded["inclusive"]],
        )
    )
    lines.append("**By package** (self time):\n")
    lines.append(
        render_table(
            ["%", "samples", "package"],
            [[f"{r['percent']:.1f}", r["samples"], r["name"]] for r in folded["packages"]],
        )
    )
    return "\n".join(lines)


def render_timeline(rows):
    lines = ["### Timeline\n"]
    if not rows:
        lines.append(
            "_(no completed timeline blocks — either the VM refused the "
            "timeline streams or nothing ran during the window)_\n"
        )
        return "\n".join(lines)
    lines.append(
        render_table(
            ["event", "count", "total ms", "mean ms", "max ms"],
            [
                [r["name"], r["count"], ms(r["total_us"]), ms(r["mean_us"]), ms(r["max_us"])]
                for r in rows
            ],
        )
    )
    return "\n".join(lines)


def render_memory(usage, classes):
    lines = ["### Memory\n"]
    heap = usage.get("heapUsage")
    if heap is not None:
        lines.append(
            f"Heap {heap / 1e6:.1f} MB of {usage.get('heapCapacity', 0) / 1e6:.1f} MB "
            f"capacity, external {usage.get('externalUsage', 0) / 1e6:.1f} MB.\n"
        )
    lines.append(
        render_table(
            ["class", "MB", "instances"],
            [[r["name"], f"{r['bytes'] / 1e6:.2f}", r["instances"]] for r in classes],
        )
    )
    return "\n".join(lines)


def render_report(data):
    lines = [
        f"# CentroidX profile — {data['collected_at']}",
        "",
        f"`{data['url']}` · isolate `{data['isolate']}` · "
        f"{data['seconds']} s window · Dart VM {data.get('vm_version', '?')}",
        "",
        render_frames(data["frames"]),
        render_cpu(data["cpu"]),
        render_timeline(data["timeline"]),
        render_memory(data["memory_usage"], data["memory_classes"]),
    ]
    if data.get("problems"):
        lines.append("### Not collected\n")
        lines.extend(f"- {problem}" for problem in data["problems"])
        lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def gather(service, seconds, top, want=("frames", "cpu", "timeline", "memory")):
    """Collect one window. Phases run in sequence so they do not perturb
    each other — a timeline recording distorts the CPU profile."""
    isolate = service.main_isolate()
    version = service.try_call("getVersion") or {}
    data = {
        "collected_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "seconds": seconds,
        "isolate": isolate,
        "vm_version": f"{version.get('major', '?')}.{version.get('minor', '?')}",
        "frames": frame_stats([]),
        "cpu": fold_cpu_samples({}),
        "timeline": [],
        "memory_usage": {},
        "memory_classes": [],
        "problems": [],
    }
    problems = []

    def attempt(section, work):
        # One unavailable section must not cost us the other three: a station
        # that answers `getVM` but refuses `getCpuSamples` still has frame
        # timings worth reading.
        if section not in want:
            return
        try:
            work()
        except ConnectionClosed:
            # The app went away. Collecting the remaining sections would only
            # produce three more identical failures; let the caller reconnect.
            raise
        except (ProfilerError, TimeoutError) as exc:
            problems.append(f"{section}: {exc}")

    attempt("frames", lambda: data.update(frames=frame_stats(collect_frames(service, seconds))))
    attempt(
        "cpu",
        lambda: data.update(cpu=fold_cpu_samples(collect_cpu(service, isolate, seconds), top)),
    )

    def do_timeline():
        payload = collect_timeline(service, seconds)
        data["timeline"] = summarise_timeline(payload, top) if payload else []

    attempt("timeline", do_timeline)

    def do_memory():
        usage, allocations = collect_memory(service, isolate)
        data["memory_usage"] = usage or (allocations.get("memoryUsage") or {})
        data["memory_classes"] = summarise_allocations(allocations, top)

    attempt("memory", do_memory)
    data["problems"] = problems
    return data


def emit(args, data, body):
    if args.json:
        text = json.dumps(data, indent=2, sort_keys=True)
    else:
        text = body
    print(text)
    if args.out_dir:
        os.makedirs(args.out_dir, exist_ok=True)
        stamp = time.strftime("%Y%m%dT%H%M%S")
        suffix = "json" if args.json else "md"
        path = os.path.join(args.out_dir, f"profile-{stamp}.{suffix}")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        print(f"\n<!-- written to {path} -->", file=sys.stderr)


def cmd_status(service, args):
    version = service.try_call("getVersion") or {}
    vm = service.call("getVM")
    isolate_id = service.main_isolate()
    usage = service.try_call("getMemoryUsage", {"isolateId": isolate_id}) or {}
    data = {
        "url": args.url,
        "vm_version": f"{version.get('major', '?')}.{version.get('minor', '?')}",
        "name": vm.get("name"),
        "pid": vm.get("pid"),
        "uptime_s": round(vm.get("startTime", 0) and (time.time() - vm["startTime"] / 1000.0), 1),
        "isolates": [i.get("name") for i in vm.get("isolates", [])],
        "main_isolate": isolate_id,
        "heap_mb": round(usage.get("heapUsage", 0) / 1e6, 1),
        "external_mb": round(usage.get("externalUsage", 0) / 1e6, 1),
    }
    body = "\n".join(f"{key:>14}: {value}" for key, value in data.items())
    emit(args, data, body)


def cmd_frames(service, args):
    stats = frame_stats(collect_frames(service, args.seconds))
    emit(args, stats, render_frames(stats))


def cmd_cpu(service, args):
    isolate = service.main_isolate()
    folded = fold_cpu_samples(collect_cpu(service, isolate, args.seconds, args.period), args.top)
    emit(args, folded, render_cpu(folded))


def cmd_timeline(service, args):
    payload = collect_timeline(service, args.seconds)
    rows = summarise_timeline(payload, args.top) if payload else []
    emit(args, rows, render_timeline(rows))


def cmd_memory(service, args):
    usage, allocations = collect_memory(service, service.main_isolate())
    classes = summarise_allocations(allocations, args.top)
    emit(args, {"usage": usage, "classes": classes}, render_memory(usage, classes))


def cmd_report(service, args):
    data = gather(service, args.seconds, args.top)
    data["url"] = args.url
    emit(args, data, render_report(data))


def cmd_watch(service, args):
    """One report per interval, until interrupted. Reconnects if the app
    restarts — a station that crashes is exactly when you want the log."""
    while True:
        started = time.monotonic()
        try:
            data = gather(service, args.seconds, args.top)
            data["url"] = args.url
            emit(args, data, render_report(data))
        except (ProfilerError, TimeoutError) as exc:
            print(f"[{time.strftime('%H:%M:%S')}] lost the VM service: {exc}", file=sys.stderr)
            service.reconnect(args.url, wait=max(args.interval, 30.0))
            continue
        slack = args.interval - (time.monotonic() - started)
        if slack > 0:
            time.sleep(slack)


COMMANDS = {
    "status": cmd_status,
    "frames": cmd_frames,
    "cpu": cmd_cpu,
    "timeline": cmd_timeline,
    "memory": cmd_memory,
    "report": cmd_report,
    "watch": cmd_watch,
}


def build_parser():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", choices=sorted(COMMANDS), help="what to collect")
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help=f"VM service WebSocket URI (default {DEFAULT_URL})",
    )
    parser.add_argument(
        "--seconds", type=float, default=15.0, help="length of each collection window"
    )
    parser.add_argument(
        "--interval", type=float, default=300.0, help="watch: seconds between reports"
    )
    parser.add_argument("--top", type=int, default=25, help="rows per table")
    parser.add_argument(
        "--period", type=int, default=250, help="CPU sampling period in microseconds"
    )
    parser.add_argument(
        "--wait",
        type=float,
        default=0.0,
        help="keep retrying the connection for this many seconds",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    parser.add_argument("--out-dir", default=None, help="also write each report into this directory")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        service = VmService.connect(args.url, wait=args.wait)
    except ProfilerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    try:
        COMMANDS[args.command](service, args)
    except KeyboardInterrupt:
        return 130
    except ProfilerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    finally:
        service.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
