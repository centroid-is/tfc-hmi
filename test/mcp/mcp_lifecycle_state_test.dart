import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../../lib/mcp/mcp_lifecycle_state.dart';

/// Minimal stub implementing the same dispose() contract as StateManStateReader.
class _FakeStateReader {
  bool disposed = false;
  void dispose() => disposed = true;
}

void main() {
  group('McpLifecycleState', () {
    late McpLifecycleState state;

    setUp(() {
      state = McpLifecycleState();
    });

    tearDown(() {
      state.dispose();
    });

    test('initial state has no reader and no timer', () {
      expect(state.activeStateReader, isNull);
      expect(state.reconnectTimer, isNull);
    });

    test('activeStateReader can be set and retrieved', () {
      final reader = _FakeStateReader();
      state.activeStateReader = reader;
      expect(state.activeStateReader, same(reader));
    });

    test('reconnectTimer can be set and retrieved', () {
      final timer = Timer(const Duration(seconds: 1), () {});
      addTearDown(timer.cancel);
      state.reconnectTimer = timer;
      expect(state.reconnectTimer, same(timer));
    });

    test('disposeReader nulls out activeStateReader', () {
      final reader = _FakeStateReader();
      state.activeStateReader = reader;
      state.disposeReader();
      expect(state.activeStateReader, isNull);
    });

    test('cancelTimer cancels and nulls reconnectTimer', () {
      var fired = false;
      state.reconnectTimer = Timer(const Duration(milliseconds: 50), () {
        fired = true;
      });
      state.cancelTimer();
      expect(state.reconnectTimer, isNull);
      // Timer should not fire after cancellation
      expect(fired, isFalse);
    });

    test('dispose cancels timer', () {
      state.reconnectTimer = Timer(const Duration(seconds: 1), () {});
      state.dispose();
      expect(state.reconnectTimer, isNull);
    });
  });
}
