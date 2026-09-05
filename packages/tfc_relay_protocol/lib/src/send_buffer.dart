/// Per-client bounded, conflating send buffer — the fault-tolerance core
/// from relay-comm-design.md §5 (notes §7.6), with the disconnect policies
/// Home Assistant's websocket_api proved in production
/// (pending-overflow: immediate; sustained-peak: after a grace window).
///
/// Pure state machine: no I/O, no clock — callers pass timestamps, so every
/// behavior is deterministic under test.
library;

import 'methods.dart';
import 'quality.dart';
import 'result_too_large.dart';
import 'wire_value.dart';

sealed class BufferVerdict {
  const BufferVerdict();
}

final class BufferOk extends BufferVerdict {
  const BufferOk();
}

/// The connection should be closed: converting silent server-heap growth
/// (dart:io WebSocket has no bufferedAmount and buffers unboundedly) into a
/// visible reconnect.
final class BufferDisconnect extends BufferVerdict {
  final int closeCode;
  final String reason;
  const BufferDisconnect(this.closeCode, this.reason);
}

/// One drained frame: priority messages first (never conflated, never
/// dropped), then per-subscription telemetry.
final class DrainedFrame {
  final List<Object?> priority;
  final Map<String, PendingSub> subs;
  const DrainedFrame(this.priority, this.subs);

  bool get isEmpty => priority.isEmpty && subs.isEmpty;
}

final class PendingSub {
  final Map<int, WireValue> changes;
  final Map<int, Quality> qualities;
  final List<int> removed;
  const PendingSub(this.changes, this.qualities, this.removed);
}

final class _SubState {
  final changes = <int, WireValue>{};
  final qualities = <int, Quality>{};
  final removed = <int>{};

  int get pendingCount => changes.length + qualities.length + removed.length;
  bool get isEmpty => pendingCount == 0;
}

final class ConflatingSendBuffer {
  /// Hard ceiling on pending entries; exceeding it is an immediate
  /// disconnect verdict (HA: MAX_PENDING_MSG).
  final int maxPending;

  /// Soft ceiling: staying above it for [peakWindowMs] continuously means
  /// the client cannot keep up (HA: PENDING_MSG_PEAK / PEAK_TIME).
  final int? peakThreshold;
  final int peakWindowMs;

  /// Ceiling on **bytes** held in the priority lane, or null for none.
  ///
  /// [maxPending] counts entries, and entries say nothing about size
  /// (03-REVIEW WR-04). The amplifier that makes that matter is json_rpc_2's
  /// own parse-error responder: `respondToFormatExceptions`
  /// (`json_rpc_2-4.1.0/lib/src/utils.dart:60-70`) answers with
  /// `exception.serialize(formatException.source)`, and `source` for a failed
  /// `jsonDecode` is the *entire offending text*. One megabyte-scale garbage
  /// frame therefore becomes one megabyte-scale error response appended
  /// verbatim into this lane, held until the next tick — and 4096 of those is
  /// a heap, not a queue.
  ///
  /// **Only the priority lane is counted**, deliberately. Telemetry is
  /// conflated, so it is bounded by the number of watched handles no matter
  /// how fast the plant moves, and measuring a `WireValue`'s size would mean
  /// encoding it on the hot path to find out. The priority lane is the one
  /// that appends whatever it is handed.
  final int? maxPendingBytes;

  final _priority = <Object?>[];
  final _subs = <String, _SubState>{};
  int? _peakSinceMs;
  int _priorityBytes = 0;

  ConflatingSendBuffer({
    required this.maxPending,
    this.peakThreshold,
    this.peakWindowMs = 10_000,
    this.maxPendingBytes,
  });

  int get pendingCount =>
      _priority.length +
      _subs.values.fold(0, (n, s) => n + s.pendingCount);

  /// Bytes held in the priority lane, as counted by [putPriority].
  int get pendingBytes => _priorityBytes;

  /// What one priority entry is charged.
  ///
  /// An already-encoded frame is charged its own length — the exact number,
  /// and the only shape big enough to matter. A structured message is charged
  /// a flat nominal cost rather than encoded to find out: those are server-
  /// built announcements (`resync`, `status`) of a known small shape, and
  /// paying an encode per put to measure them would put the cost on the path
  /// this whole class exists to keep cheap.
  static const nominalMessageBytes = 256;

  static int _cost(Object? message) =>
      message is String ? message.length : nominalMessageBytes;

  _SubState _sub(String sub) => _subs.putIfAbsent(sub, _SubState.new);

  /// Telemetry: last value wins per (sub, handle). A pending removal of the
  /// same handle is superseded.
  void putValue(String sub, int handle, WireValue value) {
    final s = _sub(sub);
    s.removed.remove(handle);
    s.qualities.remove(handle); // the value carries its own quality
    s.changes[handle] = value;
  }

  /// Quality-only transition (value unchanged upstream).
  ///
  /// Composes rather than replaces when the pending value is already flagged
  /// non-finite: that band is a property of the *value*, the pending value was
  /// sanitized to null when it was put, and a quality-only transition is by
  /// definition not news about the value. Letting it win outright would land
  /// an open-circuit 4–20 mA reading at the client as `null` under good
  /// quality — a blank box that looks like an unbound tag rather than a fault.
  void putQuality(String sub, int handle, Quality quality) {
    final s = _sub(sub);
    final pendingValue = s.changes[handle];
    if (pendingValue != null) {
      final composed = pendingValue.q == Quality.badNonFinite
          ? Quality.worst([quality, Quality.badNonFinite])
          : quality;
      s.changes[handle] =
          WireValue.of(pendingValue.v, quality: composed, t: pendingValue.t);
    } else {
      s.qualities[handle] = quality;
    }
  }

  /// The handle is gone from availability; supersedes any pending state.
  void remove(String sub, int handle) {
    final s = _sub(sub);
    s.changes.remove(handle);
    s.qualities.remove(handle);
    s.removed.add(handle);
  }

  /// Forgets everything pending for [sub].
  ///
  /// For a subscription being **re-established** under the same name: the
  /// snapshot the client is about to be handed was read from the source a
  /// moment ago, and anything still in this lane was put there before it. Left
  /// alone, that older reading is emitted on the next tick with the new
  /// generation and a sequence the client accepts, so the mimic goes backwards
  /// under good quality — which is the same failure the generation exists to
  /// stop, arriving by a different door.
  void dropSub(String sub) => _subs.remove(sub);

  /// RPC responses, write acks, status, ticks: appended verbatim, flushed
  /// ahead of telemetry, never conflated — a degraded link must still
  /// deliver the news that it is degraded.
  ///
  /// ## One entry may not exceed the whole lane (10-REVIEW WR-05)
  ///
  /// Until this check, `putPriority` accepted anything and only [poll]
  /// measured — one tick later, by which time the entry is already held. That
  /// is a gap rather than a delay, because the entry does not have to survive
  /// until the next tick to do harm: `closeSocket` calls `flushPriority`,
  /// which drains and **writes the whole lane out before the close code**, so
  /// an entry too big for the lane is written to the socket on the way to the
  /// eviction it caused.
  ///
  /// The condition is deliberately `cost > ceiling` and not
  /// `_priorityBytes + cost > ceiling`. This is an invariant about a single
  /// entry — one that can never be held no matter how empty the lane is — and
  /// not a second backpressure policy. Accumulation stays [poll]'s question,
  /// which is where the grace window and the disconnect verdict live; a door
  /// that refused on accumulation would evict a well-behaved client for
  /// arriving second.
  ///
  /// **Throwing is the honest answer here and it has a cost.** The caller is
  /// `SessionSink.add`, which is json_rpc_2's write half, so there is no
  /// request id in scope to refuse *to* — see `SessionSink.add` for what it
  /// does with this and what the caller sees. That is why every handler that
  /// can build a large answer is bounded by `data_handlers.dart`'s `_sized`
  /// first, where the refusal can name the request: this is the backstop
  /// behind those, not a substitute for them.
  void putPriority(Object? message) {
    final cost = _cost(message);
    final ceiling = maxPendingBytes;
    if (ceiling != null && cost > ceiling) {
      throw ResultTooLarge.bytes(
        limit: ceiling,
        measured: cost,
        detail: 'one response cannot exceed the whole priority lane, however '
            'empty the lane is. Nothing was queued, so the session is not '
            'evicted for it',
        suggestion: 'a narrower request, or the bounded form of this method',
      );
    }
    _priority.add(message);
    _priorityBytes += cost;
  }

  /// Disconnect policy. Call once per tick with a monotonic timestamp,
  /// **before** [drain].
  ///
  /// [poll] — not [drain] — is the only thing that decides a client has
  /// recovered, and it decides it on the count it measured before the drain
  /// emptied the buffer. See [drain] for why that used to be untrue.
  BufferVerdict poll(int nowMs) {
    final byteCeiling = maxPendingBytes;
    if (byteCeiling != null && _priorityBytes > byteCeiling) {
      return BufferDisconnect(
          CloseCodes.backpressureOverrun,
          'pending priority bytes ($_priorityBytes) exceeded the byte limit '
          '($byteCeiling)');
    }
    final pending = pendingCount;
    if (pending > maxPending) {
      return BufferDisconnect(CloseCodes.backpressureOverrun,
          'pending messages ($pending) exceeded hard limit ($maxPending)');
    }
    final threshold = peakThreshold;
    if (threshold != null) {
      if (pending > threshold) {
        _peakSinceMs ??= nowMs;
        if (nowMs - _peakSinceMs! > peakWindowMs) {
          return BufferDisconnect(CloseCodes.backpressureOverrun,
              'client unable to keep up: > $threshold pending for '
              '${peakWindowMs}ms');
        }
      } else {
        _peakSinceMs = null;
      }
    }
    return const BufferOk();
  }

  /// Drains everything pending. The buffer is empty afterwards — recovery
  /// never has a backlog to flush.
  ///
  /// **Draining is not evidence that the client caught up** (03-REVIEW WR-02).
  /// This used to clear `_peakSinceMs` whenever it drained anything, and the
  /// tick engine drains every tick — so [poll] could only ever see
  /// `_peakSinceMs == null` or `== nowMs`, the window never accumulated, and
  /// the soft verdict was unreachable in production. Only `maxPending` bit.
  /// On `dart:io` WebSockets `sink.add` never blocks and tells us nothing, so
  /// a completed drain says only that the frames left this process. What
  /// [poll] measures across ticks is therefore the *production* rate for one
  /// client staying above the soft ceiling continuously — see
  /// `server_config.dart`'s `peakThreshold`, which says so in the same words a
  /// reader will find at the other end.
  DrainedFrame drain() {
    final priority = List<Object?>.of(_priority);
    _priority.clear();
    _priorityBytes = 0;

    final subs = <String, PendingSub>{};
    _subs.forEach((name, s) {
      if (s.isEmpty) return;
      subs[name] = PendingSub(
        Map.of(s.changes),
        Map.of(s.qualities),
        List.of(s.removed),
      );
    });
    _subs.clear();
    return DrainedFrame(priority, subs);
  }
}
