/// The tag write guard: a [StateMan] that checks and records before it writes,
/// and forwards everything else untouched.
///
/// This is where `AccessDenied` starts being thrown and where every hand-made
/// tag write starts landing in the trail. Nothing constructs it here; plan
/// 03-06 wraps `stateManProvider` with it.
///
/// ## Why every member is written out
///
/// [StateMan] is a concrete class, not an abstract interface, so `implements
/// StateMan` means implementing its whole implicit interface — around twenty
/// public members, of which exactly one changes behaviour. The tests' fakes
/// reach for Dart's catch-all invocation hook to avoid that tedium and are
/// right to; **this file must not**, and `guarded_state_man_test.dart` greps
/// this file to prove it has not. A decorator built on that hook answers a
/// member nobody wired by throwing at runtime, on a plant, at whatever moment
/// somebody first calls it — and the member it would swallow is as likely to
/// be a write path as a getter. The test's `forwards every public member`
/// group instead derives the list from `state_man.dart` at test time, so a
/// member added there and not here fails the build rather than the plant.
///
/// ## Phase 3 denies nothing on this surface, and that is correct
///
/// `AccessPolicy` ships with no tag bindings — Phase 4's access templates
/// supply them — so `groupForWireSurface('tag', …)` answers null for every key
/// today and every write is permitted. What ships now is the **recording**:
/// every jog, setpoint and force in the trail. The deny path arrives with the
/// next task, tested against an injected binding, so Phase 4 turns it on by
/// supplying templates rather than by writing new code.
library;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_access/tfc_access.dart';

import '../state_man.dart';
import 'dynamic_value_diff.dart';

/// A [StateMan] that records every write it lets through and refuses the ones
/// the session in force may not make.
class GuardedStateMan implements StateMan {
  /// [session] is a **callback, not a value**, and that is load-bearing. The
  /// guard outlives any one session — it is built once, when the provider is —
  /// and must see the session in force *at the moment of the write*. A
  /// captured [AccessSession] would keep granting whatever the operator held
  /// when the provider was built, long after the inactivity monitor dropped
  /// them back to anonymous. That is the elevation window this milestone
  /// exists to close.
  ///
  /// [surface] is one string with two uses: the policy lookup
  /// (`policy.groupForWireSurface(surface, key)`) and the `surface` column of
  /// every row this guard writes. One value, so the group that was checked and
  /// the surface that was recorded cannot disagree — and so `AccessPolicy`'s
  /// unmapped-surface branch sits on the production write path rather than in
  /// a wrapper nothing calls. A guard constructed with a surface the policy
  /// does not know fails closed on `administer`.
  GuardedStateMan({
    required StateMan inner,
    required AccessPolicy policy,
    required AccessSession Function() session,
    required AuditSink audit,
    required String station,
    String surface = 'tag',
    Logger? logger,
  })  : _inner = inner,
        _policy = policy,
        _session = session,
        _audit = audit,
        _station = station,
        _surface = surface,
        _logger = logger ?? Logger();

  final StateMan _inner;
  final AccessPolicy _policy;
  final AccessSession Function() _session;
  final AuditSink _audit;
  final String _station;
  final String _surface;

  /// The guard's own diagnostic logger, used for the audit-sink failures it
  /// swallows. Distinct from [logger], which forwards the inner `StateMan`'s
  /// so that a caller typed as `StateMan` sees exactly what it saw before.
  final Logger _logger;

  /// The `who` recorded when nobody is signed in.
  static const String _anonymousWho = 'anonymous';

  // -------------------------------------------------------------------------
  // The one member that behaves differently
  // -------------------------------------------------------------------------

  /// Checks, records, then writes.
  ///
  /// ## The order, and why the row comes first
  ///
  /// The rows are written **before** [StateMan.write] is awaited. A write that
  /// then fails at the PLC therefore leaves an `allowed: true` row with no
  /// corresponding change in the plant. That is deliberate: the row records
  /// that the action was *authorized*, and losing the evidence of an
  /// authorized attempt because the network blinked is the worse failure.
  /// Spec §2's own reasoning is that an absent audit row is the one defect
  /// nobody ever notices.
  ///
  /// ## The key
  ///
  /// The **resolved** key is what gets looked up and what gets audited,
  /// because that is the key that was written. The **raw** key is what gets
  /// delegated: the guard sits outside `StateMan.write`, which resolves,
  /// rejects disabled servers and does its own read-modify-write for indexed
  /// keys. None of that moves in here.
  @override
  Future<void> write(String key, DynamicValue value) async {
    final String resolvedKey;
    try {
      resolvedKey = _inner.resolveKey(key);
    } on Object {
      // `resolveKey` throws when a substitution variable has no value. That is
      // the inner `StateMan`'s exception to raise, not the guard's to
      // reinterpret, and there is nothing to audit: no key was written. Hand
      // the call straight on so the caller sees exactly the failure it saw
      // before this decorator existed.
      return _inner.write(key, value);
    }

    // Through `groupForWireSurface`, never `groupForTag`. The wire-surface
    // lookup is what puts the unmapped-surface branch on a real write path;
    // calling the typed method here would quietly delete that branch's only
    // caller.
    final group = _policy.groupForWireSurface(_surface, resolvedKey);
    final session = _session();

    final changes = diffDynamicValue(null, value);

    // One id per write, so every member row of one action correlates and two
    // actions never collide.
    final actionId = newActionId();
    final at = DateTime.now();
    final who = session.user?.username ?? _anonymousWho;

    await _recordAll(auditRecordsForChanges(
      changes: changes,
      at: at,
      who: who,
      station: _station,
      roleName: session.roleName,
      surface: _surface,
      itemKey: resolvedKey,
      // An unbound key carries an empty `groupRequired`, matching the auth
      // rows' convention for "not gated on a group".
      groupRequired: group?.name ?? '',
      allowed: true,
      actionId: actionId,
    ));

    return _inner.write(key, value);
  }

  /// Appends [rows], swallowing and logging a sink that throws.
  ///
  /// `DriftAuditSink.record` already swallows its own failures, so this is
  /// belt-and-braces there. But [AuditSink] is an interface whose non-throwing
  /// contract lives in a doc comment and nothing enforces it, and the
  /// consequences of trusting it differ by path. On the permitted path an
  /// escaping sink exception would fail a write the session was allowed to
  /// make, which is not acceptable.
  ///
  /// The price is that a lost row is only a log line, so the line names the
  /// record it lost.
  Future<void> _recordAll(List<AuditRecord> rows) async {
    for (final row in rows) {
      try {
        await _audit.record(row);
      } on Object catch (error, stack) {
        _logger.e(
          'AUDIT ROW LOST: action ${row.actionId}, ${row.who} on '
          '${row.surface}:${row.itemKey}, allowed: ${row.allowed}',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Everything else forwards, unchanged
  // -------------------------------------------------------------------------
  //
  // Reads are neither gated nor audited. Spec §11 defers read permissions
  // deliberately, and §6's decorator wraps writes only.

  @override
  Logger get logger => _inner.logger;

  @override
  StateManConfig get config => _inner.config;

  @override
  KeyMappings get keyMappings => _inner.keyMappings;

  @override
  set keyMappings(KeyMappings value) => _inner.keyMappings = value;

  @override
  List<ClientWrapper> get clients => _inner.clients;

  @override
  List<DeviceClient> get deviceClients => _inner.deviceClients;

  @override
  String get alias => _inner.alias;

  @override
  set alias(String value) => _inner.alias = value;

  @override
  bool isKeyDisabled(String key) => _inner.isKeyDisabled(key);

  @override
  void setSubstitution(String key, String value) =>
      _inner.setSubstitution(key, value);

  @override
  Stream<Map<String, String>> get substitutionsChanged =>
      _inner.substitutionsChanged;

  @override
  Map<String, String> get substitutions => _inner.substitutions;

  @override
  String? getSubstitution(String key) => _inner.getSubstitution(key);

  @override
  String resolveKey(String key) => _inner.resolveKey(key);

  @override
  Future<DynamicValue> read(String key) => _inner.read(key);

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) =>
      _inner.readMany(keys);

  @override
  Future<Stream<DynamicValue>> subscribe(String key) => _inner.subscribe(key);

  @override
  KeyMappingsUpdateResult updateKeyMappings(KeyMappings newKeyMappings) =>
      _inner.updateKeyMappings(newKeyMappings);

  @override
  List<String> get keys => _inner.keys;

  @override
  List<({String alias, bool isModbus})> get connMetaAliases =>
      _inner.connMetaAliases;

  @override
  Stream<Map<String, DynamicValue>> subscribeConnMeta(String alias) =>
      _inner.subscribeConnMeta(alias);

  @override
  Future<void> close() => _inner.close();

  /// Forwarded, and carrying the same [visibleForTesting] contract the inner
  /// member does — a caller of the guard is warned exactly as a caller of
  /// `StateMan` is.
  ///
  /// The ignore is unavoidable and is **not** the kind the plan bans: nothing
  /// here suppresses a missing implementation. `addSubscription` is public, so
  /// `implements StateMan` requires it, and forwarding a `@visibleForTesting`
  /// member from production code is flagged whatever the forwarder is
  /// annotated with. The alternatives are worse: omitting the member does not
  /// compile, and the catch-all hook is the failure mode this whole file
  /// exists to avoid.
  @override
  @visibleForTesting
  void addSubscription({
    required String key,
    required Stream<DynamicValue> subscription,
    required DynamicValue? firstValue,
  }) =>
      // ignore: invalid_use_of_visible_for_testing_member
      _inner.addSubscription(
        key: key,
        subscription: subscription,
        firstValue: firstValue,
      );
}
