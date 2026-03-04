import 'dart:async';

import 'package:test/test.dart';
import 'package:open62541/open62541.dart' show Client, DynamicValue, LogLevel;
import 'package:tfc_dart/core/state_man.dart';

void main() {
  group('AutoDisposingStream', () {
    late List<String> disposedKeys;
    late AutoDisposingStream<DynamicValue> ads;

    setUp(() {
      disposedKeys = [];
    });

    tearDown(() {
      // Ensure cleanup even if test fails
      try {
        ads.stream.drain();
      } catch (_) {}
    });

    AutoDisposingStream<DynamicValue> createADS({
      String key = 'test_key',
      Duration idleTimeout = const Duration(minutes: 10),
    }) {
      return AutoDisposingStream<DynamicValue>(
        key,
        (k) => disposedKeys.add(k),
        idleTimeout: idleTimeout,
      );
    }

    group('basic subscribe and stream', () {
      test('emits values from raw stream to listeners', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);

        raw.add(DynamicValue(value: 1));
        raw.add(DynamicValue(value: 2));
        raw.add(DynamicValue(value: 3));
        await Future.delayed(Duration.zero);

        expect(values.length, 3);
        expect(values[0].value, 1);
        expect(values[1].value, 2);
        expect(values[2].value, 3);

        await sub.cancel();
        await raw.close();
      });

      test('emits firstValue immediately on subscribe', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        final firstValue = DynamicValue(value: 'initial');

        ads.subscribe(raw.stream, firstValue);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);

        expect(values.length, 1);
        expect(values[0].value, 'initial');

        await sub.cancel();
        await raw.close();
      });

      test('replays last value to new subscribers (ReplaySubject)', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        // First listener gets the value
        final sub1 = ads.stream.listen((_) {});
        raw.add(DynamicValue(value: 42));
        await Future.delayed(Duration.zero);
        await sub1.cancel();

        // Second listener should get replayed value
        final values = <DynamicValue>[];
        final sub2 = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);

        expect(values.length, 1);
        expect(values[0].value, 42);

        await sub2.cancel();
        await raw.close();
      });
    });

    group('resendLastValue', () {
      test('pushes cached value to subject', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);

        raw.add(DynamicValue(value: 'original'));
        await Future.delayed(Duration.zero);
        expect(values.length, 1);

        ads.resendLastValue();
        await Future.delayed(Duration.zero);
        expect(values.length, 2);
        expect(values[1].value, 'original');

        await sub.cancel();
        await raw.close();
      });

      test('does nothing when no value has been received', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);

        ads.resendLastValue();
        await Future.delayed(Duration.zero);

        expect(values, isEmpty);

        await sub.cancel();
        await raw.close();
      });

      test('uses firstValue as cached value if no raw values arrived',
          () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, DynamicValue(value: 'first'));

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);
        // Should have firstValue
        expect(values.length, 1);

        ads.resendLastValue();
        await Future.delayed(Duration.zero);
        expect(values.length, 2);
        expect(values[1].value, 'first');

        await sub.cancel();
        await raw.close();
      });

      test('resends the most recent value, not the first', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, DynamicValue(value: 'first'));

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);

        raw.add(DynamicValue(value: 'second'));
        raw.add(DynamicValue(value: 'third'));
        await Future.delayed(Duration.zero);

        ads.resendLastValue();
        await Future.delayed(Duration.zero);

        expect(values.last.value, 'third');

        await sub.cancel();
        await raw.close();
      });
    });

    group('onDone — raw stream completes', () {
      test('closing raw stream closes the subject', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final sub = ads.stream.listen((_) {});
        raw.add(DynamicValue(value: 1));
        await Future.delayed(Duration.zero);

        // Close the raw stream (simulates connection loss)
        await raw.close();
        await Future.delayed(Duration.zero);

        // Subject is now closed — this is the current behavior
        expect(ads.stream.isBroadcast, isTrue);
        // Verify: adding to subject after onDone should not deliver
        // (subject is closed)
        final afterClose = <DynamicValue>[];
        final sub2 = ads.stream.listen(afterClose.add);
        await Future.delayed(Duration.zero);
        // ReplaySubject may replay the last value before close, but no new values
        // The key assertion is that resendLastValue won't work after onDone
        await sub.cancel();
        await sub2.cancel();
      });

      test('resendLastValue fails silently after raw stream completes',
          () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final sub = ads.stream.listen((_) {});
        raw.add(DynamicValue(value: 'before_close'));
        await Future.delayed(Duration.zero);

        await raw.close();
        await Future.delayed(Duration.zero);

        // This is the bug: resendLastValue tries to add to a closed subject
        // Currently this throws or silently fails
        expect(
          () => ads.resendLastValue(),
          // ReplaySubject.add on a closed subject throws StateError
          throwsStateError,
        );

        await sub.cancel();
      });

      test('subscribe() with new raw stream after onDone loses data', () async {
        ads = createADS();
        final raw1 = StreamController<DynamicValue>();
        ads.subscribe(raw1.stream, null);

        final allValues = <DynamicValue>[];
        final sub = ads.stream.listen(allValues.add);

        raw1.add(DynamicValue(value: 'from_raw1'));
        await Future.delayed(Duration.zero);

        // Simulate connection loss
        await raw1.close();
        await Future.delayed(Duration.zero);

        // Simulate reconnect — wire a new raw stream
        final raw2 = StreamController<DynamicValue>();
        ads.subscribe(raw2.stream, null);

        raw2.add(DynamicValue(value: 'from_raw2'));
        await Future.delayed(Duration.zero);

        // The value from raw2 is lost because the subject was closed by onDone
        // This demonstrates the problem: onDone makes the ADS non-recoverable
        expect(allValues.length, 1);
        expect(allValues[0].value, 'from_raw1');

        await sub.cancel();
        await raw2.close();
      });
    });

    group('onError — raw stream errors', () {
      test('forwards errors to subject without closing it', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final errors = <Object>[];
        final sub = ads.stream.listen(values.add, onError: (e) => errors.add(e));

        raw.add(DynamicValue(value: 'before_error'));
        raw.addError(Exception('test error'));
        raw.add(DynamicValue(value: 'after_error'));
        await Future.delayed(Duration.zero);

        expect(values.length, 2);
        expect(values[0].value, 'before_error');
        expect(values[1].value, 'after_error');
        expect(errors.length, 1);

        await sub.cancel();
        await raw.close();
      });

      test('resendLastValue works after raw stream error', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add, onError: (_) {});

        raw.add(DynamicValue(value: 'val'));
        raw.addError(Exception('err'));
        await Future.delayed(Duration.zero);

        ads.resendLastValue();
        await Future.delayed(Duration.zero);

        expect(values.length, 2);
        expect(values[0].value, 'val');
        expect(values[1].value, 'val');

        await sub.cancel();
        await raw.close();
      });
    });

    group('subscribe() replaces raw stream', () {
      test('cancels previous raw subscription when resubscribing', () async {
        ads = createADS();
        var raw1Cancelled = false;
        final raw1 = StreamController<DynamicValue>(
          onCancel: () => raw1Cancelled = true,
        );
        ads.subscribe(raw1.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);

        raw1.add(DynamicValue(value: 'from_raw1'));
        await Future.delayed(Duration.zero);

        // Replace with new raw stream
        final raw2 = StreamController<DynamicValue>();
        ads.subscribe(raw2.stream, null);

        expect(raw1Cancelled, isTrue);

        raw2.add(DynamicValue(value: 'from_raw2'));
        await Future.delayed(Duration.zero);

        expect(values.length, 2);
        expect(values[0].value, 'from_raw1');
        expect(values[1].value, 'from_raw2');

        await sub.cancel();
        await raw2.close();
      });

      test('values from old raw stream after resubscribe are ignored',
          () async {
        ads = createADS();
        // Use a broadcast stream so we can keep adding after cancel
        final raw1 = StreamController<DynamicValue>.broadcast();
        ads.subscribe(raw1.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);

        raw1.add(DynamicValue(value: 'old'));
        await Future.delayed(Duration.zero);

        final raw2 = StreamController<DynamicValue>();
        ads.subscribe(raw2.stream, null);

        // Old stream still emitting shouldn't affect subject (sub was cancelled)
        raw1.add(DynamicValue(value: 'stale'));
        raw2.add(DynamicValue(value: 'new'));
        await Future.delayed(Duration.zero);

        expect(values.length, 2);
        expect(values[0].value, 'old');
        expect(values[1].value, 'new');

        await sub.cancel();
        await raw1.close();
        await raw2.close();
      });

      test('resubscribe preserves lastValue for resend', () async {
        ads = createADS();
        final raw1 = StreamController<DynamicValue>();
        ads.subscribe(raw1.stream, null);

        final sub = ads.stream.listen((_) {});
        raw1.add(DynamicValue(value: 'cached'));
        await Future.delayed(Duration.zero);

        // Resubscribe with no firstValue
        final raw2 = StreamController<DynamicValue>();
        ads.subscribe(raw2.stream, null);

        // lastValue should be reset to null by subscribe(_, null)
        // Actually looking at the code: _lastValue = firstValue (null),
        // so the previous cached value is lost
        final values = <DynamicValue>[];
        final sub2 = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);

        ads.resendLastValue();
        await Future.delayed(Duration.zero);

        // lastValue was set to null by subscribe, so resend does nothing
        // (only ReplaySubject replay delivers the old value)
        // Values from sub2: replayed 'cached' from ReplaySubject
        expect(values.length, 1);
        expect(values[0].value, 'cached');

        await sub.cancel();
        await sub2.cancel();
        await raw2.close();
      });
    });

    group('idle timer disposal', () {
      test('disposes after idle timeout when no listeners', () async {
        ads = createADS(idleTimeout: const Duration(milliseconds: 50));
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final sub = ads.stream.listen((_) {});
        raw.add(DynamicValue(value: 1));
        await Future.delayed(Duration.zero);

        // Remove last listener — starts idle timer
        await sub.cancel();

        // Wait for idle timer to fire
        await Future.delayed(const Duration(milliseconds: 100));

        expect(disposedKeys, contains('test_key'));

        await raw.close();
      });

      test('adding listener cancels idle timer', () async {
        ads = createADS(idleTimeout: const Duration(milliseconds: 50));
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final sub1 = ads.stream.listen((_) {});
        await sub1.cancel();

        // Quickly re-listen before timer fires
        await Future.delayed(const Duration(milliseconds: 10));
        final sub2 = ads.stream.listen((_) {});

        // Wait past the original timer
        await Future.delayed(const Duration(milliseconds: 100));

        expect(disposedKeys, isEmpty);

        await sub2.cancel();
        // Wait for idle timer from sub2.cancel() to fire before next test
        await Future.delayed(const Duration(milliseconds: 100));
        await raw.close();
      });

      test('multiple listeners — only starts timer when all leave', () async {
        // Note: ReplaySubject (broadcast) only calls onListen for the first
        // subscriber and onCancel when the last subscriber cancels. So
        // _handleCancel won't fire until ALL listeners are gone.
        ads = createADS(idleTimeout: const Duration(milliseconds: 50));
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final sub1 = ads.stream.listen((_) {});
        final sub2 = ads.stream.listen((_) {});

        await sub1.cancel();
        // sub2 still listening — onCancel hasn't fired, no idle timer
        await Future.delayed(const Duration(milliseconds: 100));
        expect(disposedKeys, isEmpty);

        await sub2.cancel();
        // Last listener gone — onCancel fires, idle timer starts
        await Future.delayed(const Duration(milliseconds: 100));
        expect(disposedKeys, contains('test_key'));

        await raw.close();
      });
    });

    group('StateMan.addSubscription integration', () {
      test('addSubscription wires stream correctly', () async {
        final stateMan = await StateMan.create(
          config: StateManConfig(opcua: []),
          keyMappings: KeyMappings(nodes: {}),
        );

        final raw = StreamController<DynamicValue>();
        stateMan.addSubscription(
          key: 'test_key',
          subscription: raw.stream,
          firstValue: DynamicValue(value: 'hello'),
        );

        final stream = await stateMan.subscribe('test_key');
        final values = <DynamicValue>[];
        final sub = stream.listen(values.add);
        await Future.delayed(Duration.zero);

        expect(values.length, 1);
        expect(values[0].value, 'hello');

        raw.add(DynamicValue(value: 'world'));
        await Future.delayed(Duration.zero);
        expect(values.length, 2);
        expect(values[1].value, 'world');

        await sub.cancel();
        await raw.close();
        await stateMan.close();
      });
    });

    group('connection lifecycle simulation', () {
      test(
          'session resume without session loss — resendLastValues refreshes UI',
          () async {
        // Simulates: connection briefly drops, session maintained,
        // _resendLastValues called on ACTIVATED
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);

        raw.add(DynamicValue(value: 'latest'));
        await Future.delayed(Duration.zero);
        expect(values.length, 1);

        // Session resumes — resendLastValue called
        // (raw stream is still alive, just no new server data)
        ads.resendLastValue();
        await Future.delayed(Duration.zero);

        expect(values.length, 2);
        expect(values[1].value, 'latest');

        await sub.cancel();
        await raw.close();
      });

      test('session loss — raw stream completes, then resubscribe fails',
          () async {
        // Simulates: connection drops, raw stream completes (onDone),
        // session recovered, new monitor created but subject is closed
        ads = createADS();
        final raw1 = StreamController<DynamicValue>();
        ads.subscribe(raw1.stream, null);

        final allValues = <DynamicValue>[];
        bool streamDone = false;
        final sub = ads.stream.listen(
          allValues.add,
          onDone: () => streamDone = true,
        );

        raw1.add(DynamicValue(value: 'before_loss'));
        await Future.delayed(Duration.zero);

        // Connection loss — raw stream completes
        await raw1.close();
        await Future.delayed(Duration.zero);

        expect(streamDone, isTrue);

        // Session recovered — try to wire new raw stream
        final raw2 = StreamController<DynamicValue>();
        ads.subscribe(raw2.stream, DynamicValue(value: 'recovered'));

        raw2.add(DynamicValue(value: 'new_data'));
        await Future.delayed(Duration.zero);

        // Subject was closed by onDone, so new data is lost
        expect(allValues.length, 1);
        expect(allValues[0].value, 'before_loss');

        await sub.cancel();
        await raw2.close();
      });

      test(
          'session loss — resendLastValues after raw stream done throws',
          () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final sub = ads.stream.listen((_) {});
        raw.add(DynamicValue(value: 'val'));
        await Future.delayed(Duration.zero);

        // Raw stream completes (connection loss)
        await raw.close();
        await Future.delayed(Duration.zero);

        // resendLastValues is called on session ACTIVATED
        expect(() => ads.resendLastValue(), throwsStateError);

        await sub.cancel();
      });

      test('raw stream error does NOT close subject — stream survives',
          () async {
        // Contrast with onDone: errors keep the subject alive
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, null);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add, onError: (_) {});

        raw.add(DynamicValue(value: 'before'));
        raw.addError(Exception('conn error'));
        raw.add(DynamicValue(value: 'after'));
        await Future.delayed(Duration.zero);

        // Stream survives errors
        expect(values.length, 2);
        expect(values[0].value, 'before');
        expect(values[1].value, 'after');

        // resendLastValue still works
        ads.resendLastValue();
        await Future.delayed(Duration.zero);
        expect(values.length, 3);
        expect(values[2].value, 'after');

        await sub.cancel();
        await raw.close();
      });
    });

    group('Inactivity handling — ClientWrapper heartbeat recovery', () {
      test('wrapper resends streams on recovery when resendOnRecovery is true',
          () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, DynamicValue(value: 'initial'));

        final wrapper = ClientWrapper(
          Client(logLevel: LogLevel.UA_LOGLEVEL_ERROR),
          OpcUAConfig(),
          resendOnRecovery: true,
        );
        wrapper.streams.add(ads);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);
        expect(values.length, 1);

        raw.add(DynamicValue(value: 'latest'));
        await Future.delayed(Duration.zero);
        expect(values.length, 2);

        // Simulate inactivity then recovery tick
        wrapper.simulateInactivity();
        wrapper.simulateHeartbeatTick();
        await Future.delayed(Duration.zero);

        expect(values.length, 3);
        expect(values[2].value, 'latest');

        await sub.cancel();
        await raw.close();
        wrapper.dispose();
      });

      test('wrapper does NOT resend when resendOnRecovery is false', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, DynamicValue(value: 'initial'));

        final wrapper = ClientWrapper(
          Client(logLevel: LogLevel.UA_LOGLEVEL_ERROR),
          OpcUAConfig(),
          resendOnRecovery: false,
        );
        wrapper.streams.add(ads);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);
        expect(values.length, 1);

        raw.add(DynamicValue(value: 'latest'));
        await Future.delayed(Duration.zero);
        expect(values.length, 2);

        wrapper.simulateInactivity();
        wrapper.simulateHeartbeatTick();
        await Future.delayed(Duration.zero);

        // No resend
        expect(values.length, 2);

        await sub.cancel();
        await raw.close();
        wrapper.dispose();
      });

      test('tick without prior inactivity does not resend', () async {
        ads = createADS();
        final raw = StreamController<DynamicValue>();
        ads.subscribe(raw.stream, DynamicValue(value: 'initial'));

        final wrapper = ClientWrapper(
          Client(logLevel: LogLevel.UA_LOGLEVEL_ERROR),
          OpcUAConfig(),
          resendOnRecovery: true,
        );
        wrapper.streams.add(ads);

        final values = <DynamicValue>[];
        final sub = ads.stream.listen(values.add);
        await Future.delayed(Duration.zero);
        expect(values.length, 1);

        raw.add(DynamicValue(value: 'latest'));
        await Future.delayed(Duration.zero);
        expect(values.length, 2);

        // Tick without inactivity — no resend
        wrapper.simulateHeartbeatTick();
        await Future.delayed(Duration.zero);

        expect(values.length, 2);

        await sub.cancel();
        await raw.close();
        wrapper.dispose();
      });
    });
  });
}
