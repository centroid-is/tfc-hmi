import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Tests for the health monitor error handling pattern used in database_drift.dart.
///
/// The actual `_startPoolHealthMonitor` is private and runs inside a Drift isolate,
/// so we test the equivalent error handling pattern in isolation to verify that
/// SocketException and other errors cannot escape and kill the isolate.
void main() {
  group('Pool health monitor error resilience', () {
    test('runZonedGuarded catches SocketException that escapes try-catch',
        () async {
      // Simulate the scenario: a SocketException thrown asynchronously
      // that bypasses the inner try-catch (e.g., from native socket layer).
      final caughtErrors = <Object>[];

      runZonedGuarded(() {
        // Simulate the fire-and-forget monitor pattern
        unawaited(Future<void>(() async {
          // This throw simulates a SocketException escaping the inner catch
          throw const SocketException('Connection reset by peer');
        }));
      }, (error, stack) {
        caughtErrors.add(error);
      });

      // Give microtask queue time to process
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(caughtErrors, hasLength(1));
      expect(caughtErrors.first, isA<SocketException>());
    });

    test('runZonedGuarded catches arbitrary exceptions from monitor', () async {
      final caughtErrors = <Object>[];

      runZonedGuarded(() {
        unawaited(Future<void>(() async {
          throw StateError('Unexpected state in connection pool');
        }));
      }, (error, stack) {
        caughtErrors.add(error);
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(caughtErrors, hasLength(1));
      expect(caughtErrors.first, isA<StateError>());
    });

    test('health monitor loop continues after catching inner error', () async {
      // Simulate the monitor() loop pattern with error recovery
      var iterations = 0;
      var errorsCaught = 0;
      final completer = Completer<void>();

      runZonedGuarded(() {
        unawaited(Future<void>(() async {
          // Simulate 3 iterations of the monitor loop
          while (iterations < 3) {
            try {
              iterations++;
              if (iterations <= 2) {
                // First two iterations fail (simulating conn.closed throwing)
                throw const SocketException('Network unreachable');
              }
              // Third iteration succeeds
            } catch (_) {
              errorsCaught++;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          completer.complete();
        }));
      }, (error, stack) {
        // Outer zone handler — should NOT be reached since inner catch handles it
        fail('Error should have been caught by inner try-catch: $error');
      });

      await completer.future.timeout(const Duration(seconds: 2));

      expect(iterations, 3, reason: 'Monitor should have run 3 iterations');
      expect(errorsCaught, 2,
          reason: 'Two SocketExceptions should have been caught');
    });

    test('SendPort receives false when zone catches escaped error', () async {
      // Simulate the exact pattern: monitor sends health status via SendPort,
      // and the zone error handler sends false on uncaught errors
      final receivePort = ReceivePort();
      final sendPort = receivePort.sendPort;
      final healthEvents = <bool>[];

      final subscription = receivePort.listen((message) {
        healthEvents.add(message as bool);
      });

      runZonedGuarded(() {
        unawaited(Future<void>(() async {
          sendPort.send(true); // Connection acquired
          // Simulate escaped SocketException
          throw const SocketException('Broken pipe');
        }));
      }, (error, stack) {
        // Last-resort handler sends false — prevents isolate death
        sendPort.send(false);
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(healthEvents, [true, false],
          reason:
              'Should receive true (connected) then false (zone caught error)');

      await subscription.cancel();
      receivePort.close();
    });

    test(
        'inner try-catch around conn.closed handles SocketException without zone fallback',
        () async {
      // The primary defense: inner try-catch around the conn.closed equivalent
      var innerCatchTriggered = false;
      var zoneCatchTriggered = false;

      runZonedGuarded(() {
        unawaited(Future<void>(() async {
          try {
            // Simulate: await conn.closed throwing SocketException
            await Future<void>.error(
                const SocketException('Connection reset by peer'));
          } catch (_) {
            innerCatchTriggered = true;
          }
        }));
      }, (error, stack) {
        zoneCatchTriggered = true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(innerCatchTriggered, isTrue,
          reason: 'Inner catch should handle SocketException');
      expect(zoneCatchTriggered, isFalse,
          reason: 'Zone handler should NOT be triggered when inner catch works');
    });

    test(
        'zone catches error even when inner try-catch is bypassed by native layer',
        () async {
      // Simulate the edge case: error thrown OUTSIDE the try-catch scope
      // (e.g., from a native callback or Future chain that escapes the catch)
      var zoneCatchTriggered = false;
      Object? caughtError;

      runZonedGuarded(() {
        // This simulates an error thrown from a callback registered BEFORE
        // the try-catch, which runs after the catch block completes
        Timer(const Duration(milliseconds: 5), () {
          throw const SocketException('Native socket layer error');
        });
      }, (error, stack) {
        zoneCatchTriggered = true;
        caughtError = error;
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(zoneCatchTriggered, isTrue,
          reason: 'Zone should catch errors from native callbacks');
      expect(caughtError, isA<SocketException>());
    });

    test('monitor pattern with delay between retries survives repeated errors',
        () async {
      // Verify the full pattern: loop + catch + delay + retry
      final receivePort = ReceivePort();
      final sendPort = receivePort.sendPort;
      final healthEvents = <bool>[];
      var loopCount = 0;

      final subscription = receivePort.listen((message) {
        healthEvents.add(message as bool);
      });

      final completer = Completer<void>();

      runZonedGuarded(() {
        unawaited(Future<void>(() async {
          // Simulate pool.isOpen returning true for 3 iterations then false
          while (loopCount < 3) {
            try {
              loopCount++;
              sendPort.send(true); // withConnection acquired
              // Simulate conn.closed throwing
              throw const SocketException('Connection lost');
            } catch (e) {
              sendPort.send(false);
            }
            // Shortened delay for test
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          completer.complete();
        }));
      }, (error, stack) {
        // Should not be reached — inner catch handles everything
        sendPort.send(false);
      });

      await completer.future.timeout(const Duration(seconds: 2));

      expect(loopCount, 3);
      // Pattern: true, false, true, false, true, false
      expect(healthEvents, [true, false, true, false, true, false]);

      await subscription.cancel();
      receivePort.close();
    });
  });
}
