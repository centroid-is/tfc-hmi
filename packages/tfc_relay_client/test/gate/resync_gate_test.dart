/// F9 and G3: recovery going wrong while it is happening.
///
/// **F9 — Drop during resync.** The catalogue's injection is *drop, reconnect,
/// drop again mid-resync burst, reconnect*, and it expects that the second
/// resync is complete and consistent; no key left with pre-first-drop value.
/// The operative half is the last clause: **every** key on the page, not the one
/// key the case happens to watch. A single-key page has no burst to interrupt
/// and no "every", which is why `resync_test.dart`'s in-memory arms cannot make
/// this row's claim.
///
/// **G3 — Resync storm / gap thrash.** The industry survey's version of the same
/// worry (07-RESEARCH-PUBSUB §D.1): induce repeated sequence gaps and assert
/// resyncs are **coalesced, not stacked** — one in-flight resync per
/// subscription, backoff not reset until it completes, no unbounded growth.
/// Sparkplug's rebirth and Ably's re-attach both rate-limit for this reason and
/// OPC UA Part 14 caps discovery responses at five times the KeepAliveTime;
/// ours has no stated limit, so the coalescing in `resync_engine.dart` is the
/// whole of the protection and nothing asserted it.
///
/// **What the resync of one page actually looks like on the wire, measured.**
/// A 40-key page recovers in **two inbound frames**: the `hello` answer (280 b)
/// and then the whole snapshot as a single 4275-byte response, 49 ms later. The
/// "burst" of the catalogue's phrase is not a stream of frames at this layer —
/// one subscription is one snapshot in one frame however large the page — so
/// the interruptible window is *between* those two frames: the session is
/// re-established, the client has asked for the page, and the answer has not
/// arrived. That is where F9's second kill is armed, and the case measures both
/// numbers on every run rather than trusting this paragraph.
///
/// **Neither case reaches into `_inFlight`.** The property the plant cares about
/// is how many times the *gateway* was asked to rebuild the page, so the count
/// is read from the gateway's own registry and corroborated against the
/// subscribe answers on the wire. A case that read the private map would assert
/// the implementation, and the implementation is allowed to change while the
/// property stays.
@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'package:test/test.dart';

import '../support/fault_fixture.dart';
import '../support/gate_bands.dart';

/// How many keys F9's page carries.
///
/// Forty rather than one because the row's clause is "no key left with
/// pre-first-drop value" and a one-key page cannot distinguish "the page came
/// back" from "the key this case watches came back". Forty is also the size at
/// which the snapshot stops being a rounding error on the exchange: measured,
/// forty keys are a 4275-byte answer against a 280-byte `hello` answer and a
/// 125-byte tick, and the gateway spends ~49 ms building and sending it — which
/// is the window the second kill has to land in. A smaller page shrinks that
/// window towards the scheduler's resolution; a much larger one buys nothing,
/// because the answer is still one frame.
const int _f9PageSize = 40;

/// The page F9 drives, as `ST101.CNnn.MOT01.setpoint`.
///
/// The plant's own naming (`AREAnn.DEVnn.SUBnn`), so the page reads like a page
/// rather than like `key0…key39`.
List<String> _pageKeys(int n) => [
      for (var i = 1; i <= n; i++)
        'ST101.CN${i.toString().padLeft(2, '0')}.MOT01.setpoint',
    ];

/// The gateway's answer to a `subscribe`, recognised by the one field only it
/// carries.
///
/// `generation` is spelled out in the subscribe result and abbreviated to `g` in
/// the hot-path `u` frame (`messages.dart:263-323`), so this matches the answer
/// and never an update.
bool _isSnapshotAnswer(String frame) => frame.contains('"generation"');

/// What was true at the instant the second kill fired.
///
/// Captured at a causally-defined moment — the arrival of the first frame of the
/// new connection — and asserted afterwards, which is why the readiness read
/// below is not the instant read of a wall-clock boolean the manifest's sweep
/// forbids.
typedef ArmRecord = ({int frames, bool snapshotSeen, bool isReady, int holding});

void main() {
  group('F9 — a drop in the middle of the resync', () {
    test('F9: a second drop mid-resync still leaves every key equal to the '
        'plant', () async {
      final keys = _pageKeys(_f9PageSize);
      final fixture = await faultFixture(
        keys: keys.toSet(),
        withProxy: true,
        seed: (plant) {
          for (var i = 0; i < keys.length; i++) {
            plant.setValue(keys[i], 100 + i);
          }
        },
      );
      await until('the link', () => fixture.client.isReady);
      await until('the whole page',
          () => keys.every((key) => fixture.client.read(key) != null));

      // Anti-vacuity 1: the page was carrying its pre-drop values before
      // anything was pulled. A page that never held them cannot be shown not to
      // be holding them at the end.
      final preDrop = <String, Object?>{
        for (final key in keys) key: fixture.client.read(key)?.value,
      };
      expect(preDrop.values.where((value) => value != null).length, keys.length,
          reason: 'the page did not carry a value for every key before the '
              'first drop, so the assertion below would be comparing the plant '
              'against keys that had never arrived');

      final markBefore = fixture.seam.inbound.length;
      final dialsBefore = fixture.seam.dials;
      fixture.proxy.killOnce();

      // The plant moves while the link is down — every key, to a distinct new
      // value, so the comparison at the end has something to catch on every one
      // of them.
      final postDrop = <String, Object?>{};
      for (var i = 0; i < keys.length; i++) {
        fixture.served.setValue(keys[i], 900 + i);
        postDrop[keys[i]] = 900 + i;
      }

      // The second kill is armed off an observation rather than a sleep: the
      // first frame of the new connection has arrived, so the resync exchange
      // has begun, and the snapshot has not. A `Future.delayed` here is a case
      // that stops interrupting the exchange the day the gateway gets faster.
      ArmRecord? atKill;
      final armDeadline = DateTime.now().add(recovery);
      while (atKill == null) {
        if (DateTime.now().isAfter(armDeadline)) {
          fail('no frame arrived on the reconnected link within '
              '${recovery.inMilliseconds} ms, so the second kill was never '
              'armed and this case has not run its own scenario');
        }
        final arrived = fixture.seam.inbound.sublist(markBefore);
        if (arrived.isNotEmpty) {
          atKill = (
            frames: arrived.length,
            snapshotSeen: arrived.any(_isSnapshotAnswer),
            isReady: fixture.client.isReady,
            holding: keys
                .where((key) =>
                    fixture.client.read(key)?.value == postDrop[key])
                .length,
          );
          fixture.proxy.killOnce();
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final markAfter = fixture.seam.inbound.length;
      await until('the second recovery', () => fixture.client.isReady,
          budget: recovery);
      await until('the whole page, again',
          () => keys.every((key) => fixture.client.read(key) != null),
          budget: recovery);
      // The deferred changes the gateway had queued for the abandoned
      // establishment arrive as an ordinary update a tick later; the property
      // is what the page settles on, not what it holds mid-exchange.
      await Future<void>.delayed(settle);

      // How long a *complete* exchange is, measured on this run rather than
      // asserted from the paragraph in the library doc: the frames from the
      // third dial up to and including the snapshot answer.
      final afterTheKill = fixture.seam.inbound.sublist(markAfter);
      final snapshotAt = afterTheKill.indexWhere(_isSnapshotAnswer);
      final burstFrames = snapshotAt + 1;

      print('F9: page of ${keys.length} keys; a complete resync exchange is '
          '$burstFrames inbound frames (hello answer then the snapshot); the '
          'second kill was armed on frame ${atKill.frames} of the interrupted '
          'one, with the snapshot not yet delivered '
          '(snapshotSeen=${atKill.snapshotSeen}, keys holding a post-drop '
          'value=${atKill.holding}); dials $dialsBefore -> '
          '${fixture.seam.dials}');

      // Anti-vacuity 2: the second kill landed, and it landed inside the resync
      // exchange rather than after it. Three observations, none of them a
      // clock: a third dial exists, the snapshot had not arrived when the kill
      // fired, and the interrupted exchange was shorter than a complete one.
      expect(fixture.seam.dials, dialsBefore + 2,
          reason: 'the link was dialled ${fixture.seam.dials - dialsBefore} '
              'times, not twice. Two kills cost two redials; anything else '
              'means one of them did not land and the row\'s injection — drop, '
              'reconnect, drop again mid-resync — did not happen');
      expect(atKill.snapshotSeen, isFalse,
          reason: 'the snapshot answer had already arrived when the second '
              'kill fired, so the kill landed after the resync rather than '
              'inside it and this is F1 with extra steps');
      expect(atKill.frames, lessThan(burstFrames),
          reason: 'the interrupted exchange carried ${atKill.frames} frames '
              'and a complete one carries $burstFrames, so the kill did not '
              'interrupt anything');
      expect(atKill.isReady, isFalse, // window-exempt: recorded at the arrival of the first frame of the reconnected link — the completed event this case arms its second kill on — and asserted afterwards from the record, not read live
          reason: 'the client was already ready when the second kill fired, so '
              'the resync it was supposed to interrupt had finished');

      // The row's own clause, over every key, with the expectation built from
      // the plant so the case cannot drift from what was actually set.
      final wrong = <String>[];
      for (final key in keys) {
        final plant = fixture.served.read(key)?.value;
        final panel = fixture.client.read(key)?.value;
        if (panel != plant) {
          wrong.add('$key: panel $panel, plant $plant, before the first drop '
              '${preDrop[key]}');
        }
      }
      expect(wrong, isEmpty,
          reason: 'these keys do not hold the plant\'s current value after two '
              'drops around one resync: $wrong. A key still holding its '
              'pre-first-drop value is the F9 failure exactly — the second '
              'resync completed, the banner cleared, and part of the page is '
              'a photograph of the plant from before the outage, under good '
              'quality, with nothing on screen to say so');

      // Anti-vacuity 3: the page moved. Without this the case would pass
      // against a client that ignored every frame and a plant that never
      // changed.
      final moved = keys
          .where((key) => fixture.client.read(key)?.value != preDrop[key])
          .length;
      expect(moved, keys.length,
          reason: 'only $moved of ${keys.length} keys differ from their '
              'pre-drop value, so the comparison above was partly against '
              'values that never changed and could not have caught a client '
              'that kept them');
    });
  });
}
