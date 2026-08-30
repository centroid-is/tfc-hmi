/// The contract suite with a fault proxy in the path, and the named
/// F-scenarios that need one.
///
/// Two halves, and they answer different questions.
///
/// **The suite through the proxy** asks whether the properties survive two
/// extra loopback hops with a lever on them. The settings are benign — a few
/// milliseconds of latency and a rate no snapshot in this suite comes near —
/// because the claim is *the same 44 properties, judged the same way*, not
/// "the client copes with a bad link", which is the second half's job. The
/// counts are asserted exactly as the WS leg asserts them: a fault path that
/// quietly runs fewer checks is the same defect as a leg that lowered a
/// capability flag, and it is harder to spot because the report still says the
/// fault leg passed.
///
/// **The named scenarios** are `relay-websocket-notes.md` §7's table, driven
/// against `RemoteStateMan` for the first time: F1 (clean drop, single
/// reconnect), F4/F5 (asymmetric and total half-open), F6/F7 (the link dies
/// with a write out), F13 (a high-latency link that must not read as a
/// disconnect) and F18 (a stale frame re-delivered to a stream that has moved
/// on). Each case carries its F-number in its name so the gate in Phase 7 can
/// find what already exists.
///
/// **F18's other half, and what it took to assert it.** A frame from *before*
/// a reconnect used to be untestable here, and the reason was recorded as a
/// deviation: `UpdateParams` carried `sub`, `seq` and `t` and nothing that
/// identified which establishment it belonged to, and a resync restarts the
/// sequence at the gateway's snapshot — so a frame captured before a drop
/// (`seq: 1`) was byte-indistinguishable from the first frame of the session
/// that replaced it. Driving it measured exactly that: the old value applied
/// as an in-sequence batch, and the genuine frame behind it discarded as a
/// replay.
///
/// 04-REVIEW CR-04 closed it with a per-subscription generation minted by the
/// gateway from a counter that spans the whole server — `g` on every `u`
/// frame, and in the subscribe result the client adopts. `an old-generation
/// frame after a reconnect is dropped` below is the deviation converted into
/// an assertion.
///
/// **Every timing assertion is a window.** STATE's Phase 2 handoff measured a
/// connect attempt completing on the far side of a proxy state transition —
/// `t=1204ms forwarding=false connect OK in 189ms` — so a flag read at
/// assertion time does not describe what the connection experienced. Nothing
/// here compares a duration for equality and nothing reads a proxy state at an
/// instant; the bands are the same ones the other two packages use, Linux
/// 20/100 and 75/150 elsewhere, because two packages that disagree about what
/// "on time" means would eventually disagree about whether the gateway is
/// healthy.
///
/// **Every case that depends on prior state carries an anti-vacuity arm.** A
/// fault case is the easiest kind of test to write vacuously: cut a link that
/// was never carrying anything and assert that nothing was lost.
@TestOn('vm')
@Tags(['contract', 'faults'])
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/connection_supervisor.dart' show LinkState;
import 'package:tfc_relay_client/src/failure_taxonomy.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
// The reference implementation's sub-API fakes, for the factory signature: the
// contract barrel exports no implementation on purpose, so a harness that has
// to have something to serve names them from their own library.
import 'package:tfc_stateman_contract/testing/fake_data_services.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

import '../support/client_harness.dart';
import '../support/fault_fixture.dart';

// ---------------------------------------------------------------------------
// The suite, through the proxy.
// ---------------------------------------------------------------------------

/// The designated read-only key, character-identical to the other legs.
///
/// Supplied so the read-only case *runs*: `runWriteContract` drops it when no
/// key is declared, and a dropped case is one fewer than
/// `allContractChecks.length` — which the accounting below would report as a
/// capability switched off. Correctly, because it would be one.
const _readOnlyKey = 'ST301.CN21.SEN01.temp';

/// One-way delay through the proxy for the suite leg.
///
/// Benign on purpose: a round trip crosses the proxy twice, so this is 6 ms on
/// top of a transport whose measured floor is already 50 ms (04-RESEARCH
/// Finding 8), and every `within()` budget inside the suite is 200 ms. A leg
/// that made the suite fail on timing would be reporting the proxy, not the
/// client.
const _benignLatency = Duration(milliseconds: 3);

/// Bytes per second the proxy will forward in each direction during the suite
/// leg.
///
/// 4 MB/s against a page whose largest single message — the 314-key snapshot —
/// is a few tens of kilobytes: the meter is armed and demonstrably in the path,
/// and no message in the suite waits on it for a measurable time.
const _benignThrottle = 4 * 1024 * 1024;

/// What this leg passes today, and it is the WS leg's number by construction.
///
/// The two legs judge the same implementation over the same gateway; the only
/// difference is two loopback hops. If this number and
/// `ws_contract_test.dart`'s ever disagree, one of the two legs is running a
/// different set of checks and the difference is the finding — which is why
/// the accounting case below reads that file rather than trusting this comment.
///
/// 31 until Phase 5, when the suite grew six checks — five hold-to-run
/// properties and one `writeStatus` property — all of them reachable, because
/// the gateway handler behind them landed in the same phase (05-05) rather
/// than being deferred. The WS leg's own comment carries the argument in full.
const int reachableThroughTheProxy = 37;

/// Every check this leg does not pass, by name — all of them for one cause.
///
/// **The gateway has no handler.** `browse.*`, `timeseries.*`, `historyViews.*`
/// and `preferences.*` answer -32601 method-not-found; Phase 10 owns them. The
/// list is identical to `ws_contract_test.dart`'s, and identical on purpose: a
/// proxy in the path cannot add or remove a handler, so any difference between
/// the two lists is a leg that has drifted rather than a transport that
/// behaves differently.
///
/// These are **not** skipped and **not** red. Each is handed to
/// `runStateManContract`'s `expectUnreachable`, which runs it and asserts it
/// fails with exactly -32601 — so the suite is green *because* the gap is
/// precisely what this list claims.
const List<String> unreachableThroughTheProxy = <String>[
  // browse — six checks, no `browse.*` handler on the gateway.
  'the address space has a top level, and every root is identifiable',
  "expanding a folder yields that folder's children, not another's",
  "a node's detail carries its data type, and a variable's carries a reading",
  'a resolved path runs root to leaf, and every step is a real edge',
  'a target that does not exist resolves to null, not empty and not a throw',
  'folders and variables expand; methods do not',
  // data services — seven checks: no `timeseries.*`, `historyViews.*` or
  // `preferences.*` handler either.
  'a recorded series comes back inside the window, oldest first',
  'every requested series gets an entry, including the silent ones',
  'a downsampled series is bounded and still reaches both ends of the window',
  'a history view survives create, list, read back and delete',
  'a saved time window survives add, list and delete',
  'every typed preference round-trips and containsKey agrees',
  'a preference change reaches a second listener',
];

/// The WS leg, read as text so the two gap lists cannot drift apart quietly.
///
/// A file read rather than an import: importing another test library to borrow
/// a constant couples the two legs' *names*, and the name is the part most
/// likely to change. The text is the claim.
const _wsLegPath = 'test/contract/ws_contract_test.dart';

/// One gateway-served client with the proxy in front of it, at benign settings.
///
/// The levers are armed inside `ready` rather than by the case, because the
/// proxy binds asynchronously (the whole reason the dial is a seam) and the
/// suite's factory has to return synchronously — 04-RESEARCH Finding 6, the
/// constraint this package keeps running into.
StateManApi _proxiedServedFake({
  Duration staleAfter = const Duration(milliseconds: 300),
  Set<String> readOnlyKeys = const {},
  Duration writeLatency = Duration.zero,
  FakeBrowse? browse,
  FakeTimeseries? timeseries,
  FakeHistoryViews? historyViews,
  FakePreferences? preferences,
}) {
  final fixture = relayFixture(
    staleAfter: staleAfter,
    readOnlyKeys: readOnlyKeys,
    writeLatency: writeLatency,
    browse: browse,
    timeseries: timeseries,
    historyViews: historyViews,
    preferences: preferences,
    withProxy: true,
  );
  unawaited(fixture.ready.then((_) {
    fixture.proxy.latency = _benignLatency;
    fixture.proxy.throttleBytesPerSec = _benignThrottle;
  }).catchError((Object _) {}));
  return fixture.api;
}

// ---------------------------------------------------------------------------
// The named scenarios.
// ---------------------------------------------------------------------------

/// The key every scenario case drives. Seeded before the gateway starts, so it
/// is in the address space by the time the client subscribes.
const _key = 'ST101.CN01.MOT01.setpoint';

/// How far either side of an expected instant a real event may land.
///
/// STATE's Phase 2 handoff bands, and `bands.dart` in the server package is the
/// same two numbers with the same argument: the Linux leg is a quiet dedicated
/// runner, the hosted macOS and Windows ones are neither, and tens of
/// milliseconds of event-loop jitter there is ordinary.
final Duration _slack = Platform.isLinux
    ? const Duration(milliseconds: 20)
    : const Duration(milliseconds: 75);

/// The budget for "the panel came back", named once and used everywhere.
///
/// A liveness budget rather than a latency measurement: it has to cover a
/// capped backoff draw, a dial, a handshake and a snapshot.
const Duration _recovery = Duration(seconds: 5);

/// Long enough for anything the gateway was going to send to have arrived, on a
/// tick configured at `ServerConfig.minTick`.
///
/// Used only where the property is that *nothing* happened, which is the one
/// shape a poll cannot establish.
const Duration _settle = Duration(milliseconds: 400);

// **A recovery arm ends its outage with a kill, never by lifting a
// blackhole.** Measured, not preferred.
//
// The `writeStatus` re-query goes out on *entry* to `ready`
// (`remote_state_man.dart`, `_onLinkState`) and nowhere else, so any arm
// about the recovery has to take the client out of `ready` and put it back.
// Driven by lowering the freshness deadline and waiting for the watchdog to
// notice a blackholed link, the applied-while-down arm wedged the reconnect
// past a fifteen-second budget in one run of four and finished in under a
// second in the other three. The mechanism is in the lever's own
// documentation: a blackhole swallows *both* directions, so the client's own
// close never reaches the gateway either, and the replacement session has to
// establish beside a session the gateway still believes in.
//
// `killOnce` has none of that — it is the lever F1, F6/F7 and F18 all use,
// the gateway sees the close immediately, and the arms below run in a second.
// The blackhole survives in exactly one place, the `not_received` arm, where
// swallowing the outbound frame *is* the fault being injected; that arm
// restores forwarding before it cuts.

/// The one-way delay F13 imposes. A round trip therefore costs twice this.
const Duration _f13Latency = Duration(milliseconds: 100);

/// The control deadline F13's client is given: comfortably above the round trip
/// the case imposes, which is the whole point — a link that is merely slow must
/// not read as a link that is gone.
const Duration _f13Deadline = Duration(milliseconds: 1500);

void main() {
  var ran = 0;

  final before = contractCasesRegistered;
  group('the whole contract, through a fault proxy', () {
    setUp(() => ran++);
    runStateManContract(
      _proxiedServedFake,
      readOnlyKey: _readOnlyKey,
      browseFixture: defaultBrowseFixture,
      // The only override this leg takes, and it changes *when* the link is
      // cut, never what is asserted afterwards (`client_harness.dart`).
      dropLinkWithWritesInFlight: dropUpstreamUnderAWriteInFlight,
      expectUnreachable: unreachableThroughTheProxy.toSet(),
    );
  });
  final registered = contractCasesRegistered - before;

  group('the run itself', () {
    test('every check the suite has was registered against the fault path', () {
      expect(registered, allContractChecks.length,
          reason: 'the umbrella registered $registered of '
              '${allContractChecks.length} checks through the proxy. A smaller '
              'number does not mean a proxied client carries less — it means a '
              'capability was switched off rather than met, and the cases '
              'behind it are unjudged on the one path where a fault can reach '
              'them');
    });

    test('every registered check actually started', () {
      expect(ran, allContractChecks.length,
          reason: '$ran of $registered registered cases actually ran. The '
              'difference is a case registered and then skipped, which the '
              'registration count cannot see: the report shows a skip reason, '
              'the suite stays green, and the property is as unjudged as it '
              'would have been with the capability off');
    });

    test('the reachable set and the named gap account for every check', () {
      expect(reachableThroughTheProxy + unreachableThroughTheProxy.length,
          allContractChecks.length,
          reason: 'this leg claims to pass $reachableThroughTheProxy checks '
              'and names ${unreachableThroughTheProxy.length} it does not, '
              'which is '
              '${reachableThroughTheProxy + unreachableThroughTheProxy.length} '
              'of ${allContractChecks.length}. The two must account for the '
              'whole suite or the gap is not a gap, it is a number somebody '
              'stopped maintaining');
    });

    test('the fault leg names the same gap as the WS leg', () {
      final ws = File(_wsLegPath);
      // Anti-vacuity: a sweep against a file that is not there passes by
      // having nothing to read, and the working directory `dart test` was
      // invoked from is exactly the sort of thing that changes silently.
      expect(ws.existsSync(), isTrue,
          reason: 'the WS leg was not found at $_wsLegPath, so this comparison '
              'has nothing to compare against and every name below is '
              'excused. Check the directory dart test was invoked from');

      final source = ws.readAsStringSync();
      final missing = unreachableThroughTheProxy
          .where((name) => !source.contains(name))
          .toList();
      expect(missing, isEmpty,
          reason: 'these checks are excused on the fault leg and are not '
              'excused on the WS leg: $missing. The two legs run the same '
              'client against the same gateway and differ only by two loopback '
              'hops, so a check that passes over one and is excused over the '
              'other is either a real fault-path defect wearing a known gap\'s '
              'clothes, or a gap list somebody closed in one place and forgot '
              'in the other');
    });
  });

  group('the named fault scenarios', () {
    test('F1: a clean drop mid-subscription reconnects, resyncs, and delivers '
        'what changed while it was down', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // Anti-vacuity: the page has to have been live before the drop, or
      // "it came back" is a statement about a client that never worked.
      expect(fixture.client.read(_key)?.value, 1200,
          reason: 'the subscription was not carrying the seeded value before '
              'the link was cut, so nothing below is about a recovery');
      final dialsBefore = fixture.seam.dials;
      expect(dialsBefore, greaterThan(0),
          reason: 'the client never dialled at all, so the fixture — not the '
              'fault — is what this case would be measuring');

      fixture.proxy.killOnce();
      // Changed while the link is down, which is F8's half of F1 and the only
      // reason the recovery assertion is not vacuous: a client that resynced
      // and re-delivered the *old* value would look identical without it.
      fixture.served.setValue(_key, 1500);

      await until(
          'the resync to deliver the value that changed during the outage',
          () => fixture.client.read(_key)?.value == 1500,
          budget: _recovery);

      expect(fixture.seam.dials, greaterThan(dialsBefore),
          reason: 'the value arrived without a second dial, so the link was '
              'never actually cut and this case proves nothing about '
              'reconnecting');
      expect(fixture.client.isReady, isTrue,
          reason: 'the value arrived but the client is not back at ready, so '
              'the next call an operator makes still waits on the barrier');
    });

    test('F4: a link that withholds answers degrades honestly — nothing is '
        'aged into looking current', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        config: faultClientConfig(control: const Duration(milliseconds: 400)),
        // Stamped, unlike the other cases' seeds: the gateway puts `t` on the
        // wire only when the source has one (`session_handlers.dart:297-306`),
        // and this is the one case whose property is about the *age* of the
        // cached reading rather than its value. A real PLC reading always
        // carries one.
        seed: (plant) =>
            plant.setValue(_key, 1200, sourceTime: DateTime.now().toUtc()),
      );
      await until('the link', () => fixture.client.isReady);
      final held = fixture.client.read(_key);
      expect(held?.sourceTime, isNotNull,
          reason: 'the cached reading carries no source time, so the '
              'assertion below that its age did not move is comparing two '
              'nulls (the WireValue.t decode defect 04-09 fixed)');

      // The asymmetric half-open: the client's requests still reach the
      // gateway and the gateway's answers are held. The socket stays up, which
      // is what makes this the quiet failure rather than a disconnect.
      fixture.proxy.bufferServerToClient = true;

      final started = DateTime.now();
      Object? failure;
      await fixture.client
          .readFresh(_key)
          .then<void>((_) {}, onError: (Object error) => failure = error);
      final took = DateTime.now().difference(started);

      expect(failure, isA<TimeoutException>(),
          reason: 'a forced round trip during a half-open came back with '
              '$failure. `readFresh` promises the caller a *fresh* value; the '
              'one thing it must never do is quietly answer from the cache, '
              'because then a panel behind a withheld link shows an operator a '
              'reading it has no current evidence for');
      expect(took, greaterThan(const Duration(milliseconds: 400) - _slack),
          reason: 'the call failed in ${took.inMilliseconds} ms, well inside '
              'its own deadline, so something other than the deadline ended '
              'it and the withhold is not what this measured');
      expect(took, lessThan(const Duration(milliseconds: 400) + _recovery),
          reason: 'the deadline did not bound the call: a request that '
              'outlives its deadline is the spinner the deadline exists to '
              'prevent');

      expect(fixture.client.read(_key)?.value, held?.value,
          reason: 'the cached value moved while nothing was arriving, which '
              'means it came from somewhere other than the gateway');
      expect(fixture.client.read(_key)?.sourceTime, held?.sourceTime,
          reason: 'the cached reading\'s source time advanced during an outage '
              'in which no frame arrived. That is the product\'s one '
              'unforgivable failure: a value that ages itself into looking '
              'current is indistinguishable, on screen, from a live one');

      // And the fault is survivable: releasing the direction brings the client
      // back without a reconnect, because the socket never went away.
      fixture.proxy.bufferServerToClient = false;
      fixture.served.setValue(_key, 1500);
      await until('the value after the withhold was released',
          () => fixture.client.read(_key)?.value == 1500,
          budget: _recovery);
    });

    test('F5: a total half-open resolves a write as unknown rather than '
        'refused, and the link recovers', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        config: faultClientConfig(write: const Duration(milliseconds: 400)),
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);
      expect(fixture.client.read(_key)?.value, 1200,
          reason: 'the page was not live before the blackhole, so the '
              'recovery arm at the end is about nothing');

      // Both directions swallowed, sockets still up: the fault the whole
      // project is built against, and the one no `onDone` will ever report.
      fixture.proxy.blackhole();

      final outcome = await fixture.client.write(_key, 1500).timeout(_recovery);

      expect(outcome, isA<WriteUnknown>(),
          reason: 'the write came back $outcome. Nobody knows whether the '
              'setpoint reached the device — the request may have crossed '
              'before the link went silent — and reporting a swallowed link as '
              'a refusal tells an operator a machine definitely did not move '
              'when it may well have');
      expect((outcome as WriteUnknown).reason.kind,
          anyOf(FailureKind.deadlineExpired, FailureKind.linkLost,
              FailureKind.linkDown),
          reason: 'the unknown must name something an integrator can act on; '
              'got ${outcome.reason.kind}');
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the write was sent more than once. On a plant that is a '
              'second stroke of a ram the operator commanded once, and no '
              'amount of link trouble makes it acceptable');
      expect(fixture.client.debugUnresolvedCmds, contains(outcome.cmd),
          reason: 'an unknown outcome that is not held for re-query is an '
              'outcome nobody will ever establish');

      fixture.proxy.blackhole(enabled: false);
      fixture.served.setValue(_key, 1500);
      await until('the link recovering after the blackhole lifted',
          () => fixture.client.read(_key)?.value == 1500,
          budget: _recovery);
    });

    test('F5: a half-open link stops reading ready, and says so', () async {
      // 04-REVIEW CR-06. The watchdog computed all of this correctly and
      // nothing above it could read a word, so the case the whole product is
      // built around — socket up, no frames, values frozen — presented as
      // LinkState.ready, isReady true, Quality.good, and no observable of any
      // kind for as long as the panel stayed on.
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        config: faultClientConfig(freshness: const Duration(milliseconds: 500)),
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);
      expect(fixture.client.viewIsStale, isFalse,
          reason: 'the view was already stale on a healthy link, so the '
              'transition below is not a measurement of the blackhole');

      final transitions = <bool>[];
      final watching = fixture.client.viewFreshness.listen(transitions.add);
      addTearDown(watching.cancel);

      fixture.proxy.blackhole();

      await until('the view to be reported stale',
          () => fixture.client.viewIsStale,
          budget: _recovery);
      expect(transitions, contains(true),
          reason: 'the freshness stream never emitted, so nothing above this '
              'client could render the staleness it had detected');
      await until('the link to stop reading ready',
          () => !fixture.client.isReady,
          budget: _recovery);
      expect(fixture.client.linkState, isNot(LinkState.ready),
          reason: 'a socket that has said nothing for a whole freshness '
              'deadline is one this client must stop believing in; leaving it '
              'at ready is the operator reading a five-minute-old tank level '
              'as current');

      // And it recovers on its own, which is what makes acting on the silence
      // safe: the reconnect loop is the same one every other kind of drop uses.
      fixture.proxy.blackhole(enabled: false);
      await until('the reconnect', () => fixture.client.isReady,
          budget: _recovery);
      expect(fixture.client.viewIsStale, isFalse);
      fixture.served.setValue(_key, 1500);
      await until('values flowing again',
          () => fixture.client.read(_key)?.value == 1500,
          budget: _recovery);
    });

    test('F6/F7: the link dies with a write in flight — unknown, held, and '
        'never re-actuated', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // Stalled at the plant so the cut lands while the write is genuinely
      // out, rather than before it left or after it came back — the ordering
      // `dropUpstreamUnderAWriteInFlight` exists to get right on the other leg.
      fixture.served.stallWrites();
      final pending = fixture.client.write(_key, 1500);
      await until('the write to reach the plant',
          () => fixture.served.writesInFlight > 0,
          budget: _recovery);
      expect(fixture.served.writesInFlight, greaterThan(0),
          reason: 'nothing was parked at the plant, so the cut below would '
              'have hit an idle link and the case would be F1 wearing F6\'s '
              'name');

      fixture.proxy.killOnce();

      final outcome = await pending.timeout(_recovery);
      expect(outcome, isA<WriteUnknown>(),
          reason: 'the write came back $outcome. It was out on the wire when '
              'the link died: the device may have taken it, and the only '
              'honest verdict is that nobody knows');
      expect((outcome as WriteUnknown).reason.kind,
          anyOf(FailureKind.linkLost, FailureKind.linkDown,
              FailureKind.deadlineExpired));
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the write reached the wire more than once');
      expect(fixture.client.debugUnresolvedCmds, contains(outcome.cmd),
          reason: 'the command has to survive the reconnect, because its id is '
              'the only handle `writeStatus` has on it');

      // The recovery asks; it does not re-actuate.
      await until('the writeStatus re-query after the reconnect',
          () => fixture.client.debugWriteStatusQueries.isNotEmpty,
          budget: _recovery);
      expect(fixture.client.debugWriteStatusQueries.first, contains(outcome.cmd),
          reason: 'the re-query went out without asking about the one command '
              'whose fate is unknown');
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the reconnect re-sent the write. That is the single most '
              'dangerous thing this client could do, and it is why recovery is '
              'a question about the command rather than a repeat of it');

      // **What came back, not merely that something went out** (04-REVIEW
      // CR-02). This arm is the one the old shape was missing, and its absence
      // is why nothing noticed that the gateway was answering `not_received`
      // here: the write was received, forwarded, and is parked at the plant
      // right now, and `not_received` is the one verdict that tells an operator
      // it is safe to press the button again.
      await until('the re-query to be answered',
          () => fixture.client.debugWriteStatusAnswers.isNotEmpty,
          budget: _recovery);
      final answered = fixture.client.debugWriteStatusAnswers
          .firstWhere((result) => result.cmd == outcome.cmd,
              orElse: () => fail('the re-query came back with no answer about '
                  '${outcome.cmd}, which is the only command it asked about'));
      expect(answered, isNot(isA<WriteNotReceived>()),
          reason: 'the gateway answered "never received" about a write it had '
              'received and forwarded, and which is upstream at this moment. '
              'That answer sends the operator back to the button');
      expect(answered, isA<WriteUnknown>(),
          reason: 'the write is parked at the plant: nobody knows yet, and '
              'that is the honest answer');
      expect(answered.isSafeToResend, isFalse, reason: 'a write parked at the plant is the one an operator must never be offered a re-send button for: the ram may already be moving');
      expect(fixture.client.debugUnresolvedCmds, contains(outcome.cmd),
          reason: 'an unknown answer settles nothing, so the command stays '
              'held for the next entry to ready to ask about again');

      // Released after the assertions so the plant does not carry a stalled
      // write into teardown.
      fixture.served.releaseWrites();
    });

    test('F6/F7: a write that landed while the link was down comes back '
        'applied, and resolves exactly once', () async {
      // **05-RESEARCH §E.2 gap 2.** The case above only ever reaches the arm
      // where the write is still parked at the plant, so the re-query answers
      // `unknown` and settles nothing. The other half — the write actually
      // *landed* during the outage — is the one that exercises
      // `RemoteStateMan._settle` end to end: the command leaving the
      // unresolved set, the readback adopted, and the late outcome going out
      // on `onWriteResolved` so that an operator who was told "unknown",
      // walked out to look at the machine and came back is told what
      // happened. Nothing drove that path before this arm.
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      final resolved = <WriteResult>[];
      final watching = fixture.client.onWriteResolved.listen(resolved.add);
      addTearDown(watching.cancel);

      /// Every answer this client has been given about [cmd], in order.
      List<WriteResult> answersAbout(String cmd) => fixture
          .client.debugWriteStatusAnswers
          .where((result) => result.cmd == cmd)
          .toList();

      // Stalled at the plant, so the cut lands with the write genuinely
      // upstream rather than before it left.
      fixture.served.stallWrites();
      final pending = fixture.client.write(_key, 1500);
      await until('the write to reach the plant',
          () => fixture.served.writesInFlight > 0,
          budget: _recovery);

      // `killOnce`, the same lever the case above uses, and **not** a
      // blackhole. Driven at a blackhole this arm wedged the reconnect for
      // 15 s in one run of four: the client's own close is swallowed too, so
      // the gateway keeps the dead session — and its subscription — while the
      // replacement session tries to establish. The kill is the fault this arm
      // is about anyway, and it is the one the rest of this file is built on.
      fixture.proxy.killOnce();
      final outcome = await pending.timeout(_recovery);
      expect(outcome, isA<WriteUnknown>(),
          reason: 'the write came back $outcome with the link cut under it; '
              'nobody could know yet');
      expect(fixture.client.debugUnresolvedCmds, contains(outcome.cmd),
          reason: 'the command was not held for re-query, so the resolution '
              'this case is about could never be asked for');

      // **The first re-query still finds it parked**, and that is the state
      // the existing case above ends in. The gateway records
      // `unknown(in_flight)` *before* it crosses into the plant, precisely so
      // that a question asked at this moment is answered "on its way to a
      // machine" rather than "never received".
      await until('the first re-query after the reconnect to be answered',
          () => answersAbout(outcome.cmd).isNotEmpty,
          budget: _recovery);
      expect(answersAbout(outcome.cmd).first, isA<WriteUnknown>(),
          reason: 'the first answer was '
              '${answersAbout(outcome.cmd).first}, not unknown — the write is '
              'stalled at the plant at this instant, so anything else means '
              'this arm never passed through the state it is supposed to '
              'resolve *from* and proves nothing the case above does not');
      expect(resolved.where((result) => result.cmd == outcome.cmd), isEmpty,
          reason: 'an unknown answer settles nothing and must not be announced '
              'to the operator as a resolution');
      expect(fixture.client.read(_key)?.value, isNot(1500),
          reason: 'the client already shows the new value, so the plant took '
              'the write before this case released it and the resolution '
              'below is a subscription update wearing a re-query\'s clothes');

      // And now it lands, with the panel no longer waiting on it.
      fixture.served.releaseWrites();
      await until('the plant to take the write',
          () => fixture.served.writesInFlight == 0,
          budget: _recovery);

      // The next entry to `ready` is what asks again — the re-query goes out
      // there and nowhere else. Counted rather than watched for `isReady`
      // going false: the reconnect can be over before a 10 ms poll sees it.
      final answersBefore = answersAbout(outcome.cmd).length;
      fixture.proxy.killOnce();
      await until(
          'the re-query that goes out after the write had landed',
          () => answersAbout(outcome.cmd).length > answersBefore,
          budget: _recovery);

      final answered = answersAbout(outcome.cmd).last;
      expect(answered, isA<WriteApplied>(),
          reason: 'the write reached the device and the device took it, and '
              'the re-query answered $answered. An operator who was shown '
              '"unknown" and is now shown anything other than "applied" has '
              'been told the machine may not have moved when it did');
      expect(answered.isSafeToResend, isFalse,
          reason: 'a write that has already been applied is not re-send-safe. '
              'Offering the button again here is the second stroke of a ram '
              'the operator commanded once');
      // **What this arm does not force.** The reconnect's own snapshot carries
      // the plant's current reading too, so the store showing 1500 does not
      // isolate `_adoptReadback` from the resync — the same shape 04-REVIEW
      // WR-01 recorded rather than pretended away. What it does isolate is
      // everything below: one emission, and the command settled.
      expect(fixture.client.read(_key)?.value, 1500,
          reason: 'the resolution never reached the store, so the mimic still '
              'shows the setpoint the operator typed over');
      expect(resolved.where((result) => result.cmd == outcome.cmd), hasLength(1),
          reason: 'the late outcome went out '
              '${resolved.where((r) => r.cmd == outcome.cmd).length} times. '
              'Zero means the operator is never told how the unknown ended; '
              'more than one means the panel raises the same resolution twice '
              'and the second one reads as a new event');
      expect(fixture.client.debugUnresolvedCmds, isNot(contains(outcome.cmd)),
          reason: 'the command stayed unresolved after an established answer, '
              'so it is re-queried on every reconnect for the rest of the '
              'shift');
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the recovery re-actuated the plant. It asks what became of '
              'the command; it never repeats it');
    });

    test('F6/F7: an answer of not_received settles the command, and is the '
        'only re-send-safe verdict', () async {
      // **05-RESEARCH §E.2 gap 3.** The server side has this
      // (`value_handlers_test.dart:423-431`); nothing exercised the *client's*
      // handling of a `not_received` answer arriving from a re-query. It is
      // not `WriteUnknown`, so it falls through to `_settle` — and it is the
      // one verdict the re-send-safe getter is true for, which makes this the
      // arm where being wrong sends an operator back to a button.
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      final resolved = <WriteResult>[];
      final watching = fixture.client.onWriteResolved.listen(resolved.add);
      addTearDown(watching.cancel);

      // **Swallowed on the way out**, before the gateway sees a byte of it,
      // and the blackhole is the only lever that can do that: `killOnce`
      // would cut before the frame left or after it arrived, and `sever` on
      // the in-memory pair drops server-to-client only. Blackholed bytes are
      // lost and never replayed (`fault_proxy.dart`, RESEARCH Finding 4),
      // which is what makes the answer below honest rather than merely early.
      //
      // The command is freshly minted, datable, after the outcome log's own
      // start and inside its TTL: the positive evidence the gateway insists on
      // before it will say "never received" (`value_handlers.dart`,
      // `_statusOf`). Forgetting is not evidence.
      fixture.proxy.blackhole();
      final outcome = await fixture.client.write(_key, 1500).timeout(_recovery);

      expect(outcome, isA<WriteUnknown>(),
          reason: 'the write came back $outcome into a swallowed link');
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the frame never left this client, so the gateway has '
              'nothing to have an opinion about and the answer below would be '
              'unremarkable');
      expect(fixture.served.upstreamWriteAttempts(outcome.cmd), 0,
          reason: 'the plant recorded an attempt for a command the link '
              'swallowed, so this case is not about a write that never '
              'arrived');
      expect(fixture.client.debugUnresolvedCmds, contains(outcome.cmd),
          reason: 'an unknown that is not held for re-query is an unknown '
              'nobody will ever establish');

      // Forwarding restored and *then* the link cut: the re-query goes out on
      // entry to `ready` and nowhere else, and a kill is how this file's other
      // cases get there. Waiting for a blackholed link to be noticed by the
      // freshness watchdog instead left the gateway holding a session whose
      // close it never saw, which wedged the replacement's establishment for
      // fifteen seconds in one run of four.
      fixture.proxy.blackhole(enabled: false);
      fixture.proxy.killOnce();
      await until(
          'the re-query to come back with an answer about ${outcome.cmd}',
          () => fixture.client.debugWriteStatusAnswers
              .any((result) => result.cmd == outcome.cmd),
          budget: _recovery);

      final answered = fixture.client.debugWriteStatusAnswers
          .firstWhere((result) => result.cmd == outcome.cmd);
      expect(answered, isA<WriteNotReceived>(),
          reason: 'the gateway answered $answered about a command it demonstrably '
              'never saw. "Unknown" here is merely unhelpful; anything that '
              'settles the command as having happened would be a lie about a '
              'machine');
      expect(answered.isSafeToResend, isTrue,
          reason: 'this is the one verdict that licenses offering the button '
              'again, and it is only safe because the gateway had to date the '
              'command against its own clock to reach it');
      expect(fixture.client.debugUnresolvedCmds, isNot(contains(outcome.cmd)),
          reason: 'never-received is an established answer and must settle the '
              'command; leaving it unresolved re-asks a question the gateway '
              'has already answered, on every reconnect, forever');
      expect(resolved.where((result) => result.cmd == outcome.cmd), hasLength(1),
          reason: 'the operator was shown "unknown" and is owed the '
              'resolution exactly once');
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the client re-sent the write on learning it was never '
              'received. Re-send-safe is a statement about what an operator '
              'may be offered, never about what this client does on its own — '
              'that distinction is the whole of WRT-03');
      expect(fixture.served.upstreamWriteAttempts(outcome.cmd), 0,
          reason: 'the plant was actuated by the recovery');
    });

    test('F6/F7: a refusal over a socket means the plant was untouched',
        () async {
      // **05-RESEARCH §E.2 gap 4, and the direct answer to the CONTEXT threat
      // flag.** The gateway proves this at the handler
      // (`value_handlers_test.dart:355-370`, `upstreamWriteAttempts`
      // unchanged); nothing proved it over a real socket. The claim being
      // judged is the standing ruling that `INVALID_PARAMS` on the write path
      // means definitively no effect — because a refusal that might have
      // actuated is a button an operator presses twice.
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      final cmd = newUlid();
      final first = await fixture.client
          .write(_key, 1500, cmd: cmd)
          .timeout(_recovery);
      expect(first, isA<WriteApplied>(),
          reason: 'the first write under this id came back $first, so the '
              'collision below would be a collision with nothing');
      expect(fixture.served.upstreamWriteAttempts(cmd), 1,
          reason: 'the plant did not record the first write under the id the '
              'client minted, so the count this case reads afterwards is not '
              'about this command');

      // The same id, a different value: two different operator intents under
      // one action id, which 05-03 deliberately keeps a refusal rather than
      // folding into the replay window (D-P5-B).
      final second = await fixture.client
          .write(_key, 1600, cmd: cmd)
          .timeout(_recovery);

      expect(second, isA<WriteRejected>(),
          reason: 'a duplicate-id collision came back as $second. Rejected is '
              'the only honest mapping: the gateway raised before it touched '
              'the plant, so this is the one refusal that carries a guarantee '
              'about the machine');
      expect((second as WriteRejected).reason.kind, FailureKind.serverRefused);
      expect(second.isSafeToResend, isFalse,
          reason: 'a refusal is not a licence to re-send. The defect is in the '
              'caller — two different writes under one id — and repeating it '
              'under a fresh id is an operator decision about a machine, never '
              'this client\'s');
      expect(second.reason.message, contains('nothing was sent'),
          reason: 'the sentence that reaches the operator is what makes the '
              'refusal actionable, and "nothing was sent" is the part that '
              'stops them pressing again to be sure. Got: '
              '${second.reason.message}');
      expect(fixture.served.upstreamWriteAttempts(cmd), 1,
          reason: 'the plant recorded '
              '${fixture.served.upstreamWriteAttempts(cmd)} attempts for this '
              'command. The second frame was refused before the gateway '
              'crossed into the plant, so anything above 1 means '
              'INVALID_PARAMS on the write path does not mean "no effect" — '
              'and every refusal this client has ever reported as definitive '
              'stops being one');
      expect(fixture.served.read(_key)?.value, 1500,
          reason: 'the tag carries the refused value, so the second write '
              'reached the device after all');
      expect(fixture.client.debugWritesSent, 2,
          reason: 'the second frame never left, so the refusal was this '
              'client\'s local duplicate-id guard rather than the gateway\'s '
              '— and the property this case exists to prove is about the '
              'gateway');
      expect(fixture.client.debugUnresolvedCmds, isNot(contains(cmd)),
          reason: 'a refusal is an established answer; holding it for re-query '
              'asks the gateway forever about a write it already refused');
    });

    test('F13: a slow link is slow, not down', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        config: faultClientConfig(control: _f13Deadline, write: _f13Deadline),
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);
      final dialsBefore = fixture.seam.dials;

      // Live: it reaches the connection that is already open, which is the
      // only shape "the link degrades while the panel is connected" comes in.
      fixture.proxy.latency = _f13Latency;

      final started = DateTime.now();
      final value = await fixture.client.readFresh(_key).timeout(_recovery);
      final took = DateTime.now().difference(started);

      expect(value.quality, Quality.good,
          reason: 'a slow answer is still an answer; degrading its quality '
              'because it took 200 ms would grey a healthy plant');
      expect(took, greaterThan(_f13Latency * 2 - _slack),
          reason: 'the round trip took ${took.inMilliseconds} ms, less than '
              'the two one-way delays the proxy was told to impose. The lever '
              'did not reach the open connection, so this case is measuring an '
              'ordinary link');
      expect(took, lessThan(_f13Deadline),
          reason: 'a round trip of ${took.inMilliseconds} ms exceeded the '
              'deadline it was given. That is not a fault report, it is a '
              'false one: the gateway answered');

      // And no false disconnect over a window. Instants are useless here —
      // the whole point is that nothing happens for a while.
      await Future<void>.delayed(_settle);
      expect(fixture.seam.dials, dialsBefore,
          reason: 'the client redialled during a link that was merely slow. A '
              'panel that reconnects on latency turns a congested switch into '
              'a reconnect storm, and the storm is what keeps the switch '
              'congested');
      expect(fixture.client.isReady, isTrue,
          reason: 'the client left ready on a link that was answering');
    });

    test('F18: a stale frame from a stream that has moved on is discarded, '
        'never applied', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // A real frame, captured off the wire rather than hand-written: F18 is
      // about a frame the gateway genuinely sent, and a stand-in would be
      // asserting against a shape somebody guessed. `Methods.update` is `'u'`
      // — one character on purpose, it is the hot path — so the marker comes
      // from the constant rather than from the word "update", which appears
      // nowhere on the wire.
      fixture.served.setValue(_key, 1300);
      await until('an update frame carrying the older value',
          () => fixture.client.read(_key)?.value == 1300);
      final staleFrame = fixture.seam.lastMatching(
          (message) => message.contains('"method":"${Methods.update}"'));
      expect(staleFrame, isNotNull,
          reason: 'no update frame was captured, so the injection below would '
              'deliver nothing and this case would pass by doing nothing');

      // The stream moves on, so the captured frame is now genuinely behind it.
      fixture.served.setValue(_key, 1500);
      await until('the current value',
          () => fixture.client.read(_key)?.value == 1500);

      // Re-delivered: the framing bug, the store-and-forward peer, the
      // reconnect that replayed a queue. Injected rather than provoked because
      // TCP does not duplicate frames on its own — the only way to drive this
      // against a real client is to be the peer that sends it.
      fixture.seam.inject(staleFrame!);
      await Future<void>.delayed(_settle);

      expect(fixture.client.read(_key)?.value, 1500,
          reason: 'the reading fell back to a value the stream had already '
              'moved past. That is the F18 failure exactly: a number from two '
              'batches ago rendered under good quality, with nothing on screen '
              'to say it is old, on a mimic an operator is about to act on. '
              '`ValueStore.applyBatch` judges the sequence before it applies '
              'anything for this reason, and a batch at or behind the last '
              'applied one is discarded rather than written');
      expect(
          fixture.client.complaints
              .where((complaint) => complaint.contains('never announced')),
          isEmpty,
          reason: 'the injected frame named a handle this session does not '
              'know, so it was dropped for the wrong reason and the assertion '
              'above is vacuous: nothing was ever going to be applied');

      // And the client is still usable. A replay makes the resync engine
      // resubscribe — "a duplicate on the wire means the stream is not what
      // the client thought it was" — and against the real gateway that
      // resubscribe is *refused*, because the subscription still exists on the
      // live session (-32602, `subscription_registry.dart:214`). The recovery
      // therefore fails, and the property that matters is that failing
      // recovery costs the panel nothing it was still holding: the cache is
      // untouched, the link is up, and the next call is answered. The gap this
      // leaves is written up in the 04-11 SUMMARY, because closing it is a
      // decision about what `subscribe` means on a live session and not
      // something a test may make on its own.
      final fresh = await fixture.client.readFresh(_key).timeout(_recovery);
      expect(fresh.value, 1500,
          reason: 'a forced round trip after the replay did not come back with '
              'the current reading, so the failed resubscribe took something '
              'down with it');
      expect(fixture.client.isReady, isTrue,
          reason: 'the panel left ready over a link that never closed');
    });

    test('F18: an old-generation frame after a reconnect is dropped', () async {
      final fixture = await faultFixture(
        keys: const {_key},
        withProxy: true,
        seed: (plant) => plant.setValue(_key, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // A real frame from *this* establishment, captured off the wire.
      fixture.served.setValue(_key, 1300);
      await until('an update frame from the first session',
          () => fixture.client.read(_key)?.value == 1300);
      final beforeTheDrop = fixture.seam.lastMatching(
          (message) => message.contains('"method":"${Methods.update}"'));
      expect(beforeTheDrop, isNotNull,
          reason: 'nothing was captured, so the injection below delivers '
              'nothing and this case passes by doing nothing');

      // The link dies and comes back: a new session, a new epoch, a new
      // subscription — and, because the counter spans the gateway rather than
      // the socket, a generation the captured frame cannot match.
      fixture.proxy.killOnce();
      await until('the reconnect', () => fixture.client.isReady,
          budget: _recovery);
      fixture.served.setValue(_key, 1500);
      await until('the current value after the reconnect',
          () => fixture.client.read(_key)?.value == 1500,
          budget: _recovery);

      fixture.seam.inject(beforeTheDrop!);
      await Future<void>.delayed(_settle);

      expect(fixture.client.read(_key)?.value, 1500,
          reason: 'a reading from the session before the drop went onto the '
              'mimic under good quality. Worse than the number itself: it '
              'takes the sequence baseline with it, so the genuine frame at '
              'that seq is then discarded as a replay and the operator keeps '
              'the old number until the tag next changes');
      expect(
          fixture.client.complaints
              .where((complaint) => complaint.contains('never announced')),
          isEmpty,
          reason: 'handles are server-global and never released, so the '
              'captured frame names a handle this session does know. If it '
              'did not, the frame would have been dropped for the wrong '
              'reason and the assertion above would be vacuous');
    });
  });
}
