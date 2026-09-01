/// The OPC UA adapter, against a real OPC UA server.
///
/// `@TestOn('!windows')` for `subscription_inactivity_test.dart:1`'s reason:
/// the CI matrix includes `windows-latest` and an in-process open62541 `Server`
/// is not run there. The annotation goes on the FILE, which is why the legs
/// that need a real server live in their own files and the package's pure legs
/// stay vm-clean.
@TestOn('!windows')
@Tags(['opcua'])
library;

import 'dart:async';

import 'package:open62541/open62541.dart' as ua;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:test/test.dart';

import 'support/opcua_server_fixture.dart';

/// The plant's own spelling, as everywhere else in this package.
const String speedKey = 'ST101.CN01.MOT01.speed';
const String setpointKey = 'ST101.CN01.MOT01.setpoint';
const String secondKey = 'ST101.CN02.MOT01.speed';

/// This link's alias. 08-04's handoff is emphatic: the router does **not**
/// filter candidate links by `server_alias` — it offers a key to every link in
/// order and takes the first claim — so the adapter checks the alias itself or
/// it takes another PLC's key on a two-PLC plant.
const String alias = 'ST101';

/// Generous: none of these cases is a latency measurement.
const Duration generous = Duration(seconds: 10);

/// The keymapping entry the router would hand `resolve`.
KeyMappingEntry mappingFor(String key, {String? serverAlias = alias, int? arrayIndex}) {
  final node = OpcUANodeConfig(namespace: fixtureNamespace, identifier: key)
    ..serverAlias = serverAlias
    ..arrayIndex = arrayIndex;
  return KeyMappingEntry()..opcuaNode = node;
}

/// A mapping entry describing a node this adapter cannot reach.
KeyMappingEntry get nonOpcUaMapping => KeyMappingEntry();

void main() {
  group('the fixture stands up and comes down cleanly', () {
    test('ten times in a row, no port collision and no SEGV', () async {
      // The concurrency-tolerance claim the wave structure rests on, in the
      // cheapest form that can falsify it: a literal port would fail this on
      // the second iteration and a fixed range would fail it across two
      // shells. Ten cycles in one process is the first half; the second half
      // is running this file from two shells at once, which is an acceptance
      // criterion rather than a case (nothing inside one process can assert
      // about another).
      final ports = <int>{};
      for (var i = 0; i < 10; i++) {
        final fixture = await OpcUaServerFixture.start(valueKeys: [speedKey]);
        ports.add(fixture.port);
        await fixture.dispose();
      }
      expect(ports, hasLength(greaterThan(1)),
          reason: 'ten fixtures that all got the same port would mean the '
              'allocator is handing out a constant, and every claim this file '
              'makes about parallel runs would be false');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('a value from a real server carries the server\'s own time', () {
    late OpcUaServerFixture fixture;
    late OpcUaUpstreamLink link;

    setUp(() async {
      fixture = await OpcUaServerFixture.start(
        valueKeys: [speedKey, secondKey],
        writeKeys: [setpointKey],
      );
      addTearDown(fixture.dispose);
      link = OpcUaUpstreamLink(
        alias: alias,
        endpoint: fixture.endpoint,
        // False in the fixture so a test can reach into the client; true in
        // production, where the blocking FFI stays off the tick isolate.
        useIsolate: false,
      );
      addTearDown(link.dispose);
      await link.connect(deadline: generous);
    });

    test(
        'sourceTime is the instant the SERVER stamped, not the instant the '
        'sample arrived — the phase\'s headline evidence', () async {
      // The server stamps a plain variable node's sourceTimestamp when the
      // value is written and KEEPS it; every later sample reports that same
      // instant. So writing, then waiting, then subscribing produces a sample
      // whose source time is measurably OLDER than its own arrival. That is
      // the discrimination the plan asks for: an adapter stamping
      // DateTime.now() reports the arrival instant and fails here.
      fixture.setValue(speedKey, 42);
      final stampedAround = DateTime.now().toUtc();

      // Long enough that no clock granularity, no sampling interval and no
      // scheduling hiccup can account for the gap.
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      final ref = link.resolve(speedKey, mappingFor(speedKey))!;
      final sample = await link
          .subscribe(ref)
          .firstWhere((v) => v.value != null)
          .timeout(generous);
      final arrivedAt = DateTime.now().toUtc();

      final sourceTime = sample.sourceTime!.toUtc();
      final offset = arrivedAt.difference(sourceTime);
      print('HEADLINE server sourceTime = ${sourceTime.toIso8601String()}');
      print('HEADLINE arrival instant   = ${arrivedAt.toIso8601String()}');
      print('HEADLINE offset            = ${offset.inMilliseconds} ms');

      expect(sample.value, 42);
      expect(offset.inMilliseconds, greaterThan(1000),
          reason: 'the reported instant must be the one the server stamped at '
              'write time, which was more than a second before this sample '
              'arrived. An adapter that stamps DateTime.now() reports an '
              'offset near zero, and "fresh" then means "we heard about it '
              'just now" rather than "the plant measured it just now"');
      expect(sourceTime.difference(stampedAround).abs().inMilliseconds,
          lessThan(1000),
          reason: 'and it must be the write instant, not some other past '
              'instant — an adapter reporting a constant would also pass the '
              'offset check above');
      expect(sample.quality, Quality.good);
    });

    test('a value with no source timestamp falls back to arrival, says so, '
        'and is NOT degraded for it', () async {
      // Nothing in this fixture can strip a source timestamp off the wire —
      // open62541's server supplies one for every sampled read — so the
      // fallback is exercised where it lives, as a function, and the counter
      // it feeds is asserted through the link.
      final before = link.sourceTimeFallbacks;
      final arrival = DateTime.utc(2026, 9, 1, 12);
      final translated = translateOpcUaSample(
        ua.DynamicValue(value: 7),
        arrivedAt: arrival,
        onSourceTimeFallback: () {},
      );

      expect(translated.sourceTime, arrival);
      expect(translated.quality, Quality.good,
          reason: 'a server that does not send a source timestamp is not a '
              'server sending a bad reading. Degrading the quality for it '
              'would make every such server permanently suspect');
      expect(link.sourceTimeFallbacks, before,
          reason: 'the counter belongs to the link, and this call did not go '
              'through one — a counter that moves for a bare function call is '
              'counting the test rather than the plant');
    });

    test('resolve claims its own alias and refuses another PLC\'s key', () {
      expect(link.resolve(speedKey, mappingFor(speedKey)), isNotNull);
      expect(link.resolve(speedKey, mappingFor(speedKey, serverAlias: 'ST201')),
          isNull,
          reason: '08-04: the router does not filter by alias, it asks every '
              'link in order and takes the first claim. A resolve that claims '
              'anything with the right SHAPE takes ST201\'s key on a two-PLC '
              'plant, and the router\'s ambiguity check does not save you '
              'because the two links have different aliases');
      expect(link.resolve(speedKey, nonOpcUaMapping), isNull,
          reason: 'an entry with no opcua_node is not this adapter\'s');
      expect(link.resolve(speedKey, const <String, Object?>{}), isNull,
          reason: 'and neither is something that is not a mapping entry at '
              'all — null is "not mine", never a throw');
    });

    test('a handle is stamped with the link\'s current epoch', () {
      final ref = link.resolve(speedKey, mappingFor(speedKey))!;
      expect(ref.epoch, link.epoch);
      expect(ref.alias, alias);
      expect(ref.key, speedKey);
    });

    test('read answers the server\'s value inside the deadline', () async {
      fixture.setValue(speedKey, 11);
      final ref = link.resolve(speedKey, mappingFor(speedKey))!;

      final seen = await link.read(ref, deadline: generous);

      expect(seen.value, 11);
      expect(seen.quality, Quality.good);
    });

    test('the link reports connected, and maps from EffectiveDeviceStatus',
        () async {
      expect(link.state, UpstreamLinkState.connected);
      expect(
          mapEffectiveStatus(EffectiveDeviceStatus.opcuaUnhealthy),
          UpstreamLinkState.unhealthy,
          reason: 'connected-but-the-subscription-is-dead is unhealthy, not '
              'connected. That is F27\'s shape and Phase 9 wants it');
      expect(mapEffectiveStatus(EffectiveDeviceStatus.connected),
          UpstreamLinkState.connected);
      expect(mapEffectiveStatus(EffectiveDeviceStatus.connecting),
          UpstreamLinkState.connecting);
      expect(mapEffectiveStatus(EffectiveDeviceStatus.disconnected),
          UpstreamLinkState.disconnected);
      expect(mapEffectiveStatus(EffectiveDeviceStatus.umasUnhealthy),
          UpstreamLinkState.unhealthy);
    });

    test('a write reaches the server exactly once and reads back applied',
        () async {
      final ref = link.resolve(setpointKey, mappingFor(setpointKey))!;

      final result = await link.write(ref, DynamicValue.of(5),
          cmd: 'cmd-1', deadline: generous);

      expect(result, isA<WriteApplied>());
      expect(result.cmd, 'cmd-1');
      expect(fixture.writeCount(setpointKey), 1,
          reason: 'counted at the far end of the wire, which is the only '
              'place that can tell one write from a re-issued one');
    });

    test('an array-element write is refused by name, without an expect',
        () async {
      // 08-06's handoff: guardArrayElementWrite has no caller until an adapter
      // that can see the arrayIndex calls it, and this is that adapter. The
      // UpstreamLink signature carries no `expect`, so an element write is
      // always the read-modify-write the ruling refuses.
      final ref = link.resolve(
          setpointKey, mappingFor(setpointKey, arrayIndex: 2))!;

      final result = await link.write(ref, DynamicValue.of(5),
          cmd: 'cmd-arr', deadline: generous);

      expect(result, isA<WriteRejected>());
      expect((result as WriteRejected).reason.kind,
          'array_element_requires_expect');
      expect(fixture.writeCount(setpointKey), 0,
          reason: 'a refusal that still wrote is not a refusal');
    });

    test('a read-only link rejects rather than throwing', () async {
      final readOnly = OpcUaUpstreamLink(
        alias: alias,
        endpoint: fixture.endpoint,
        useIsolate: false,
        supportsWrites: false,
      );
      addTearDown(readOnly.dispose);
      await readOnly.connect(deadline: generous);
      final ref = readOnly.resolve(setpointKey, mappingFor(setpointKey))!;

      final result = await readOnly.write(ref, DynamicValue.of(5),
          cmd: 'cmd-ro', deadline: generous);

      expect(result, isA<WriteRejected>());
      expect((result as WriteRejected).reason.status, 'Bad_NotWritable');
    });

    test('the iterate loop is supervised and stops on dispose', () async {
      // The shape being replaced is `state_man.dart:1364` and `:1398`: two
      // unawaited `() async {…}()` loops with a bare Logger() and no error
      // seam. The property that matters is that the loop is owned, countable
      // and stoppable.
      expect(link.iterateTicks, greaterThan(0),
          reason: 'a supervised loop that never ran is a loop nobody is '
              'driving, and every value in this file arrived by accident');
      final atDispose = link.iterateTicks;

      await link.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(link.iterateTicks, atDispose,
          reason: 'a timer that outlives dispose keeps a blocking FFI call on '
              'the event loop of whatever runs next');
      expect(link.iterateErrors, isEmpty,
          reason: 'and its errors reach a seam a test can read, rather than a '
              'bare Logger()');
    });
  });

  group('the quality table, against a real server', () {
    late OpcUaServerFixture fixture;
    late OpcUaUpstreamLink link;

    setUp(() async {
      fixture = await OpcUaServerFixture.start(
        valueKeys: [speedKey],
        writeKeys: [setpointKey],
      );
      addTearDown(fixture.dispose);
      link = OpcUaUpstreamLink(
        alias: alias,
        endpoint: fixture.endpoint,
        useIsolate: false,
      );
      addTearDown(link.dispose);
      await link.connect(deadline: generous);
    });

    test('a Bad sample arrives as a value with a mapped quality, not as a '
        'dropped sample', () async {
      // The opt-in delivery flag is what makes this possible at all: at the
      // binding's default a Bad sample is DROPPED and its code survives only
      // as English on the error channel (08-01). And a Bad sample carries no
      // payload — statusCode != 0 with a stale-or-null value — so arrival is
      // not evidence of freshness.
      final ref = link.resolve(setpointKey, mappingFor(setpointKey))!;
      final seen = <DynamicValue>[];
      final sub = link.subscribe(ref).listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      fixture.setReadFails(setpointKey);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(seen.any((v) => v.quality.isBad || v.quality.isError), isTrue,
          reason: 'without deliverBadStatus: true the sample never arrives at '
              'all and this key just stops updating — a value frozen at its '
              'last plausible number, which is the exact failure this project '
              'exists to prevent');
      expect(seen.last.value, isNull,
          reason: 'a Bad DataValue has hasValue clear: there is no payload, '
              'and rendering the last one under a bad badge is still a number '
              'nobody measured');
    });

    test('BadNodeIdUnknown is errorConfig, because waiting will not fix it',
        () {
      expect(qualityForOpcUaStatus(opcUaBadNodeIdUnknown), Quality.errorConfig);
      expect(qualityForOpcUaStatus(opcUaBadNodeIdInvalid), Quality.errorConfig);
    });

    test('the code mapping is the table in §C.4', () {
      expect(qualityForOpcUaStatus(0), Quality.good,
          reason: 'an absent status means Good (Part 4), and 0 is a positive '
              'claim rather than the absence of one');
      expect(qualityForOpcUaStatus(null), Quality.good);
      expect(qualityForOpcUaStatus(opcUaBadCommunicationError),
          Quality.badCommFault);
      expect(qualityForOpcUaStatus(opcUaBadTypeMismatch),
          Quality.errorTypeMismatch);
      expect(qualityForOpcUaStatus(opcUaUncertainLastUsableValue),
          Quality.uncertainLastKnown);
      expect(qualityForOpcUaStatus(opcUaBadInternalError), Quality.badCommFault,
          reason: 'a Bad code this table does not name is a comms fault: the '
              'link said something went wrong and waiting might fix it. '
              'Calling it errorConfig would tell the operator to stop waiting');
    });

    test('read against a disconnected server answers inside the deadline and '
        'does not hang', () async {
      final ref = link.resolve(speedKey, mappingFor(speedKey))!;
      await fixture.dispose();

      final stopwatch = Stopwatch()..start();
      final seen = await link
          .read(ref, deadline: const Duration(milliseconds: 300))
          .timeout(const Duration(seconds: 5),
              onTimeout: () => fail('read outran its own deadline — this is '
                  'state_man.dart:1868 inherited rather than prevented, and a '
                  'disconnected PLC pends the caller forever'));
      stopwatch.stop();
      print('DEADLINE read answered in ${stopwatch.elapsedMilliseconds} ms');

      expect(seen.quality.isBad || seen.quality.isError, isTrue);
      expect(seen.value, isNull,
          reason: 'a timed-out read has no reading, and the last one is not '
              'an answer to the question that was asked');
    });

    test('a stale handle never answers a value', () async {
      final ref = link.resolve(speedKey, mappingFor(speedKey))!;
      link.debugBumpEpoch();

      final seen = await link.read(ref, deadline: generous);

      expect(seen.value, isNull,
          reason: 'SRV-07: no stale-handle read ever returns a value. The '
              'handle addresses a node that may now mean a different tag');
      expect(link.peek(ref), isNull);
      final written = await link.write(ref, DynamicValue.of(1),
          cmd: 'cmd-stale', deadline: generous);
      expect(written, isNot(isA<WriteApplied>()));
    });
  });
}
