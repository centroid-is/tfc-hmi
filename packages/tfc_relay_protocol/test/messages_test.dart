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

  test('WriteParams sanitizes its value — a write cannot poison a frame', () {
    final w = WriteParams(
        cmd: '01J8', key: 'ST101.x', value: double.nan, ttlMs: 15000);
    expect(w.value, isNull);
    expect(() => jsonEncode(w.toJson()), returnsNormally);
    final r = WriteParams.fromJson(viaJson(w.toJson()));
    expect(r.cmd, '01J8');
    expect(r.ttlMs, 15000);
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
