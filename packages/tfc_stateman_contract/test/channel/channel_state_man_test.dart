/// The client end of the harness, on the properties the sub-suites do not
/// reach.
///
/// `channel_subscribe_contract_test.dart` and `channel_store_contract_test.dart`
/// judge this implementation against the Phase 1 cases, which is the real
/// verdict. What is left over is a short list of things those cases assume
/// rather than assert, and each one is a way the harness could look right and
/// be measuring the wrong object: a client that answered `read` from something
/// other than its own store, a client whose `subscribe` streams outlive the
/// source, a client that satisfied `StateManApi` but not `harnessOf`, and the
/// round-trip counter — which lives on the *served* side and is therefore the
/// one observable a naive channel client would silently stop being judged by.
@Tags(['meta'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

const _speedKey = 'ST101.CN01.MOT01.speed';
const _otherKey = 'ST201.CN04.MOT01.speed';
const _missingKey = 'ST301.CN17.VLV02.stat';

void main() {
  test('a driver can take the control surface off it', () {
    final api = channelServedFake();
    addTearDown(api.dispose);

    // Not `expect(api, isA<StateManHarness>())`: harnessOf is what every
    // sub-suite actually calls, and it reports a missing control surface
    // through `fail` rather than a cast error. Calling it is the only way to
    // prove the message an author would get is the one they should get.
    expect(harnessOf(api), same(api),
        reason: 'a channel-served implementation that does not satisfy '
            'harnessOf cannot be handed to any sub-suite at all — no case '
            'could make a value arrive for it');
  });

  test('read answers from the client store: null until an update arrives',
      () async {
    final api = channelServedFake();
    addTearDown(api.dispose);
    final plant = harnessOf(api);

    expect(api.read(_speedKey), isNull,
        reason: 'a key nothing has arrived for must read as not-known, which '
            'is a different fact from a known-bad value and the reason read() '
            'is nullable at all');

    final seen = observe(api.listen(_speedKey));
    plant.setValue(_speedKey, 1450);
    await within(seen.next, 'the first value arriving over the channel');

    expect(api.read(_speedKey)?.asInt, 1450);
    expect(api.read(_missingKey), isNull,
        reason: 'a key the source never served must stay unknown on the '
            'client; a client that invented a value for it would launder a '
            'mistyped page binding into a plausible reading');
    expect(api.keys, contains(_speedKey),
        reason: 'the client key list must grow as updates arrive — it is what '
            'the picker and the diagnostics page read');
  });

  test('a quality change with an unchanged number still notifies; an '
      'identical re-delivery does not', () async {
    final api = channelServedFake();
    addTearDown(api.dispose);
    final plant = harnessOf(api);

    final node = api.listen(_speedKey);
    final seen = observe(node);
    plant.setValue(_speedKey, 1450);
    await within(seen.next, 'the first value');

    plant.setQuality(_speedKey, Quality.badStale);
    await within(seen.next, 'the notification for a value that went stale');
    expect(node.value.quality, Quality.badStale,
        reason: 'the number did not move but its trustworthiness did, and that '
            'is the change an operator most needs to see — a client that '
            'compared values only would leave a stale reading looking healthy');

    final before = seen.count;
    plant.setValue(_speedKey, 1450, quality: Quality.badStale);

    // A barrier on a key that genuinely changed, so the absence of an event is
    // asserted after something that would have carried one.
    final barrier = observe(api.listen(_otherKey));
    plant.setValue(_otherKey, 3);
    await within(barrier.next, 'a genuinely changed key notifying');

    expect(seen.count, before,
        reason: 're-delivering an identical value over the channel rebuilt the '
            'page. The unchanged-value guard has to survive encode/decode, or '
            'every poll cycle costs a rebuild per key on the busiest page in '
            'the plant');
  });

  test('dispose closes every stream subscribe handed out', () async {
    final api = channelServedFake();
    addTearDown(api.dispose);
    final plant = harnessOf(api);

    final closed = Completer<void>();
    final firstValue = Completer<DynamicValue>();
    final received = <DynamicValue>[];
    final subscription = api.subscribe(_speedKey).listen(
      (value) {
        received.add(value);
        if (!firstValue.isCompleted) firstValue.complete(value);
      },
      onDone: closed.complete,
    );
    addTearDown(subscription.cancel);

    plant.setValue(_speedKey, 1450);
    await within(firstValue.future,
        'the subscribe() stream carrying a value over the channel');

    await within(api.dispose(), 'dispose() completing');
    await within(closed.future,
        'the handed-out stream closing when the source was disposed');

    expect(received.single.asInt, 1450,
        reason: 'the stream adapter must carry what the store carries; two '
            'numbers for one tag on one page is the worst thing this API can '
            'do');
  });

  test('the round-trip counter measures the client, though it lives on the '
      'source', () async {
    final api = channelServedFake();
    addTearDown(api.dispose);
    final plant = harnessOf(api);

    plant.setValue(_speedKey, 1450);
    plant.setValue(_otherKey, 3);
    await within(observe(api.listen(_otherKey)).next, 'the seed values',
        budget: const Duration(seconds: 1));

    final before = plant.roundTrips;
    final many = await within(
        api.readMany([_speedKey, _otherKey]), 'readMany over the channel');

    expect(many[_speedKey]?.asInt, 1450);
    expect(plant.roundTrips - before, 1,
        reason: 'reading two keys cost ${plant.roundTrips - before} round '
            'trips. A client that fans readMany out into one request per key '
            'is invisible on its own side and shows up here — which is the '
            'whole reason this counter is read off the served source rather '
            'than mirrored over the channel');

    await within(api.readFresh(_speedKey), 'readFresh over the channel');
    expect(plant.roundTrips - before, 2,
        reason: 'a forced read must reach the source; a client answering it '
            'from its own cache would defeat the one call a diagnostics page '
            'makes when the cache is the thing under suspicion');
  });
}
