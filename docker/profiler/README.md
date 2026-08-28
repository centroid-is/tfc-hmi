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

`ghcr.io/centroid-is/centroid-hmi:latest-profile` is that profile build (see
`.github/workflows/centroid-hmi.yml`). It is AOT-compiled like release — the
performance numbers it reports are real, unlike a debug/JIT build — and pays
for the instrumentation with a slightly larger binary and the sampling
profiler's overhead while a profile is actually being taken.

The engine then needs three switches. The flutter-elinux embedder reads them
from the environment (`GetSwitchesFromEnvironment`), which is why they are
plain compose `environment:` entries rather than command-line arguments:

```yaml
FLUTTER_ENGINE_SWITCHES: 3
FLUTTER_ENGINE_SWITCH_1: enable-dart-profiling      # without this getCpuSamples returns "Feature is disabled"
FLUTTER_ENGINE_SWITCH_2: vm-service-port=8181       # otherwise a random port, printed once, to the log
FLUTTER_ENGINE_SWITCH_3: disable-service-auth-codes # otherwise the ws path contains a per-boot secret
```

## Why a sidecar, and why it still is not exposed

Anyone who can open that port can read the app's memory, evaluate Dart in its
isolate and restart it. So it keeps the VM service's **default 127.0.0.1
bind** — there is no `vm-service-host` switch and no `ports:` entry — and the
profiler reaches it by sharing the flutter container's network namespace
(`network_mode: "service:flutter"`). That container's `127.0.0.1` *is* the
app's loopback.

Measured, because it is the whole security argument:

| from | result |
|---|---|
| sidecar with `network_mode: service:flutter` | connects |
| sibling container on the compose network | `ECONNREFUSED` |
| plant network | no published port |

That gets the isolation of running the script inside the app container without
any of its costs:

- **The app has a 1 GB limit.** A CPU-sample response for a real window is tens
  of megabytes of JSON. A diagnostic must never be the thing that OOM-kills the
  HMI an operator is using — so the profiler carries its own 512 MB budget.
- **Updating the profiler would otherwise mean republishing and restarting the
  app image**, disturbing the thing being measured and blanking a screen on a
  production line to change a tool.
- **It reconnects across app restarts**, so the reports either side of a crash
  survive. A process inside the container dies with it — losing exactly the
  window you wanted.
- The image also stays a generic tool you can point at a dev machine's
  `flutter run --profile` or at a tunnel.

The one cost: recreating `flutter` destroys the namespace the profiler is
attached to, so recreate the profiler too. Rare, since it is normally not
running.

To profile from your laptop instead, tunnel to the station and run the script
from a checkout, or run the collection on the station and copy the reports out.

## Using it

```sh
# opt in — the service sits behind a compose profile so it never runs by default
docker compose --profile profiling up -d profiler
docker compose logs -f profiler

# one-shot, straight to your terminal
docker compose run --rm profiler report --seconds 30

# just the hot functions and the call tree behind them
docker compose run --rm profiler cpu --seconds 20

# keep hunting for hiccups while somebody drives the screen
docker compose run --rm profiler slow --seconds 20 --repeat

# containers, threads and the database — works even if the app is wedged
docker compose run --rm profiler system --seconds 10

# from a checkout, against anything reachable
python3 tools/hmi_profiler.py report --url ws://10.50.10.11:8181/ws
```

Reports written by the `watch` command land in the `profiler-reports` volume:

```sh
docker compose cp profiler:/reports ./profiler-reports
```

## Finding the hiccup, not just the average

Aggregates hide the thing you are looking for. A 40 ms stall once a second is
invisible in a mean and obvious to an operator.

`slow` looks for timeline blocks that took far longer than the **median for
their own name** — 12 ms is catastrophic for a paint and unremarkable for a
page load, so an absolute threshold alone is useless — and then dumps the call
tree built only from samples taken inside that block's window:

```
**RENDER** — 16.6 ms, 163x its median of 0.1 ms (seen 634x)

100.0%  ... -> Timeline.timeSync -> <closure> -> slowPath [app.dart] x15 deep (self 2%)
   97.6%  fib [app.dart] x12 deep (self 98%)
```

That correlation works because the VM timeline and the CPU profiler share the
same monotonic clock — verified against a live VM, where 7144 of 7302 samples
fell inside the recorded timeline span.

A window with **no** samples in it is reported explicitly rather than left
blank: it means the thread was blocked, not computing — waiting on I/O, a
lock, or the platform thread — which is a different bug with a different fix.

Tuning: `--slow-factor` (default 3x the median), `--slow-floor-ms` (default 8,
so a 0.2 ms block being 20x its median is ignored), `--keep`, `--repeat`.

## Three layers, one document

A slow HMI is not always a slow *Dart* HMI, and the Dart VM Service can only
see one of the three places the problem might be.

| layer | what it answers | how |
|---|---|---|
| Dart VM Service | which code is hot, which frames dropped, what the heap holds | websocket to the app |
| OS | is the **raster** thread pegged while the UI thread idles; how much RSS is *outside* the Dart heap | `/proc`, via a shared PID namespace |
| Stack | is any container near its memory limit; is the database the one that is slow | Docker API + `psql` |

The middle row matters more than it looks. `getMemoryUsage` reports the Dart
heap; the engine, Skia, pdfium and open62541 all allocate outside it. An app
can show an 80 MB heap while RSS sits at 950 MB of a 1 GB limit, and the report
calls that out explicitly rather than leaving you to notice.

`report` collects all three over one wall-clock window. `system` collects the
bottom two and **needs no VM service**, so it still answers when the app is
wedged and the service will not respond — which is when you most want it.

### What it needs

- **Threads**: `pid: "service:flutter"` on the profiler service. Without it,
  `/proc` shows only the profiler itself and the section says so.
- **Containers**: the Docker socket, plus `group_add` with the host's docker
  GID. That GID is station-specific (`getent group docker`) — get it wrong and
  you lose this one section, with the report telling you why. Mounting the
  socket is a real grant: the Docker API is root on the host however it is
  mounted. `--no-docker` opts out.
- **Database**: `CENTROID_PG*`, the same credentials the backend uses. Only
  `pg_stat_*` views are read. `pg_stat_statements` is not preloaded by the
  timescaledb image, so that one table is normally absent and reported as such;
  the other four work regardless.

### What is not covered

`centroidx-backend` gets container and (with a second profiler instance
pointed at it) thread-level figures, but **no call trees**. It is built with
`dart build cli`, which produces product-mode AOT with the service protocol
compiled out — confirmed: the executable ignores `--enable-vm-service`
entirely. Dart-level profiling of the backend needs a JIT-runtime image
variant, and that variant would be *slower* than the AOT one, so it is a
diagnostic to swap in temporarily rather than something to run permanently.

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
