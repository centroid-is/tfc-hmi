/// The `PIPE.upstream.<alias>.*` producer: HLTH-01's and HLTH-02's per-PLC half.
///
/// Every PLC's condition is an ordinary subscribable tag — same store, same
/// quality codes, same widgets as a temperature. *"There is no health method"*
/// is a recorded decision (design §4.7), so these keys are the health API, and
/// they have to behave like keys or a client has no way at all to ask whether a
/// PLC is alive.
///
/// Four properties, and each one is a way an indicator lies:
///
///  1. **Seeded before anything can subscribe.** A health indicator that reads
///     "unknown" until the first fault tells an operator nothing at the moment
///     they most need telling (`fake_state_man.dart:616-622`).
///  2. **Honest about what it does not know.** A reading the gateway cannot
///     produce is null under `errorConfig` — never `0`, never `false`.
///     `cert_health_state_man.dart:115-126`: a zero reads as a real
///     measurement and fires the alarm for a misspelled path, and the next real
///     warning is the one everybody ignores. `connected: false` on a link
///     nobody has asked about yet is the same lie wearing a bit instead of a
///     number.
///  3. **Carrying nothing an operator should not see.** `last_error` is fanned
///     out to every panel in the plant; an endpoint, a username or a
///     certificate path in it is information disclosure with the gateway's own
///     authority behind it (T-08-33).
///  4. **Excluded from their own freshness accounting** (HLTH-02). Every key
///     here changes only on an event, so freshness accounting would grey the
///     lot of them out permanently and precisely while nothing is wrong.
///
/// A note recorded rather than built: `@conn/<alias>/<field>`
/// (`conn_meta.dart:30-64`) is the app's shipped equivalent, with an almost
/// identical field catalogue — `reconnectCount` is `birth_count` under another
/// name and `uptimeSec` is `last_death_at` inverted. 08-CONTEXT ruling 4 says
/// the gateway serves the reserved namespace only, with an alias layer
/// available later if page churn proves painful.
library;

import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart'
    show KeyMappingEntry, KeyMappings;
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'support/fake_upstream_link.dart';
import 'support/keymap_fixtures.dart';

/// A credentialed OPC UA endpoint of the shape open62541 and `dart:io` really
/// do put into their messages.
const String credentialedEndpoint =
    'opc.tcp://plc-user:hunter2@10.104.29.11:4840/UA/Server';

/// Every secret a fixture in this package injects.
///
/// The local half of 06-06's server-side "the credential appears in no message"
/// sweep. The two together are what make the security section's
/// information-disclosure row real rather than aspirational: that one watches
/// the wire, this one watches the namespace an unprivileged panel can read.
const List<String> injectedSecrets = <String>[
  'hunter2',
  'plc-user',
  '10.104.29.11',
  'opc.tcp',
];

/// A movable clock, so a gauge measured in milliseconds can be tested without
/// sleeping for any of them.
final class TestClock {
  DateTime at = DateTime.utc(2026, 9, 2, 6);
  DateTime call() => at;
  void advance(Duration by) => at = at.add(by);
}

({
  LocalStateMan man,
  FakeUpstreamLink st101,
  FakeUpstreamLink st201,
  TestClock clock,
}) buildTwoLinks({Duration staleAfter = const Duration(seconds: 30)}) {
  final clock = TestClock();
  final st101 = FakeUpstreamLink(alias: st101Alias, keys: <String>[st101Key]);
  final st201 = FakeUpstreamLink(alias: st201Alias, keys: <String>[st201Key]);
  final man = LocalStateMan(
    links: <UpstreamLink>[st101, st201],
    router: KeyRouter.overLinks(
      <UpstreamLink>[st101, st201],
      mappings: KeyMappings(nodes: <String, KeyMappingEntry>{
        ...keyMappingsOf(<String>[st101Key], alias: st101Alias).nodes,
        ...keyMappingsOf(<String>[st201Key], alias: st201Alias).nodes,
      }),
    ),
    staleAfter: staleAfter,
    now: clock.call,
  );
  return (man: man, st101: st101, st201: st201, clock: clock);
}

void main() {
  group('seeded at construction, before anything can subscribe', () {
    late LocalStateMan man;

    setUp(() {
      man = buildTwoLinks().man;
      addTearDown(man.dispose);
    });

    test('every configured link has its whole key set before start() runs', () {
      for (final alias in <String>[st101Alias, st201Alias]) {
        final expected = PipeHealth.keysFor(alias);
        expect(expected, hasLength(7),
            reason: 'six from 08-02 plus data_age_ms, which this plan adds to '
                'the protocol package rather than re-spelling here');
        expect(man.keys, containsAll(expected),
            reason: 'keys is the router set UNION the health keys this '
                'instance produces, so a minted key appears there with no '
                'second roster to keep in step');
      }
    });

    test('an unasked link reads null under errorConfig on every key — never '
        'false, never zero', () {
      for (final key in PipeHealth.keysFor(st101Alias)) {
        final seeded = man.read(key);
        expect(seeded, isNotNull, reason: '$key is not seeded at all');
        expect(seeded!.value, isNull,
            reason: '$key reads ${seeded.value}. "Not known yet" and "known to '
                'be down" are different things on a wall: a good-quality '
                'false on connected sends somebody to a PLC that is fine, and '
                'a zero on birth_count reads as a link that has never come up');
        expect(seeded.quality, Quality.errorConfig, reason: key);
      }
    });

    test('a seeded key is in a subscribe snapshot, not merely in the store',
        () async {
      final first = await man.subscribe(PipeKeys.upstreamState(st101Alias)).first;
      expect(first.quality, Quality.errorConfig);
      expect(first.value, isNull);
    });
  });

  group('the producer tracks the link it reports on', () {
    late LocalStateMan man;
    late FakeUpstreamLink st101;
    late FakeUpstreamLink st201;
    late TestClock clock;

    setUp(() async {
      final built = buildTwoLinks();
      man = built.man;
      st101 = built.st101;
      st201 = built.st201;
      clock = built.clock;
      await man.start();
      addTearDown(man.dispose);
    });

    test('a live link reads connected, in the wire vocabulary, with one birth',
        () {
      expect(man.read(PipeKeys.upstreamConnected(st101Alias))!.value, isTrue);
      expect(man.read(PipeKeys.upstreamState(st101Alias))!.value,
          UpstreamLinkState.connected.wireName,
          reason: 'the state travels as the string StatusParams documents '
              '(messages.dart:493-495), so the same vocabulary answers a '
              'subscribed key and a status notification');
      expect(man.read(PipeKeys.upstreamBirthCount(st101Alias))!.value, 1);
    });

    test('last_error with nothing wrong is NULL under good quality, not the '
        'empty string', () {
      final quiet = man.read(PipeKeys.upstreamLastError(st101Alias))!;
      expect(quiet.value, isNull,
          reason: 'an empty string is a value. A page bound to it shows a '
              'blank where it should show nothing at all, and a blank is what '
              'a broken binding looks like too');
      expect(quiet.quality, Quality.good,
          reason: 'good, not errorConfig: the gateway looked and the answer is '
              '"nothing". That is knowledge, not the absence of it');
    });

    test('last_death_at on a link that has never dropped is NULL under good '
        'quality — not 0, not the epoch', () {
      final never = man.read(PipeKeys.upstreamLastDeathAt(st101Alias))!;
      expect(never.value, isNull,
          reason: 'an epoch-zero timestamp renders as 1 January 1970 on a '
              'panel, which is a death this link never had');
      expect(never.quality, Quality.good);
    });

    test('the epoch is published as an OPAQUE string and nothing else', () {
      final epoch = man.read(PipeKeys.upstreamEpoch(st101Alias))!;
      expect(epoch.value, st101.epoch);
      expect(epoch.value, isA<String>(),
          reason: 'no parsing, no ordering, no "newer than" — equality is the '
              'entire vocabulary an epoch token has (08-08)');
      expect(epoch.quality, Quality.good);
    });

    test('the keys push on change to a listener attached before it', () async {
      final handle = man.listen(PipeKeys.upstreamConnected(st101Alias));
      var pushes = 0;
      void count() => pushes++;
      handle.addListener(count);
      addTearDown(() => handle.removeListener(count));

      st101.disconnectUpstream();
      await pumpEventQueue();

      expect(pushes, greaterThan(0),
          reason: 'a health key nobody is pushed about is a diagnostics page '
              'that has to be re-opened to be believed');
      expect(handle.value.value, isFalse);
      expect(man.read(PipeKeys.upstreamState(st101Alias))!.value,
          UpstreamLinkState.disconnected.wireName);
      expect(man.read(PipeKeys.upstreamLastDeathAt(st101Alias))!.value,
          isA<int>(),
          reason: 'a death now has a time, and it is a real one');
    });

    test('one link\'s loss leaves the OTHER link\'s health keys alone', () async {
      st101.disconnectUpstream();
      await pumpEventQueue();

      expect(man.read(PipeKeys.upstreamConnected(st201Alias))!.value, isTrue,
          reason: 'ST201 is up and its own indicator must say so while ST101 '
              'is down. The alias in the key is what keeps four PLCs apart');
      expect(man.read(PipeKeys.upstreamLastDeathAt(st201Alias))!.value, isNull);
    });

    test('data_age_ms is null under errorConfig until a value has arrived on '
        'that link, and a real number afterwards', () {
      final key = PipeKeys.upstreamDataAgeMs(st101Alias);
      final before = man.read(key)!;
      expect(before.value, isNull,
          reason: 'a link that has delivered nothing has no newest value. A '
              'zero here reads as "a sample just landed", which is the '
              'plausible-zero failure exactly inverted');
      expect(before.quality, Quality.errorConfig);

      man.applyUpstreamBatch(<String, DynamicValue>{
        st101Key: DynamicValue(value: 41),
      });
      expect(man.read(key)!.value, 0);
      expect(man.read(key)!.quality, Quality.good);
    });

    test('read() re-derives data_age_ms, so a poll is never a frozen gauge',
        () {
      final key = PipeKeys.upstreamDataAgeMs(st101Alias);
      man.applyUpstreamBatch(<String, DynamicValue>{
        st101Key: DynamicValue(value: 41),
      });
      final handle = man.listen(key);
      expect(handle.value.value, 0);

      // Nothing arrives, nothing is announced, and three seconds pass.
      clock.advance(const Duration(seconds: 3));

      expect(man.read(key)!.value, 3000,
          reason: 'this is 08-05\'s property 2 applied to the health '
              'namespace: the verdict is re-derived on read, so a value nobody '
              'has pushed about is still correct when somebody asks. A gauge '
              'that reads 0 ms old three seconds after the last sample is the '
              'stale-but-plausible number this project exists to prevent');
      expect(handle.value.value, 0,
          reason: 'and the re-derivation does NOT write: a read is not an '
              'event, and one that notified every listener would make a '
              'diagnostics page\'s poll a rebuild storm');
    });
  });

  group('HLTH-02: the health keys are outside their own freshness accounting',
      () {
    test('a link idle for ten times staleAfter still reads its own state '
        'correctly', () async {
      final built = buildTwoLinks(staleAfter: const Duration(seconds: 5));
      final man = built.man;
      addTearDown(man.dispose);
      await man.start();

      man.applyUpstreamBatch(<String, DynamicValue>{
        st101Key: DynamicValue(value: 41),
      });
      expect(man.read(st101Key)!.quality, Quality.good);

      built.clock.advance(const Duration(seconds: 50));

      expect(man.read(st101Key)!.quality, Quality.badStale,
          reason: 'anti-vacuity: if the plant key has not gone stale then the '
              'composition below is asserting nothing at all');
      for (final key in PipeHealth.keysFor(st101Alias)) {
        final health = man.read(key)!;
        expect(health.quality, isNot(Quality.badStale),
            reason: '$key greyed out because it had not changed in fifty '
                'seconds. 06-09 found this on days_to_expiry and it is not '
                'specific to that key: every one of these changes only on an '
                'event, so freshness accounting greys the whole indicator set '
                'out permanently and precisely while nothing is wrong');
      }
      expect(man.read(PipeKeys.upstreamState(st101Alias))!.value,
          UpstreamLinkState.connected.wireName);
    });
  });

  group('T-08-33: no key value carries a credential', () {
    test('a credentialed endpoint in an upstream error reaches no key value',
        () async {
      final built = buildTwoLinks();
      final man = built.man;
      addTearDown(man.dispose);
      await man.start();

      built.st101.setLastError('$credentialedEndpoint refused the session');
      built.st101.disconnectUpstream();
      await pumpEventQueue();

      final published = man.read(PipeKeys.upstreamLastError(st101Alias))!;
      print('LAST ERROR ${published.value}');

      expect(published.value, isNotNull,
          reason: 'redacted to nothing is not redaction, it is deletion — the '
              'message still has to say what kind of thing went wrong');
      final text = published.value as String;
      // Each named separately, so a partial redaction fails loudly rather than
      // passing on whichever half the assertion happened to check.
      expect(text, isNot(contains('10.104.29.11')),
          reason: 'the plant topology is not public');
      expect(text, isNot(contains('plc-user')),
          reason: 'the service account name is half a credential');
      expect(text, isNot(contains('hunter2')),
          reason: 'and that is the other half');
      expect(text, isNot(contains('opc.tcp')),
          reason: 'the scheme goes with the endpoint it introduced');
    });
  });
}
