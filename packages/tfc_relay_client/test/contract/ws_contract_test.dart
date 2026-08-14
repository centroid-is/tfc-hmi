/// The shared contract suite, judged against `RemoteStateMan` over a real
/// WebSocket, in front of a real `RelayServer`, in front of a real plant fake.
///
/// This is CLI-01's headline and the leg that makes it mean something: the
/// same 44 properties `LocalStateMan` is held to, driven through a socket, a
/// gateway session and a handle table. A defect in `RemoteStateMan` shows up
/// here as a *named property* failing rather than as a mystery on a socket.
///
/// **Why the count is asserted and not the greenness.** Copied wholesale from
/// `ws_contract_test.dart:18-27` in the server package, because the argument
/// transfers unchanged: a harness has one cheap way to look green, and it is
/// to declare a capability `false`. Doing that deletes cases, the report says
/// "skipped" rather than "passed", and the suite stays green while properties
/// go unjudged over this transport forever. So two numbers are checked from
/// two different places — what the umbrella *registered* under the flags it
/// was given, and what the runner actually *started* — and both against
/// [allContractChecks] rather than against a literal, because a literal is a
/// number somebody updates to match.
///
/// **The gap is named, not hidden.** [reachableChecks] is what this leg
/// currently *passes*, measured by running it, and [unreachableChecks] lists
/// every check it does not, by name and by cause. The two are asserted to add
/// up to `allContractChecks.length`, so neither can drift: a check that starts
/// passing must be deleted from the gap list for the arithmetic to hold, and a
/// check that regresses cannot be quietly absorbed. That is the whole point of
/// spelling the gap out — a leg that asserted a smaller number with no list
/// stays green forever while the gap never closes.
@TestOn('vm')
@Tags(['contract', 'ws'])
library;

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

import '../support/client_harness.dart';

/// The designated read-only key, carried across from the server package's
/// `ws_contract_test.dart:64` **character-identical**.
///
/// Supplied so the read-only case *runs*: `runWriteContract` drops it when no
/// key is declared, and a dropped case is one fewer than
/// `allContractChecks.length` — which the accounting below would then report
/// as a capability switched off. Correctly, because it would be one.
///
/// Identical on every leg by necessity rather than by tidiness: a leg that
/// judged a different set of cases would make the parity claim meaningless.
const _readOnlyKey = 'ST301.CN21.SEN01.temp';

/// What this leg passes today. Measured, not chosen.
///
/// See [unreachableChecks] for the other 13 and why every one of them is a
/// missing *handler* rather than a missing behaviour. The number goes **up** as
/// the gateway grows those handlers; it must never go down without the gap list
/// growing to match, which the arithmetic case below enforces.
///
/// It was 21 when this leg was first measured (04-09). The other ten were
/// closed rather than excused, and what each of them turned out to be is worth
/// keeping here because the causes were not what the count suggested:
///
///  * **Two** were a real write-safety defect in the gateway. It minted its own
///    `cmd` when forwarding a write, so the id the operator's action was minted
///    under never reached the plant and no attempt count could ever be
///    attributed to it. Fixed in `value_handlers.dart` by forwarding the
///    client's id; `StateManApi.write` grew the `cmd` parameter that lets a
///    relay say "this action already has a name".
///  * **Five** were defects in this package. `WireValue.t` was dropped at all
///    three decode sites, so every value reached the store with no source time
///    and nothing downstream could age it. `readMany` discarded the gateway's
///    `rejected` map, so a key the source cannot serve came back as an absence
///    instead of a fault. And an applied write's readback was left to arrive on
///    the tick-quantised push path, so `await write(...)` routinely returned
///    while the store still held the old value under a pending badge.
///  * **Three** were the harness lying to the gateway rather than either of
///    them misbehaving: it handed the server a source with no address space, so
///    every key a case seeded after construction was classified as a typo and
///    silently never delivered. See `_PlantAddressSpace`.
const int reachableChecks = 31;

/// Every check this leg does not pass, by name — all of them for one cause.
///
/// **The gateway has no handler.** `browse.*`, `timeseries.*`, `historyViews.*`
/// and `preferences.*` all answer -32601 method-not-found. Phase 10 owns them.
/// Nothing on the client side can close these: the client's sub-APIs
/// (`client_sub_apis.dart`) already send the right methods and get told the
/// server has never heard of them.
///
/// These are **not** skipped and **not** red. Each one is handed to
/// `runStateManContract`'s `expectUnreachable`, which runs it and asserts it
/// fails with exactly -32601 — so the suite is green *because* the gap is
/// precisely what this list claims, and any of three things breaks it: the
/// handler landing (the case now passes, and must be deleted from here and
/// judged properly), the case failing some other way (a real defect wearing a
/// known gap's clothes), or the name going stale (the last accounting case).
///
/// The two `cmd`-correlation entries that used to sit here were a genuine
/// write-safety defect and are fixed, not excused; the eight behavioural
/// entries were closed the same way. [reachableChecks] records what each was.
const List<String> unreachableChecks = <String>[
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

void main() {
  var ran = 0;

  final before = contractCasesRegistered;
  group('the whole contract, against a real gateway over a real WebSocket', () {
    setUp(() => ran++);
    runStateManContract(
      relayServedFake,
      readOnlyKey: _readOnlyKey,
      browseFixture: defaultBrowseFixture,
      // The only override this leg takes, and it changes *when* the link is
      // cut, never what is asserted afterwards. See
      // `dropUpstreamUnderAWriteInFlight`: over a socket the default lever
      // disconnects before the write has reached the plant, so the case never
      // reaches the state it is named for.
      dropLinkWithWritesInFlight: dropUpstreamUnderAWriteInFlight,
      // Proven, not skipped: each of these runs and must fail with exactly
      // -32601. See [unreachableChecks].
      expectUnreachable: unreachableChecks.toSet(),
    );
  });
  final registered = contractCasesRegistered - before;

  group('the run itself', () {
    test('every check the suite has was registered against the gateway', () {
      expect(registered, allContractChecks.length,
          reason: 'the umbrella registered $registered of '
              '${allContractChecks.length} checks against a gateway-served '
              'source that declared every capability. A smaller number does '
              'not mean the gateway carries less — it means a capability was '
              'switched off rather than met, and the cases behind it are '
              'unjudged for every panel that uses this client afterwards. Fix '
              'the forwarding; do not lower the flag');
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
      expect(reachableChecks + unreachableChecks.length,
          allContractChecks.length,
          reason: 'this leg claims to pass $reachableChecks checks and names '
              '${unreachableChecks.length} it does not, which is '
              '${reachableChecks + unreachableChecks.length} of '
              '${allContractChecks.length}. The two must account for the whole '
              'suite or the gap is not a gap, it is a number somebody stopped '
              'maintaining — which is exactly the failure mode a named '
              'constant with no list has');
    });

    test('every named gap is a real check name, not a stale string', () {
      final names = allContractChecks.keys.toSet();
      final unknown =
          unreachableChecks.where((name) => !names.contains(name)).toList();
      expect(unknown, isEmpty,
          reason: 'these entries in the gap list match no check in the suite: '
              '$unknown. A gap entry that names nothing is how a list like '
              'this rots: the arithmetic still adds up, the constant still '
              'looks maintained, and a check that started passing years ago '
              'is still being excused');
    });
  });
}
