#!/usr/bin/env python3
"""CPU profiler for Flutter apps via the Dart VM Service.

Kept for the old call signature; the work now lives in `hmi_profiler.py`,
which folds the same samples plus frame timings, timeline and heap, and needs
no `websockets` package.

Usage:
  python3 tools/cpu_profile.py ws://127.0.0.1:53309/cbGW2JoeB_M=/ws [seconds]

Get the ws:// URI from the `flutter run --profile` output, or use
`hmi_profiler.py` directly against a station:

  python3 tools/hmi_profiler.py report --url ws://10.50.10.11:8181/ws
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hmi_profiler  # noqa: E402


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 1
    uri, *rest = argv
    duration = rest[0] if rest else "10"
    return hmi_profiler.main(["cpu", "--url", uri, "--seconds", duration])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
