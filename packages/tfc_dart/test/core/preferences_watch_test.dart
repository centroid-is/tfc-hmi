// PreferencesWatcher: change detection for flutter_preferences rows edited by
// other processes. These tests drive the watcher through injected primitives
// (digest fetcher + notify stream) — no database. The real wiring is covered
// by test/integration/preferences_watch_integration_test.dart.
@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_dart/core/preferences_watch.dart';

/// Digest source the tests mutate between refreshes.
class _FakeDigests {
  Map<String, String> current;
  int fetchCount = 0;
  bool failNext = false;

  _FakeDigests(this.current);

  Future<Map<String, String>> fetch(Set<String> keys) async {
    fetchCount++;
    if (failNext) {
      failNext = false;
      throw StateError('database unreachable');
    }
    return {
      for (final k in keys)
        if (current.containsKey(k)) k: current[k]!,
    };
  }
}

Future<void> _settle([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _FakeDigests digests;
  late StreamController<String> notify;
  PreferencesWatcher? watcher;

  PreferencesWatcher build({
    Duration poll = const Duration(hours: 1),
    Stream<String> Function()? listen,
  }) {
    return PreferencesWatcher(
      keys: {'key_mappings', 'alarm_man_config'},
      fetchDigests: digests.fetch,
      listenForChanges: listen ?? () => notify.stream,
      pollInterval: poll,
      notifyDebounce: const Duration(milliseconds: 5),
      relistenBackoff: const Duration(milliseconds: 20),
    );
  }

  setUp(() {
    digests = _FakeDigests({'key_mappings': 'a', 'alarm_man_config': 'b'});
    notify = StreamController<String>.broadcast();
  });

  tearDown(() async {
    await watcher?.close();
    watcher = null;
    await notify.close();
  });

  test('notify for a watched key with a changed digest emits that key',
      () async {
    watcher = build();
    final seen = <String>[];
    watcher!.changes.listen(seen.add);
    await watcher!.start();

    digests.current['key_mappings'] = 'a2';
    notify.add('key_mappings');
    await _settle();

    expect(seen, ['key_mappings']);
  });

  test('notify with an unchanged digest emits nothing', () async {
    watcher = build();
    final seen = <String>[];
    watcher!.changes.listen(seen.add);
    await watcher!.start();

    notify.add('key_mappings'); // HMI re-saved an identical value
    await _settle();

    expect(seen, isEmpty);
  });

  test('notify for an unwatched key does not even fetch', () async {
    watcher = build();
    await watcher!.start();
    final fetchesAfterStart = digests.fetchCount;

    notify.add('some_other_pref');
    await _settle();

    expect(digests.fetchCount, fetchesAfterStart);
  });

  test('poll catches a change with no notification at all', () async {
    watcher = build(
      poll: const Duration(milliseconds: 30),
      listen: () => const Stream<String>.empty(),
    );
    final seen = <String>[];
    watcher!.changes.listen(seen.add);
    await watcher!.start();

    digests.current['alarm_man_config'] = 'b2';
    await _settle(120);

    expect(seen, contains('alarm_man_config'));
  });

  test('a deleted row counts as a change', () async {
    watcher = build();
    final seen = <String>[];
    watcher!.changes.listen(seen.add);
    await watcher!.start();

    digests.current.remove('key_mappings');
    notify.add('key_mappings');
    await _settle();

    expect(seen, ['key_mappings']);
  });

  test('a failed baseline fetch cannot fabricate change events', () async {
    digests.failNext = true;
    watcher = build();
    final seen = <String>[];
    watcher!.changes.listen(seen.add);
    await watcher!.start(); // baseline fetch fails, tolerated

    // First successful refresh becomes the baseline — silently.
    await watcher!.refreshNow();
    await _settle();
    expect(seen, isEmpty);

    // Only a change relative to that baseline emits.
    digests.current['key_mappings'] = 'a2';
    notify.add('key_mappings');
    await _settle();
    expect(seen, ['key_mappings']);
  });

  test('a dead notify stream is re-listened and the gap is re-checked',
      () async {
    var listens = 0;
    final second = StreamController<String>.broadcast();
    watcher = build(listen: () {
      listens++;
      return listens == 1 ? notify.stream : second.stream;
    });
    final seen = <String>[];
    watcher!.changes.listen(seen.add);
    await watcher!.start();

    // Change happens, then the stream dies before we hear about it.
    digests.current['key_mappings'] = 'a2';
    await notify.close();
    await _settle(100);

    // The re-listen's catch-up refresh found the change without any notify.
    expect(listens, greaterThanOrEqualTo(2));
    expect(seen, contains('key_mappings'));

    // And the new stream is live.
    digests.current['alarm_man_config'] = 'b2';
    second.add('alarm_man_config');
    await _settle();
    expect(seen, contains('alarm_man_config'));
    await second.close();
  });

  test('close stops timers and the changes stream', () async {
    watcher = build(poll: const Duration(milliseconds: 10));
    await watcher!.start();
    final done = watcher!.changes.drain<void>();
    await watcher!.close();
    await done; // stream closed
    final fetches = digests.fetchCount;
    await _settle(60);
    expect(digests.fetchCount, fetches, reason: 'poll must stop after close');
    watcher = null;
  });
}
