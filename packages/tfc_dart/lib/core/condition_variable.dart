import 'dart:async';
import 'dart:collection';

// FIFO Queue for async operations, should sleep the process while waiting.
class CV {
  Future<void> wait() {
    _waiters.add(Completer<void>());
    return _waiters.last.future;
  }

  void releaseOne() {
    if (_waiters.isEmpty) return;
    final handle = _waiters.removeFirst();
    handle.complete();
  }

  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
}
