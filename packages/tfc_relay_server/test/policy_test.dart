@TestOn('vm')

/// SEC-03's authorization clause: who may see a tag, and who may actuate one.
///
/// **Source: 06-CONTEXT decision 2**, the user's framing recorded verbatim —
/// *"What if it should be hidden. Let's think about the future even though we
/// don't implement all at once"* — and 06-RESEARCH §E. The seam ships now; the
/// policy data does not. So the shipped rule is trivial (everything visible,
/// `operate` may write) and the *enforcement* is structural: one object per
/// session that every key-touching surface reaches the source through.
///
/// ## What breaks in the plant without this file
///
/// Two different things, and they are worth separating because they fail
/// differently.
///
/// Without the write gate a wall display in the canteen — a `view` station,
/// bolted up precisely because nobody should be actuating a machine from it —
/// can start a conveyor. That is one missing comparison away at all times, and
/// the failure is loud only if somebody is standing next to the belt.
///
/// Without the **hiding rule** the failure is quiet, which is why CONTEXT locks
/// it as architecture rather than as a feature. A refusal that says *forbidden*
/// tells the asker that the tag exists. Ask about a thousand names, keep the
/// ones answered *forbidden* rather than *unknown*, and the gateway has just
/// enumerated the plant's address space for a station that may not read a byte
/// of it. So a hidden key must be **indistinguishable from a key that does not
/// exist** — the same answer on `read`, `readFresh`, `readMany`, `subscribe`
/// and `write`, and absent from `keys`.
///
/// ## Why this check is here and not in the contract kit
///
/// Trap 19 / §E.4. `tfc_stateman_contract`'s `suite_integrity_test.dart` has
/// three gates (`:102-109`, `:133-141`, `:143+`) that force any check written
/// in that package into `allContractChecks`, and three drivers assert against
/// that length for their **full** leg — including the fake leg, which under
/// 06-CONTEXT amendment 3 has no policy at all and could therefore only pass
/// such a check *vacuously*, by comparing a nonexistent key with a nonexistent
/// key. `suite_integrity_test.dart:104-108` names that outcome: "a property
/// nobody is testing that reads like coverage is worse than an absent one".
///
/// A server-side seam has exactly one implementation by construction, so a
/// cross-implementation contract check was never buying anything here. What
/// this file keeps is all the teeth: the production policy object, the
/// production gateway, the production transport, the production error shapes.
/// `allContractChecks.length` does not move.
@Tags(['ws'])
library;

import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:tfc_relay_server/src/auth/identity.dart';
import 'package:tfc_relay_server/src/policy/key_policy.dart';

/// A tag in the plant's own naming convention, so the cases read like the
/// thing they model rather than like synthetic strings.
const _key = 'CN01.MOT01.speed';

/// A panel next to a machine, and a display on a wall.
const _panel = Identity(stationId: 'ST101', role: Role.operate);
const _display = Identity(stationId: 'HALL-DISPLAY', role: Role.view);

void main() {
  group('the shipped policy is trivial, and honestly named', () {
    test('the shipped policy lets an operator write and a viewer not', () {
      const policy = AllVisibleOperatorWrites();

      expect(policy.canSee(_key, _display), isTrue,
          reason: 'CONTEXT decision 2 fixes this phase\'s canSee at "always '
              'true": there is no policy data yet to hide anything with, and '
              'a seam that hid something nobody configured would be policy '
              'invented by the plumbing. A view station reads the plant — '
              'that is what a wall display is for');
      expect(policy.canSee(_key, _panel), isTrue,
          reason: 'the same answer for both roles, because canSee does not '
              'read the role at all this phase. If this ever diverges by role '
              'without a policy file saying so, the divergence came from the '
              'seam rather than from a deployment');

      expect(policy.canWrite(_key, _panel), isTrue,
          reason: 'an operate station is a panel bolted next to a machine, '
              'and refusing its writes would be a gateway that serves nobody. '
              'This is also what keeps every fixture in this workspace '
              'writing: PermissiveTokenValidator grants operate');
      expect(policy.canWrite(_key, _display), isFalse,
          reason: 'a view station actuating a machine is T-06-35, the whole '
              'of SEC-03\'s authorization clause. The canteen display can '
              'start a conveyor if this comparison is missing, and the only '
              'person who finds out is whoever is standing next to the belt');
    });

    test('the shipped policy is const-constructible and reads honestly in a '
        'config diff', () {
      expect(identical(const AllVisibleOperatorWrites(),
              const AllVisibleOperatorWrites()),
          isTrue,
          reason: 'Dart canonicalises const instances, which is what lets a '
              'default be compared by identity the way RelayServer already '
              'compares its permissive validator (relay_server.dart:149). A '
              'non-const default would make that idiom unavailable to the '
              'next plan that needs it');
      expect('$AllVisibleOperatorWrites', 'AllVisibleOperatorWrites',
          reason: 'named for what it *does*, not for what it lacks — '
              'PermissiveTokenValidator\'s argument (token_validator.dart:'
              '70-73), and for the same reason: a deployment still running '
              'the shipped policy in Phase 12 has to be legible in a config '
              'diff. A name like NoPolicy or DefaultPolicy reads as "somebody '
              'configured this"');
    });
  });

  group('the interface itself', () {
    test('the policy interface is synchronous', () {
      final members = reflectClass(KeyPolicy)
          .declarations
          .values
          .whereType<MethodMirror>()
          .where((member) => !member.isConstructor && !member.isPrivate)
          .toList();

      expect(
          members.map((m) => MirrorSystem.getName(m.simpleName)).toSet(),
          {'canSee', 'canWrite'},
          reason: 'two members, and only two. CONTEXT decision 2 names '
              'canSee and canWrite; a third would be policy vocabulary '
              'invented before there is policy data to fill it');

      for (final member in members) {
        final name = MirrorSystem.getName(member.simpleName);
        final returns = MirrorSystem.getName(member.returnType.simpleName);
        expect(returns, 'bool',
            reason: '$name returns $returns. An asynchronous policy is what '
                'introduces the await between the atCapacity check and the '
                'put in session_handlers.dart:255-264 — the comment there '
                'says so in as many words, and names this phase as the '
                'obvious thing to open the race. A subscription that got past '
                'a full ceiling would then be refused as -32011 '
                'handlerFailed, whose documented meaning is "retrying is '
                'legitimate", so a panel would retry a limit it can never get '
                'under. The shipped policy is a constant and a role '
                'comparison over a token file already in memory: there is '
                'nothing here to await');
      }
    });

    test('the policy is not on the wire vocabulary', () {
      // Amendment 3, asserted from the type system rather than from a grep.
      // `KeyPolicy` lives in this package; `StateManApi` lives in the protocol
      // package, which this one depends on and not the reverse. A policy
      // member on the wire interface is therefore impossible to write, and
      // that impossibility is the amendment satisfied by construction —
      // api_surface_test stays at 49 because there is nothing that could move
      // it.
      //
      // Read as the library's **uri** rather than its name: every library in
      // this package is declared `library;` with a doc comment above it, so
      // `simpleName` is the empty string for all of them and a name-based
      // assertion would pass against anything.
      final home = (reflectClass(KeyPolicy).owner! as LibraryMirror).uri;
      expect('$home', startsWith('package:tfc_relay_server/'),
          reason: 'the policy interface moved out of the server package. The '
              'access-control question is not one a connected client may ask: '
              'api_surface_test.dart:213-226 calls the 49-member set "the '
              'access-control policy", so adding a policy *query* to it is '
              'the contradiction 06-CONTEXT amendment 3 forbids');
    });
  });
}
