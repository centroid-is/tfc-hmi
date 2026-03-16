import 'dart:async';

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/tools/tool_registry.dart';

void main() {
  group('Semaphore', () {
    test('allows up to maxCount concurrent executions', () async {
      final semaphore = Semaphore(3);
      var running = 0;
      var maxRunning = 0;

      final completers = List.generate(3, (_) => Completer<void>());

      final futures = <Future<int>>[];
      for (var i = 0; i < 3; i++) {
        futures.add(semaphore.run(() async {
          running++;
          if (running > maxRunning) maxRunning = running;
          await completers[i].future;
          running--;
          return i;
        }));
      }

      // Allow microtasks to settle so all 3 can start
      await Future<void>.delayed(Duration.zero);
      expect(maxRunning, equals(3),
          reason: 'All 3 should run concurrently');

      // Complete them all
      for (final c in completers) {
        c.complete();
      }
      final results = await Future.wait(futures);
      expect(results, equals([0, 1, 2]));
    });

    test('queues excess calls and processes them when slots free up', () async {
      final semaphore = Semaphore(2);
      final events = <String>[];
      final completers = List.generate(4, (_) => Completer<void>());

      final futures = <Future<int>>[];
      for (var i = 0; i < 4; i++) {
        futures.add(semaphore.run(() async {
          events.add('start-$i');
          await completers[i].future;
          events.add('end-$i');
          return i;
        }));
      }

      // Let microtasks settle -- only first 2 should start
      await Future<void>.delayed(Duration.zero);
      expect(events, equals(['start-0', 'start-1']),
          reason: 'Only 2 should have started (maxCount=2)');

      // Complete task 0 -- should let task 2 start
      completers[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, contains('start-2'),
          reason: 'Task 2 should start after task 0 frees a slot');

      // Complete task 1 -- should let task 3 start
      completers[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, contains('start-3'),
          reason: 'Task 3 should start after task 1 frees a slot');

      // Complete remaining
      completers[2].complete();
      completers[3].complete();
      final results = await Future.wait(futures);
      expect(results, equals([0, 1, 2, 3]));
    });

    test('releases slot on exception', () async {
      final semaphore = Semaphore(1);
      final events = <String>[];

      // First call throws
      try {
        await semaphore.run<void>(() async {
          events.add('start-0');
          throw StateError('boom');
        });
      } on StateError {
        events.add('caught-0');
      }

      // Second call should proceed (slot was released despite exception)
      await semaphore.run<void>(() async {
        events.add('start-1');
      });

      expect(events, equals(['start-0', 'caught-0', 'start-1']),
          reason: 'Slot should be released even when handler throws');
    });

    test('returns handler result', () async {
      final semaphore = Semaphore(2);
      final result = await semaphore.run(() async => 42);
      expect(result, equals(42));
    });

    test('propagates exception from handler', () async {
      final semaphore = Semaphore(2);
      expect(
        () => semaphore.run<void>(() async => throw ArgumentError('test')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
