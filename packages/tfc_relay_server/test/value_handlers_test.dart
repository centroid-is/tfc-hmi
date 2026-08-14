/// The five value methods, judged as handler bodies rather than over a wire.
///
/// They are called here the way `RelaySession._on` calls them — one
/// `rpc.Parameters`, one answer or one `RpcException` — with a hand-cranked
/// clock, because everything the outcome log promises is arithmetic about
/// *when* a command was seen and nothing about how long a test is willing to
/// sleep. Registration is 04-02 task 2's subject and is asserted over a real
/// socket in `surface_test.dart`; what is asserted below is what each body
/// answers once it has been reached.
///
/// Two of these cases exist because the wrong answer is worse than no answer:
///
///  * **`not_received` is a licence to re-actuate.** It is the one outcome
///    that tells an operator a re-send is safe, so a gateway that has merely
///    *forgotten* a command must never spell its amnesia that way. The
///    aged-out case below is the one that separates "we never saw it" from
///    "we no longer remember it".
///  * **A non-finite `expect` is not a value to clean up.** Null is this
///    path's encoding of "no compare-and-set guard", so sanitizing an
///    `Infinity` away turns "only if it still reads 1200" into "whatever it
///    reads" — a guarded write silently made unconditional
///    (`messages.dart:373-401`, `channel_state_man.dart:229-250`).
library;

import 'package:json_rpc_2/error_code.dart' as rpc_error;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/value_handlers.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

import 'support/fake_clock.dart';

/// A clock far enough from zero that a ULID minted on it is a plausible id:
/// the timestamp field is 48 bits of epoch milliseconds, and a test that
/// minted at zero would be asserting about ids from 1970.
const int _epochStart = 1_760_000_000_000;

/// The handlers under test, their source, and the clock both share.
final class _Kit {
  _Kit(this.handlers, this.api, this.clock);

  final ValueHandlers handlers;
  final FakeStateMan api;
  final FakeClock clock;

  /// A cmd minted on this kit's clock, exactly as a client would mint one at
  /// the moment the operator pressed the button.
  String mintCmd() => newUlid(nowMs: clock.nowMs);
}

_Kit _kit({
  Duration writeOutcomeTtl = const Duration(seconds: 60),
  Set<String> readOnlyKeys = const {},
}) {
  final api = FakeStateMan(readOnlyKeys: readOnlyKeys);
  final clock = FakeClock(start: _epochStart);
  addTearDown(api.dispose);
  return _Kit(
    ValueHandlers(
      api: api,
      config: ServerConfig(writeOutcomeTtl: writeOutcomeTtl),
      now: clock.now,
    ),
    api,
    clock,
  );
}

rpc.Parameters _params(String method, Map<String, Object?> value) =>
    rpc.Parameters(method, value);

Map<String, Object?> _asMap(Object? raw) => (raw! as Map).cast<String, Object?>();

/// Ten plant keys in the house convention, all with values.
Map<String, Object?> _tenKeys() => {
      for (var i = 1; i <= 10; i++)
        'CN${i.toString().padLeft(2, '0')}.MOT01.speed': i,
    };

Future<rpc.RpcException> _refusal(
    Future<Object?> call, String what) async {
  try {
    await call;
  } on rpc.RpcException catch (error) {
    return error;
  }
  fail('$what was answered instead of refused');
}

void main() {
  group('read', () {
    test('a key the plant serves answers from the cache', () async {
      final kit = _kit();
      kit.api.setValue('CN01.MOT01.speed', 1200);

      final answer =
          _asMap(await kit.handlers.read(_params(Methods.read, {
        'key': 'CN01.MOT01.speed',
      })));

      expect(answer['key'], 'CN01.MOT01.speed');
      expect(WireValue.fromJson(_asMap(answer['value'])).v, 1200,
          reason: 'read is the cached path: it answers with what the gateway '
              'last heard from the PLC, which is the number already on the '
              'operator\'s screen');
      expect(answer['rejected'], isNull);
    });

    test('a key the source does not serve is answered, not thrown', () async {
      final kit = _kit();
      kit.api.setValues(_tenKeys());

      final answer =
          _asMap(await kit.handlers.read(_params(Methods.read, {
        'key': 'CN99.NOPE01.invented',
      })));

      final wire = WireValue.fromJson(_asMap(answer['value']));
      expect(wire.v, isNull);
      expect(wire.q, Quality.errorConfig,
          reason: 'a tag this source cannot serve is a configuration error '
              'and not a value that is late: waiting will not fix a typo in a '
              'page config, and an uncertain code would tell the operator to '
              'wait');
      expect(_asMap(answer['rejected'])['kind'], 'unknownKey',
          reason: 'the reason rides with the answer so a page editor can say '
              'which of its 1500 bindings is wrong');
    });

    test('a blank key is refused', () async {
      final kit = _kit();

      final error = await _refusal(
          kit.handlers.read(_params(Methods.read, {'key': '  '})),
          'a read of a blank key');

      expect(error.code, rpc_error.INVALID_PARAMS);
    });
  });

  group('readFresh', () {
    test('the forced round trip keeps the source timestamp', () async {
      final kit = _kit();
      kit.api.setValue('CN01.MOT01.speed', 1200,
          sourceTime: DateTime.fromMillisecondsSinceEpoch(_epochStart));

      final before = kit.api.roundTrips;
      final answer =
          _asMap(await kit.handlers.readFresh(_params(Methods.readFresh, {
        'key': 'CN01.MOT01.speed',
      })));

      expect(kit.api.roundTrips, before + 1,
          reason: 'readFresh is the call a diagnostics page makes when the '
              'cache is the thing under suspicion; answering it from the '
              'cache would answer the wrong question');
      final wire = WireValue.fromJson(_asMap(answer['value']));
      expect(wire.t, _epochStart,
          reason: 'the readback check compares the instant the PLC produced '
              'the value, not the instant the gateway relayed it');
    });
  });

  group('readMany', () {
    test('one mistyped key among ten costs that one key, not the call',
        () async {
      final kit = _kit();
      kit.api.setValues(_tenKeys());

      final answer =
          _asMap(await kit.handlers.readMany(_params(Methods.readMany, {
        'keys': [..._tenKeys().keys, 'CN99.NOPE01.invented'],
      })));

      expect(_asMap(answer['values']).keys.toSet(), _tenKeys().keys.toSet(),
          reason: 'a page config carries ~1500 hand-edited keys; failing the '
              'whole call on one typo turns it into a blank control-room '
              'screen');
      expect(_asMap(answer['rejected']).keys, ['CN99.NOPE01.invented']);
    });

    test('one round trip serves however many keys were asked for', () async {
      final kit = _kit();
      kit.api.setValues(_tenKeys());

      final before = kit.api.roundTrips;
      await kit.handlers.readMany(_params(Methods.readMany, {
        'keys': _tenKeys().keys.toList(),
      }));

      expect(kit.api.roundTrips, before + 1,
          reason: 'ten keys as ten round trips over a link with 200 ms of '
              'latency is the failure this method exists to remove');
    });

    test('an empty key list is refused', () async {
      final kit = _kit();

      final error = await _refusal(
          kit.handlers.readMany(_params(Methods.readMany, {'keys': <String>[]})),
          'a readMany asking for nothing');

      expect(error.code, rpc_error.INVALID_PARAMS);
    });

    test('a list over the server\'s ceiling is refused', () async {
      final kit = _kit();
      final config = ServerConfig();

      final error = await _refusal(
          kit.handlers.readMany(_params(Methods.readMany, {
            'keys': [
              for (var i = 0; i <= config.maxKeysPerSubscribe; i++) 'CN01.K$i.v'
            ],
          })),
          'a readMany over the key ceiling');

      expect(error.code, rpc_error.INVALID_PARAMS);
      expect(error.message, contains('${config.maxKeysPerSubscribe}'));
    });
  });

  group('write', () {
    test('the answer carries an outcome and the client\'s own cmd', () async {
      final kit = _kit();
      kit.api.setValue('CN01.MOT01.speed', 0);
      final cmd = kit.mintCmd();

      final answer = _asMap(await kit.handlers.write(_params(Methods.write, {
        'cmd': cmd,
        'key': 'CN01.MOT01.speed',
        'value': 1200,
      })));

      expect(answer['outcome'], 'applied');
      expect(answer['cmd'], cmd,
          reason: 'the cmd the operator\'s action was minted under is what '
              'writeStatus is queried by; an answer carrying the gateway\'s '
              'own id could never be reconciled');
      expect(WriteResult.fromJson(answer), isA<WriteApplied>());
    });

    test('a rejection is an answer, not an error', () async {
      final kit = _kit(readOnlyKeys: {'CN01.MOT01.speed'});
      kit.api.setValue('CN01.MOT01.speed', 0);

      final answer = _asMap(await kit.handlers.write(_params(Methods.write, {
        'cmd': kit.mintCmd(),
        'key': 'CN01.MOT01.speed',
        'value': 1200,
      })));

      expect(WriteResult.fromJson(answer), isA<WriteRejected>(),
          reason: 'the device said no. A JSON-RPC error means "definitively '
              'no effect and safe to retry", which is a different sentence');
    });

    test('a non-finite expect is refused rather than silently dropped',
        () async {
      final kit = _kit();
      kit.api.setValue('CN01.MOT01.speed', 1200);

      final error = await _refusal(
          kit.handlers.write(_params(Methods.write, {
            'cmd': kit.mintCmd(),
            'key': 'CN01.MOT01.speed',
            'value': 1400,
            'expect': double.infinity,
          })),
          'a write carrying a non-finite compare-and-set guard');

      expect(error.code, rpc_error.INVALID_PARAMS);
      expect(error.message, contains('guard'),
          reason: 'the refusal names the consequence — a guarded write made '
              'unconditional — rather than naming a type');
      expect(kit.api.mintedCmds, isEmpty,
          reason: 'refused before the plant was touched');
    });

    test('a write the gateway loses track of answers unknown, not an error',
        () async {
      final kit = _kit();
      final cmd = kit.mintCmd();
      // A disposed source is the cheapest thing that throws from `write`; the
      // shape being asserted is any failure the gateway cannot interpret.
      await kit.api.dispose();

      final answer = _asMap(await kit.handlers.write(_params(Methods.write, {
        'cmd': cmd,
        'key': 'CN01.MOT01.speed',
        'value': 1200,
      })));

      expect(WriteResult.fromJson(answer), isA<WriteUnknown>(),
          reason: 'a throw on the write path collapses "the PLC may have '
              'applied this" into "this definitely did not happen", and the '
              'second sentence is what makes an operator press the button '
              'again');
    });
  });

  group('writeStatus', () {
    test('a command written a moment ago answers with the outcome it got',
        () async {
      final kit = _kit();
      kit.api.setValue('CN01.MOT01.speed', 0);
      final cmd = kit.mintCmd();
      await kit.handlers.write(_params(Methods.write, {
        'cmd': cmd,
        'key': 'CN01.MOT01.speed',
        'value': 1200,
      }));

      final results = await _status(kit, [cmd]);

      expect(results.single, isA<WriteApplied>());
      expect(results.single.cmd, cmd);
    });

    test('a command the gateway never saw answers not_received', () async {
      final kit = _kit();

      final results = await _status(kit, [kit.mintCmd()]);

      expect(results.single, isA<WriteNotReceived>(),
          reason: 'the command was minted inside the window and no outcome '
              'was ever recorded for it, so the gateway can say it never '
              'arrived — the one answer that makes a re-send safe');
    });

    test(
        'an aged-out command answers unknown, because not_received is a '
        'licence to re-actuate machinery', () async {
      final kit = _kit(writeOutcomeTtl: const Duration(seconds: 60));
      kit.api.setValue('CN01.MOT01.speed', 0);
      final cmd = kit.mintCmd();
      await kit.handlers.write(_params(Methods.write, {
        'cmd': cmd,
        'key': 'CN01.MOT01.speed',
        'value': 1200,
      }));

      kit.clock.advance(const Duration(seconds: 61).inMilliseconds);
      final results = await _status(kit, [cmd]);

      expect(results.single, isA<WriteUnknown>(),
          reason: 'the gateway forgot the outcome; forgetting is not evidence '
              'that the write never happened, and not_received would tell the '
              'operator it is safe to actuate the machine a second time');
      expect(results.single.cmd, cmd);
    });

    test('the outcome log does not grow across aged-out commands', () async {
      final kit = _kit(writeOutcomeTtl: const Duration(seconds: 60));
      kit.api.setValue('CN01.MOT01.speed', 0);

      for (var i = 0; i < 20; i++) {
        await kit.handlers.write(_params(Methods.write, {
          'cmd': kit.mintCmd(),
          'key': 'CN01.MOT01.speed',
          'value': i,
        }));
        kit.clock.advance(const Duration(seconds: 10).inMilliseconds);
        await _status(kit, [kit.mintCmd()]);
      }

      expect(kit.handlers.recordedOutcomes, lessThanOrEqualTo(7),
          reason: 'a log with a TTL and no pruning is a memory leak an '
              'authenticated client can drive: at one write per ten seconds '
              'and a 60 s window, seven entries is everything still inside it');
    });

    test('a command still in flight is answerable, and not as not_received',
        () async {
      final kit = _kit();
      kit.api.setValue('CN01.MOT01.speed', 0);
      final cmd = kit.mintCmd();
      kit.api.stallWrites();

      final inFlight = kit.handlers.write(_params(Methods.write, {
        'cmd': cmd,
        'key': 'CN01.MOT01.speed',
        'value': 1200,
      }));
      await pumpEventQueue();
      final results = await _status(kit, [cmd]);

      expect(results.single, isNot(isA<WriteNotReceived>()),
          reason: 'the command is upstream right now. Telling the operator it '
              'never arrived, while it is in flight, is the one answer that '
              'invites a second actuation of a moving machine');
      expect(results.single, isA<WriteUnknown>());

      kit.api.releaseWrites();
      await inFlight;
    });

    test('an empty cmd list is refused', () async {
      final kit = _kit();

      final error = await _refusal(
          kit.handlers.writeStatus(
              _params(Methods.writeStatus, {'cmds': <String>[]})),
          'a writeStatus asking about nothing');

      expect(error.code, rpc_error.INVALID_PARAMS);
    });

    test('a cmd that is not an id at all answers unknown', () async {
      final kit = _kit();

      final results = await _status(kit, ['not-a-ulid']);

      expect(results.single, isA<WriteUnknown>(),
          reason: 'nothing can be dated, so nothing can be ruled out; the '
              'safe answer to "I cannot tell" is unknown');
    });
  });

  group('the error armor', () {
    test('every refusal carries a pre-substituted request', () async {
      final kit = _kit();

      final refusals = <rpc.RpcException>[
        await _refusal(kit.handlers.read(_params(Methods.read, {'key': ''})),
            'a blank read'),
        await _refusal(
            kit.handlers
                .readMany(_params(Methods.readMany, {'keys': <String>[]})),
            'an empty readMany'),
        await _refusal(
            kit.handlers.write(_params(Methods.write, {
              'cmd': kit.mintCmd(),
              'key': 'CN01.MOT01.speed',
              'value': 1,
              'expect': double.nan,
            })),
            'a write with a non-finite guard'),
        await _refusal(
            kit.handlers
                .writeStatus(_params(Methods.writeStatus, {'cmds': <String>[]})),
            'an empty writeStatus'),
      ];

      for (final error in refusals) {
        expect(_asMap(error.data)['request'], isA<String>(),
            reason: 'RpcException.serialize copies the offending request into '
                'error.data unless data["request"] is already set. One request '
                'carrying 1e999 would then make the *error* unencodable, the '
                'peer drops it, and every caller with no deadline waits '
                'forever (the 02-05 hang)');
      }
    });
  });
}

/// `writeStatus` for [cmds], decoded.
Future<List<WriteResult>> _status(_Kit kit, List<String> cmds) async {
  final answer = _asMap(await kit.handlers
      .writeStatus(_params(Methods.writeStatus, {'cmds': cmds})));
  return [
    for (final raw in answer['results']! as List)
      WriteResult.fromJson((raw as Map).cast<String, Object?>()),
  ];
}
