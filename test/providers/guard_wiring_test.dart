// The wiring: the policy every guard consults, the stream every denial lands
// on, the two providers that put the guards in front of every caller, and the
// counted set of writes the app makes on its own behalf.
//
// `ProviderContainer` rather than widget tests — this is provider graph
// behaviour and does not need a tree.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_access/tfc_access.dart';

import 'package:tfc/access_routes.dart';
import 'package:tfc/route_registry.dart';
import 'package:tfc/providers/access_policy.dart';

void main() {
  group('accessPolicyProvider', () {
    test('answers the same group for every route as accessGroupForRoute does',
        () async {
      // Two sources for one truth: `kRaisedRoutes` reaches the policy through
      // its `routes` parameter and the registry through `installRaisedRoutes`.
      // Comparing the two answers is what makes the duplication safe; an
      // expected-value table here would drift silently the day somebody edits
      // one side.
      RouteRegistry().clearRouteGroups();
      installRaisedRoutes();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final policy = container.read(accessPolicyProvider);

      for (final path in kRaisedRoutes.keys) {
        expect(policy.groupForRoute(path), accessGroupForRoute(path),
            reason: 'the policy and the registry disagree about $path');
      }
      // And a path nobody raised, so the test cannot pass by both sides
      // answering `administer` for everything.
      expect(policy.groupForRoute('/alarms'), accessGroupForRoute('/alarms'));
      expect(policy.groupForRoute('/alarms'), AccessGroup.operate);
    });

    test('carries all six raised routes, not an empty map', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final policy = container.read(accessPolicyProvider);

      expect(kRaisedRoutes, hasLength(6));
      expect(
          policy.groupForRoute('/advanced/page-editor'), AccessGroup.configure);
      expect(policy.groupForRoute(kServerConfigRoute), AccessGroup.administer);
    });

    test('binds no tag, so groupForTag answers null for every key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final policy = container.read(accessPolicyProvider);

      expect(policy.groupForTag('Line1.p_cmd_JogFwd'), isNull);
      expect(policy.groupForTag('anything', member: 'at_all'), isNull);
    });

    test('is the same instance on a second read — it is a pure value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
          identical(container.read(accessPolicyProvider),
              container.read(accessPolicyProvider)),
          isTrue);
    });

    test('the source reaches no provider that could cascade into it', () {
      // The policy is a pure value. A `databaseProvider`, `preferencesProvider`
      // or `accessSessionProvider` read at a provider's build here would make
      // rebuilding the policy cascade — and the session one would rebuild
      // StateMan on every sign-in. Comment lines are stripped so that the
      // comment naming the rule cannot satisfy the test enforcing it.
      final source = File('lib/providers/access_policy.dart').readAsLinesSync();
      final code =
          source.where((l) => !l.trimLeft().startsWith('//')).join('\n');

      for (final forbidden in const [
        'databaseProvider',
        'preferencesProvider',
        'accessSessionProvider',
      ]) {
        expect(code.contains(forbidden), isFalse,
            reason: 'lib/providers/access_policy.dart must not reach '
                '$forbidden — it is the leaf both guards depend on');
      }
      // Non-vacuous: the file really was read, and the stripping did not eat
      // the code along with the comments.
      expect(code, contains('AccessPolicy accessPolicy(Ref ref)'));
      expect(code, contains('accessDenialsProvider'));
    });
  });

  group('accessDenialsProvider', () {
    test('is broadcast: two listeners both see the same denial', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final stream = container.read(accessDenialsProvider);
      final first = <AccessDenied>[];
      final second = <AccessDenied>[];
      final subA = stream.listen(first.add);
      final subB = stream.listen(second.add);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      reportAccessDenial(container.read(_refProbe), _denial('key_mappings'));
      await Future<void>.delayed(Duration.zero);

      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(first.single.itemKey, 'key_mappings');
    });

    test('drops events when nobody is listening rather than buffering them',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final stream = container.read(accessDenialsProvider);
      // Nobody attached yet. A denial four screens ago must not be replayed at
      // the operator the moment a prompt widget mounts.
      reportAccessDenial(
          container.read(_refProbe), _denial('state_man_config'));
      await Future<void>.delayed(Duration.zero);

      final seen = <AccessDenied>[];
      final sub = stream.listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });

    test('the controller is closed when the container is disposed', () async {
      final container = ProviderContainer();
      final stream = container.read(accessDenialsProvider);
      final done = Completer<void>();
      final sub = stream.listen((_) {}, onDone: done.complete);
      addTearDown(sub.cancel);

      container.dispose();
      await done.future.timeout(const Duration(seconds: 2));

      expect(done.isCompleted, isTrue);
    });

    test('reporting after dispose is a no-op, not a StateError', () {
      final container = ProviderContainer();
      final ref = container.read(_refProbe);
      container.read(accessDenialsProvider);
      container.dispose();

      // A guard's `onDenied` can fire from an in-flight write while the app is
      // tearing down. Adding to a closed controller throws; the operator would
      // see a crash instead of nothing.
      expect(
          () => reportAccessDenial(ref, _denial('anything')), returnsNormally);
    });
  });
}

AccessDenied _denial(String key) => AccessDenied(key, AccessGroup.configure);

/// Hands a test the `Ref` that [reportAccessDenial] takes.
///
/// The entry point is typed to `Ref` because every production caller is a
/// provider's `onDenied` closure, which has one. A test has a container, so it
/// borrows one here rather than the entry point growing a second signature for
/// the benefit of tests.
final _refProbe = Provider<Ref>((ref) => ref);
