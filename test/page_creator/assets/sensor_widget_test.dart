import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/sensor.dart';
import 'package:tfc/page_creator/assets/sensor_painter.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

void main() {
  // Wraps a widget in ProviderScope + MaterialApp so showDialog has a
  // Navigator. No provider overrides — tests use the empty-detectionKey path
  // so no real StateMan is needed for tap / stale / rotation assertions.
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('Tap to show details (Plan 04-05)', () {
    // Plan 04-05: tapping a Sensor at runtime opens a READ-ONLY details
    // dialog — NOT the config editor. Config remains editor-only via
    // page_editor.dart's _showConfigDialog → asset.configure(context).
    //
    // Locks the SENS-01 contract: operators can inspect runtime state
    // (kind, detection key, polarity, edge-delay keys, tag) but must
    // never mutate page configuration via runtime taps.

    // Plan 260811 moved this surface from an `AlertDialog` to the non-modal
    // `SidePane`; the SENS-01 contract (read-only, never the editor) is
    // unchanged, so these tests assert on `SidePane` and the same labels.
    tearDown(closeSidePane);

    testWidgets('tap on sensor opens details pane (NOT config dialog)',
        (tester) async {
      final config = SensorConfig(
        detectionKey: 'sensor/01/det',
        kind: SensorKind.opticField,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      expect(find.byType(SidePane), findsOneWidget,
          reason: 'Tap must open the docked details pane.');
      // Locked field labels — these identify the dialog without coupling
      // to private widget types.
      expect(find.text('Detection key'), findsOneWidget,
          reason: 'Details pane must show "Detection key" label.');
      expect(find.text('Kind'), findsOneWidget,
          reason: 'Details pane must show "Kind" label.');

      // Negative locks — no editor controls in the runtime details pane.
      expect(find.byType(SegmentedButton<SensorKind>), findsNothing,
          reason: 'Runtime tap must NOT open the config editor '
              '(no SensorKind SegmentedButton).');
      // The locked editor label "Detection State Key" (capital S, plus
      // "Key" suffix) is unique to _SensorConfigEditor and MUST NOT appear.
      expect(find.text('Detection State Key'), findsNothing,
          reason: 'Runtime tap must NOT render the editor KeyField label.');
    });

    testWidgets('details pane has Close button that dismisses it',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      expect(find.byType(SidePane), findsOneWidget);
      // The Close action — locked copy.
      final closeBtn = find.widgetWithText(TextButton, 'Close');
      expect(closeBtn, findsOneWidget,
          reason: 'Details pane must have a TextButton labelled "Close".');

      await tester.tap(closeBtn);
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing,
          reason: 'Tapping Close must dismiss the details pane.');
    });

    testWidgets('details pane does NOT contain editable fields',
        (tester) async {
      final config = SensorConfig(detectionKey: 'sensor/01/det');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      // Editor-specific widgets MUST NOT appear in the runtime details
      // dialog. These are the unique surface markers of _SensorConfigEditor.
      expect(find.byType(SegmentedButton<SensorKind>), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing,
          reason: 'No SwitchListTile (Invert Active Polarity is editor-only).');
      // No "Save" button (the editor has no save button either, but this
      // negative lock guards against future drift towards editor surface).
      expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
    });

    testWidgets('details dialog shows tag when configured',
        (tester) async {
      final config = SensorConfig(
        detectionKey: 'sensor/01/det',
        tag: 'PE-101A',
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      expect(find.text('Tag'), findsOneWidget);
      expect(find.text('PE-101A'), findsOneWidget);
    });

    testWidgets(
        'tap survives Transform.translate ancestor (Phase 3 forward-compat)',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        Transform.translate(
          offset: const Offset(0, 100),
          child: SizedBox(
            width: 80,
            height: 40,
            child: Sensor(config: config),
          ),
        ),
      ));

      // find.byType locates the Sensor regardless of translation; the tap
      // is dispatched at the translated position because Transform.translate
      // sets transformHitTests=true by default (UI-SPEC §Interaction Contract).
      // ELEV-19 lock: hit-test geometry survives translation. Plan 04-05
      // changes WHAT the gesture does (details pane), not WHETHER it
      // works through translation.
      await tester.tap(find.byType(Sensor));
      await tester.pumpAndSettle();

      expect(find.byType(SidePane), findsOneWidget);
      expect(find.text('Detection key'), findsOneWidget);
    });
  });

  group('Tag pass-through', () {
    // Pre-refactor (commit 5509d610) these tests asserted that
    // `config.tag` flowed to the painter as a `label:` constructor arg.
    // The painter no longer draws the label — `AssetStack` does, via
    // `Asset.text` (aliased onto `tag` by `SensorConfig`). The tests
    // are kept at the same conceptual level (tag pass-through from the
    // config) but assert the new contract: `config.text == config.tag`.
    test('config.tag is exposed through Asset.text', () {
      final config = SensorConfig(detectionKey: '', tag: 'PE-101A');
      expect(config.text, 'PE-101A',
          reason: 'AssetStack reads asset.text to paint the label outside '
              'the rotated subtree (lib/pages/page_view.dart). SensorConfig '
              'must alias tag onto text so this path picks it up.');
    });

    test('null tag yields null Asset.text', () {
      final config = SensorConfig(detectionKey: '');
      expect(config.text, isNull,
          reason: 'AssetStack short-circuits the label render block on '
              'null/empty text — a sensor without a tag must produce a null '
              'text so no label widget is positioned.');
    });
  });

  group('Stale rendering', () {
    testWidgets('empty detectionKey causes painter to receive isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.redLight,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(customPaint.painter, isA<RedLightBeamPainter>());
      expect((customPaint.painter as RedLightBeamPainter).isStale, isTrue);
    });

    testWidgets(
        'opticField + empty detectionKey causes OpticFieldPainter with isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.opticField,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(customPaint.painter, isA<OpticFieldPainter>());
      expect((customPaint.painter as OpticFieldPainter).isStale, isTrue);
    });

    testWidgets(
        'inductiveField + empty detectionKey causes InductiveFieldPainter with isStale=true',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '',
        kind: SensorKind.inductiveField,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(customPaint.painter, isA<InductiveFieldPainter>());
      expect((customPaint.painter as InductiveFieldPainter).isStale, isTrue);
    });
  });

  group('Rotation', () {
    testWidgets('config.coordinates.angle is honoured via LayoutRotatedBox',
        (tester) async {
      final config = SensorConfig(detectionKey: '')
        ..coordinates = Coordinates(x: 0.5, y: 0.5, angle: 90.0);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final rotated = tester.widgetList<LayoutRotatedBox>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(LayoutRotatedBox),
        ),
      );
      expect(rotated, isNotEmpty);
      expect(
        rotated.first.angle,
        closeTo(90.0 * (3.141592653589793 / 180.0), 1e-9),
      );
    });

    testWidgets('null angle defaults to 0 radians', (tester) async {
      final config = SensorConfig(detectionKey: '')
        ..coordinates = Coordinates(x: 0.5, y: 0.5);
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));

      final rotated = tester.widgetList<LayoutRotatedBox>(
        find.descendant(
          of: find.byType(Sensor),
          matching: find.byType(LayoutRotatedBox),
        ),
      );
      expect(rotated, isNotEmpty);
      expect(rotated.first.angle, 0.0);
    });
  });

  group('Polarity through widget', () {
    testWidgets(
        'rawBool=true with invertActivePolarity=false yields isActive=true',
        (tester) async {
      // Use detectionKey '/k' to exercise the stream path; the test reads
      // the @visibleForTesting helper directly so the widget tree never
      // actually pumps a value (StateMan is unconfigured under ProviderScope
      // with no overrides — its provider Future never completes in this
      // synchronous test pump). The helper itself is pure.
      final config = SensorConfig(
        detectionKey: '/k',
        invertActivePolarity: false,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      expect(state.resolveIsActive(true), isTrue);
      expect(state.resolveIsActive(false), isFalse);
    });

    testWidgets('invertActivePolarity=true flips both directions',
        (tester) async {
      final config = SensorConfig(
        detectionKey: '/k',
        invertActivePolarity: true,
      );
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      expect(state.resolveIsActive(true), isFalse);
      expect(state.resolveIsActive(false), isTrue);
    });

    test(
        'Sensor widget file contains no AnimationController or Tween references (SENS-05 immediate-flip guard)',
        () async {
      final source =
          await File('lib/page_creator/assets/sensor.dart').readAsString();
      expect(source, isNot(contains('AnimationController')));
      expect(source, isNot(contains('TweenAnimationBuilder')));
      expect(source, isNot(contains('animateTo')));
    });
  });

  group('Tooltip removed', () {
    // The hover tooltip + `_SensorTooltipContent` widget are gone. Operators
    // still get the full detail panel via tap → `_showDetailsDialog`; the
    // tooltip path was redundant and noisy on a busy HMI canvas.
    testWidgets('Sensor widget tree contains NO Tooltip',
        (tester) async {
      final config = SensorConfig(detectionKey: '');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final tooltip = find.descendant(
        of: find.byType(Sensor),
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsNothing,
          reason: 'Sensor must not wrap its painter in a Tooltip — the '
              'tap-to-open details dialog replaces the hover affordance.');
    });

    test(
        'sensor.dart source has no Tooltip or _SensorTooltipContent references',
        () async {
      final source =
          await File('lib/page_creator/assets/sensor.dart').readAsString();
      expect(source, isNot(contains('Tooltip')),
          reason: 'Tooltip wrapper has been removed from Sensor.');
      expect(source, isNot(contains('_SensorTooltipContent')),
          reason: 'Tooltip content widget has been removed from Sensor.');
    });
  });

  group('Stream lifecycle', () {
    testWidgets('rebuilds with same detectionKey do not re-hoist the stream',
        (tester) async {
      final config = SensorConfig(detectionKey: '/k1');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      // Stream identity at t=0 (after initState).
      final streamRef1 = state.debugDetectionStream;

      // Trigger a rebuild WITHOUT changing the config — same SensorConfig
      // instance, same detectionKey. didUpdateWidget must NOT re-hoist.
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config)),
      ));
      final streamRef2 = state.debugDetectionStream;

      expect(
        identical(streamRef1, streamRef2),
        isTrue,
        reason: 'Stream identity must persist across rebuilds (Pitfall 2)',
      );
    });

    testWidgets('changing detectionKey re-hoists the stream', (tester) async {
      final config1 = SensorConfig(detectionKey: '/k1');
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config1)),
      ));
      final dynamic state = tester.state(find.byType(Sensor));
      final streamRef1 = state.debugDetectionStream;

      // Mutate config to a different key — this is the path the editor
      // dialog takes (config object is reused across rebuilds; keys mutate).
      config1.detectionKey = '/k2';
      await tester.pumpWidget(wrap(
        SizedBox(width: 80, height: 40, child: Sensor(config: config1)),
      ));
      final streamRef2 = state.debugDetectionStream;

      expect(
        identical(streamRef1, streamRef2),
        isFalse,
        reason:
            'Stream must re-hoist when detectionKey changes (didUpdateWidget guard)',
      );
    });

    test(
        'build() does not construct a stream inline (Pitfall 2 source-level guard)',
        () async {
      final source =
          await File('lib/page_creator/assets/sensor.dart').readAsString();
      // Strip line-comments to avoid false positives from doc-comments.
      final stripped = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // Find the _SensorState.build(...) method body and check no stream
      // construction expressions live inside it.
      final buildSection =
          RegExp(r'Widget build\(BuildContext context\) \{[\s\S]*?\n  \}')
                  .firstMatch(stripped)
                  ?.group(0) ??
              '';
      expect(buildSection, isNotEmpty,
          reason: 'Could not locate build() method in sensor.dart');
      expect(buildSection, isNot(contains('stateManProvider')));
      expect(buildSection, isNot(contains('subscribe(')));
    });
  });

  group('Config dialog smoke (editor path — configure())', () {
    // Plan 04-05: the config dialog is now editor-only. Tests invoke
    // SensorConfig.configure(context) directly inside a Dialog — same
    // pattern as page_editor.dart:_showConfigDialog (which is the only
    // production caller that opens this dialog).
    //
    // This bypasses the runtime tap path (which now opens a read-only
    // details dialog per Plan 04-05 / SENS-01) while preserving the
    // UI-SPEC §Copywriting Contract assertions on the editor body itself.

    /// Pumps a SensorConfig editor wrapped in the same Dialog chrome that
    /// page_editor.dart uses. Returns immediately so the caller can
    /// pumpAndSettle().
    Future<void> openConfigEditor(WidgetTester tester, SensorConfig config) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(child: config.configure(context)),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('config dialog renders all locked field-labels',
        (tester) async {
      final config = SensorConfig();
      await openConfigEditor(tester, config);

      // Locked copy from UI-SPEC §Copywriting Contract — verbatim.
      expect(find.text('Sensor Kind'), findsOneWidget);
      expect(find.text('Red Light'), findsOneWidget);
      expect(find.text('Optic Field'), findsOneWidget);
      expect(find.text('Inductive Field'), findsOneWidget);
      expect(find.text('Invert Active Polarity'), findsOneWidget);
      expect(find.text('Active Color'), findsOneWidget);
      expect(find.text('Inactive Color'), findsOneWidget);
    });

    testWidgets(
        'Invert Active Polarity subtitle copy reflects current value',
        (tester) async {
      final config = SensorConfig(invertActivePolarity: false);
      await openConfigEditor(tester, config);
      expect(find.text('Active when state is true'), findsOneWidget);

      // Toggle the switch — subtitle copy must flip per UI-SPEC.
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('Active when state is false'), findsOneWidget);
    });

    testWidgets('changing kind via SegmentedButton updates config.kind',
        (tester) async {
      final config = SensorConfig(kind: SensorKind.redLight);
      await openConfigEditor(tester, config);

      // Tap the "Optic Field" segment.
      await tester.tap(find.text('Optic Field'));
      await tester.pumpAndSettle();
      expect(config.kind, SensorKind.opticField);
    });

    testWidgets(
        'CoordinatesField is in the config dialog (SENS-15 — angle is part of CoordinatesField)',
        (tester) async {
      final config = SensorConfig();
      await openConfigEditor(tester, config);
      expect(find.byType(CoordinatesField), findsOneWidget);
    });

    testWidgets('config dialog exposes a DropdownButton<TextPos>',
        (tester) async {
      // Mirrors Button (button.dart:758) / LED (led.dart:164) — operators
      // must be able to pick where the asset label sits (above/below/left/
      // right/inside). The field+storage already exist on BaseAsset; this
      // test pins the picker's presence in the sensor's editor body.
      final config = SensorConfig();
      await openConfigEditor(tester, config);
      expect(find.byType(DropdownButton<TextPos>), findsOneWidget,
          reason: 'Sensor config dialog must expose a DropdownButton<TextPos> '
              'so operators can choose label position.');
    });

    testWidgets('changing TextPos via dropdown updates config.textPos',
        (tester) async {
      final config = SensorConfig();
      await openConfigEditor(tester, config);

      // Editor body lives in a SingleChildScrollView; the dropdown sits
      // below the fold. Scroll it into view before tapping.
      final dropdown = find.byType(DropdownButton<TextPos>);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      // Open the dropdown and pick "above". The menu items render in an
      // overlay; tapping the "above" text in the overlay selects it.
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      // Tap the menu item for `above`. There can be multiple `above` texts
      // (collapsed item + overlay item); the overlay-rendered one is `last`.
      await tester.tap(find.text('above').last);
      await tester.pumpAndSettle();
      expect(config.textPos, TextPos.above);
    });
  });
}
