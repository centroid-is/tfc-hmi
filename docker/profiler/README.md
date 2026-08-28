# hmi-profiler

Turns the Dart VM Service of a running CentroidX into a markdown report:
frame build/raster percentiles, the hot functions behind them, the timeline
blocks (`BUILD`/`LAYOUT`/`PAINT`, GC) and the largest classes on the heap.

The point is to make "why is this station sluggish" answerable from a
terminal — or by an agent — without attaching DevTools to a machine in a fish
factory.

## What has to be true

The app must be a **profile** build. Release strips the VM Service, the CPU
profiler and the `Flutter.Frame` events out of the engine entirely, so there
is nothing to connect to.

`ghcr.io/centroid-is/centroid-hmi:latest-release` is that profile build (see
`.github/workflows/centroid-hmi.yml`). It is AOT-compiled like release — the
performance numbers it reports are real, unlike a debug/JIT build — and pays
for the instrumentation with a slightly larger binary and the sampling
profiler's overhead while a profile is actually being taken.

The engine then needs four switches. The flutter-elinux embedder reads them
from the environment (`GetSwitchesFromEnvironment`), which is why they are
plain compose `environment:` entries rather than command-line arguments:

```yaml
FLUTTER_ENGINE_SWITCHES: 4
FLUTTER_ENGINE_SWITCH_1: enable-dart-profiling      # without this getCpuSamples returns "Feature is disabled"
FLUTTER_ENGINE_SWITCH_2: vm-service-port=8181       # otherwise a random port, printed once, to the log
FLUTTER_ENGINE_SWITCH_3: vm-service-host=0.0.0.0    # otherwise 127.0.0.1, unreachable from another container
FLUTTER_ENGINE_SWITCH_4: disable-service-auth-codes # otherwise the ws path contains a per-boot secret
```

## Security

Anyone who can open that port can read the app's memory, evaluate Dart in its
isolate and restart it. Port 8181 is therefore **not published to the host** in
`docker-compose.yml` — it is reachable only from another container on the
compose network. To use it from your laptop, tunnel:

```sh
ssh -L 8181:localhost:8181 centroid@<station>   # only if the host can route to the container
```

or, more reliably, run the collection on the station and copy the reports out.

## Using it

```sh
# opt in — the service sits behind a compose profile so it never runs by default
docker compose --profile profiling up -d profiler
docker compose logs -f profiler

# one-shot, straight to your terminal
docker compose run --rm profiler report --seconds 30

# just the hot functions, JSON for something else to chew on
docker compose run --rm profiler cpu --seconds 20 --json

# from a checkout, against anything reachable
python3 tools/hmi_profiler.py report --url ws://10.50.10.11:8181/ws
```

Reports written by the `watch` command land in the `profiler-reports` volume:

```sh
docker compose cp profiler:/reports ./profiler-reports
```

## Reading the output

- **Frames.** Anything over 16.7 ms dropped a frame at 60 Hz. The
  `bottleneck` line says which half of the pipeline to look at: `build` is the
  UI thread — Dart, widget rebuilds, layout — and is yours to fix; `raster` is
  the GPU thread, usually too much overdraw, a saveLayer, or an image being
  resized every frame.
- **CPU self time** is where cycles actually burn. **Inclusive** time tells
  you which caller to delete instead.
- **Timeline** totals are per 15-second window, so a `PAINT` total near the
  window length means the app is painting continuously.
- **Memory** is a snapshot, not a leak detector; run it twice and compare.

An idle HMI posts no frames at all. If the Frames section is empty, make
something move on screen before believing the app is fast.
