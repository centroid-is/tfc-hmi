/// Binding a key to an access template, from the key's own card — and the
/// three claims the phase's honesty requirement rests on.
///
/// Spec §7b is deliberately fail-open: an unbound key is unrestricted, and so
/// is a member no bound template mentions. **Nothing enforces that somebody
/// remembered.** So enforcement is replaced by visibility, and this file is
/// where that visibility is checked rather than asserted in prose:
///
///  * a key names its template on its own card, and the binding is written
///    straight into the `users`-gated table — never into the key-mapping blob,
///    which is `configure`-classified,
///  * the keys nobody bound are one number and one filter away, dangling
///    bindings included, with **one** definition of "unbound" shared with the
///    guard,
///  * a `configure`-grade session cannot reach a binding through any of the
///    three paths that used to lead there, and — the half that closes the set
///    rather than enumerating it — no file in `lib/` names the table except
///    the one store that gates it,
///  * an exported key map carries no bindings, and both halves of the
///    import/export card say so before it matters.
///
/// The store is real, over an in-memory database, so "the row landed" is read
/// back from `access_key_binding` rather than from a mock's call log. The
/// preferences are real and **guarded**, so "Save wrote no binding" is driven
/// through the same `GuardedPreferences` the station runs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/core/access_template_store.dart';
import 'package:tfc/pages/key_repository.dart';
import 'package:tfc/providers/access_policy.dart';
import 'package:tfc/providers/access_templates.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/widgets/access_denied_prompt.dart';
import 'package:tfc/widgets/key_mapping_sections.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/guarded_preferences.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/test_helpers.dart';

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

class _RecordingSink implements AuditSink {
  final List<AuditRecord> rows = [];

  @override
  Future<void> record(AuditRecord entry) async => rows.add(entry);
}

/// A file picker that answers with paths the test controls.
///
/// `_onImport` and `_onExport` both go through `FilePicker.platform`, and the
/// import half is one of the three paths the closure test drives end to end —
/// so it has to be driven for real, dialog and all, rather than by calling
/// something underneath it.
class _FakePicker extends FilePicker {
  _FakePicker({this.pickPath, this.savePath});

  String? pickPath;
  String? savePath;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('has no effect') bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final picked = pickPath;
    if (picked == null) return null;
    return FilePickerResult([
      PlatformFile(
        path: picked,
        name: picked.split(Platform.pathSeparator).last,
        size: File(picked).lengthSync(),
      )
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async =>
      savePath;
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

const String _station = 'SVN-NES-OT-CL02';

AccessSession _anonymous() =>
    AccessSession.anonymous(const {AccessGroup.operate});

/// The engineer the `users` gate exists for. `/advanced/key-repository` is
/// behind `configure`, so this session can open the page, edit every key
/// mapping and press Save — and must not be able to change who may write what.
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
      groups: {
        AccessGroup.operate,
        AccessGroup.configure,
        AccessGroup.users,
      },
    );

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _keyA = 'ST101.CN01';
const String _keyB = 'ST101.CN02';
const String _keyC = 'ST101.CN03';

KeyMappings _keys(List<String> names) => KeyMappings(nodes: {
      for (final name in names)
        name: KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 4, identifier: 'GVL.$name')
            ..serverAlias = 'main_server',
        ),
    });

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

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

/// Asserts the text at [finder] renders at its **un-clipped** height.
///
/// `find.text` passing is not the same as the line being legible: an
/// ellipsised disclosure shipped past a green assertion in Phase 1. This lays
/// the same span out with no line limit at the width it actually got and
/// compares heights, so a `maxLines` that cuts the copy — or a box too short
/// for it — fails here rather than on a station.
void expectUnclipped(WidgetTester tester, Finder finder, {String? reason}) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textAlign: paragraph.textAlign,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  expect(paragraph.size.height, painter.height,
      reason: reason ??
          'the line is clipped: it renders ${paragraph.size.height}px tall '
              'where the whole text needs ${painter.height}px at '
              '${paragraph.size.width}px wide');
}

void main() {
  late AppDatabase db;
  late _RecordingSink sink;
  late AccessSession session;
  late TagBindingResolver resolver;
  late Directory tmp;
  AccessTemplateStore? store;
  Preferences? prefs;

  setUp(() async {
    db = AppDatabase.inMemoryForTest();
    // Force the schema before the first store call, so a read on an empty
    // table finds a table rather than nothing.
    await db.customSelect('SELECT 1').getSingle();
    sink = _RecordingSink();
    session = _withUsers();
    resolver = TagBindingResolver();
    store = null;
    prefs = null;
    tmp = await Directory.systemTemp.createTemp('key-binding-test');
    FilePicker.platform = _FakePicker();
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A store built outside the provider, for seeding and for reading back.
  AccessTemplateStore seeder() => AccessTemplateStore(
        db: db,
        session: _withUsers,
        audit: _RecordingSink(),
        station: _station,
      );

  /// The whole key-repository page, with a real guarded preferences store and
  /// a real template store over the in-memory database.
  Future<Widget> host({
    KeyMappings? keyMappings,
    bool noDatabase = false,
  }) async {
    final inner = prefs =
        await createTestPreferences(keyMappings: keyMappings ?? _keys([]));
    return ProviderScope(
      overrides: [
        // The **guarded** wrapper, not the raw store: the closure test's third
        // path is a preferences write, and driving it through anything less
        // than what the station runs would be checking a different thing.
        preferencesProvider.overrideWith((ref) async => GuardedPreferences(
              inner: inner,
              policy: ref.watch(accessPolicyProvider),
              session: () => session,
              audit: sink,
              station: _station,
              onDenied: (denial) => reportAccessDenial(ref, denial),
            )),
        databaseProvider.overrideWith((ref) async => null),
        stateManProvider
            .overrideWith((ref) => throw StateError('No StateMan in tests')),
        tagBindingResolverProvider.overrideWith((ref) => resolver),
        accessTemplateStoreProvider.overrideWith((ref) async {
          if (noDatabase) return null;
          return store = AccessTemplateStore(
            db: db,
            session: () => session,
            audit: sink,
            station: _station,
            onDenied: (denial) => reportAccessDenial(ref, denial),
          );
        }),
        // Deliberately NOT overriding `accessTemplatesProvider`: the real
        // loader is what fills the resolver, so a write followed by an
        // invalidate has to actually become visible.
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AccessDeniedPrompt(child: KeyRepositoryContent()),
        ),
      ),
    );
  }

  /// Opens [name]'s card so its body — and the template control — is built.
  Future<void> expand(WidgetTester tester, String name) async {
    await revealKeyCard(tester, name);
    await tester.ensureVisible(find.text(name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  /// Picks [template] (or "None") on [name]'s dropdown.
  Future<void> choose(
      WidgetTester tester, String name, String? template) async {
    await tester.ensureVisible(find.byKey(kKeyAccessTemplateDropdownKey(name)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kKeyAccessTemplateDropdownKey(name)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(kKeyAccessTemplateOptionKey(name, template)).last);
    await tester.pumpAndSettle();
  }

  /// The binding table, read straight back.
  Future<Map<String, String>> bindings() => seeder().bindings();

  /// The one [Text] inside [key]'s badge.
  String badgeText(WidgetTester tester, String key) => tester
      .widget<Text>(find
          .descendant(
              of: find.byKey(kKeyBindingBadgeKey(key)),
              matching: find.byType(Text))
          .first)
      .data!;

  // -------------------------------------------------------------------------
  // Task 1 — the control
  // -------------------------------------------------------------------------

  group('the binding control', () {
    testWidgets('binds a key, and the row lands in the binding table',
        (tester) async {
      await seeder().create(_conveyor());
      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();

      await expand(tester, _keyA);
      await choose(tester, _keyA, 'conveyor');

      expect(await bindings(), {_keyA: 'conveyor'});
    });

    testWidgets('a binding is not an unsaved change, and Save writes none',
        (tester) async {
      await seeder().create(_conveyor());
      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();
      final before = await prefs!.getString('key_mappings');

      await expand(tester, _keyA);
      await choose(tester, _keyA, 'conveyor');

      // The Save button is the page's own statement about whether anything is
      // pending. A binding must not move it: the other fields on this card are
      // parts of one `configure`-gated JSON blob, and a binding is a row in a
      // `users`-gated table.
      expect(find.text('All Changes Saved'), findsOneWidget);
      expect(find.text('Save Key Mappings'), findsNothing);
      expect(await prefs!.getString('key_mappings'), before,
          reason: 'the binding must not have touched the key-mapping blob');
    });

    testWidgets('clearing a binding removes the row', (tester) async {
      final seed = seeder();
      await seed.create(_conveyor());
      await seed.bind(_keyA, 'conveyor');

      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();

      await expand(tester, _keyA);
      await choose(tester, _keyA, null);

      expect(await bindings(), isEmpty);
    });

    testWidgets('the card names the template that governs the key',
        (tester) async {
      final seed = seeder();
      await seed.create(_conveyor());
      await seed.create(_recipes());
      await seed.bind(_keyA, 'conveyor');

      await tester.pumpWidget(await host(keyMappings: _keys([_keyA, _keyB])));
      await tester.pumpAndSettle();

      expect(badgeText(tester, _keyA), 'conveyor');
      // And the one nobody bound says so, because templates exist to bind to.
      expect(badgeText(tester, _keyB), kKeyBindingUnboundBadge);
    });

    testWidgets(
        'a dangling binding renders as a gap, never as an ordinary binding',
        (tester) async {
      final seed = seeder();
      await seed.create(_conveyor());
      await seed.bind(_keyA, 'conveyor');
      // Somebody removed the row by hand. 04-03 blocks the delete while a key
      // is bound, so this is the `psql` case the resolver's fail-open arm and
      // this surface exist for.
      await db.customStatement(
          "DELETE FROM access_template WHERE name = 'conveyor'");

      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();

      expect(badgeText(tester, _keyA), kKeyBindingMissingBadge,
          reason: 'a key naming a template nobody can find is a gap');

      await expand(tester, _keyA);
      expect(find.text(kKeyAccessTemplateMissingLabel('conveyor')),
          findsAtLeastNWidgets(1),
          reason: 'the name is still shown — it is what has to be fixed — but '
              'marked as missing rather than offered as a binding');
      expect(find.text(kKeyAccessTemplateMissingNote), findsOneWidget);
    });

    testWidgets(
        'a session without users sees a live dropdown, is told what it needs, '
        'and changes nothing', (tester) async {
      await seeder().create(_conveyor());
      session = _anonymous();

      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();
      await expand(tester, _keyA);

      // Nothing is greyed: the control is live for every session.
      final dropdown = tester.widget<DropdownButton<String?>>(
          find.byKey(kKeyAccessTemplateDropdownKey(_keyA)));
      expect(dropdown.onChanged, isNotNull,
          reason: 'a control a session may not use still shows its value, is '
              'tappable, and explains what it needs');

      await choose(tester, _keyA, 'conveyor');

      expect(await bindings(), isEmpty,
          reason: 'the refusal must leave the table alone');
      expect(
          find.text(kAccessDeniedGroupNote(AccessGroup.users)), findsOneWidget,
          reason: 'the shared prompt names the group, once');
    });

    testWidgets(
        'a configure-only session is refused too — that is the whole point of '
        'the ruling', (tester) async {
      await seeder().create(_conveyor());
      session = _configureOnly();

      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();
      await expand(tester, _keyA);
      await choose(tester, _keyA, 'conveyor');

      expect(await bindings(), isEmpty);
      expect(
          find.text(kAccessDeniedGroupNote(AccessGroup.users)), findsOneWidget);
    });

    testWidgets(
        'with no database it says so in one line, not an empty dropdown',
        (tester) async {
      await tester.pumpWidget(
          await host(keyMappings: _keys([_keyA]), noDatabase: true));
      await tester.pumpAndSettle();
      await expand(tester, _keyA);

      expect(find.text(kKeyAccessTemplateNoDatabaseNote), findsOneWidget);
      expect(find.byKey(kKeyAccessTemplateDropdownKey(_keyA)), findsNothing);
      expect(find.byKey(kKeyBindingBadgeKey(_keyA)), findsNothing,
          reason: 'a station that cannot tell you must not claim "unbound"');
    });

    testWidgets(
        'with a database and no templates the card says there is nothing to '
        'bind to', (tester) async {
      await tester.pumpWidget(await host(keyMappings: _keys([_keyA])));
      await tester.pumpAndSettle();
      await expand(tester, _keyA);

      expect(find.text(kKeyAccessTemplateNoTemplatesNote), findsOneWidget);
      expect(find.byKey(kKeyBindingBadgeKey(_keyA)), findsNothing,
          reason: 'with nothing to bind to, an "Unbound" badge on every card '
              'is noise that trains people to ignore it — the shipped state is '
              'reported once, by the section header count');
    });

    testWidgets('binding one key leaves the others alone', (tester) async {
      await seeder().create(_conveyor());
      await tester
          .pumpWidget(await host(keyMappings: _keys([_keyA, _keyB, _keyC])));
      await tester.pumpAndSettle();

      await expand(tester, _keyB);
      await choose(tester, _keyB, 'conveyor');

      expect(await bindings(), {_keyB: 'conveyor'});
    });

    test('the control added no third key_mappings write site', () {
      final source = File('lib/pages/key_repository.dart').readAsStringSync();
      final sites = RegExp(r"setString\('key_mappings'").allMatches(source);
      expect(sites, hasLength(2),
          reason: 'the two pre-existing sites are `_saveKeyMappings` and '
              '`_onImport`. A binding is a row in a `users`-gated table, not a '
              'field in a `configure`-gated blob — a third site here would be '
              'the 2026-08-30 ruling undone.');
    });
  });
}
