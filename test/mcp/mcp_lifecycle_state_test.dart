import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/mcp/mcp_lifecycle_state.dart';

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

    test('initial state has no reader, no timer, and listener not set up', () {
      expect(state.activeStateReader, isNull);
      expect(state.reconnectTimer, isNull);
      expect(state.toggleListenerSetUp, isFalse);
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

    test('toggleListenerSetUp can be toggled', () {
      state.toggleListenerSetUp = true;
      expect(state.toggleListenerSetUp, isTrue);
      state.toggleListenerSetUp = false;
      expect(state.toggleListenerSetUp, isFalse);
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

    test('dispose cancels timer and resets toggleListenerSetUp', () {
      state.reconnectTimer = Timer(const Duration(seconds: 1), () {});
      state.toggleListenerSetUp = true;
      state.dispose();
      expect(state.reconnectTimer, isNull);
      expect(state.toggleListenerSetUp, isFalse);
    });
  });
}
