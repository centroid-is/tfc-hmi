@TestOn('vm')
@Tags(['meta'])

/// The method table of the wire, written down.
///
/// This test exists to break the build on purpose. Every name below is a thing
/// a connected client may ask the gateway to do, so the set of names *is* the
/// access-control policy: capability is defined by surface. Registering a
/// handler on [RelaySession] without editing this file fails; editing this
/// file is the deliberate act that says "yes, the wire may now do this too".
///
/// The expected sets are hand-written literals, never derived from the class
/// they check. A set computed from the session — or spelled with the protocol
/// package's own name constants — would agree with any change and assert
/// nothing. The point is that a human reads a diff of these lines, so the
/// literals are bare strings and the wire spelling is repeated here on
/// purpose. (That is also why the constants class is not imported below: a
/// reference to it would make this file track the very thing it is pinning.)
///
/// Two properties are enforced here:
///
///  * **Closure, in both directions.** The session registers exactly these
///    nine names. One direction alone is half a check: a declared name with no
///    handler answers METHOD_NOT_FOUND from a table claiming to carry it, and
///    a handler under a name nobody wrote down is surface nobody counted. The
///    argument is `suite_integrity_test.dart:22-33`, applied server-side.
///  * **Notifications are not handlers.** The five names the server *sends*
///    are listed in their own literal and asserted absent from the handler
///    table. A notification registered as a handler is a request a client
///    could make of the server — the wrong direction on a one-way name.
///
/// The session publishes its own ledger (`registeredMethods`), so no
/// reflection is needed: `dart:mirrors` would read the class where the ledger
/// already reads the registrations, and the registrations are what ship.
///
/// **Phase note.** Phase 4 pulled `write`, `writeStatus`, `read`, `readFresh`
/// and `readMany` forward from Phase 5: 04-RESEARCH Finding 4 ran the method
/// sweep against a live server and found all five answering `-32601`, which
/// put 28 of the contract suite's 44 checks out of reach over the real
/// gateway. Phase 5 still owns their *semantics* (three-state depth beyond the
/// plumbing, idempotency windows, hold-to-run) and Phase 10 adds the
/// data-service methods (timeseries, history, preferences). Each of those is
/// an edit to [expectedHandlerTable] below, made by a human, in a diff.
library;

import 'package:json_rpc_2/error_code.dart' as rpc_errors;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
// Deliberately narrowed: the wire's name constants are *not* pulled in, so no
// expected set below can accidentally be spelled with the thing it pins.
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart'
    show ConflatingSendBuffer, protocolVersion;
import 'package:tfc_relay_server/src/handle_table.dart';
import 'package:tfc_relay_server/src/relay_session.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/token_validator.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

import 'support/ws_harness.dart';

/// Every method a connected client may call, as of Phase 4 plan 02.
///
/// Hand-written. Not derived. See the library doc for why.
const Set<String> expectedHandlerTable = {
  'hello',
  'ping',
  'subscribe',
  'unsubscribe',
  'write',
  'writeStatus',
  'read',
  'readFresh',
  'readMany',
};

/// Every name the server *sends* as a notification, and therefore may never
/// register as a handler.
///
/// `u` is `update` on the wire — one character on purpose, because it is the
/// hot path. Spelling it as the wire spells it is the whole point of a literal.
const Set<String> expectedNotifications = {
  'u',
  'tick',
  'resync',
  'status',
  'bye',
};

/// Names that are declared but that nothing answers.
///
/// A pure set operation, kept as a named function so the falsification cases
/// below can point it at a deliberately wrong input without constructing a
/// deliberately wrong session. `_on` is private and `_registered` has no
/// setter, which is correct: the way to prove this check bites is to feed the
/// comparison a bad set, not to open a seam in production code so a test can
/// misuse it.
Set<String> unhandled(Set<String> declared, Set<String> registered) =>
    declared.difference(registered);

/// Names that are answered but that nobody declared.
Set<String> undeclared(Set<String> registered, Set<String> declared) =>
    registered.difference(declared);

/// A session over an in-memory channel, with no client on the far end.
///
/// Nothing is called on it — only its ledger is read — so the far end stays
/// empty on purpose.
RelaySession _session() {
  final pair = channelPair();
  final api = FakeStateMan();
  final session = RelaySession.serve(
    channel: pair.server,
    api: api,
    config: ServerConfig(),
    handles: HandleTable(),
    buffer: ConflatingSendBuffer(maxPending: 4096),
    validator: const PermissiveTokenValidator(),
    serverSupported: const [protocolVersion],
  );
  addTearDown(() async {
    await session.close(1000, 'surface test over');
    await api.dispose();
  });
  return session;
}

void main() {
  group('the handler table is closed', () {
    test('every declared name has a handler', () {
      final registered = _session().registeredMethods;

      expect(unhandled(expectedHandlerTable, registered), isEmpty,
          reason: 'a name in expectedHandlerTable that the session never '
              'registered is a method the table claims to carry and the peer '
              'answers METHOD_NOT_FOUND for. Either register it or delete the '
              'line.');
    });

    test('every handler has a declared name', () {
      final registered = _session().registeredMethods;

      expect(undeclared(registered, expectedHandlerTable), isEmpty,
          reason: 'the session registered a method nobody wrote down. The set '
              'of names is the access-control policy, so this is an '
              'authorization change that reached the wire without a diff. Add '
              'it to expectedHandlerTable deliberately, or remove the '
              'registration.');
    });

    test('the table is exactly the nine names a client may call today', () {
      expect(_session().registeredMethods, expectedHandlerTable,
          reason: 'both directions at once, stated as one equality so the '
              'failure prints the whole table rather than a difference');
    });

    test('neither side of the comparison is empty', () {
      // Anti-vacuity: two empty sets satisfy both directions above and prove
      // nothing. If either of these fails, the checks above are asserting
      // that nothing is missing from nothing.
      expect(expectedHandlerTable, isNotEmpty,
          reason: 'an empty literal makes every direction-one check vacuous');
      expect(_session().registeredMethods, isNotEmpty,
          reason: 'a session that registered nothing makes every '
              'direction-two check vacuous — the ledger is not being read');
    });
  });

  group('the closure check bites', () {
    test('an extra registration is caught by name', () {
      final registered = _session().registeredMethods;
      final widened = {...registered, 'dropDatabase'};

      final found = undeclared(widened, expectedHandlerTable);

      expect(found, {'dropDatabase'},
          reason: 'direction two must name the offending method, because the '
              'failure a reviewer reads is the method that appeared');
      expect(found.single, 'dropDatabase');
    });

    test('a declared name with no handler is caught by name', () {
      final registered = _session().registeredMethods;
      final overclaimed = {...expectedHandlerTable, 'ghostMethod'};

      final found = unhandled(overclaimed, registered);

      expect(found, {'ghostMethod'},
          reason: 'direction one must name the method the table claims to '
              'carry but nothing answers');
    });

    test('the comparison reports the offender in its failure text', () {
      // The reason strings above are only worth having if the matcher's own
      // output carries the name. Provoke the real failure and read it.
      late final Object caught;
      try {
        expect(undeclared({...expectedHandlerTable, 'dropDatabase'},
            expectedHandlerTable), isEmpty);
        fail('the closure check passed a widened table');
      } on TestFailure catch (error) {
        caught = error;
      }

      expect('$caught', contains('dropDatabase'),
          reason: 'a failure that does not name the method makes the reviewer '
              'diff the session by hand');
    });
  });

  // The sweep 04-RESEARCH Finding 4 ran against a live gateway, kept as a
  // case. The literal above is a statement about a ledger; this is the same
  // statement made where a client stands, over a real socket, and the two can
  // only disagree if `_on` has stopped being the way a method reaches the
  // table.
  group('every declared name answers over a real socket', () {
    test('no name in the table comes back -32601', () async {
      final fixture = relayFixture();
      await fixture.ready;
      await fixture.hello();
      fixture.served.setValue('CN01.MOT01.speed', 1200);

      // Params good enough to be *dispatched*; a refusal on the contents is a
      // pass here, because the property is that the method exists at all.
      const params = <String, Object?>{
        'sub': 'surface-probe',
        'keys': ['CN01.MOT01.speed'],
        'key': 'CN01.MOT01.speed',
        'cmd': '01JZZZZZZZZZZZZZZZZZZZZZZZ',
        'value': 1200,
        'cmds': ['01JZZZZZZZZZZZZZZZZZZZZZZZ'],
      };

      final methodNotFound = <String>[];
      for (final method in expectedHandlerTable) {
        if (method == 'hello') continue; // one hello per session, spent above.
        try {
          await fixture.request(method, params: params, what: 'a $method answer');
        } on rpc.RpcException catch (error) {
          if (error.code == rpc_errors.METHOD_NOT_FOUND) {
            methodNotFound.add(method);
          }
        }
      }

      expect(methodNotFound, isEmpty,
          reason: 'a name in the frozen table that the wire answers '
              '"unknown method" for is a client staring at a control it can '
              'never use: $methodNotFound');
    }, tags: 'ws');
  });

  group('notifications are not handlers', () {
    test('no notification name is registered as a method', () {
      final registered = _session().registeredMethods;

      final overlap = registered.intersection(expectedNotifications);

      expect(overlap, isEmpty,
          reason: 'a notification registered as a handler is a one-way name '
              'the client can now call: $overlap');
    });

    test('the two literals are disjoint', () {
      expect(expectedHandlerTable.intersection(expectedNotifications), isEmpty,
          reason: 'a name cannot be both something the client asks for and '
              'something the server announces');
    });

    test('the notification literal is not empty', () {
      // Anti-vacuity: an empty notification set makes the disjointness and
      // intersection checks above true for free.
      expect(expectedNotifications, isNotEmpty,
          reason: 'an empty literal makes both notification checks vacuous');
      expect(expectedNotifications, hasLength(5),
          reason: 'update/tick/resync/status/bye — five names as of Phase 3; '
              'changing this count is a deliberate edit');
    });
  });
}
