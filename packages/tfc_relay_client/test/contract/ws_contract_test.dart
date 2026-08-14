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
/// See [unreachableChecks] for the other 23 and why each one is there. The
/// number goes **up** as the gateway grows handlers and as the observables in
/// [unreachableChecks]'s third group get their side channel; it must never go
/// down without the gap list growing to match, which the arithmetic case below
/// enforces.
const int reachableChecks = 21;

/// Every check this leg does not yet pass, by name, grouped by cause.
///
/// Three distinct causes, and only the third is a defect in this package:
///
///  1. **The gateway has no handler** (13). `browse.*`, `timeseries.*`,
///     `historyViews.*` and `preferences.*` all answer -32601 method-not-found.
///     Phase 10 owns them. Nothing on the client side can close these; the
///     client's sub-APIs (`client_sub_apis.dart`) already send the right
///     methods and get told the server has never heard of them.
///
///  2. **The observable does not survive the gateway** (2). The plant's
///     `upstreamWriteAttempts` and `mintedCmds` are keyed by the `cmd` the
///     *plant* saw, and the gateway mints its own when it forwards a write —
///     so a client-minted id can never be correlated against the plant's
///     counter from this side. `client_harness.dart` throws `UnsupportedError`
///     rather than returning the 0 that would make the no-auto-retry check
///     pass vacuously, which is why these two are red instead of falsely
///     green. Closing them needs the side channel 04-RESEARCH Finding 4
///     describes, or a `upstreamWriteAttempts:` hook wired to a correlation
///     the gateway publishes.
///
///  3. **A real behavioural gap between the two implementations** (8). These
///     are the ones worth chasing: a readback that does not reach the client's
///     store, a pending write that is not visible on the value, a `readMany`
///     that does not answer for every key asked of it, a forced read that
///     comes back null, a quality that improves on its own after an upstream
///     drop, and two notification-count cases whose anti-vacuity arm never
///     sees its changed key. Each one is a property an operator depends on and
///     each has a named check waiting for it.
const List<String> unreachableChecks = <String>[
  // 1 — no handler on the gateway (Phase 10).
  'the address space has a top level, and every root is identifiable',
  "expanding a folder yields that folder's children, not another's",
  "a node's detail carries its data type, and a variable's carries a reading",
  'a resolved path runs root to leaf, and every step is a real edge',
  'a target that does not exist resolves to null, not empty and not a throw',
  'folders and variables expand; methods do not',
  'a recorded series comes back inside the window, oldest first',
  'every requested series gets an entry, including the silent ones',
  'a downsampled series is bounded and still reaches both ends of the window',
  'a history view survives create, list, read back and delete',
  'a saved time window survives add, list and delete',
  'every typed preference round-trips and containsKey agrees',
  'a preference change reaches a second listener',
  // 2 — the observable does not survive the gateway (04-RESEARCH Finding 4).
  'exactly one upstream attempt per cmd — nothing re-sends an operator write',
  'every write mints its own 26-character cmd',
  // 3 — a real behavioural gap in RemoteStateMan or the gateway's forwarding.
  'an unchanged value notifies nobody',
  'a synchronous read costs no round trip',
  'a forced read costs exactly one round trip and is never older than the cache',
  'a batched read answers for every key asked of it, including empty ones',
  'quality never improves on its own',
  'a write in flight when the link drops is unknown, never a failure',
  'a write in flight is visible as pending on the value',
  'the store shows the readback, not the value that was typed',
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
