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

  final _priority = <Object?>[];
  final _subs = <String, _SubState>{};
  int? _peakSinceMs;

  ConflatingSendBuffer({
    required this.maxPending,
    this.peakThreshold,
    this.peakWindowMs = 10_000,
  });

  int get pendingCount =>
      _priority.length +
      _subs.values.fold(0, (n, s) => n + s.pendingCount);

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

  /// RPC responses, write acks, status, ticks: appended verbatim, flushed
  /// ahead of telemetry, never conflated — a degraded link must still
  /// deliver the news that it is degraded.
  void putPriority(Object? message) => _priority.add(message);

  /// Disconnect policy. Call once per tick with a monotonic timestamp.
  BufferVerdict poll(int nowMs) {
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
  DrainedFrame drain() {
    final priority = List<Object?>.of(_priority);
    _priority.clear();

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
    if (priority.isNotEmpty || subs.isNotEmpty) _peakSinceMs = null;
    return DrainedFrame(priority, subs);
  }
}
