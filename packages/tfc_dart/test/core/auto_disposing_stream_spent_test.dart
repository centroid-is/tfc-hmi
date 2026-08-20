// A subscription whose subject has closed must not be handed to the next
// subscriber.
//
// Symptom that led here: the throughput readouts on the home page went blank
// on returning to the page, and picking a DIFFERENT averaging period made
// them work again. The keys are templated -- `Line1.$sb_line_stats_period` --
// so a different period is a different key, with no cached entry to inherit.
// The same period reused the cached one, whose subject had closed when the
// raw stream completed, so the widget got the replay buffer and then `done`.
//
// The idle path always removed the entry before closing. The onDone path
// closed without removing, leaving a spent entry in StateMan._subscriptions
// for the next caller to find.

import 'dart:async';

import 'package:tfc_dart/core/state_man.dart';
import 'package:test/test.dart';

void main() {
  group('AutoDisposingStream', () {
    test('is not spent while the raw stream is open', () {
      final raw = StreamController<int>();
      addTearDown(raw.close);
      final ads = AutoDisposingStream<int>('k', (_) {});
      ads.subscribe(raw.stream, null);
      expect(ads.isSpent, isFalse);
    });

    test('is spent once the raw stream completes', () async {
      final raw = StreamController<int>();
      final ads = AutoDisposingStream<int>('k', (_) {});
      ads.subscribe(raw.stream, null);

      await raw.close();
      await Future<void>.delayed(Duration.zero);

      expect(ads.isSpent, isTrue,
          reason: 'a closed subject can never deliver again');
    });

    test('retires itself from the registry when the raw stream completes',
        () async {
      final disposed = <String>[];
      final raw = StreamController<int>();
      final ads = AutoDisposingStream<int>('Line1.avgBPM5Minute', disposed.add);
      ads.subscribe(raw.stream, null);

      await raw.close();
      await Future<void>.delayed(Duration.zero);

      // Without this the entry stays in StateMan._subscriptions and _monitor
      // hands the closed subject to whoever subscribes next.
      expect(disposed, ['Line1.avgBPM5Minute']);
    });

    test('a spent stream gives a new listener no values', () async {
      final raw = StreamController<int>();
      final ads = AutoDisposingStream<int>('k', (_) {});
      ads.subscribe(raw.stream, null);
      raw.add(1);
      await Future<void>.delayed(Duration.zero);
      await raw.close();
      await Future<void>.delayed(Duration.zero);

      // Whatever a late listener gets, it is finished immediately -- which is
      // indistinguishable from a dead key to the widget above it.
      final got = await ads.stream.toList();
      expect(got, isNot(contains(2)));
      expect(ads.isSpent, isTrue);
    });

    test('values arriving after close are dropped, not delivered', () async {
      final raw = StreamController<int>.broadcast();
      final ads = AutoDisposingStream<int>('k', (_) {});
      ads.subscribe(raw.stream, null);
      await raw.close();
      await Future<void>.delayed(Duration.zero);
      expect(ads.isSpent, isTrue);
      // The production code logs "RAW STREAM emitted value but subject is
      // CLOSED -- data lost!" for exactly this case.
    });
  });
}
