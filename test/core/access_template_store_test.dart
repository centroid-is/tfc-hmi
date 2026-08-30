// The one gate over both authorization tables.
//
// `access_template` says who may write what; `access_key_binding` says which
// keys it says it for. Both are authorization data, so both sit behind
// `kAccessTemplateGroup` — `users`, not `configure` (spec §7c). The tests here
// drive a `configure`-only session into every write on purpose: that is the
// exact confusion the `users` gate exists to prevent, and it would pass
// unnoticed if only the anonymous case were covered.
//
// Every deny assertion reads the row count back **from the database**, not from
// a mock call count: the claim is that the Drift statement was never issued,
// and only the table can answer that.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/access_template_store.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/database_drift.dart';

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

class _RecordingSink implements AuditSink {
  final List<AuditRecord> rows = [];

  @override
  Future<void> record(AuditRecord entry) async => rows.add(entry);
}

/// A sink that fails every write, for the two "the trail is not the write path"
/// tests.
class _ThrowingSink implements AuditSink {
  int calls = 0;

  @override
  Future<void> record(AuditRecord entry) async {
    calls++;
    throw StateError('the audit database blinked');
  }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// Nobody signed in. Anonymous is Operator by construction (Phase 1).
AccessSession _anonymous() =>
    AccessSession.anonymous(const {AccessGroup.operate});

/// The engineer who can edit pages and key mappings — and must not be able to
/// re-scope who may write what.
AccessSession _configureOnly() => const AccessSession(
      user: AuthenticatedUser(username: 'engineer', roleName: 'Engineering'),
      groups: {AccessGroup.operate, AccessGroup.setpoints, AccessGroup.device, AccessGroup.configure},
    );

/// The administrator who holds `users`.
AccessSession _withUsers() => const AccessSession(
      user: AuthenticatedUser(username: 'admin', roleName: 'Administrator'),
      groups: {AccessGroup.operate, AccessGroup.configure, AccessGroup.users},
    );

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AccessTemplate _conveyor() => AccessTemplate(
      name: 'conveyor',
      rules: const {
        'p_cfg_ManualFreq': AccessGroup.device,
        'p_cmd_JogFwd': AccessGroup.operate,
      },
    );

void main() {
  late AppDatabase db;
  late _RecordingSink sink;
  late List<AccessDenied> denials;
  late AccessSession session;

  AccessTemplateStore buildStore({AuditSink? audit}) => AccessTemplateStore(
        db: db,
        session: () => session,
        audit: audit ?? sink,
        station: 'SVN-NES-OT-CL02',
        onDenied: denials.add,
      );

  Future<int> templateRowCount() async {
    final row =
        await db.customSelect('SELECT COUNT(*) AS c FROM access_template')
            .getSingle();
    return row.read<int>('c');
  }

  setUp(() async {
    db = AppDatabase.inMemoryForTest();
    // Force the schema to be created before the first store call, so a row
    // count read back on the deny path is reading a real, empty table rather
    // than failing to find one.
    await db.customSelect('SELECT 1').getSingle();
    sink = _RecordingSink();
    denials = [];
    session = _withUsers();
  });

  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  // The constant
  // -------------------------------------------------------------------------

  group('kAccessTemplateGroup', () {
    test('is users, and is the only group this store names', () {
      expect(kAccessTemplateGroup, AccessGroup.users,
          reason: 'spec §7c: templates change who may do what, which is the '
              'same concern as roles and the trail, not machine '
              'configuration. Lowering this to configure would let anybody '
              'who can edit a page re-scope the rules that govern the plant.');
    });
  });

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  group('reads', () {
    test('list returns every template with its rules decoded', () async {
      final store = buildStore();
      await store.create(_conveyor());
      await store.create(
          AccessTemplate(name: 'recipes', rules: const {'*': AccessGroup.configure}));

      final all = await store.list();
      expect(all.map((t) => t.name), ['conveyor', 'recipes']);
      expect(all.first.groupFor('p_cfg_ManualFreq'), AccessGroup.device);
      expect(all.last.groupFor(null), AccessGroup.configure,
          reason: 'the whole-key row is kWholeKeyMember, "*"');
    });

    test('template(name) returns null for a name nobody created', () async {
      final store = buildStore();
      expect(await store.template('no-such-template'), isNull);
    });

    test('reads are ungated and unaudited', () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();

      session = _anonymous();
      expect((await store.list()).single.name, 'conveyor');
      expect((await store.template('conveyor'))!.name, 'conveyor');

      expect(sink.rows, isEmpty,
          reason: 'reading the rules is not an authorization change; spec §11 '
              'defers read permissions and a row per render would bury the '
              'writes that matter');
      expect(denials, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // The gate — template writes
  // -------------------------------------------------------------------------

  group('the users gate on template writes', () {
    test('an anonymous session is refused on create and the table is unchanged',
        () async {
      final store = buildStore();
      session = _anonymous();

      await expectLater(
          store.create(_conveyor()), throwsA(isA<AccessDenied>()));

      expect(await templateRowCount(), 0,
          reason: 'the Drift statement must never be issued on the deny path');
      expect(sink.rows, hasLength(1));
      expect(sink.rows.single.allowed, isFalse);
      expect(sink.rows.single.who, 'anonymous');
      expect(sink.rows.single.groupRequired, 'users');
      expect(denials, hasLength(1));
      expect(denials.single.itemKey, 'access_template.conveyor');
      expect(denials.single.required, AccessGroup.users);
    });

    test(
        'a configure-only session is refused on create — configure is not users',
        () async {
      final store = buildStore();
      session = _configureOnly();

      await expectLater(store.create(_conveyor()),
          throwsA(isA<AccessDenied>()),
          reason: 'spec §7c: gate these on **users** — they change '
              'authorization, which is the same concern as roles and the '
              'trail, not machine configuration. An engineer who can edit a '
              'page must not be able to re-scope who may write what.');

      expect(await templateRowCount(), 0);
      expect(sink.rows.single.allowed, isFalse);
      expect(sink.rows.single.roleName, 'Engineering');
    });

    test('a configure-only session is refused on update, rename and delete',
        () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();
      session = _configureOnly();

      await expectLater(
          store.update(AccessTemplate(
              name: 'conveyor', rules: const {'*': AccessGroup.operate})),
          throwsA(isA<AccessDenied>()));
      await expectLater(
          store.rename('conveyor', 'conveyor-strict'),
          throwsA(isA<AccessDenied>()));
      await expectLater(store.delete('conveyor'), throwsA(isA<AccessDenied>()));

      expect(await templateRowCount(), 1,
          reason: 'not one of the three reached the database');
      final stored = await store.template('conveyor');
      expect(stored!.groupFor('p_cfg_ManualFreq'), AccessGroup.device,
          reason: 'the refused update must not have re-scoped anything');
      expect(sink.rows, hasLength(3));
      expect(sink.rows.every((r) => !r.allowed), isTrue);
      expect(sink.rows.every((r) => r.groupRequired == 'users'), isTrue);
      expect(denials, hasLength(3));
    });

    test('an anonymous session is refused on update, rename and delete',
        () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();
      session = _anonymous();

      await expectLater(
          store.update(AccessTemplate(name: 'conveyor', rules: const {})),
          throwsA(isA<AccessDenied>()));
      await expectLater(
          store.rename('conveyor', 'other'), throwsA(isA<AccessDenied>()));
      await expectLater(store.delete('conveyor'), throwsA(isA<AccessDenied>()));

      expect(await templateRowCount(), 1);
      expect(sink.rows, hasLength(3));
      expect(sink.rows.every((r) => !r.allowed), isTrue);
    });

    test('the session is read per call, so an elevation that has since lapsed '
        'grants nothing', () async {
      // T-04-15: the store is built once per operation from providers that
      // outlive any one session. A captured AccessSession would keep granting
      // whatever was held when it was built, after the inactivity monitor had
      // already dropped the operator back to anonymous.
      final store = buildStore();
      await store.create(_conveyor());

      session = _anonymous();
      await expectLater(store.delete('conveyor'), throwsA(isA<AccessDenied>()));
      expect(await templateRowCount(), 1);
    });
  });

  // -------------------------------------------------------------------------
  // The rows
  // -------------------------------------------------------------------------

  group('the audit rows', () {
    test('a create writes one allowed row with a null oldValue and the '
        'encoded rules in newValue', () async {
      final store = buildStore();
      await store.create(_conveyor());

      expect(sink.rows, hasLength(1));
      final row = sink.rows.single;
      expect(row.allowed, isTrue);
      expect(row.surface, AccessSurface.pref.wireName);
      expect(row.itemKey, 'access_template.conveyor');
      expect(row.groupRequired, 'users');
      expect(row.oldValue, isNull, reason: 'there was nothing there before');
      expect(row.newValue, AccessTemplate.encodeRules(_conveyor().rules));
      expect(row.who, 'admin');
      expect(row.station, 'SVN-NES-OT-CL02');
      expect(row.origin, 'operator');
      expect(row.actionId, isNotEmpty);
    });

    test('an update writes both the old and the new rules, so a re-scope is '
        'readable from the trail', () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();

      final rescoped = AccessTemplate(
        name: 'conveyor',
        rules: const {
          'p_cfg_ManualFreq': AccessGroup.configure,
          'p_cmd_JogFwd': AccessGroup.operate,
        },
      );
      await store.update(rescoped);

      final row = sink.rows.single;
      expect(row.oldValue, AccessTemplate.encodeRules(_conveyor().rules));
      expect(row.newValue, AccessTemplate.encodeRules(rescoped.rules));
      expect((await store.template('conveyor'))!.groupFor('p_cfg_ManualFreq'),
          AccessGroup.configure);
    });

    test('a delete writes a null newValue and the rules it destroyed',
        () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();

      await store.delete('conveyor');

      final row = sink.rows.single;
      expect(row.allowed, isTrue);
      expect(row.itemKey, 'access_template.conveyor');
      expect(row.oldValue, AccessTemplate.encodeRules(_conveyor().rules));
      expect(row.newValue, isNull);
      expect(await templateRowCount(), 0);
    });

    test('a rename produces one actionId across its rows', () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();

      await store.rename('conveyor', 'conveyor-strict');

      expect(sink.rows.length, greaterThanOrEqualTo(2),
          reason: 'the trail has to be findable from the old name and from '
              'the new one');
      expect(sink.rows.map((r) => r.actionId).toSet(), hasLength(1),
          reason: 'one human action gets one correlation id — a rename is not '
              'two unrelated events');
      expect(sink.rows.map((r) => r.itemKey).toSet(), {
        'access_template.conveyor',
        'access_template.conveyor-strict',
      });
      expect(sink.rows.every((r) => r.oldValue == 'conveyor'), isTrue);
      expect(sink.rows.every((r) => r.newValue == 'conveyor-strict'), isTrue);

      expect(await store.template('conveyor'), isNull);
      expect((await store.template('conveyor-strict'))!.rules,
          _conveyor().rules);
    });

    test('a reason is carried into the row', () async {
      final store = buildStore();
      await store.create(_conveyor(), reason: 'commissioning line 4');
      expect(sink.rows.single.reason, contains('commissioning line 4'));
    });
  });

  // -------------------------------------------------------------------------
  // Origin
  // -------------------------------------------------------------------------

  group('origin', () {
    test("origin: 'mcp' lands in the row while who is the approving human",
        () async {
      // T-04-14, spec §7c: "Audit them with origin = 'mcp' and who = the
      // approving user, never the agent."
      final store = buildStore();
      await store.create(_conveyor(), origin: 'mcp');

      final row = sink.rows.single;
      expect(row.origin, 'mcp');
      expect(row.who, 'admin',
          reason: 'who comes from the session callback and is never a '
              'parameter, so an agent cannot name itself or anybody else');
      expect(row.roleName, 'Administrator');
    });

    test('an mcp-origin write is gated exactly like an operator one', () async {
      final store = buildStore();
      session = _configureOnly();
      await expectLater(store.create(_conveyor(), origin: 'mcp'),
          throwsA(isA<AccessDenied>()));
      expect(await templateRowCount(), 0);
      expect(sink.rows.single.origin, 'mcp');
      expect(sink.rows.single.allowed, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Preconditions
  // -------------------------------------------------------------------------

  group('preconditions', () {
    test('an invalid template name is rejected before the gate, with no row',
        () async {
      final store = buildStore();
      session = _anonymous();

      await expectLater(
          store.create(AccessTemplate(name: '', rules: const {})),
          throwsA(isA<InvalidTemplateNameException>()));
      await expectLater(
          store.create(AccessTemplate(name: '  padded', rules: const {})),
          throwsA(isA<InvalidTemplateNameException>()));

      expect(sink.rows, isEmpty,
          reason: 'a name that cannot be stored is a caller bug, not an '
              'authorization event');
      expect(denials, isEmpty);
      expect(await templateRowCount(), 0);
    });

    test('create on a name that already exists throws and writes no row',
        () async {
      final store = buildStore();
      await store.create(_conveyor());
      sink.rows.clear();

      await expectLater(store.create(_conveyor()),
          throwsA(isA<TemplateExistsException>()));
      expect(sink.rows, isEmpty);
      expect(await templateRowCount(), 1);
    });

    test('update on a name that does not exist throws and writes no row',
        () async {
      final store = buildStore();
      await expectLater(
          store.update(AccessTemplate(name: 'ghost', rules: const {})),
          throwsA(isA<TemplateNotFoundException>()));
      expect(sink.rows, isEmpty);
    });

    test('rename from a missing name, and onto an existing one, both throw',
        () async {
      final store = buildStore();
      await store.create(_conveyor());
      await store.create(AccessTemplate(name: 'recipes', rules: const {}));
      sink.rows.clear();

      await expectLater(store.rename('ghost', 'whatever'),
          throwsA(isA<TemplateNotFoundException>()));
      await expectLater(store.rename('conveyor', 'recipes'),
          throwsA(isA<TemplateExistsException>()));
      expect(sink.rows, isEmpty);
      expect(await templateRowCount(), 2);
    });

    test('delete of a name that does not exist throws and writes no row',
        () async {
      final store = buildStore();
      await expectLater(
          store.delete('ghost'), throwsA(isA<TemplateNotFoundException>()));
      expect(sink.rows, isEmpty);
    });

    test('none of the precondition failures is an AccessDenied', () async {
      final store = buildStore();
      await store.create(_conveyor());
      expect(
          () => store.create(_conveyor()), throwsA(isNot(isA<AccessDenied>())));
      expect(() => store.delete('ghost'), throwsA(isNot(isA<AccessDenied>())));
      expect(denials, isEmpty,
          reason: 'rendering these through the locked prompt would tell an '
              'operator to find somebody who cannot help either');
    });
  });

  // -------------------------------------------------------------------------
  // The trail is not the write path
  // -------------------------------------------------------------------------

  group('an audit sink that throws', () {
    test('does not fail a permitted write', () async {
      final throwing = _ThrowingSink();
      final store = buildStore(audit: throwing);

      await store.create(_conveyor());

      expect(throwing.calls, 1);
      expect(await templateRowCount(), 1,
          reason: 'the same rule, in the same words, as 03-04 / 03-05 / 03-10: '
              'a lost row is a log line, never a refused write');
    });

    test('does not replace AccessDenied', () async {
      final throwing = _ThrowingSink();
      final store = buildStore(audit: throwing);
      session = _anonymous();

      await expectLater(
          store.create(_conveyor()), throwsA(isA<AccessDenied>()));

      expect(throwing.calls, 1);
      expect(denials, hasLength(1),
          reason: 'onDenied still fires, so the prompt still appears');
      expect(await templateRowCount(), 0);
    });
  });

  // -------------------------------------------------------------------------
  // onDenied
  // -------------------------------------------------------------------------

  group('onDenied', () {
    test('a listener that throws changes neither the refusal nor the row',
        () async {
      final store = AccessTemplateStore(
        db: db,
        session: () => session,
        audit: sink,
        station: 'SVN-NES-OT-CL02',
        onDenied: (_) => throw StateError('a broken prompt'),
      );
      session = _anonymous();

      await expectLater(
          store.create(_conveyor()), throwsA(isA<AccessDenied>()));
      expect(sink.rows.single.allowed, isFalse);
      expect(await templateRowCount(), 0);
    });
  });
}
