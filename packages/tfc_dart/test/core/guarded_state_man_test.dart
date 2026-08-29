// The tag write guard: what it records, what it refuses, and what it leaves
// alone.
//
// Everything the guard touches is real — a real `AccessPolicy`, real
// `AccessSession` values, real `DynamicValue`s and the real
// `diffDynamicValue`. Only the two ends are stand-ins: the `StateMan` beneath
// it and the `AuditSink` beside it, both of which record into **one ordered
// journal** so that "the row was written before the delegate call" is an
// assertion about a list rather than a claim in a comment.

import 'dart:async';
import 'dart:io' show File;

import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:test/test.dart';
import 'package:tfc_access/tfc_access.dart';

import 'package:tfc_dart/core/access/guarded_state_man.dart';
import 'package:tfc_dart/core/state_man.dart';

// ---------------------------------------------------------------------------
// The journal
// ---------------------------------------------------------------------------

/// One ordered record of everything that happened, from both stand-ins.
///
/// Two separate lists could not answer "did the row precede the delegate
/// call?", which is the ordering spec §6 makes a requirement rather than an
/// illustration. So both the inner `StateMan` and the `AuditSink` append here.
class _Journal {
  final List<Object> entries = <Object>[];

  List<_WriteCall> get writes => entries.whereType<_WriteCall>().toList();
  List<AuditRecord> get rows => entries.whereType<AuditRecord>().toList();
  List<_ReadCall> get reads => entries.whereType<_ReadCall>().toList();

  /// Position of the first entry satisfying [test], or -1.
  int indexWhere(bool Function(Object) test) => entries.indexWhere(test);
}

class _WriteCall {
  _WriteCall(this.key, this.value);
  final String key;
  final DynamicValue value;
  @override
  String toString() => '_WriteCall($key)';
}

class _ReadCall {
  _ReadCall(this.key);
  final String key;
  @override
  String toString() => '_ReadCall($key)';
}

// ---------------------------------------------------------------------------
// The two stand-ins
// ---------------------------------------------------------------------------

/// A `StateMan` that records rather than talking to a PLC.
///
/// `noSuchMethod` is the repo's test idiom for this
/// (`start_stop_button_widget_test.dart:303`) and is fine *here*: a test that
/// reaches an unwired member fails loudly in a test run. It is banned in
/// `guarded_state_man.dart`, where the same failure would land on a plant.
class _RecordingStateMan implements StateMan {
  _RecordingStateMan(this._journal);

  final _Journal _journal;

  /// Keys whose resolution fails, as `resolveKey` fails for an unresolved
  /// substitution variable (`state_man.dart:1627`).
  final Set<String> unresolvable = <String>{};

  /// `write` -> `resolveKey` substitutions, so a test can tell the raw key the
  /// caller passed from the resolved key the audit row must carry.
  final Map<String, String> resolutions = <String, String>{};

  final Map<String, DynamicValue> readValues = <String, DynamicValue>{};

  @override
  final Logger logger = Logger(level: Level.off);

  @override
  String resolveKey(String key) {
    if (unresolvable.contains(key)) {
      throw StateManException('Unresolved substitution variable in "$key"');
    }
    return resolutions[key] ?? key;
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    _journal.entries.add(_WriteCall(key, value));
    // The real `write` resolves first and throws before it reaches a client,
    // so a guard that delegated an unresolvable key must see that exception.
    if (unresolvable.contains(key)) {
      throw StateManException('Unresolved substitution variable in "$key"');
    }
  }

  @override
  Future<DynamicValue> read(String key) async {
    _journal.entries.add(_ReadCall(key));
    return readValues[key] ?? DynamicValue(value: 0);
  }

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    for (final key in keys) {
      _journal.entries.add(_ReadCall(key));
    }
    return {for (final key in keys) key: readValues[key] ?? DynamicValue(value: 0)};
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    _journal.entries.add(_ReadCall(key));
    return const Stream<DynamicValue>.empty();
  }

  @override
  List<String> get keys => const ['CN04.MOT01.HMI', 'CN05.MOT01.HMI'];

  @override
  Map<String, String> get substitutions => const {'station': 'CN04'};

  @override
  String? getSubstitution(String key) => substitutions[key];

  @override
  bool isKeyDisabled(String key) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '_RecordingStateMan: ${invocation.memberName} is not wired in this '
        'test. Wire it rather than reaching for a looser fake.',
      );
}

/// An `AuditSink` that appends into the shared journal.
///
/// [failWith] makes it throw, which the `AuditSink` interface does not forbid:
/// its non-throwing contract lives in a doc comment and `DriftAuditSink`
/// honours it, but a Phase 5 or relay implementation is free not to.
class _RecordingAuditSink implements AuditSink {
  _RecordingAuditSink(this._journal);

  final _Journal _journal;

  /// When non-null, every `record` call throws this instead of appending.
  Object? failWith;

  @override
  Future<void> record(AuditRecord entry) async {
    final failure = failWith;
    if (failure != null) throw failure;
    _journal.entries.add(entry);
  }
}

/// An `AccessPolicy` that records what it was asked.
///
/// A subclass rather than a fake, so the answers are the real policy's — the
/// only thing added is the log of `(surface, key, member)` triples, which is
/// what lets a test prove the surface that was *checked* is the surface that
/// was *recorded*.
class _RecordingPolicy extends AccessPolicy {
  _RecordingPolicy({super.tagBindings});

  final List<({String surface, String key, String? member})> lookups =
      <({String surface, String key, String? member})>[];

  @override
  AccessGroup? groupForWireSurface(String surface, String key,
      {String? member}) {
    lookups.add((surface: surface, key: key, member: member));
    return super.groupForWireSurface(surface, key, member: member);
  }
}

// ---------------------------------------------------------------------------
// Sessions and values
// ---------------------------------------------------------------------------

/// Nobody signed in. Anonymous is the `Operator` role by construction.
final AccessSession _anonymous =
    AccessSession.anonymous(const {AccessGroup.operate});

/// A signed-in shift leader: operate plus setpoints, and nothing else.
final AccessSession _shiftLeader = AccessSession(
  user: const AuthenticatedUser(
    username: 'gudrun',
    roleName: 'Shift Leader',
    displayName: 'Guðrún',
  ),
  groups: const {AccessGroup.operate, AccessGroup.setpoints},
  expiresAt: DateTime.utc(2030),
);

/// A struct built the way the copy-on-write assets build one
/// (`conveyor.dart:2383`): a fresh value with members assigned by name.
DynamicValue _struct(Map<String, Object?> members) {
  final v = DynamicValue();
  members.forEach((key, value) {
    v[key] = value is DynamicValue ? value : DynamicValue(value: value);
  });
  return v;
}

/// A `TagBindingLookup` binding exactly [bound] to [group] and nothing else.
///
/// This is the injected lookup Phase 4's access templates will replace. It is
/// how Phase 3 tests a deny path that nothing turns on until then.
TagBindingLookup _bind(String bound, AccessGroup group) =>
    (String key, String? member) => key == bound ? group : null;

void main() {
  late _Journal journal;
  late _RecordingStateMan inner;
  late _RecordingAuditSink audit;
  late _RecordingPolicy policy;
  late AccessSession current;

  setUp(() {
    journal = _Journal();
    inner = _RecordingStateMan(journal);
    audit = _RecordingAuditSink(journal);
    policy = _RecordingPolicy();
    current = _anonymous;
  });

  GuardedStateMan build({
    AccessPolicy? withPolicy,
    String surface = 'tag',
  }) =>
      GuardedStateMan(
        inner: inner,
        policy: withPolicy ?? policy,
        session: () => current,
        audit: audit,
        station: 'SVN-NES-OT-CL02',
        surface: surface,
        logger: Logger(level: Level.off),
      );

  group('the decorator', () {
    test('constructs and is a StateMan', () {
      expect(build(), isA<StateMan>());
    });

    test('reads produce zero audit rows and are never gated', () async {
      final guard = build();
      inner.readValues['CN04.MOT01.HMI'] = DynamicValue(value: 42);

      final value = await guard.read('CN04.MOT01.HMI');
      final many = await guard.readMany(['CN04.MOT01.HMI', 'CN05.MOT01.HMI']);
      await guard.subscribe('CN04.MOT01.HMI');

      expect(value.value, 42);
      expect(many.keys, ['CN04.MOT01.HMI', 'CN05.MOT01.HMI']);
      expect(journal.reads, hasLength(4));
      expect(journal.rows, isEmpty,
          reason: 'spec §11 defers read permissions; a read is neither gated '
              'nor recorded');
    });

    test('the non-write members return exactly what inner returns', () {
      final guard = build();

      expect(guard.keys, inner.keys);
      expect(guard.substitutions, inner.substitutions);
      expect(guard.getSubstitution('station'), 'CN04');
      expect(guard.isKeyDisabled('CN04.MOT01.HMI'), isFalse);
      expect(guard.resolveKey('CN04.MOT01.HMI'), 'CN04.MOT01.HMI');
      expect(identical(guard.logger, inner.logger), isTrue);
      expect(journal.rows, isEmpty);
    });
  });

  group('the allow path', () {
    test('an unbound key reaches inner.write with the same key and value',
        () async {
      final guard = build();
      final value = DynamicValue(value: true);

      await guard.write('CN04.MOT01.HMI.p_cmd_Start', value);

      expect(journal.writes, hasLength(1));
      expect(journal.writes.single.key, 'CN04.MOT01.HMI.p_cmd_Start');
      expect(identical(journal.writes.single.value, value), isTrue);
    });

    test('the group lookup goes through groupForWireSurface with the guard\'s '
        'own surface', () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      expect(policy.lookups, hasLength(1));
      expect(policy.lookups.single.surface, 'tag');
      expect(policy.lookups.single.key, 'CN04.MOT01.HMI.p_cmd_Start');
    });

    test('the surface that was checked is the surface that was recorded',
        () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      expect(policy.lookups, hasLength(1));
      expect(journal.rows, isNotEmpty);
      for (final row in journal.rows) {
        expect(row.surface, policy.lookups.single.surface,
            reason: 'a guard that audits one surface while checking another '
                'is worse than no audit');
      }
    });

    test('a permitted write carries who, station, role, origin and allowed',
        () async {
      current = _shiftLeader;
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      final row = journal.rows.single;
      expect(row.who, 'gudrun');
      expect(row.station, 'SVN-NES-OT-CL02');
      expect(row.roleName, 'Shift Leader');
      expect(row.origin, 'operator');
      expect(row.allowed, isTrue);
      expect(row.actionId, isNotEmpty);
    });

    test('an anonymous session is recorded as anonymous in the Operator role',
        () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      expect(journal.rows.single.who, 'anonymous');
      expect(journal.rows.single.roleName, kOperatorRoleName);
    });

    test('an unbound key records an empty groupRequired', () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      expect(journal.rows.single.groupRequired, '',
          reason: "the auth rows' convention for 'not gated on a group'");
    });

    test('the audited itemKey is the resolved key', () async {
      inner.resolutions['{station}.MOT01.HMI.p_cmd_Start'] =
          'CN04.MOT01.HMI.p_cmd_Start';
      final guard = build();

      await guard.write(
          '{station}.MOT01.HMI.p_cmd_Start', DynamicValue(value: true));

      expect(journal.rows.single.itemKey, 'CN04.MOT01.HMI.p_cmd_Start');
      expect(policy.lookups.single.key, 'CN04.MOT01.HMI.p_cmd_Start');
      expect(journal.writes.single.key, '{station}.MOT01.HMI.p_cmd_Start',
          reason: 'the guard sits outside StateMan.write, which resolves the '
              'key itself');
    });

    test('when resolveKey throws, nothing is audited and the exception is the '
        "inner StateMan's own", () async {
      inner.unresolvable.add('{station}.MOT01.HMI.p_cmd_Start');
      final guard = build();

      await expectLater(
        guard.write('{station}.MOT01.HMI.p_cmd_Start',
            DynamicValue(value: true)),
        throwsA(isA<StateManException>()),
      );

      expect(journal.rows, isEmpty);
      expect(journal.writes, hasLength(1),
          reason: 'the guard must not swallow an unresolved key: the caller '
              "sees StateMan's own exception, unchanged");
    });

    test('the audit row is written before the delegate call', () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      final rowAt = journal.indexWhere((e) => e is AuditRecord);
      final writeAt = journal.indexWhere((e) => e is _WriteCall);
      expect(rowAt, isNonNegative);
      expect(writeAt, isNonNegative);
      expect(rowAt, lessThan(writeAt),
          reason: 'spec §6: the row records that the action was authorized, '
              'and losing that evidence because the PLC blinked is the worse '
              'failure');
    });

    test('an audit sink that throws does not prevent a permitted write',
        () async {
      audit.failWith = StateError('the audit database blinked');
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));

      expect(journal.rows, isEmpty);
      expect(journal.writes, hasLength(1));
    });

    test('each write mints one action id, and two writes never share one',
        () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));
      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: false));

      expect(journal.rows, hasLength(2));
      expect(journal.rows[0].actionId, isNot(journal.rows[1].actionId));
    });

    test('the session is read at each write, so a change between two writes '
        'is seen by the second', () async {
      final guard = build();

      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: true));
      current = _shiftLeader;
      await guard.write('CN04.MOT01.HMI.p_cmd_Start',
          DynamicValue(value: false));

      expect(journal.rows[0].who, 'anonymous');
      expect(journal.rows[1].who, 'gudrun',
          reason: 'a captured AccessSession would keep granting whatever the '
              'operator held when the provider was built');
    });

    test('with no baseline a write is one row flagged as having none',
        () async {
      final guard = build();

      await guard.write(
          'CN04.MOT01.HMI', _struct({'p_cmd_JogFwd': true, 'p_cfg_Freq': 42.5}));

      expect(journal.rows, hasLength(1));
      expect(journal.rows.single.member, isNull);
      expect(journal.rows.single.oldValue, isNull);
      expect(journal.rows.single.newValue, contains('p_cmd_JogFwd'));
    });
  });

  group('the source', () {
    test('carries no noSuchMethod', () {
      expect(_guardSourceWithoutComments(), isNot(contains('noSuchMethod')),
          reason: 'a noSuchMethod decorator answers a member nobody wired by '
              'throwing at runtime, on a plant');
    });
  });
}

/// The guard's own source, with comment lines removed.
///
/// The comment stripping is what makes every source assertion here honest:
/// otherwise a comment explaining why there is no `noSuchMethod` would itself
/// fail the test enforcing that there is none.
String _guardSourceWithoutComments() {
  final file = File('lib/core/access/guarded_state_man.dart');
  expect(file.existsSync(), isTrue,
      reason: 'Run this suite from packages/tfc_dart. Without the file these '
          'source assertions would pass vacuously.');
  return file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}
