/// The all-keys preference change signal.
///
/// Skeleton — 10-09 task 2's GREEN merges the LISTEN/NOTIFY half in. Right now
/// this carries only writes made through this gateway, which is exactly the
/// gap DB-03 exists to close.
library;

import 'dart:async';

import 'timescale_reader.dart' show DatabaseSupplier;

/// Merges this gateway's own preference writes with everybody else's.
final class PreferenceChangeFeed {
  PreferenceChangeFeed({
    required this.database,
    required Stream<String> local,
    void Function()? invalidate,
    Future<Set<String>> Function()? resync,
    this.window = defaultWindow,
    this.relistenBackoff = defaultRelistenBackoff,
    DateTime Function()? now,
    this.log,
  })  : _local = local,
        _invalidate = invalidate,
        _resync = resync,
        _now = now ?? DateTime.now;

  /// How long after emitting a key another event for it is treated as the
  /// same change.
  static const Duration defaultWindow = Duration(milliseconds: 250);

  /// How long to wait before listening again after the channel dropped.
  static const Duration defaultRelistenBackoff = Duration(seconds: 5);

  final DatabaseSupplier database;
  final Duration window;
  final Duration relistenBackoff;
  final void Function(String message)? log;

  final Stream<String> _local;
  final void Function()? _invalidate;
  final Future<Set<String>> Function()? _resync;
  final DateTime Function() _now;

  StreamSubscription<String>? _localSub;
  bool _closed = false;

  late final StreamController<String> _controller =
      StreamController<String>.broadcast(onListen: _start, onCancel: _stop);

  /// Every key whose value changed. Broadcast, and listener-gated.
  Stream<String> get changes => _controller.stream;

  /// Whether anybody is listening right now.
  bool get hasListener => _controller.hasListener;

  /// Whether the cross-process channel is currently subscribed.
  bool get channelUp => false;

  void _start() {
    _localSub = _local.listen((key) {
      if (!_closed && !_controller.isClosed) _controller.add(key);
    });
  }

  void _stop() {
    unawaited(_localSub?.cancel().catchError((Object _) {}));
    _localSub = null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _localSub?.cancel();
    _localSub = null;
    await _controller.close();
  }
}
