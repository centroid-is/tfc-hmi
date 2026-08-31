/// F18: a frame that belongs to a stream, or a session, that has moved on.
///
/// **F18 — Duplicate/stale frames after reconnect.** Scripted server sends
/// old-epoch `values` after resync. The catalogue asks that the client discards
/// frames from a previous connection epoch — epoch/generation id in the
/// protocol, asserted here.
///
/// Two arms, and they are two different staleness questions. The first replays
/// a frame inside one establishment: the sequence number has moved on and the
/// old frame must not be applied behind it. The second replays a frame from
/// *before* a reconnect, which is the harder half — a resync restarts the
/// sequence at the gateway's snapshot, so without a per-subscription generation
/// a pre-drop frame is byte-indistinguishable from the first frame of the
/// session that replaced it. 04-REVIEW CR-04 minted `g` for exactly this, and
/// the second arm is the deviation that recorded the gap converted into an
/// assertion.
///
/// Both frames are captured off the wire rather than hand-written: F18 is about
/// a frame the gateway genuinely sent, and a stand-in would assert against a
/// shape somebody guessed.
///
/// Moved here verbatim from `test/contract/fault_contract_test.dart` in Phase 7
/// (07-02); bodies unchanged.

@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../support/fault_fixture.dart';
import '../support/gate_bands.dart';

void main() {
  group('F18 — a frame from a stream that has moved on', () {
    test('F18a: a stale frame from a stream that has moved on is discarded, '
        'never applied', () async {
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        seed: (plant) => plant.setValue(scenarioKey, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // A real frame, captured off the wire rather than hand-written: F18 is
      // about a frame the gateway genuinely sent, and a stand-in would be
      // asserting against a shape somebody guessed. `Methods.update` is `'u'`
      // — one character on purpose, it is the hot path — so the marker comes
      // from the constant rather than from the word "update", which appears
      // nowhere on the wire.
      fixture.served.setValue(scenarioKey, 1300);
      await until('an update frame carrying the older value',
          () => fixture.client.read(scenarioKey)?.value == 1300);
      final staleFrame = fixture.seam.lastMatching(
          (message) => message.contains('"method":"${Methods.update}"'));
      expect(staleFrame, isNotNull,
          reason: 'no update frame was captured, so the injection below would '
              'deliver nothing and this case would pass by doing nothing');

      // The stream moves on, so the captured frame is now genuinely behind it.
      fixture.served.setValue(scenarioKey, 1500);
      await until('the current value',
          () => fixture.client.read(scenarioKey)?.value == 1500);

      // Re-delivered: the framing bug, the store-and-forward peer, the
      // reconnect that replayed a queue. Injected rather than provoked because
      // TCP does not duplicate frames on its own — the only way to drive this
      // against a real client is to be the peer that sends it.
      fixture.seam.inject(staleFrame!);
      await Future<void>.delayed(settle);

      expect(fixture.client.read(scenarioKey)?.value, 1500,
          reason: 'the reading fell back to a value the stream had already '
              'moved past. That is the F18 failure exactly: a number from two '
              'batches ago rendered under good quality, with nothing on screen '
              'to say it is old, on a mimic an operator is about to act on. '
              '`ValueStore.applyBatch` judges the sequence before it applies '
              'anything for this reason, and a batch at or behind the last '
              'applied one is discarded rather than written');
      expect(
          fixture.client.complaints
              .where((complaint) => complaint.contains('never announced')),
          isEmpty,
          reason: 'the injected frame named a handle this session does not '
              'know, so it was dropped for the wrong reason and the assertion '
              'above is vacuous: nothing was ever going to be applied');

      // And the client is still usable. A replay makes the resync engine
      // resubscribe — "a duplicate on the wire means the stream is not what
      // the client thought it was" — and against the real gateway that
      // resubscribe is *refused*, because the subscription still exists on the
      // live session (-32602, `subscription_registry.dart:214`). The recovery
      // therefore fails, and the property that matters is that failing
      // recovery costs the panel nothing it was still holding: the cache is
      // untouched, the link is up, and the next call is answered. The gap this
      // leaves is written up in the 04-11 SUMMARY, because closing it is a
      // decision about what `subscribe` means on a live session and not
      // something a test may make on its own.
      final fresh = await fixture.client.readFresh(scenarioKey).timeout(recovery);
      expect(fresh.value, 1500,
          reason: 'a forced round trip after the replay did not come back with '
              'the current reading, so the failed resubscribe took something '
              'down with it');
      expect(fixture.client.isReady, isTrue, // window-exempt: the readFresh round trip two lines above completed and returned the current reading — a completed event that cannot happen over a link the client has stopped believing in; this asserts consistency with it
          reason: 'the panel left ready over a link that never closed');
    });

    test('F18b: an old-generation frame after a reconnect is dropped', () async {
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        seed: (plant) => plant.setValue(scenarioKey, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // A real frame from *this* establishment, captured off the wire.
      fixture.served.setValue(scenarioKey, 1300);
      await until('an update frame from the first session',
          () => fixture.client.read(scenarioKey)?.value == 1300);
      final beforeTheDrop = fixture.seam.lastMatching(
          (message) => message.contains('"method":"${Methods.update}"'));
      expect(beforeTheDrop, isNotNull,
          reason: 'nothing was captured, so the injection below delivers '
              'nothing and this case passes by doing nothing');

      // The link dies and comes back: a new session, a new epoch, a new
      // subscription — and, because the counter spans the gateway rather than
      // the socket, a generation the captured frame cannot match.
      fixture.proxy.killOnce();
      await until('the reconnect', () => fixture.client.isReady,
          budget: recovery);
      fixture.served.setValue(scenarioKey, 1500);
      await until('the current value after the reconnect',
          () => fixture.client.read(scenarioKey)?.value == 1500,
          budget: recovery);

      fixture.seam.inject(beforeTheDrop!);
      await Future<void>.delayed(settle);

      expect(fixture.client.read(scenarioKey)?.value, 1500,
          reason: 'a reading from the session before the drop went onto the '
              'mimic under good quality. Worse than the number itself: it '
              'takes the sequence baseline with it, so the genuine frame at '
              'that seq is then discarded as a replay and the operator keeps '
              'the old number until the tag next changes');
      expect(
          fixture.client.complaints
              .where((complaint) => complaint.contains('never announced')),
          isEmpty,
          reason: 'handles are server-global and never released, so the '
              'captured frame names a handle this session does know. If it '
              'did not, the frame would have been dropped for the wrong '
              'reason and the assertion above would be vacuous');
    });
  });
}
