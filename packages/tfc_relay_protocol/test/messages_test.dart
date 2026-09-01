import 'dart:convert';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// Every shape must survive encode → jsonEncode → jsonDecode → decode, and
/// decoders must ignore unknown fields (forward compatibility).
void main() {
  Map<String, Object?> viaJson(Map<String, Object?> json,
          {Map<String, Object?> extra = const {'futureField': 123}}) =>
      jsonDecode(jsonEncode({...json, ...extra})) as Map<String, Object?>;

  test('HelloParams / HelloResult round-trip and tolerate unknown fields',
      () {
    final params = HelloParams(
      protocol: protocolVersion,
      supported: const [protocolVersion],
      client: const PeerInfo('centroid-hmi', '1.4.0'),
      capabilities: const {'deltaPush': true},
      session: const SessionResume(
          id: '01J8', epoch: '01J7', lastSeq: {'s1': 4210}),
    );
    final p = HelloParams.fromJson(viaJson(params.toJson()));
    expect(p.protocol, protocolVersion);
    expect(p.session!.lastSeq, {'s1': 4210});
    expect(p.capabilities['deltaPush'], true);

    final result = HelloResult(
      protocol: protocolVersion,
      server: const PeerInfo('tfc-relay', '0.1.0'),
      sessionId: 'sid',
      epoch: 'e1',
      resumed: false,
      serverTime: 1786000000123,
    );
    final r = HelloResult.fromJson(viaJson(result.toJson()));
    expect(r.resumed, isFalse);
    expect(r.serverTime, 1786000000123);
  });

  test('a hello carries the panel\'s credential in a typed field', () {
    final params = HelloParams(
      protocol: protocolVersion,
      supported: const [protocolVersion],
      client: const PeerInfo('centroid-hmi', '1.4.0'),
      token: 'station-ST101-0123456789abcdef',
    );

    final wire = params.toJson();
    expect(wire['token'], 'station-ST101-0123456789abcdef',
        reason: 'the credential rides in its own key, not folded into '
            '`capabilities` — an open map the session logs and copies. A '
            'typed field is what makes "does anything log the token?" a grep '
            'rather than an audit');

    final p = HelloParams.fromJson(viaJson(wire));
    expect(p.token, 'station-ST101-0123456789abcdef',
        reason: 'a credential that does not survive the round trip is a panel '
            'the gateway refuses for a reason nobody can diagnose, because '
            'the token was sent and simply never arrived');
  });

  test('a hello with no credential carries no token key', () {
    final params = HelloParams(
      protocol: protocolVersion,
      supported: const [protocolVersion],
      client: const PeerInfo('centroid-hmi', '1.4.0'),
    );

    final wire = params.toJson();
    expect(wire.containsKey('token'), isFalse,
        reason: 'an absent credential must be absent, not an empty string: a '
            'diagnostic dump of a tokenless hello that shows `token: ""` '
            'tells the integrator the station was configured with a blank '
            'credential when it was configured with none, and those are two '
            'different faults with two different fixes. It is also the '
            'compatibility property — encoders omit absent optionals, so a '
            'tokenless hello is byte-identical to the one this build sent '
            'before the field existed');

    expect(HelloParams.fromJson(viaJson(wire)).token, isNull,
        reason: 'a hello with no token key decodes to no token; anything else '
            'invents a credential the panel never presented');
  });

  test('hello advertises the heartbeat deadline', () {
    // **Why the gateway has to say this number out loud.** The reaper closes
    // any session that has been silent longer than `heartbeatDeadline`
    // (`tick_engine.dart`), and the panel's only defence is to not be silent.
    // A cadence hard-coded on the client is a number nobody diffs against the
    // gateway's config: raise the deadline and the panel over-pings for ever;
    // lower it and every healthy panel in the plant is reaped once a deadline,
    // reconnecting and resyncing its whole page each time. That is not a
    // hypothetical — it is what this build did before 07-08b, measured in
    // 07-08-SUMMARY deviation 3.
    //
    // `tickMs` is the precedent in every respect: an additive key on the open
    // `capabilities` map, so a gateway that does not send it and a client that
    // does not read it are both still correct.
    final result = HelloResult(
      protocol: protocolVersion,
      server: const PeerInfo('tfc-relay', '0.1.0'),
      capabilities: const {'tickMs': 50, 'heartbeatDeadlineMs': 6000},
      sessionId: 'sid',
      epoch: 'e1',
      resumed: false,
      serverTime: 1786000000123,
    );

    final r = HelloResult.fromJson(viaJson(result.toJson()));
    expect(r.capabilities[HelloCapabilities.heartbeatDeadlineMs], 6000,
        reason: 'the deadline rides in the open capabilities map beside '
            'tickMs, so a gateway that predates the key and a client that '
            'ignores it are both still speaking this protocol');
    expect(r.heartbeatDeadlineMs, 6000,
        reason: 'the typed reader is what the client actually calls; a client '
            'that reached into the map itself would be the second place the '
            'key is spelled, and the first typo in it is silent');
  });

  test('an unusable heartbeat deadline reads as none at all', () {
    // The same tolerance `FreshnessWatchdog.learnedTickMs` applies to `tickMs`,
    // and for the same reason: `capabilities` is an open map, so whatever is
    // under this key came off a wire and may be a string, a negative number,
    // `1e999` decoded to Infinity, or absent. Every one of those has to mean
    // "this gateway told me nothing" — a pump that divided a garbage value by
    // three would either spin (0 ms) or never beat at all.
    // The value is spliced in as raw JSON **text** rather than as a Dart
    // object, because two of the cases below cannot be produced any other way:
    // `jsonEncode` throws on Infinity and NaN (CLAUDE.md's wire hazards), so a
    // fixture that built the frame with `jsonEncode` could never deliver the
    // `1e999` poison this reader has to survive. Decoding is the direction the
    // hazard actually arrives from.
    HelloResult withCapability(String rawJson) =>
        HelloResult.fromJson((jsonDecode('{'
                '"protocol":"$protocolVersion",'
                '"server":{"name":"tfc-relay","version":"0.1.0"},'
                '"capabilities":{"heartbeatDeadlineMs":$rawJson},'
                '"session":{"id":"s","epoch":"e","resumed":false},'
                '"clock":{"serverTime":1786000000123}}') as Map)
            .cast<String, Object?>());

    for (final unusable in <String>[
      'null',
      '0',
      '-1',
      '"soon"',
      // `1e999` decodes to Infinity in Dart, silently. It is named in
      // CLAUDE.md as decode poison and it is the reason this reader exists at
      // all rather than a bare `as int?`.
      '1e999',
      '-1e999',
    ]) {
      expect(withCapability(unusable).heartbeatDeadlineMs, isNull,
          reason: 'a gateway that advertised $unusable as its heartbeat '
              'deadline has advertised nothing usable, and the client must '
              'fall back on its own floor rather than derive a cadence from '
              'it');
    }

    expect(withCapability('6000.0').heartbeatDeadlineMs, 6000,
        reason: 'JSON has one number type and a gateway written in another '
            'language may well send 6000.0; refusing it would be refusing the '
            'same number for its spelling');
  });

  test('SubscribeResult: handles, snapshot, meta, and per-key rejection', () {
    final result = SubscribeResult(
      sub: 's1',
      epoch: 'e1',
      seq: 0,
      handles: const {'ST101.CN01.MOT01.speed': 1},
      meta: const {1: {'unit': 'rpm'}},
      snapshot: {1: WireValue.of(1450, t: 123)},
      rejected: const {'BOGUS.KEY': KeyReject('unknown_key')},
    );
    final r = SubscribeResult.fromJson(viaJson(result.toJson()));
    expect(r.handles['ST101.CN01.MOT01.speed'], 1);
    expect(r.snapshot[1]!.v, 1450);
    expect((r.meta[1] as Map)['unit'], 'rpm');
    expect(r.rejected['BOGUS.KEY']!.kind, 'unknown_key');
  });

  test('UpdateParams round-trips int handles through JSON string keys', () {
    final u = UpdateParams(
      sub: 's1',
      seq: 4211,
      t: 1786000000123,
      changes: {1: WireValue.of(42.5)},
      qualities: const {2: Quality.badStale},
      removed: const [7],
    );
    final r = UpdateParams.fromJson(viaJson(u.toJson()));
    expect(r.changes[1]!.v, 42.5);
    expect(r.qualities[2], Quality.badStale);
    expect(r.removed, [7]);
    expect(r.seq, 4211);
  });

  test('empty maps are omitted from the hot-path frame', () {
    final u = UpdateParams(sub: 's1', seq: 1, t: 2);
    final json = u.toJson();
    expect(json.containsKey('c'), isFalse);
    expect(json.containsKey('q'), isFalse);
    expect(json.containsKey('r'), isFalse);
  });

  test('TickParams carries per-subscription liveness', () {
    final tick = TickParams(
      serverTime: 1786000000123,
      subs: const {'s1': SubTick(seq: 4211, evaluatedAt: 1786000000100)},
    );
    final r = TickParams.fromJson(viaJson(tick.toJson()));
    expect(r.subs['s1']!.seq, 4211);
    expect(r.subs['s1']!.evaluatedAt, 1786000000100);
  });

  test('ResyncParams and StatusParams round-trip', () {
    final resync = ResyncParams(
        sub: 's1', epoch: 'e2', reason: 'gateway_stalled', stalledMs: 42000);
    final r = ResyncParams.fromJson(viaJson(resync.toJson()));
    expect(r.reason, 'gateway_stalled');
    expect(r.stalledMs, 42000);

    final status = StatusParams(
        alias: 'ST201', state: 'disconnected', error: 'BadNotConnected');
    final s = StatusParams.fromJson(viaJson(status.toJson()));
    expect(s.alias, 'ST201');
    expect(s.error, 'BadNotConnected');
  });

  test('WriteParams round-trips and can never poison a frame', () {
    final w = WriteParams(
        cmd: '01J8', key: 'ST101.x', value: 1500, expect: 1400, ttlMs: 15000);
    expect(() => jsonEncode(w.toJson()), returnsNormally);
    final r = WriteParams.fromJson(viaJson(w.toJson()));
    expect(r.cmd, '01J8');
    expect(r.value, 1500);
    expect(r.expect, 1400);
    expect(r.ttlMs, 15000);
  });

  group('WriteParams refuses a non-finite argument', () {
    // CR-03. Sanitizing is right for telemetry; on the write path it turns
    // an operator's intent into a different actuation, silently.

    test('a non-finite value would write null to the tag', () {
      expect(
          () => WriteParams(cmd: '01J8', key: 'ST101.x', value: double.nan),
          throwsA(isA<ArgumentError>()
              .having((e) => e.name, 'name', 'value')
              .having((e) => e.message.toString(), 'message',
                  contains('did not choose'))));
    });

    test('a non-finite expect would drop the compare-and-set guard', () {
      // The sharper of the two: null means "no guard" in this encoding, so
      // a guarded write would silently become an unconditional one.
      expect(
          () => WriteParams(
              cmd: '01J8',
              key: 'ST101.x',
              value: 1,
              expect: double.infinity),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'expect')));
    });

    test('a non-finite buried inside a structure is found too', () {
      expect(
          () => WriteParams(
              cmd: '01J8',
              key: 'ST101.setpoint',
              value: {
                'lo': 1.0,
                'hi': [2.0, double.negativeInfinity]
              }),
          throwsArgumentError);
    });

    test('a 1e999 arriving from a peer is a malformed frame, not a write', () {
      // jsonDecode turns 1e999 into Infinity without complaint, so the
      // refusal is reachable from the wire; there it is a FormatException.
      final decoded = jsonDecode('{"cmd":"c","key":"k","value":1e999}')
          as Map<String, Object?>;
      expect(() => WriteParams.fromJson(decoded), throwsFormatException);
    });

    test('a finite write is untouched', () {
      final w = WriteParams(cmd: 'c', key: 'k', value: 0.0, expect: -1.5);
      expect([w.value, w.expect], [0.0, -1.5]);
    });
  });

  group('WriteParams carries the hold flag', () {
    // D-P5-C: engage and release are ordinary write frames carrying an
    // optional hold flag, so the request table stays at nine names and the
    // three-state outcome comes for free.

    test('a hold engage round-trips with the flag set', () {
      final w = WriteParams(cmd: '01J8', key: 'ST101.jog', value: 1, hold: true);
      expect(w.hold, isTrue);
      expect(w.toJson()['hold'], true);
      expect(WriteParams.fromJson(viaJson(w.toJson())).hold, isTrue);
    });

    test('an ordinary write omits the flag from the frame', () {
      final w = WriteParams(cmd: '01J8', key: 'ST101.sp', value: 5);
      expect(w.hold, isFalse);
      expect(w.toJson().containsKey('hold'), isFalse,
          reason: 'the hot path pays nothing for a field it does not use');
    });

    test('a frame with no hold key decodes to false', () {
      final decoded = jsonDecode('{"cmd":"c","key":"k","value":1}')
          as Map<String, Object?>;
      expect(WriteParams.fromJson(decoded).hold, isFalse);
    });

    test('a non-boolean hold flag is a malformed frame, not a coerced true',
        () {
      final decoded = jsonDecode('{"cmd":"c","key":"k","value":1,"hold":"yes"}')
          as Map<String, Object?>;
      expect(() => WriteParams.fromJson(decoded), throwsFormatException,
          reason: 'coercing would turn an ordinary write into a hold engage, '
              'or the reverse, and the gateway routes on this flag');
    });
  });

  group('WriteStatusParams', () {
    test('round-trips the ids it was asked about', () {
      final p = WriteStatusParams(const ['01ONE', '01TWO']);
      expect(p.toJson(), {
        'cmds': ['01ONE', '01TWO'],
      });
      expect(WriteStatusParams.fromJson(viaJson(p.toJson())).cmds,
          ['01ONE', '01TWO']);
    });

    test('a non-string cmd is refused at decode, not at iteration', () {
      // 05-REVIEW IN-03. `(json['cmds'] as List).cast<String>()` is a lazy
      // view: it decodes without complaint and throws later, wherever the
      // list is first walked — outside the decoder's try, which is exactly
      // the shape this package's tolerant decoders are built against.
      final decoded =
          jsonDecode('{"cmds":["01ONE",7]}') as Map<String, Object?>;
      expect(() => WriteStatusParams.fromJson(decoded), throwsFormatException,
          reason: 'the frame was accepted and the failure deferred to '
              'whoever iterates the list next');
    });

    test('a cmds that is not a list at all is refused', () {
      expect(() => WriteStatusParams.fromJson(const {'cmds': '01ONE'}),
          throwsFormatException);
      expect(() => WriteStatusParams.fromJson(const {}), throwsFormatException);
    });
  });

  group('HoldTickParams', () {
    test('round-trips through the slim wire keys', () {
      final t = HoldTickParams(key: 'ST101.CN01.jog', counter: 42);
      expect(t.toJson(), {'k': 'ST101.CN01.jog', 'n': 42});
      final r = HoldTickParams.fromJson(viaJson(t.toJson()));
      expect(r.key, 'ST101.CN01.jog');
      expect(r.counter, 42);
    });

    test('a tick with no key names no tag and is refused', () {
      expect(() => HoldTickParams.fromJson(const {'n': 1}),
          throwsFormatException);
      expect(() => HoldTickParams.fromJson(const {'k': '', 'n': 1}),
          throwsFormatException);
    });

    test('a non-numeric counter is refused', () {
      expect(() => HoldTickParams.fromJson(const {'k': 'x', 'n': 'two'}),
          throwsFormatException);
      expect(() => HoldTickParams.fromJson(const {'k': 'x'}),
          throwsFormatException);
    });

    test('a fractional counter is refused', () {
      expect(() => HoldTickParams.fromJson(const {'k': 'x', 'n': 1.5}),
          throwsFormatException);
    });

    test('a 1e999 counter decodes to Infinity and is refused', () {
      // The same poison the write path refuses: jsonDecode turns 1e999 into
      // Infinity without complaint, and `Infinity.toInt()` throws something
      // nobody at the boundary is catching.
      final decoded =
          jsonDecode('{"k":"ST101.jog","n":1e999}') as Map<String, Object?>;
      expect(() => HoldTickParams.fromJson(decoded), throwsFormatException);
    });

    test('a tick that names no tag cannot be constructed either', () {
      expect(() => HoldTickParams(key: '', counter: 1), throwsArgumentError);
    });
  });

  test('Icelandic strings survive every shape they can appear in', () {
    const name = 'Þorskflök í raspi';
    final u = UpdateParams(
        sub: 's1', seq: 1, t: 2, changes: {1: WireValue.of(name)});
    expect(
        UpdateParams.fromJson(viaJson(u.toJson())).changes[1]!.v, name);
    final rej = SubscribeResult.fromJson(viaJson(SubscribeResult(
      sub: 's1', epoch: 'e', seq: 0, handles: const {},
      snapshot: const {},
      rejected: {name: const KeyReject('unknown_key', message: name)},
    ).toJson()));
    expect(rej.rejected[name]!.message, name);
  });
}
