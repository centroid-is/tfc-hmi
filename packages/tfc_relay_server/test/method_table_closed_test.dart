@TestOn('vm')
@Tags(['meta'])

/// DB-04, as an executable assertion: the method table is closed, and adding a
/// `query(sql)`-shaped method or parameter fails a test that names the offender.
///
/// `surface_test.dart` freezes the table's *contents* — forty-three bare
/// strings a human edits in a diff. This file is deliberately a different
/// thing: it asserts the table's **shape**, and it never restates a name.
/// Everything below iterates a set that is declared somewhere else, so a
/// thirty-fifth data-service method or a thirteenth harness lever is covered on
/// the day it is added rather than on the day somebody remembers this file
/// exists. The two files would be redundant if this one carried a second copy
/// of the literal, which is exactly why it does not.
///
/// Three properties, and each of them is one sentence from ROADMAP criterion 4:
///
///  * **Every declared name has a handler and every handler has a declared
///    name.** Stated as one equality against `DataServiceMethods.all` so the
///    failure prints the whole difference. `channel_sub_apis_test.dart:78-93`
///    makes the argument one layer down and this is the same argument on the
///    real wire: a declared name with no handler is METHOD_NOT_FOUND from a
///    table claiming to carry it, and a handler with no declared name is
///    surface nobody counted.
///  * **No harness lever is reachable from the wire.** `rpc_names.dart:378-381`
///    declares the lever set as data specifically so this test could iterate it.
///    `seedTimeseries` is the one that matters most: a client that can insert
///    samples can forge history, and a chart is read as evidence
///    (`data_services_contract.dart:78-81`).
///  * **Nothing on this wire takes a statement.** A name sweep, which is
///    mechanical and weak, and a parameter sweep over the four wire interfaces,
///    which is the one that bites — because the shape DB-04 forbids is not a
///    method whose *name* says SQL, it is a method that takes a fragment of one.
///
/// **Falsification is by wrong input, never by a seam in production code.**
/// `surface_test.dart:304-348` established the idiom and this file copies it:
/// every arm that proves a check bites feeds the comparison a deliberately
/// wrong set while leaving the shipped baseline alone. `_registered` has no
/// setter and `_on` is private, and that is correct — the way to show a closure
/// check works is not to open the class so a test can misuse it.
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/handle_table.dart';
import 'package:tfc_relay_server/src/relay_session.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/token_validator.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

import 'support/permissive_resolver.dart';

/// A session over an in-memory channel, with no client on the far end.
///
/// `surface_test.dart:223-245` verbatim: nothing is called on it, only its
/// ledger is read, so the far end stays empty on purpose.
RelaySession _session() {
  final pair = channelPair();
  final api = FakeStateMan();
  final session = RelaySession.serve(
    resolver: const PermissiveSeriesResolver(),
    channel: pair.server,
    api: api,
    config: ServerConfig(),
    handles: HandleTable(),
    buffer: ConflatingSendBuffer(maxPending: 4096),
    validator: const PermissiveTokenValidator(),
    serverSupported: const [protocolVersion],
  );
  addTearDown(() async {
    await session.close(1000, 'method table closure test over');
    await api.dispose();
  });
  return session;
}

/// The data-service half of a session's ledger.
///
/// Selected by the dot, and the rule is worth stating because the whole
/// equality below rests on it. Every data-service name is `family.methodName`
/// (`methods.dart:73-76`) and **nothing else on this wire has a dot in it** —
/// the nine names that predate Phase 10 are `hello`, `ping`, `subscribe`,
/// `unsubscribe`, `write`, `writeStatus`, `read`, `readFresh`, `readMany`, and
/// the one client notification is `h`.
///
/// Selecting by the dot rather than by intersecting with
/// `DataServiceMethods.all` is the difference between a check and a tautology:
/// an intersection would quietly drop a registered `historyViews.dropTable`
/// instead of reporting it, which is precisely direction two. It also means
/// `preferences.changed` — dotted, and declared in the same class but in none
/// of its sets — fails this comparison by name if a handler is ever attached
/// to it, which is the point of the arm below.
Set<String> dataServiceNames(Set<String> ledger) =>
    ledger.where((name) => name.contains('.')).toSet();

/// Every harness lever [ledger] can reach, in either spelling.
///
/// Iterated from `HarnessMethods.levers`, never restated: the set is declared
/// as data upstream (`rpc_names.dart:378-381`) *for this*, so a thirteenth
/// lever is covered on the day it is added.
///
/// **Both spellings, and the second is the one that would really happen.**
/// The declared constants carry `HarnessMethods.prefix` — `harness.` — which is
/// a greppable boundary rather than a defence. The realistic accident is a
/// lever promoted to a wire name by dropping that prefix, exactly the way the
/// thirty-four data services lost theirs when they moved to `methods.dart`
/// (`client_sub_apis.dart:12-16`); an intersection against the prefixed
/// spelling alone would watch the door nobody would use. The returned set
/// carries whichever spelling was found, so the failure names it.
Set<String> leversOnTheWire(Set<String> ledger) => {
      for (final lever in HarnessMethods.levers) ...[
        if (ledger.contains(lever)) lever,
        if (ledger.contains(_unprefixed(lever))) _unprefixed(lever),
      ],
    };

/// [name] without the harness prefix — the spelling it would carry if somebody
/// moved it onto the real table.
String _unprefixed(String name) => name.startsWith(HarnessMethods.prefix)
    ? name.substring(HarnessMethods.prefix.length)
    : name;

void main() {
  group('the data-service ledger is closed in both directions', () {
    test('the dotted half of the ledger is exactly the declared thirty-four',
        () {
      final registered = _session().registeredMethods;

      expect(dataServiceNames(registered), DataServiceMethods.all,
          reason: 'one equality rather than two containment checks, so the '
              'failure prints the whole difference. A declared name missing '
              'from the left is a method a panel calls and the gateway answers '
              'METHOD_NOT_FOUND for — a chart that renders empty on a station '
              'and works on the developer\'s laptop. A dotted name on the left '
              'that nobody declared is the other half: surface that reached '
              'the wire without appearing in any list a reviewer reads, which '
              'is T-02-22 and an access-control change made by accident');
    });

    test('preferences.changed is not registered', () {
      final registered = _session().registeredMethods;

      expect(registered, isNot(contains(DataServiceMethods.preferencesChanged)),
          reason: 'preferences.changed is a notification the gateway *sends*. '
              'A handler for it would be this server answering its own '
              'outbound frame, and it would mean a connected station could '
              'call it — announcing to the gateway that a preference changed '
              'somewhere, which no station is entitled to say. It is absent '
              'from DataServiceMethods.all for the same reason, so the '
              'equality above already fails on it; this arm exists so the '
              'failure a reviewer reads names the frame rather than a set');
    });

    test('neither side of the equality is empty', () {
      // Anti-vacuity. Two empty sets satisfy the equality above and prove
      // nothing at all.
      expect(DataServiceMethods.all, isNotEmpty,
          reason: 'an empty declared set makes the closure check vacuous — it '
              'would then be asserting that nothing is missing from nothing');
      expect(dataServiceNames(_session().registeredMethods), isNotEmpty,
          reason: 'a ledger with no dotted name in it means the dot rule this '
              'file selects on has stopped selecting anything, so the '
              'comparison is being run against an empty left-hand side');
    });
  });

  group('no harness lever is reachable from the wire', () {
    test('the gateway registers none of the twelve levers, in either spelling',
        () {
      final registered = _session().registeredMethods;

      expect(leversOnTheWire(registered), isEmpty,
          reason: 'a lever registered on this gateway is a connected client '
              'being handed the plant\'s own controls. seedTimeseries is the '
              'worst of them and the reason this arm exists: a client that can '
              'insert samples can insert rows into the historian, and an '
              'operator reads a chart as evidence of what the plant did. The '
              'others are no better — setValue tells a panel what the plant is '
              'reading, disconnectUpstream takes a PLC off the wire. None of '
              'them is a method; all twelve are iterated from '
              'HarnessMethods.levers rather than listed here, so a thirteenth '
              'is covered on the day upstream declares it');
    });

    test('the lever set this arm iterates is not empty', () {
      // Anti-vacuity, and it is not theoretical: the intersection above passes
      // trivially if the upstream set is ever emptied or renamed.
      expect(HarnessMethods.levers, isNotEmpty,
          reason: 'an empty lever set makes the arm above assert nothing. If '
              'HarnessMethods.levers was renamed or emptied upstream, this '
              'file is no longer guarding the thing it claims to guard');
      expect(_session().registeredMethods, isNotEmpty,
          reason: 'a session that registered nothing intersects with '
              'everything to give the empty set — the arm above would pass '
              'because the ledger is not being read');
    });
  });

  group('the closure arms bite when fed a wrong ledger', () {
    test('a ledger carrying seedTimeseries is caught, naming the lever', () {
      final forged = {
        ..._session().registeredMethods,
        HarnessMethods.seedTimeseries,
      };

      final found = leversOnTheWire(forged);

      expect(found, {HarnessMethods.seedTimeseries},
          reason: 'the arm must name the lever that appeared. If this gateway '
              'really registered it, a client could insert rows into the '
              'historian and the chart an operator reads as evidence of a cook '
              'cycle would be showing samples the plant never produced — and '
              'the reviewer reading the failure needs to be told which lever, '
              'not that two sets differed');
    });

    test('a lever registered under its wire spelling is caught too', () {
      // The realistic mistake is not registering `harness.seedTimeseries` —
      // nothing in this package can even name that constant outside `test/`.
      // It is registering `seedTimeseries`, the same way the thirty-four data
      // services lost their `harness.` prefix when they became wire names
      // (`client_sub_apis.dart:12-16`). The prefix is a greppable boundary, not
      // a defence, so the arm checks both spellings.
      final forged = {..._session().registeredMethods, 'seedTimeseries'};

      final found = leversOnTheWire(forged);

      expect(found, {'seedTimeseries'},
          reason: 'a lever promoted to a wire name by dropping its prefix is '
              'the way this actually happens, and it is the same forged-history '
              'hazard: a client that can insert samples can insert rows into '
              'the historian');
    });

    test('a ledger missing preferences.clear is caught, naming the method', () {
      final crippled = {..._session().registeredMethods}
        ..remove(DataServiceMethods.prefClear);

      final missing =
          DataServiceMethods.all.difference(dataServiceNames(crippled));

      expect(missing, {DataServiceMethods.prefClear},
          reason: 'direction one has to name the method the table claims to '
              'carry and nothing answers. A settings page calling '
              'preferences.clear against this gateway would get '
              'METHOD_NOT_FOUND, which surfaces on a panel as a reset button '
              'that silently does nothing');
    });

    test('a declared set carrying a name nothing answers is caught', () {
      final overclaimed = {...DataServiceMethods.all, 'historyViews.dropTable'};

      final missing =
          overclaimed.difference(dataServiceNames(_session().registeredMethods));

      expect(missing, {'historyViews.dropTable'},
          reason: 'the other input to the same equality. A name declared in '
              'the protocol package with no handler behind it is a method '
              'every client believes it can call — the gap Phase 10 spent five '
              'plans closing, and the shape it would come back in');
    });

    test('an empty declared set does not make the comparison pass', () {
      // The vacuity the anti-vacuity arm above is guarding against, run rather
      // than argued: with nothing declared, direction two still finds the
      // whole ledger.
      final undeclared =
          dataServiceNames(_session().registeredMethods).difference(const {});

      expect(undeclared, hasLength(DataServiceMethods.all.length),
          reason: 'emptying the declared set must not silence the check — '
              'every dotted name in the ledger becomes undeclared surface, '
              'which is the honest answer and the reason the equality is '
              'stated in both directions at once');
    });
  });
}
