/// The key repository's access-templates section (spec §7d).
///
/// MCP does the plant in a pass; this section is where somebody works out what
/// the rules should *be*. So the claims here are about **legibility and the
/// boundary**, not about the store — 04-03's own file already drives every
/// write through a `configure`-only session and reads the row counts back from
/// the database.
///
/// What is asserted here that nothing else can assert:
///
///  * a session without `users` sees every control, may press every one of
///    them, and is told what it needs — nothing is greyed,
///  * the delete dialog shows the bound keys **before** the confirm, and offers
///    no confirm at all while any key is bound,
///  * the rename dialog says, in words, that the bound keys become
///    unrestricted — the only warning that exists, since 04-03's `rename`
///    deliberately does not re-point them,
///  * rendering the list costs **no** per-template database query: the counts
///    come from the resolver's in-memory snapshot,
///  * a station with no database says why, rather than showing an empty list
///    that reads as "no templates exist".
///
/// The store is real, over an in-memory database, so a test that says "the
/// template was created" is reading the table rather than a mock's call log.
/// The recording subclass exists for the one claim a table cannot answer:
/// which methods were *called*.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/access_template_store.dart';
import 'package:tfc/pages/access_templates_section.dart';
import 'package:tfc/providers/access_policy.dart';
import 'package:tfc/providers/access_templates.dart';
import 'package:tfc/widgets/access_denied_prompt.dart';
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

/// The real store, over the real (in-memory) tables, with a call log.
///
/// Subclassed rather than faked: the claims about *what happened* must be read
/// back from the tables, and only the claim about **which methods the section
/// reached for** needs a log. A hand-written fake would have let the
/// no-query-per-template test pass while the section quietly asked the
/// database something else.
class _RecordingStore extends AccessTemplateStore {
  _RecordingStore({
    required super.db,
    required super.session,
    required super.audit,
    required super.station,
    super.onDenied,
  });

  final List<String> calls = [];

  @override
  Future<List<AccessTemplate>> list() {
    calls.add('list');
    return super.list();
  }

  @override
  Future<Map<String, String>> bindings() {
    calls.add('bindings');
    return super.bindings();
  }

  @override
  Future<List<String>> keysBoundTo(String templateName) {
    calls.add('keysBoundTo:$templateName');
    return super.keysBoundTo(templateName);
  }

  @override
  Future<void> update(
    AccessTemplate value, {
    String origin = 'operator',
    String? reason,
  }) {
    calls.add('update:${value.name}:${AccessTemplate.encodeRules(value.rules)}');
    return super.update(value, origin: origin, reason: reason);
  }
}

/// A store whose `delete` loses the race: `keysBoundTo` answered "none", and
/// between that answer and the statement another station bound a key.
class _RacingStore extends _RecordingStore {
  _RacingStore({
    required super.db,
    required super.session,
    required super.audit,
    required super.station,
    super.onDenied,
  });

  /// What the delete throws, once. Cleared after it fires, so a second attempt
  /// behaves normally.
  List<String>? raceKeys;

  @override
  Future<void> delete(
    String name, {
    String origin = 'operator',
    String? reason,
  }) async {
    final keys = raceKeys;
    if (keys != null) {
      raceKeys = null;
      throw TemplateInUseException(name, keys);
    }
    return super.delete(name, origin: origin, reason: reason);
  }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

AccessSession _anonymous() =>
    AccessSession.anonymous(const {AccessGroup.operate});

/// The engineer the `users` gate exists for: they can open this page — the
/// route is `configure` — and must not be able to re-scope who may write what.
AccessSession _configureOnly() => const AccessSession(
      user: AuthenticatedUser(username: 'engineer', roleName: 'Engineering'),
      groups: {
        AccessGroup.operate,
        AccessGroup.setpoints,
        AccessGroup.device,
        AccessGroup.configure,
      },
    );

AccessSession _withUsers() => const AccessSession(
      user: AuthenticatedUser(username: 'admin', roleName: 'Administrator'),
      groups: {AccessGroup.operate, AccessGroup.configure, AccessGroup.users},
    );

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _conveyorKeyA = 'ST101.CN01';
const String _conveyorKeyB = 'ST101.CN02';

AccessTemplate _conveyor() => AccessTemplate(
      name: 'conveyor',
      rules: const {
        'p_cfg_ManualFreq': AccessGroup.device,
        'p_cmd_JogFwd': AccessGroup.operate,
      },
    );

AccessTemplate _recipes() => AccessTemplate(
      name: 'recipes',
      rules: const {kWholeKeyMember: AccessGroup.setpoints},
    );

void main() {
  late AppDatabase db;
  late _RecordingSink sink;
  late AccessSession session;
  late TagBindingResolver resolver;
  _RecordingStore? store;

  setUp(() async {
    db = AppDatabase.inMemoryForTest();
    // Force the schema before the first store call, so a read on an empty
    // table finds a table rather than nothing.
    await db.customSelect('SELECT 1').getSingle();
    sink = _RecordingSink();
    session = _withUsers();
    resolver = TagBindingResolver();
    store = null;
  });

  tearDown(() => db.close());

  List<Override> overrides({
    AccessTemplateStore? withStore,
    bool noDatabase = false,
    Future<List<AccessTemplate>>? templates,
  }) =>
      [
        tagBindingResolverProvider.overrideWith((ref) => resolver),
        accessTemplateStoreProvider.overrideWith((ref) async {
          if (noDatabase) return null;
          return withStore ??
              (store = _RecordingStore(
                db: db,
                session: () => session,
                audit: sink,
                station: 'SVN-NES-OT-CL02',
                // The same wiring the real provider does, so a refusal here
                // reaches the shared prompt exactly as it does on the station.
                onDenied: (denial) => reportAccessDenial(ref, denial),
              ));
        }),
        // Deliberately NOT overriding `accessTemplatesProvider`: the real
        // loader is what fills the resolver, and a test that stubbed it would
        // stop checking that a write followed by an invalidate is visible.
        if (templates != null)
          accessTemplatesProvider.overrideWith((ref) => templates),
      ];

  /// The section on its own, under a real [AccessDeniedPrompt] — the prompt a
  /// refusal has to reach, rather than a listener of the test's own.
  Widget host(List<Override> o) => ProviderScope(
        overrides: o,
        child: const MaterialApp(
          home: Scaffold(
            body: AccessDeniedPrompt(child: AccessTemplatesSection()),
          ),
        ),
      );

  /// A store built outside the provider, for seeding rows before the pump.
  AccessTemplateStore seeder() => AccessTemplateStore(
        db: db,
        session: () => _withUsers(),
        audit: sink,
        station: 'SVN-NES-OT-CL02',
      );

  // -------------------------------------------------------------------------
  // The list
  // -------------------------------------------------------------------------

  group('the list', () {
    testWidgets('names every template with its rule count and how many keys '
        'it governs', (tester) async {
      final seed = seeder();
      await seed.create(_conveyor());
      await seed.create(_recipes());
      await seed.bind(_conveyorKeyA, 'conveyor');
      await seed.bind(_conveyorKeyB, 'conveyor');

      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.text(kAccessTemplatesHeadline), findsOneWidget);
      expect(find.text('conveyor'), findsOneWidget);
      expect(find.text('recipes'), findsOneWidget);
      expect(find.text(kAccessTemplateSummary(2, 2)), findsOneWidget,
          reason: 'the conveyor template: two rules, two keys');
      expect(find.text(kAccessTemplateSummary(1, 0)), findsOneWidget,
          reason: 'recipes: one whole-key rule, nothing bound');
    });

    testWidgets(
        'the bound-key counts come from the resolver: rendering N templates '
        'asks the database nothing per template', (tester) async {
      final seed = seeder();
      for (var i = 0; i < 5; i++) {
        await seed.create(AccessTemplate(
            name: 'template$i', rules: const {'m': AccessGroup.device}));
        await seed.bind('KEY$i', 'template$i');
      }

      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      // The load is two queries for the whole section — `list` and `bindings`,
      // in one `setSnapshot`. What must not appear is a `keysBoundTo` per
      // template: five here, and a per-frame cost on a real station.
      expect(store!.calls.where((c) => c.startsWith('keysBoundTo')), isEmpty,
          reason: 'the store\'s keysBoundTo reads the database and is reserved '
              'for the delete block. Rendering must use the resolver.');
      expect(store!.calls, ['list', 'bindings']);

      // The list is bounded and lazy, so not every tile is built at once —
      // scrolling to the end must not turn the counts into queries either.
      await tester.drag(
          find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(store!.calls, ['list', 'bindings']);
      expect(find.text(kAccessTemplateSummary(1, 1)), findsAtLeastNWidgets(1));
    });

    testWidgets('while the templates are loading it renders nothing, not a '
        'spinner that flashes', (tester) async {
      // A load that never lands. Matching AccessLockBadge's and
      // AccessStatusAction's ruling: nothing, rather than a spinner for one
      // frame on every station that has no templates.
      final never = Completer<List<AccessTemplate>>().future;
      await tester.pumpWidget(host(overrides(templates: never)));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessTemplatesSectionKey), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(kAccessTemplatesHeadline), findsNothing);
    });

    testWidgets('with no database it says why, rather than showing an empty '
        'list that reads as "no templates"', (tester) async {
      await tester.pumpWidget(host(overrides(noDatabase: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessTemplatesNoDatabaseKey), findsOneWidget);
      expect(find.text(kAccessTemplatesNoDatabaseNote), findsOneWidget);
      expect(find.text(kAccessTemplatesEmptyNote), findsNothing,
          reason: '"no templates yet" is a different claim from "this station '
              'cannot tell you", and only one of them is true here');
    });

    testWidgets('with a database and no templates it says so', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      expect(find.text(kAccessTemplatesEmptyNote), findsOneWidget);
      expect(find.byKey(kAccessTemplatesNoDatabaseKey), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Create
  // -------------------------------------------------------------------------

  group('create', () {
    testWidgets('a users session creates a template and the list shows it',
        (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessTemplatesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessTemplateNameFieldKey), 'baader');
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text('baader'), findsOneWidget);
      expect((await seeder().list()).map((t) => t.name), ['baader']);
    });

    testWidgets('a duplicate name is refused before the store is called',
        (tester) async {
      await seeder().create(_conveyor());
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      store!.calls.clear();

      await tester.tap(find.byKey(kAccessTemplatesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(kAccessTemplateNameFieldKey), 'conveyor');
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessTemplateDuplicateNameNote), findsOneWidget);
      expect(store!.calls, isEmpty);
      expect((await seeder().list()).length, 1);
    });

    testWidgets('a name the store could not store is refused before the store '
        'is called', (tester) async {
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      store!.calls.clear();

      await tester.tap(find.byKey(kAccessTemplatesCreateKey));
      await tester.pumpAndSettle();
      // Untrimmed — `AccessTemplate.isValidTemplateName` refuses it, and a
      // typo is not an authorization event.
      await tester.enterText(
          find.byKey(kAccessTemplateNameFieldKey), ' conveyor ');
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessTemplateInvalidNameNote), findsOneWidget);
      expect(store!.calls, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // The users gate — nothing is greyed, and nothing gets through
  // -------------------------------------------------------------------------

  group('the users gate (T-04-37)', () {
    testWidgets('an anonymous session sees the create control enabled, and '
        'pressing it through says the users permission is what is missing',
        (tester) async {
      session = _anonymous();
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      final create =
          tester.widget<OutlinedButton>(find.byKey(kAccessTemplatesCreateKey));
      expect(create.onPressed, isNotNull,
          reason: 'no control on this section is greyed for lack of a '
              'permission — it is pressed, and then explained');

      await tester.tap(find.byKey(kAccessTemplatesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessTemplateNameFieldKey), 'baader');
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessDeniedBodyKey), findsOneWidget);
      expect(find.text(kAccessDeniedGroupNote(AccessGroup.users)),
          findsOneWidget);
      expect(await seeder().list(), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a configure-only session — the one the gate exists for — is '
        'refused the same way', (tester) async {
      session = _configureOnly();
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessTemplatesCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(kAccessTemplateNameFieldKey), 'baader');
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessDeniedGroupNote(AccessGroup.users)),
          findsOneWidget,
          reason: 'spec §7c: somebody who can edit a page must not be able to '
              're-scope who may write what');
      expect(await seeder().list(), isEmpty);
    });

    testWidgets('the delete control is enabled for a session that cannot use '
        'it, and explains itself when pressed', (tester) async {
      await seeder().create(_conveyor());
      session = _anonymous();
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      final delete = tester.widget<IconButton>(
          find.byKey(kAccessTemplateDeleteKey('conveyor')));
      expect(delete.onPressed, isNotNull);

      await tester.tap(find.byKey(kAccessTemplateDeleteKey('conveyor')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text(kAccessDeniedGroupNote(AccessGroup.users)),
          findsOneWidget);
      expect((await seeder().list()).length, 1);
    });
  });

  // -------------------------------------------------------------------------
  // Rename — the only warning a silent unrestriction gets
  // -------------------------------------------------------------------------

  group('rename', () {
    testWidgets('with keys bound, the dialog says they become unrestricted and '
        'names them', (tester) async {
      final seed = seeder();
      await seed.create(_conveyor());
      await seed.bind(_conveyorKeyA, 'conveyor');
      await seed.bind(_conveyorKeyB, 'conveyor');

      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessTemplateRenameKey('conveyor')));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessTemplateRenameWarningKey), findsOneWidget);
      expect(find.text(kAccessTemplateRenameWarning('conveyor', 2)),
          findsOneWidget);
      expect(find.text(_conveyorKeyA), findsOneWidget);
      expect(find.text(_conveyorKeyB), findsOneWidget);

      // A warning, not a block.
      final confirm =
          tester.widget<FilledButton>(find.byKey(kAccessTemplateConfirmKey));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('with nothing bound there is no warning', (tester) async {
      await seeder().create(_conveyor());
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessTemplateRenameKey('conveyor')));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessTemplateRenameWarningKey), findsNothing);
    });

    testWidgets('renaming moves the name and the list follows', (tester) async {
      await seeder().create(_conveyor());
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessTemplateRenameKey('conveyor')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(kAccessTemplateNameFieldKey), 'conveyor-line-4');
      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text('conveyor-line-4'), findsOneWidget);
      expect(find.text('conveyor'), findsNothing);
      expect((await seeder().list()).map((t) => t.name), ['conveyor-line-4']);
    });
  });

  // -------------------------------------------------------------------------
  // Delete — the list first, and no confirm while it would cost anything
  // -------------------------------------------------------------------------

  group('delete', () {
    testWidgets('with keys bound the dialog lists them and offers no delete',
        (tester) async {
      final seed = seeder();
      await seed.create(_conveyor());
      await seed.bind(_conveyorKeyA, 'conveyor');

      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kAccessTemplateDeleteKey('conveyor')));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessTemplateDeleteBlockedKey), findsOneWidget);
      expect(find.text(kAccessTemplateDeleteBlockedNote('conveyor', 1)),
          findsOneWidget);
      expect(find.text(_conveyorKeyA), findsOneWidget);
      expect(find.byKey(kAccessTemplateConfirmKey), findsNothing,
          reason: 'spec §7d: show the keys and block. A control that is '
              'present and always refuses teaches the operator to press it '
              'twice, and no sign-in fixes this one.');

      // And the list came from the store, not the snapshot: this is the one
      // decision that must not rest on something a second stale.
      expect(store!.calls, contains('keysBoundTo:conveyor'));
    });

    testWidgets('with nothing bound it deletes', (tester) async {
      await seeder().create(_conveyor());
      await tester.pumpWidget(host(overrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessTemplateDeleteKey('conveyor')));
      await tester.pumpAndSettle();
      expect(find.text(kAccessTemplateDeleteFreeNote), findsOneWidget);

      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(await seeder().list(), isEmpty);
      expect(find.text('conveyor'), findsNothing);
    });

    testWidgets('a race — another station bound a key between the question and '
        'the statement — re-renders the dialog with the new list, not an error',
        (tester) async {
      await seeder().create(_conveyor());
      final racing = _RacingStore(
        db: db,
        session: () => session,
        audit: sink,
        station: 'SVN-NES-OT-CL02',
      )..raceKeys = [_conveyorKeyA];

      await tester.pumpWidget(host(overrides(withStore: racing)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAccessTemplateDeleteKey('conveyor')));
      await tester.pumpAndSettle();
      // The database said nothing was bound, so the confirm is offered.
      expect(find.byKey(kAccessTemplateConfirmKey), findsOneWidget);

      await tester.tap(find.byKey(kAccessTemplateConfirmKey));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(kAccessTemplateDeleteBlockedKey), findsOneWidget);
      expect(find.text(_conveyorKeyA), findsOneWidget);
      expect(find.byKey(kAccessTemplateConfirmKey), findsNothing);
      expect((await seeder().list()).length, 1);
    });
  });
}
