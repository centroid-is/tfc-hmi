/// What this gateway answers about a tag its source does not serve.
///
/// **Source: 06-RESEARCH §E.1**, a probe executed against a live `RelayServer`
/// over a real socket. It measured every surface and found two with no answer
/// at all:
///
///  * `readFresh` forwarded straight to `api.readFresh` and reported whatever
///    the source said — `{"v":null,"q":258}` on the fake, with **no `rejected`
///    map** — where `read` answered `q:770` plus `KeyReject(unknownKey)`. Two
///    read methods disagreeing about one tag is the divergence 04-REVIEW WR-11
///    already fixed once, between `read` and `readMany`.
///  * `write` was worse than unchecked: it **applied and created the key**
///    (`{"outcome":"applied","readback":1}`, and `api.keys` gained the tag).
///
/// ## What breaks in the plant without this file
///
/// A page config carries ~1500 hand-edited tag names. When one of them is a
/// typo, or names a tag an upstream engineer renamed last Tuesday, the panel
/// has to be told so — and told the *same* thing by whichever read method the
/// widget happens to use. A `readFresh` answering `uncertainNotYetKnown` says
/// "wait, it is coming", so the tag renders as merely quiet and the typo
/// survives on the page for months. That is the stale-but-plausible failure
/// PROJECT.md exists to prevent, arriving through the one method whose entire
/// purpose is to settle whether a value is real.
///
/// The write half is heavier. A write to a tag the source does not serve used
/// to *create* it: the operator got "applied", the readback confirmed it, and
/// nothing at all had happened in the plant. On a safety-relevant path a
/// gateway that invents a tag rather than refusing is the worst available
/// option — the one three-state outcome an operator cannot act on is a false
/// "applied".
///
/// ## Why the agreement is asserted against itself
///
/// The first case compares `read`'s answer to `readFresh`'s **field by field**
/// rather than against hard-coded literals. A later phase is free to change
/// the shape — 06-08's hiding rule imitates it, and Phase 10 adds surfaces —
/// and the property that must survive all of it is that the two read methods
/// say the same thing about the same tag. A literal would go stale; this does
/// not.
@Tags(['ws'])
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
// `KeyRejectKinds` is the server's own vocabulary, not the protocol's, so it
// arrives from the source file rather than from the barrel.
import 'package:tfc_relay_server/src/session_handlers.dart' show KeyRejectKinds;

import 'support/ws_harness.dart';

/// A tag no fixture ever seeds, in the plant's own naming convention so that
/// the case reads like the mistake it models — a real key with a typo in it —
/// rather than like a synthetic string.
const _ghost = 'CN01.MOT01.speeed';

/// A tag the fixture does seed. The control arm of every case here.
const _served = 'CN01.MOT01.speed';

void main() {
  group('the two read methods agree about a tag this source does not serve',
      () {
    test('read and readFresh give the same answer about a tag this source '
        'does not serve', () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();
      fixture.served.setValue(_served, 1200);

      final fromRead = _asMap(
          await fixture.request(Methods.read, params: {'key': _ghost}));
      final fromFresh = _asMap(
          await fixture.request(Methods.readFresh, params: {'key': _ghost}));

      expect(fromFresh, equals(fromRead),
          reason: 'read and readFresh answered differently about "$_ghost". '
              'One of them is telling the panel the tag is merely quiet and '
              'the other that it does not exist, so which sentence the '
              'operator gets depends on which method the widget happened to '
              'call — and the quiet one is how a renamed PLC tag survives on '
              'a page for months. Asserted against each other rather than '
              'against a literal so that a later phase changing the shape '
              'still has to change both');
    });

    test('the shared answer is the errorConfig one, not the not-yet-known one',
        () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();

      final answer = _asMap(
          await fixture.request(Methods.readFresh, params: {'key': _ghost}));
      final value = _asMap(answer['value']);
      final rejected = _asMap(answer['rejected']);

      expect(value['q'], Quality.errorConfig.code,
          reason: 'readFresh answered quality ${value['q']} for a tag the '
              'source does not serve. 258 (uncertainNotYetKnown) means "no '
              'reading has arrived yet, wait"; 770 (errorConfig) means "the '
              'source affirmatively says this tag is gone". The gateway knows '
              'the second, and only the second is a sentence an engineer can '
              'act on');
      expect(value['v'], isNull,
          reason: 'a tag that does not exist has no reading, and a non-null '
              'value under a bad quality is what a widget renders as a real '
              'number in a warning colour');
      expect(_asMap(rejected[_ghost])['kind'], KeyRejectKinds.unknownKey,
          reason: 'the rejection is keyed by tag and names unknownKey, so a '
              'client decodes it the same way it decodes read\'s and '
              'readMany\'s — 04-REVIEW WR-11 is the divergence that cost');
    });

    test('readFresh on a served key still forces exactly one round trip',
        () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();
      fixture.served.setValue(_served, 1200);

      final before = fixture.served.roundTrips;
      final answer = _asMap(
          await fixture.request(Methods.readFresh, params: {'key': _served}));

      expect(fixture.served.roundTrips, before + 1,
          reason: 'an existence check that also swallowed the round trip '
              'would turn "the cache is under suspicion" into "the cache '
              'answers", which is the one thing readFresh exists not to do');
      expect(answer.containsKey('rejected'), isFalse,
          reason: 'a served key carries no rejection map; a client that saw '
              'one would decode a healthy tag as misconfigured');
      expect(_asMap(answer['value'])['v'], 1200,
          reason: 'the forced read must carry the reading the source has');
    });
  });
}

/// One decoded JSON object, cast where the wire hands back `Object?`.
Map<String, Object?> _asMap(Object? raw) =>
    (raw! as Map).cast<String, Object?>();
