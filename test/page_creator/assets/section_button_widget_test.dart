import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc/page_creator/assets/section_button.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/theme.dart' show HmiStateColors;
import 'package:tfc/widgets/hit_boundary.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

/// The section button end to end: the face's colours, the pane it opens, and
/// the `p_cmd_*` bits that leave it — for one section and for several.
void main() {
  setUp(() => sectionNow = () => _clockNow);
  tearDown(() {
    sectionNow = DateTime.now;
    _clockNow = _t0;
    closeSidePane(immediate: true);
  });

  Widget wrap(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  /// The pane is a full-height strip; on the 800x600 default surface its body
  /// runs past the bottom and `tester.tap` on a scrolled-out button lands on
  /// the pinned action bar instead. Give every test a surface the pane fits
  /// in, so a tap goes where the finder says it does.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  SectionButtonConfig config(List<String> keys, {String? label}) =>
      SectionButtonConfig(
        label: label ?? 'Before freezers',
        sections: [for (final k in keys) SectionRef(key: k)],
      );

  Future<void> pumpButton(
    WidgetTester tester,
    _FakeStateMan fake, {
    SectionButtonConfig? cfg,
  }) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(
      SizedBox(
        width: 80,
        height: 80,
        child: SectionButton(config: cfg ?? config(['sec/a'])),
      ),
      overrides: [stateManProvider.overrideWith((_) async => fake)],
    ));
    await _settle(tester);
  }

  PowerButtonPainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(SectionButton),
      matching: find.byType(CustomPaint),
    ));
    return paint.painter as PowerButtonPainter;
  }

  HmiStateColors palette(WidgetTester tester) =>
      HmiStateColors.of(tester.element(find.byType(SectionButton)));

  group('one section — the face', () {
    testWidgets('running is green with no split', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      expect(painterOf(tester).disc, palette(tester).green);
      expect(painterOf(tester).splitWith, isNull);
      expect(painterOf(tester).unreadable, isFalse);
    });

    testWidgets('cleaning is blue', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', cleaning: true);
      await pumpButton(tester, fake);
      expect(painterOf(tester).disc, palette(tester).blue);
    });

    testWidgets('stopped is grey, and readable — no exclamation',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a');
      await pumpButton(tester, fake);
      expect(painterOf(tester).disc, palette(tester).grey);
      expect(painterOf(tester).unreadable, isFalse);
    });

    testWidgets('held off is yellow, not red', (tester) async {
      // Waiting, not faulted: the only permissive that is ever FALSE on this
      // plant is the box-packing pair holding each other off.
      final fake = _FakeStateMan()..push('sec/a', permissive: false);
      await pumpButton(tester, fake);
      expect(painterOf(tester).disc, palette(tester).yellow);
      expect(painterOf(tester).disc, isNot(palette(tester).red));
    });

    testWidgets('nothing from the PLC yet is grey with an exclamation',
        (tester) async {
      // Grey alone means "stopped, all is well". A button that cannot read
      // its section must not say that.
      final fake = _FakeStateMan();
      await pumpButton(tester, fake);
      expect(painterOf(tester).disc, palette(tester).grey);
      expect(painterOf(tester).unreadable, isTrue);
    });

    testWidgets('a struct missing p_stat_xPermissive is unreadable',
        (tester) async {
      final value = DynamicValue();
      value[kSectionStatEnabled] =
          DynamicValue(value: false, typeId: NodeId.boolean);
      value[kSectionStatCleanEnabled] =
          DynamicValue(value: false, typeId: NodeId.boolean);
      final fake = _FakeStateMan()..pushRaw('sec/a', value);
      await pumpButton(tester, fake);
      expect(painterOf(tester).unreadable, isTrue,
          reason: 'a missing member is unknown, never a safe-looking false');
    });

    testWidgets('no sections configured paints the mark and opens no pane',
        (tester) async {
      await pumpButton(tester, _FakeStateMan(),
          cfg: SectionButtonConfig.preview());
      expect(painterOf(tester).unreadable, isTrue);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.byType(SidePane), findsNothing);
    });
  });

  group('several sections — the face splits when they disagree', () {
    testWidgets('all running stays one solid colour', (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true)
        ..push('sec/c', enabled: true);
      await pumpButton(tester, fake,
          cfg: config(['sec/a', 'sec/b', 'sec/c']));

      expect(painterOf(tester).disc, palette(tester).green);
      expect(painterOf(tester).splitWith, isNull,
          reason: 'agreement must look exactly like a single-section button');
    });

    testWidgets('two running, one stopped splits green over grey',
        (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true)
        ..push('sec/c');
      await pumpButton(tester, fake,
          cfg: config(['sec/a', 'sec/b', 'sec/c']));

      expect(painterOf(tester).disc, palette(tester).green);
      expect(painterOf(tester).splitWith, palette(tester).grey);
    });

    testWidgets('a member that cannot be read marks the whole button',
        (tester) async {
      // Only two of the three have reported. The button speaks for all
      // three, so it must not claim to know.
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true);
      await pumpButton(tester, fake,
          cfg: config(['sec/a', 'sec/b', 'sec/c']));

      expect(painterOf(tester).unreadable, isTrue);
      expect(painterOf(tester).disc, palette(tester).green);
      expect(painterOf(tester).splitWith, palette(tester).grey);
    });

    testWidgets('the split follows the sections as they change',
        (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b');
      await pumpButton(tester, fake, cfg: config(['sec/a', 'sec/b']));
      expect(painterOf(tester).splitWith, palette(tester).grey);

      fake.push('sec/b', enabled: true);
      await _settle(tester);
      expect(painterOf(tester).splitWith, isNull,
          reason: 'once they agree the seam has to go');
    });
  });

  group('the pane', () {
    testWidgets('one section is titled and subtitled as one', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(find.byType(SidePane), findsOneWidget);
      expect(find.text('Before freezers'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Auto mode'), findsOneWidget);
      // A one-section pane pays nothing for the group feature: no member
      // rows, and the commands keep their plain names.
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Run all'), findsNothing);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Stop all'), findsNothing);
      expect(find.text('Allowed to start'), findsOneWidget,
          reason: 'the pane says it in operator words, not "permissive"');
      expect(find.text('Permissive'), findsNothing);
    });

    testWidgets('a group is counted, and lists every member', (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true)
        ..push('sec/c');
      await pumpButton(
        tester,
        fake,
        cfg: SectionButtonConfig(label: 'Before freezers', sections: [
          SectionRef(key: 'sec/a', label: 'ST101'),
          SectionRef(key: 'sec/b', label: 'ST201'),
          SectionRef(key: 'sec/c', label: 'ST301'),
        ]),
      );
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(find.text('3 sections'), findsOneWidget);
      expect(find.text('Mixed'), findsWidgets); // chip + state tile
      expect(find.text('2 of 3'), findsOneWidget);
      // The per-member list is how the operator finds the odd one out.
      expect(find.text('ST101'), findsOneWidget);
      expect(find.text('ST201'), findsOneWidget);
      expect(find.text('ST301'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
      // Per-section rows replace the single section's two mode-bit rows.
      expect(find.text('Auto mode'), findsNothing);
      // Every control says its own scope. Nothing is selected, so nothing
      // relies on the operator remembering what the pane is pointed at.
      expect(find.text('Run all'), findsOneWidget);
      expect(find.text('Clean all'), findsOneWidget);
      expect(find.text('Stop all'), findsOneWidget);
      // PaneSection upper-cases its heading.
      expect(find.text('ALL SECTIONS'), findsOneWidget);
      // ...and each member carries its own three, one row per section.
      expect(find.text('Run'), findsNWidgets(3));
      expect(find.text('Clean'), findsNWidgets(3));
      expect(find.text('Stop'), findsNWidgets(3));
    });

    testWidgets('a second tap on the same button closes it', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);

      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.byType(SidePane), findsOneWidget);

      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.byType(SidePane), findsNothing);
    });

    testWidgets('the pane cannot outlive the button that opened it',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.byType(SidePane), findsOneWidget);

      // Leaving the page. Same override list — Riverpod forbids changing how
      // many a scope has.
      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        overrides: [stateManProvider.overrideWith((_) async => fake)],
      ));
      await _settle(tester);
      expect(find.byType(SidePane), findsNothing);
    });
  });

  group('commands', () {
    Future<_FakeStateMan> openPane(
      WidgetTester tester,
      _FakeStateMan fake,
      SectionButtonConfig cfg,
    ) async {
      await pumpButton(tester, fake, cfg: cfg);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      return fake;
    }

    testWidgets('Run writes p_cmd_Start and nothing else', (tester) async {
      final fake = _FakeStateMan()..push('sec/a');
      await openPane(tester, fake, config(['sec/a']));
      await tester.tap(find.byKey(const Key('section-run')));
      await _settle(tester);

      expect(fake.writes, hasLength(1));
      expect(fake.writes.single.key, 'sec/a');
      expect(fake.writes.single.value[kSectionCmdStart].asBool, isTrue);
      expect(fake.writes.single.value[kSectionCmdStartClean].asBool, isFalse);
      expect(fake.writes.single.value[kSectionCmdStop].asBool, isFalse);
    });

    testWidgets('Clean writes p_cmd_StartClean', (tester) async {
      final fake = _FakeStateMan()..push('sec/a');
      await openPane(tester, fake, config(['sec/a']));
      await tester.tap(find.byKey(const Key('section-clean')));
      await _settle(tester);
      expect(fake.writes.single.value[kSectionCmdStartClean].asBool, isTrue);
    });

    testWidgets('Stop writes p_cmd_Stop', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await openPane(tester, fake, config(['sec/a']));
      await tester.tap(find.byKey(const Key('section-stop')));
      await _settle(tester);
      expect(fake.writes.single.value[kSectionCmdStop].asBool, isTrue);
    });

    testWidgets('Run is inert while the one section is already running',
        (tester) async {
      // p_cmd_Start toggles q_xEnabled: a live Run here would stop the line.
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await openPane(tester, fake, config(['sec/a']));
      expect(_enabled(tester, const Key('section-run')), isFalse);

      await tester.tap(find.byKey(const Key('section-run')));
      await _settle(tester);
      expect(fake.writes, isEmpty);
    });

    testWidgets('Stop fans out to every section', (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true);
      await openPane(tester, fake, config(['sec/a', 'sec/b']));

      await tester.tap(find.byKey(const Key('section-stop')));
      await _settle(tester);

      expect(fake.writes.map((w) => w.key), ['sec/a', 'sec/b']);
      for (final w in fake.writes) {
        expect(w.value[kSectionCmdStop].asBool, isTrue);
      }
    });

    testWidgets('Run skips the members already running', (tester) async {
      // THE bug this guard exists for. p_cmd_Start toggles, so broadcasting
      // it to a half-running group would start the stopped one and STOP the
      // running ones — one press leaving the line as it was, inverted.
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true)
        ..push('sec/c');
      await openPane(tester, fake, config(['sec/a', 'sec/b', 'sec/c']));

      expect(_enabled(tester, const Key('section-run')), isTrue,
          reason: 'one member can still start, so the button is live');

      await tester.tap(find.byKey(const Key('section-run')));
      await _settle(tester);

      expect(fake.writes.map((w) => w.key), ['sec/c'],
          reason: 'only the stopped member may be sent a start');
      expect(fake.writes.single.value[kSectionCmdStart].asBool, isTrue);
    });

    testWidgets('Clean skips the members already cleaning', (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', cleaning: true)
        ..push('sec/b', enabled: true);
      await openPane(tester, fake, config(['sec/a', 'sec/b']));

      await tester.tap(find.byKey(const Key('section-clean')));
      await _settle(tester);
      expect(fake.writes.map((w) => w.key), ['sec/b']);
    });

    testWidgets('a member that cannot be read is never commanded',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a');
      await openPane(tester, fake, config(['sec/a', 'sec/b']));

      await tester.tap(find.byKey(const Key('section-stop')));
      await _settle(tester);
      expect(fake.writes.map((w) => w.key), ['sec/a'],
          reason: 'sending a command blind to an unreadable section could '
              'start machinery nobody can see the state of');
    });

    testWidgets('Run stays live while any one member could start',
        (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', permissive: false);
      await openPane(tester, fake, config(['sec/a', 'sec/b']));
      // sec/a is running (cannot start), sec/b is held (cannot start).
      expect(_enabled(tester, const Key('section-run')), isFalse);
      // But Clean can still act on the running one.
      expect(_enabled(tester, const Key('section-clean')), isTrue);
    });
  });

  group('driving one member without touching the others', () {
    Future<_FakeStateMan> threeUp(WidgetTester tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true)
        ..push('sec/c');
      await pumpButton(tester, fake,
          cfg: SectionButtonConfig(label: 'Before freezers', sections: [
            SectionRef(key: 'sec/a', label: 'ST101'),
            SectionRef(key: 'sec/b', label: 'ST201'),
            SectionRef(key: 'sec/c', label: 'ST301'),
          ]));
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      return fake;
    }

    testWidgets("a member's Run starts only that member", (tester) async {
      final fake = await threeUp(tester);
      await tester.tap(find.byKey(const Key('section-2-run')));
      await _settle(tester);

      expect(fake.writes.map((w) => w.key), ['sec/c']);
      expect(fake.writes.single.value[kSectionCmdStart].asBool, isTrue);
    });

    testWidgets("a member's Stop stops only that member", (tester) async {
      final fake = await threeUp(tester);
      await tester.tap(find.byKey(const Key('section-0-stop')));
      await _settle(tester);

      expect(fake.writes.map((w) => w.key), ['sec/a']);
      expect(fake.writes.single.value[kSectionCmdStop].asBool, isTrue);
    });

    testWidgets("a member's Clean cleans only that member", (tester) async {
      final fake = await threeUp(tester);
      await tester.tap(find.byKey(const Key('section-1-clean')));
      await _settle(tester);

      expect(fake.writes.map((w) => w.key), ['sec/b']);
      expect(fake.writes.single.value[kSectionCmdStartClean].asBool, isTrue);
    });

    testWidgets('a running member has a dead Run, because Start toggles',
        (tester) async {
      final fake = await threeUp(tester);
      // ST101 and ST201 are running; ST301 is not.
      expect(_enabled(tester, const Key('section-0-run')), isFalse);
      expect(_enabled(tester, const Key('section-1-run')), isFalse);
      expect(_enabled(tester, const Key('section-2-run')), isTrue);

      await tester.tap(find.byKey(const Key('section-0-run')));
      await _settle(tester);
      expect(fake.writes, isEmpty);
    });

    testWidgets('an unreadable member offers nothing at all', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake,
          cfg: SectionButtonConfig(label: 'Before freezers', sections: [
            SectionRef(key: 'sec/a', label: 'ST101'),
            SectionRef(key: 'sec/b', label: 'ST201'),
          ]));
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(_enabled(tester, const Key('section-1-run')), isFalse);
      expect(_enabled(tester, const Key('section-1-clean')), isFalse);
      expect(_enabled(tester, const Key('section-1-stop')), isFalse,
          reason: 'commanding a section nobody can read could start '
              'machinery blind');
    });

    testWidgets('a held member shows it on its own row and offers no start',
        (tester) async {
      // Per-section "allowed to start" is the member's own state word: a
      // section that is idle and not permitted reads `Can't start`, and the
      // summary row above counts how many.
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true)
        ..push('sec/c', permissive: false);
      await pumpButton(tester, fake,
          cfg: SectionButtonConfig(label: 'Before freezers', sections: [
            SectionRef(key: 'sec/a', label: 'ST101'),
            SectionRef(key: 'sec/b', label: 'ST201'),
            SectionRef(
              key: 'sec/c',
              label: 'ST301',
              holdReason: 'The washdown interlock is open.',
            ),
          ]));
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(find.text('No for 1 of 3'), findsOneWidget);
      expect(find.text("Can't start"), findsOneWidget,
          reason: "the held member's own row says so");
      expect(find.textContaining('ST301: The washdown interlock is open.'),
          findsOneWidget);

      // The PLC ignores start commands without the go-ahead, so neither of
      // that member's start buttons is offered — but Stop still is.
      expect(_enabled(tester, const Key('section-2-run')), isFalse);
      expect(_enabled(tester, const Key('section-2-clean')), isFalse);
      expect(_enabled(tester, const Key('section-2-stop')), isTrue);

      // Nobody can start: two are running and the third is held.
      expect(_enabled(tester, const Key('section-run')), isFalse);
      // But the running pair can still be sent to cleaning.
      expect(_enabled(tester, const Key('section-clean')), isTrue);
    });

    testWidgets('the group buttons still act on the group', (tester) async {
      // The two scopes live side by side and neither borrows the other's.
      final fake = await threeUp(tester);
      await tester.tap(find.byKey(const Key('section-stop')));
      await _settle(tester);
      expect(fake.writes.map((w) => w.key), ['sec/a', 'sec/b', 'sec/c']);
    });

    testWidgets('member buttons are named after their section', (tester) async {
      // Scope an eye reads off the layout has to reach automation and a
      // screen reader too.
      await threeUp(tester);
      final semantics = tester.getSemantics(find.byKey(
        const Key('section-2-stop'),
      ));
      expect(semantics.label, contains('Stop ST301'));
    });
  });

  group('the hold reason is per section, not baked in', () {
    testWidgets('an unconfigured section explains only what is always true',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', permissive: false);
      await pumpButton(tester, fake, cfg: config(['sec/a'], label: 'Line 1'));
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(find.textContaining('Run and Clean are ignored'), findsOneWidget);
      // No guess about WHY. An asset cannot know which interlock holds a
      // section, and a confident wrong instruction is worse than none.
      expect(find.textContaining('vacuum'), findsNothing);
      expect(find.textContaining('freezer'), findsNothing);
    });

    testWidgets('a configured section shows its own words', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', permissive: false);
      await pumpButton(
        tester,
        fake,
        cfg: SectionButtonConfig(label: 'Box packing film', sections: [
          SectionRef(
            key: 'sec/a',
            holdReason: 'The vacuum mode has the line. Stop it and this one '
                'is free.',
          ),
        ]),
      );
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(
          find.textContaining('The vacuum mode has the line'), findsOneWidget);
      // The always-true sentence stays: the operator still needs to know
      // that pressing the buttons will not help.
      expect(find.textContaining('Run and Clean are ignored'), findsOneWidget);
    });

    testWidgets('in a group each held member names itself', (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', permissive: false);
      await pumpButton(
        tester,
        fake,
        cfg: SectionButtonConfig(label: 'Box packing', sections: [
          SectionRef(key: 'sec/a', label: 'ST201', holdReason: 'never shown'),
          SectionRef(key: 'sec/b', label: 'ST301', holdReason: 'Vacuum has it'),
        ]),
      );
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      expect(find.text('No for 1 of 2'), findsOneWidget);
      expect(find.textContaining('ST301: Vacuum has it'), findsOneWidget);
      // ST201 is running, not held — its reason is not an explanation of
      // anything right now.
      expect(find.textContaining('never shown'), findsNothing);
    });

    testWidgets('blank and whitespace-only reasons add no empty paragraph',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', permissive: false);
      await pumpButton(
        tester,
        fake,
        cfg: SectionButtonConfig(label: 'Line 1', sections: [
          SectionRef(key: 'sec/a', holdReason: '   '),
        ]),
      );
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.text('   '), findsNothing);
    });

    testWidgets('the whole config round-trips through JSON', (tester) async {
      final json = SectionButtonConfig(label: 'Before freezers', sections: [
        SectionRef(key: 'sec/a', label: 'ST101', holdReason: 'Vacuum has it'),
        SectionRef(key: 'sec/b'),
      ]).toJson();

      final back = SectionButtonConfig.fromJson(json);
      expect(back.label, 'Before freezers');
      expect(back.sections.map((s) => s.key), ['sec/a', 'sec/b']);
      expect(back.sections.first.label, 'ST101');
      expect(back.sections.first.holdReason, 'Vacuum has it');
      // Nested keys are invisible to the base class's JSON introspection, so
      // the override is what stops unused-key cleanup deleting them.
      expect(back.allKeys, ['sec/a', 'sec/b']);
    });

    testWidgets('a section with a blank key is not subscribed or listed',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(
        tester,
        fake,
        cfg: SectionButtonConfig(label: 'Line 1', sections: [
          SectionRef(key: 'sec/a'),
          SectionRef(key: '   '),
        ]),
      );
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.text('Section'), findsOneWidget,
          reason: 'one usable key means this is a single-section pane');
    });
  });

  group('mode timer', () {
    testWidgets('counts up from the moment the state was first seen',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.text('0s'), findsOneWidget);

      _clockNow = _t0.add(const Duration(minutes: 12, seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('12m 30s'), findsOneWidget);
    });

    testWidgets('the first reading is hedged — it is a floor, not the truth',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      // An earlier `Timer started: when the page opened` row said this in
      // words nobody could parse. The tile label carries it now.
      expect(find.text('For at least'), findsOneWidget);
      expect(find.text('Timer started'), findsNothing);
    });

    testWidgets('a change restarts the count and stops hedging',
        (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      _clockNow = _t0.add(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1h 0m'), findsOneWidget);

      fake.push('sec/a', cleaning: true);
      await _settle(tester);
      expect(find.text('0s'), findsOneWidget);
      expect(find.text('For'), findsOneWidget);
      expect(find.text('For at least'), findsNothing);
    });

    testWidgets('one member changing restarts the group counter',
        (tester) async {
      final fake = _FakeStateMan()
        ..push('sec/a', enabled: true)
        ..push('sec/b', enabled: true);
      await pumpButton(tester, fake, cfg: config(['sec/a', 'sec/b']));
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      _clockNow = _t0.add(const Duration(minutes: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('30m 0s'), findsOneWidget);

      // The group is no longer what it was, so the count is no longer of it.
      fake.push('sec/b');
      await _settle(tester);
      expect(find.text('0s'), findsOneWidget);
    });

    testWidgets('closing and reopening the pane does not restart the count',
        (tester) async {
      // The counter belongs to the sections, not to the window onto them.
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);

      _clockNow = _t0.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('5m 0s'), findsOneWidget);

      await tester.tap(find.byType(SectionButton)); // close
      await _settle(tester);
      await tester.tap(find.byType(SectionButton)); // reopen
      await _settle(tester);
      expect(find.text('5m 0s'), findsOneWidget);
    });

    testWidgets('no ticker survives the pane', (tester) async {
      final fake = _FakeStateMan()..push('sec/a', enabled: true);
      await pumpButton(tester, fake);
      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.byType(SectionModeTimer), findsOneWidget);

      await tester.tap(find.byType(SectionButton));
      await _settle(tester);
      expect(find.byType(SectionModeTimer), findsNothing);
      // A leaked Timer.periodic fails the test binding at tearDown.
    });
  });

  group('the published hit shape', () {
    // The shape the plant view rings while this button's pane is open. It is
    // published in the coordinates of the box the button is laid out in, so
    // it has to be derived from THAT box — not from
    // `RelativeSize.toSize(MediaQuery…)`, which is a fraction of the whole
    // screen while `AssetStack` sizes assets off the canvas (the screen less
    // the app bar, the nav rail, and whatever a docked pane covers). Deriving
    // it from the screen put the ring low and wide of the disc on every page
    // whose canvas is not the full window.
    Future<void> pumpInBox(WidgetTester tester, Size box) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(
        SizedBox(
          width: box.width,
          height: box.height,
          child: SectionButton(config: config(['sec/a'])),
        ),
        overrides: [
          stateManProvider.overrideWith((_) async => _FakeStateMan())
        ],
      ));
      await _settle(tester);
    }

    Rect publishedShape(WidgetTester tester) =>
        tester.widget<AssetHitShape>(find.byType(AssetHitShape)).shape()
            .getBounds();

    Rect paintedBox(WidgetTester tester) => tester.getRect(find.descendant(
          of: find.byType(SectionButton),
          matching: find.byType(CustomPaint),
        ));

    testWidgets('is the disc as drawn, centred in the laid-out box',
        (tester) async {
      // A box the config's own numbers cannot produce: 0.05 of a 1400x1100
      // screen is 70x55, and nothing about 96x96 follows from it.
      await pumpInBox(tester, const Size(96, 96));

      final shape = publishedShape(tester);
      final box = paintedBox(tester);
      expect(box.size, const Size(96, 96));
      expect(shape.center, Offset(box.width / 2, box.height / 2),
          reason: 'the ring goes round the disc, which is in the middle');
      expect(shape.width / 2,
          PowerButtonPainter.radiusFor(box.size));
      expect(shape.height / 2,
          PowerButtonPainter.radiusFor(box.size));
    });

    testWidgets('follows an oblong box rather than the screen it is on',
        (tester) async {
      // The disc is inscribed in the box's shorter side; the shape has to say
      // the same thing the painter draws.
      await pumpInBox(tester, const Size(140, 60));

      final shape = publishedShape(tester);
      expect(shape.center, const Offset(70, 30));
      expect(shape.width, closeTo(58, 0.01)); // 60/2 - 1, doubled
    });
  });
}

/// Pumps frames without `pumpAndSettle`.
///
/// The pane carries a one-second [SectionModeTimer], which schedules a frame
/// forever — `pumpAndSettle` would spin until its own timeout instead of
/// returning. Ten 100 ms frames outlast every animation in the pane's opening
/// (the longest is the 220 ms glide) without reaching the first tick.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Whether the button carrying [key] is live.
bool _enabled(WidgetTester tester, Key key) {
  final button = tester.widget(find.byKey(key));
  return (button as dynamic).onPressed != null;
}

final DateTime _t0 = DateTime.utc(2026, 8, 29, 6, 0, 0);
DateTime _clockNow = _t0;

typedef _Write = ({String key, DynamicValue value});

class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};
  final List<_Write> writes = [];

  /// Publishes an `ST_Section_HMI` struct with the given status bits and the
  /// three command bits cleared, the way `FB_Section` leaves them.
  void push(
    String key, {
    bool enabled = false,
    bool cleaning = false,
    bool permissive = true,
  }) {
    final value = DynamicValue();
    for (final field in [
      kSectionCmdStart,
      kSectionCmdStartClean,
      kSectionCmdStop,
    ]) {
      value[field] = DynamicValue(value: false, typeId: NodeId.boolean);
    }
    value[kSectionStatEnabled] =
        DynamicValue(value: enabled, typeId: NodeId.boolean);
    value[kSectionStatCleanEnabled] =
        DynamicValue(value: cleaning, typeId: NodeId.boolean);
    value[kSectionStatPermissive] =
        DynamicValue(value: permissive, typeId: NodeId.boolean);
    pushRaw(key, value);
  }

  void pushRaw(String key, DynamicValue value) {
    _streams.putIfAbsent(key, () => BehaviorSubject<DynamicValue>()).add(value);
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async =>
      _streams.putIfAbsent(key, () => BehaviorSubject<DynamicValue>()).stream;

  @override
  Future<void> write(String key, DynamicValue value) async {
    writes.add((key: key, value: value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
      );
}
