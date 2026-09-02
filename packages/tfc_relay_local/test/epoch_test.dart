/// The multi-input epoch: the token that says which server this is.
///
/// `@TestOn('!windows')` for `opcua_link_test.dart:1-8`'s reason — the CI matrix
/// includes `windows-latest` and an in-process open62541 `Server` is not run
/// there. The annotation has no granularity below the file, so it goes here and
/// costs the pure arms their Windows run; the `opcua` **tag**, by contrast, is
/// per-group, so `--exclude-tags opcua` still leaves the combination arms
/// selectable. Those two facts pull in opposite directions and this is the
/// split that keeps the pure logic runnable in the cheap lane.
@TestOn('!windows')
library;

import 'dart:async';

import 'package:open62541/open62541.dart' as ua;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:test/test.dart';

import 'support/opcua_server_fixture.dart';

/// The plant's own spelling, as everywhere else in this package.
const String speedKey = 'ST101.CN01.MOT01.speed';
const String secondKey = 'ST101.CN02.MOT01.speed';

/// This link's alias.
const String alias = 'ST101';

/// Generous: none of these cases is a latency measurement.
const Duration generous = Duration(seconds: 10);

/// A reading that is not the reading the next one is.
final DateTime startedAt = DateTime.utc(2026, 9, 2, 6, 30);
final DateTime startedLater = DateTime.utc(2026, 9, 2, 6, 31);

/// The keymapping entry the router would hand `resolve`.
KeyMappingEntry mappingFor(String key, {String? serverAlias = alias}) {
  final node = OpcUANodeConfig(namespace: fixtureNamespace, identifier: key)
    ..serverAlias = serverAlias;
  return KeyMappingEntry()..opcuaNode = node;
}

/// Waits until [link] reports [UpstreamLinkState.connected].
Future<void> awaitConnected(OpcUaUpstreamLink link,
    {Duration within = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(within);
  while (link.state != UpstreamLinkState.connected) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the link never reached connected; it is ${link.state} and the '
          'heartbeat has not ticked');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Polls [predicate] until it holds or [within] runs out.
Future<void> until(bool Function() predicate, String what,
    {Duration within = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(within);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  group('the combination is pure, deterministic and honest', () {
    test('a change in StartTime alone changes the epoch', () {
      final before = EpochInputs(
          startTime: startedAt,
          namespaceArrayHash: hashNamespaceArray(const ['a', 'b']),
          buildStamp: '7');
      final after = EpochInputs(
          startTime: startedLater,
          namespaceArrayHash: hashNamespaceArray(const ['a', 'b']),
          buildStamp: '7');

      expect(after.combine(), isNot(before.combine()),
          reason: 'StartTime moving is the roadmap\'s named detector for a '
              'server that restarted underneath the handles we hold');
    });

    test('a change in the NamespaceArray hash alone changes the epoch', () {
      final before = EpochInputs(
          startTime: startedAt,
          namespaceArrayHash: hashNamespaceArray(const ['a', 'b']),
          buildStamp: '7');
      final after = EpochInputs(
          startTime: startedAt,
          namespaceArrayHash: hashNamespaceArray(const ['a', 'b', 'c']),
          buildStamp: '7');

      expect(after.combine(), isNot(before.combine()),
          reason: 'a re-import that renumbers namespace indices is exactly the '
              'event this input exists to catch, and it can happen with the '
              'TF6100 service — and therefore StartTime — untouched');
    });

    test('a change in the build stamp alone changes the epoch', () {
      final before = EpochInputs(
          startTime: startedAt,
          namespaceArrayHash: hashNamespaceArray(const ['a', 'b']),
          buildStamp: '7');
      final after = EpochInputs(
          startTime: startedAt,
          namespaceArrayHash: hashNamespaceArray(const ['a', 'b']),
          buildStamp: '8');

      expect(after.combine(), isNot(before.combine()),
          reason: 'the build stamp is the one input the integrator controls, '
              'and it is the fallback that survives A1 being wrong');
    });

    test('the same unchanged reading produces the same epoch, one hundred '
        'times', () {
      // The anti-vacuity arm for every case above — three arms saying "these
      // differ" prove nothing if the function differs from itself — and the
      // one that catches a hash folded over a Map with non-deterministic
      // iteration order.
      final epochs = <String>{};
      for (var i = 0; i < 100; i++) {
        epochs.add(EpochInputs(
          startTime: DateTime.utc(2026, 9, 2, 6, 30),
          namespaceArrayHash: hashNamespaceArray(
              const ['http://opcfoundation.org/UA/', 'urn:st101']),
          buildStamp: 'build-4711',
        ).combine());
      }
      print('DETERMINISM 100 combinations produced ${epochs.length} distinct '
          'epoch(s): ${epochs.single}');
      expect(epochs, hasLength(1));
    });

    test('the NamespaceArray hash is order-sensitive', () {
      final forwards =
          hashNamespaceArray(const ['http://opcfoundation.org/UA/', 'urn:st101']);
      final backwards =
          hashNamespaceArray(const ['urn:st101', 'http://opcfoundation.org/UA/']);

      expect(backwards, isNot(forwards),
          reason: 'the namespace INDEX is what a NodeId carries, so the same '
              'uris in a different order name different nodes. A set hash '
              'here would read a renumbering as no change at all');
    });

    test('all three unreadable is marked as such and never agrees with a real '
        'reading', () {
      const nothing = EpochInputs();
      final real = EpochInputs(
          startTime: startedAt,
          namespaceArrayHash: hashNamespaceArray(const ['a']),
          buildStamp: '7');

      expect(nothing.isUnreadable, isTrue);
      expect(isUnreadableEpoch(nothing.combine()), isTrue,
          reason: 'a server that answered nothing must SAY it answered '
              'nothing; an identifier derived from three nulls is a plausible '
              'zero applied to an identity');
      expect(nothing.combine(), isNot(real.combine()));
      expect(isUnreadableEpoch(real.combine()), isFalse);
      expect(real.contributed, hasLength(3),
          reason: 'the epoch has to be able to say which inputs it rests on, '
              'or a partially-blind detector looks exactly like a working one');
      expect(nothing.contributed, isEmpty);
    });

    test('a partial reading still yields an epoch, and says which inputs it '
        'rests on', () {
      final partial = EpochInputs(startTime: startedAt);

      expect(partial.isUnreadable, isFalse);
      expect(isUnreadableEpoch(partial.combine()), isFalse);
      expect(partial.contributed, <EpochInput>{EpochInput.startTime});
      expect(
          partial.combine(),
          isNot(EpochInputs(
                  startTime: startedAt,
                  namespaceArrayHash: hashNamespaceArray(const ['a']))
              .combine()),
          reason: 'a server that stopped answering one of its own identity '
              'nodes has changed in a way this gateway cannot rule out');
    });

    test('the unconnected epoch is neither a reading nor the unreadable one',
        () {
      expect(unconnectedEpoch, isNot(unreadableEpoch),
          reason: '"never asked" and "asked and got nothing" are different '
              'statements, and only the second one is evidence about a server');
      expect(isUnreadableEpoch(unconnectedEpoch), isFalse);
    });
  });

  group('reading the inputs off a real server', () {
    late OpcUaServerFixture fixture;
    late ua.Client client;
    late Timer driver;

    setUp(() async {
      fixture = await OpcUaServerFixture.start(valueKeys: [speedKey]);
      addTearDown(fixture.dispose);
      client = ua.Client(logLevel: ua.LogLevel.UA_LOGLEVEL_ERROR);
      // The crank has to turn for `connect` to complete — measured, not
      // assumed: without this the connect future never finishes and the case
      // dies on the suite timeout rather than on an assertion.
      driver = Timer.periodic(const Duration(milliseconds: 10), (_) {
        try {
          client.runIterate(const Duration(milliseconds: 10));
        } catch (_) {
          // A crank turned against a client a test already deleted.
        }
      });
      addTearDown(() async {
        driver.cancel();
        await client.delete();
      });
      await client.connect(fixture.endpoint).timeout(generous);
    });

    test('StartTime and the NamespaceArray both arrive, and the epoch rests '
        'on both', () async {
      final inputs = await readEpochInputs(client, deadline: generous);

      print('INPUTS start=${inputs.startTime} ns=${inputs.namespaceArrayHash} '
          'stamp=${inputs.buildStamp} contributed=${inputs.contributed}');
      expect(inputs.startTime, isNotNull,
          reason: 'ns=0;i=2257 is Server_ServerStatus_StartTime and every OPC '
              'UA server has it');
      expect(inputs.namespaceArrayHash, isNotNull);
      expect(inputs.buildStamp, isNull,
          reason: 'the build stamp is opt-in: nobody configured a key here');
      expect(inputs.contributed,
          <EpochInput>{EpochInput.startTime, EpochInput.namespaceArray});
      expect(isUnreadableEpoch(inputs.combine()), isFalse);
    });

    test('a configured build-stamp key that does not resolve is the unreadable '
        'case, not an exception', () async {
      final inputs = await readEpochInputs(client,
          deadline: generous,
          buildStampNode: ua.NodeId.fromString(fixtureNamespace, 'no-such-tag'));

      expect(inputs.buildStamp, isNull,
          reason: 'a misconfigured build-stamp key must not take the whole '
              'epoch down with it — the other two inputs still identify the '
              'server, and a throw here would leave the link with no epoch at '
              'all on a server that is answering perfectly well');
      expect(inputs.contributed,
          <EpochInput>{EpochInput.startTime, EpochInput.namespaceArray});
    });

    test('a configured build-stamp key that resolves contributes', () async {
      final inputs = await readEpochInputs(client,
          deadline: generous,
          buildStampNode: fixtureNodeId(speedKey));

      expect(inputs.buildStamp, isNotNull);
      expect(inputs.contributed, hasLength(3));
    });

    test('a server that answers nothing yields the unreadable epoch, not a '
        'plausible one', () async {
      await fixture.dispose();

      final inputs =
          await readEpochInputs(client, deadline: const Duration(seconds: 2));

      expect(inputs.isUnreadable, isTrue);
      expect(isUnreadableEpoch(inputs.combine()), isTrue);
      print('UNREADABLE epoch=${inputs.combine()}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, tags: 'opcua');
}
