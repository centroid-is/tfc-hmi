#!/usr/bin/env python3
"""
CPU profiler for Flutter apps via VM Service WebSocket.

Usage:
  # Auto-detect VM service URI from running flutter process:
  python3 tools/cpu_profile.py

  # Or provide the WebSocket URI directly:
  python3 tools/cpu_profile.py ws://127.0.0.1:53309/cbGW2JoeB_M=/ws

  # Custom duration (default 10s):
  python3 tools/cpu_profile.py ws://127.0.0.1:53309/xxx/ws 15
"""
import asyncio, json, sys, subprocess, re
from collections import Counter

try:
    import websockets
except ImportError:
    print("pip install websockets")
    sys.exit(1)


def find_vm_service_uri():
    """Try to find the VM service URI from a running flutter process."""
    try:
        result = subprocess.run(
            ["lsof", "-i", "TCP", "-sTCP:LISTEN", "-P", "-n"],
            capture_output=True, text=True, timeout=5
        )
        # Look for Dart VM service ports
        for line in result.stdout.splitlines():
            if "dart" in line.lower() or "flutter" in line.lower():
                match = re.search(r"127\.0\.0\.1:(\d+)", line)
                if match:
                    port = match.group(1)
                    print(f"Found potential VM service on port {port}")
                    return None  # Can't determine full path from lsof
    except Exception:
        pass
    return None


async def profile(ws_uri, duration=10):
    async with websockets.connect(ws_uri, max_size=200_000_000) as ws:
        # 1. Get VM to find main isolate
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": "1", "method": "getVM", "params": {}}))
        vm = json.loads(await ws.recv())
        isolates = vm["result"]["isolates"]

        main_iso = None
        for iso in isolates:
            if iso["name"] == "main":
                main_iso = iso["id"]
                break
        if not main_iso:
            main_iso = isolates[0]["id"]
        print(f"Isolate: {main_iso}")

        # 1b. Boost sampling rate: 1000μs (default) → 250μs (4x more samples)
        await ws.send(json.dumps({
            "jsonrpc": "2.0", "id": "1b",
            "method": "setFlag",
            "params": {"name": "profile_period", "value": "250"}
        }))
        flag_resp = json.loads(await ws.recv())
        if "error" not in flag_resp:
            print("Sampling rate set to 250μs (4x default)")
        else:
            print(f"Could not set sampling rate: {flag_resp.get('error', {}).get('message', '?')}")

        # 2. Clear old samples
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": "2", "method": "clearCpuSamples", "params": {"isolateId": main_iso}}))
        await ws.recv()

        # 3. Wait
        print(f"Recording CPU samples for {duration}s...")
        await asyncio.sleep(duration)

        # 4. Get CPU samples
        await ws.send(json.dumps({
            "jsonrpc": "2.0", "id": "3", "method": "getCpuSamples",
            "params": {"isolateId": main_iso, "timeOriginMicros": 0, "timeExtentMicros": 999999999999999}
        }))
        resp = json.loads(await ws.recv())

        result = resp.get("result", {})
        samples = result.get("samples", [])
        functions = result.get("functions", [])

        print(f"Collected {len(samples)} samples, {len(functions)} functions")
        if not samples:
            print("No samples. Is the app doing work?")
            return

        # 5. Analyze
        self_counts = Counter()
        inclusive_counts = Counter()
        total = len(samples)

        for sample in samples:
            stack = sample.get("stack", [])
            if not stack:
                continue
            top_idx = stack[0]
            if isinstance(top_idx, int) and top_idx < len(functions):
                fn = functions[top_idx]
                rurl = fn.get("resolvedUrl", "")
                name = fn.get("function", "???")
                if isinstance(name, dict):
                    name = name.get("name", "???")
                short_file = rurl.split("/")[-1] if rurl else "native"
                self_counts[f"{name} [{short_file}]"] += 1

            for idx in stack:
                if isinstance(idx, int) and idx < len(functions):
                    fn = functions[idx]
                    rurl = fn.get("resolvedUrl", "")
                    name = fn.get("function", "???")
                    if isinstance(name, dict):
                        name = name.get("name", "???")
                    short_file = rurl.split("/")[-1] if rurl else "native"
                    inclusive_counts[f"{name} [{short_file}]"] += 1

        print(f"\n{'=' * 70}")
        print(f"CPU PROFILE — {total} samples over {duration}s")
        print(f"{'=' * 70}")

        print(f"\n--- TOP 40 SELF TIME (where CPU actually burns) ---")
        for name, count in self_counts.most_common(40):
            pct = 100 * count / total
            bar = "#" * int(pct / 2)
            print(f"  {pct:5.1f}%  {count:5d}  {bar:25s}  {name}")

        print(f"\n--- TOP 40 INCLUSIVE TIME ---")
        for name, count in inclusive_counts.most_common(40):
            pct = 100 * count / total
            print(f"  {pct:5.1f}%  {count:5d}  {name}")

        # Save full profile
        with open("/tmp/cpu_profile_full.json", "w") as f:
            json.dump(result, f)
        print(f"\nFull profile saved to /tmp/cpu_profile_full.json")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 tools/cpu_profile.py <ws://...> [duration_seconds]")
        print("Get the ws:// URI from 'flutter run --profile' output")
        sys.exit(1)

    ws_uri = sys.argv[1]
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    asyncio.run(profile(ws_uri, duration))
