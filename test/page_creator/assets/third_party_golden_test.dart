import 'dart:async';
import 'dart:collection' show LinkedHashMap;
import 'dart:io' show File, Platform;
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/widgets/panes/pane_chrome.dart'
    show PaneStatus, PaneSection, PaneDetailRow;
import 'package:tfc/widgets/panes/side_pane.dart' show SidePane, closeSidePane;
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/ratio_number.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc_dart/core/database.dart' show Database;
import 'package:tfc/page_creator/assets/third_party.dart';
import 'package:tfc/page_creator/assets/third_party_painter.dart';

const _key = Key('third_party_golden');

/// Golden canvas size for a kind, at that machine's true plan aspect ratio.
///
/// Fitted into a 720 x 820 box rather than fixed-width, because the kinds run
/// from a 5.4:1 Multivac strip to a PORTRAIT SpeedBatcher — pinning the width
/// would run the SpeedBatcher off the bottom of the golden.
Size _canvasFor(ThirdPartyEquipmentKind kind, {int strapMachines = 3}) {
  const maxW = 720.0;
  const maxH = 820.0;
  final aspect = kind.aspectRatio(strapMachines: strapMachines);
  double w = maxW;
  double h = maxW / aspect;
  if (h > maxH) {
    h = maxH;
    w = maxH * aspect;
  }
  return Size(w, h);
}

/// Wraps the painted body in a minimal tree for golden capture.
///
/// Renders [ThirdPartyEquipmentBody] rather than [ThirdPartyEquipment] so no
/// `StateMan` is needed — the LED colour is passed directly, which is exactly
/// what the live widget resolves it to.
Widget buildBody({
  required ThirdPartyEquipmentKind kind,
  Color? ledColor = Colors.green,
  Color outlineColor = const Color(0xFF37474F),
  double strokeWidth = 2.5,
  int strapMachines = 3,
}) {
  final size = _canvasFor(kind, strapMachines: strapMachines);
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: RepaintBoundary(
          key: _key,
          child: ThirdPartyEquipmentBody(
            painter: thirdPartyPainterFor(
              kind,
              color: outlineColor,
              strokeWidth: strokeWidth,
              strapMachines: strapMachines,
            ),
            paintSize: size,
            ledColor: ledColor,
          ),
        ),
      ),
    ),
  );
}

/// Loads real fonts for the populated and pane goldens.
///
/// Without this every glyph renders as a filled black box — the Flutter test
/// font draws no actual letterforms — which turns the readouts into bars and
/// makes the golden useless for judging whether a weight beside a belt is
/// legible. RobotoMono is already in the repo under `lib/fonts/`.
///
/// MaterialIcons is loaded too, from the Flutter SDK: the pane goldens carry
/// icons (the header glyph, the status chip's dot) and without the icon font
/// they render as tofu boxes, which is not what an operator sees.
Future<void> loadRealFont() async {
  final data = File('lib/fonts/roboto-mono/RobotoMono-Regular.ttf')
      .readAsBytesSync()
      .buffer
      .asByteData();
  final loader = FontLoader('Roboto')..addFont(Future.value(data));
  await loader.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (flutterRoot != null && iconFont.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(iconFont.readAsBytesSync().buffer.asByteData()));
    await iconLoader.load();
  }
}

/// The scaffolded station with both checkweigher belts RUNNING.
///
/// The readouts are the real `NumberConfig` children the scaffold creates, on
/// their real anchors, switched to the preview key so they show a value
/// without a PLC.
///
/// The belts are the real [ConveyorPainter] the `Conveyor` asset paints with,
/// given the same arguments the asset would pass — bidirectional, geometry
/// from `ConveyorPathGeometry.build` — plus a frequency the test supplies.
/// That last part is the one thing a widget test cannot get honestly: the
/// frequency arrives over a `StateMan` subscription, and `StateMan` has a
/// private constructor that spins real OPC UA client loops, so there is no
/// test double to hand. Feeding the painter directly is what makes the
/// run-direction arrow visible here.
Widget buildRunningStation({double frequency = 50.0}) {
  final children = buildSpeedBatcherStationChildren(acceptWindowMinutes: 30);

  // Both readouts go in as real children, on their real anchors, each
  // switched to its own asset's preview keys so it shows a value with no PLC
  // behind it: NumberWidget renders its sample weight, RatioNumber its
  // sample percentage.
  final readouts = children.where((e) => e.child is! ConveyorConfig).toList();
  for (final entry in readouts) {
    final child = entry.child;
    if (child is NumberConfig) child.key = 'Number preview';
    if (child is RatioNumberConfig) {
      child.key1 = 'key1';
      child.key2 = 'key2';
    }
  }

  final size = _canvasFor(ThirdPartyEquipmentKind.speedBatcher);
  final area = thirdPartyMachineArea(size);

  Widget belt(Rect frame) {
    final deck = SpeedBatcherPainter.deckOf(frame);
    final rect = Rect.fromLTRB(
      area.left + deck.left * area.width,
      area.top + deck.top * area.height,
      area.left + deck.right * area.width,
      area.top + deck.bottom * area.height,
    );
    final beltSize = Size(rect.width, rect.height);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      // The scaffold turns the weigh belts half a revolution (product runs
      // right-to-left), which `LayoutRotatedBox` applies for a live child;
      // for 180 degrees a plain Transform.rotate lands on the same pixels.
      child: Transform.rotate(
        angle: pi,
        child: CustomPaint(
          size: beltSize,
          painter: ConveyorPainter(
            color: Colors.green,
            bidirectional: true,
            reverseDirection: false,
            showFrequency: false,
            frequency: frequency,
            batches: const {},
            angle: 180,
            geometry: ConveyorPathGeometry.build(const [], beltSize),
          ),
        ),
      ),
    );
  }

  return ProviderScope(
    overrides: [
      // RatioNumber's timeseries mixin arms its refresh timer only after
      // `databaseProvider` resolves. A widget test has no database, and a
      // timer left running fails the binding at teardown. Handing it a
      // future that never completes parks the mixin at its first await —
      // the widget still builds and paints, which is all a golden needs.
      databaseProvider.overrideWith((ref) => Completer<Database?>().future),
    ],
    child: MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: _key,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: thirdPartyPainterFor(
                        ThirdPartyEquipmentKind.speedBatcher,
                        color: const Color(0xFF37474F),
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                  belt(SpeedBatcherPainter.checkweigher1Frame),
                  belt(SpeedBatcherPainter.checkweigher2Frame),
                  // Readouts on top of the belts, via the real body so their
                  // anchors and sizing come from production code.
                  Positioned.fill(
                    child: ThirdPartyEquipmentBody(
                      painter: _NoopPainter(),
                      paintSize: size,
                      ledColor: Colors.green,
                      children: readouts,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Draws nothing — lets the body be reused purely to place children over an
/// already-painted machine.
class _NoopPainter extends ThirdPartyMachinePainter {
  const _NoopPainter() : super(color: const Color(0x00000000), strokeWidth: 0);
  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {}
  @override
  void paint(Canvas canvas, Size size) {}
}

void main() {
  group('ThirdPartyEquipment plan-view goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    // One golden per equipment kind, running. These are the drawings to
    // review — each is a simplified plan view of the real machine, sourced
    // from the manufacturer photos and spec sheets cited at the top of
    // `third_party_painter.dart`.
    for (final kind in ThirdPartyEquipmentKind.values) {
      testWidgets('${kind.name} — running', (tester) async {
        tester.view.physicalSize = const Size(1400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildBody(kind: kind));
        await expectLater(
          find.byKey(_key),
          matchesGoldenFile('goldens/third_party_${kind.name}_running.png'),
        );
      });
    }

    // The SpeedBatcher station with "Build checkweighers" applied and both
    // belts RUNNING: full-width conveyor per checkweigher, run-direction
    // arrow mid-belt, live weight right of the arrow, accept rate left. This
    // is the golden to judge the layout by.
    // testWidgets name kept stable so the golden file name does not churn.
    testWidgets('speedBatcher — checkweighers populated', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildRunningStation());
      await tester.pump(const Duration(milliseconds: 16));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_speedBatcher_populated.png'),
      );


    });

    // The SpeedBatcher side pane's Status section, every diode state at once:
    // Running lit green, Cleaning lit blue, Batch ready off (white), and the
    // two bits absent from the struct — the way a PLC that does not expose
    // them hands it over — as the grey `!` unknown. This is the golden to
    // judge the diode treatment by. The header badge comes through
    // `speedBatcherPaneStatus` on the same struct, so it reads Cleaning here
    // — the case that used to misreport as Stopped.
    testWidgets('speedBatcher — status pane diodes', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final status = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
        'p_stat_Running': true,
        'p_stat_Cleaning': true,
        'p_stat_BatchReady': false,
      }));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: _key,
              child: SizedBox(
                width: 420,
                height: 560,
                child: Material(
                  child: SidePane(
                    title: 'SB-01',
                    subtitle: 'Marel SpeedBatcher',
                    icon: Icons.precision_manufacturing,
                    status: speedBatcherPaneStatus(
                        status, const PaneStatus.stale()),
                    child: PaneSection(
                      title: 'Status',
                      child: StructStatusDiodes(
                        status: status,
                        bits: speedBatcherStatusBits,
                        machine: 'SpeedBatcher',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_speedBatcher_status_pane.png'),
      );
    });

    // The WHOLE reworked side pane, driven through the real widget — machine
    // on the page, pane opened by the real tap. Live figures per
    // checkweigher (each readout switched to its preview keys so it shows a
    // value without a PLC), the diode section beneath, and none of the
    // wiring the pane used to carry: no footprint, no run-status keys, no
    // polarity wording, no inside-the-box inventory. This is the golden to
    // judge the pane rework by.
    testWidgets('speedBatcher — side pane', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(closeSidePane);

      final children =
          buildSpeedBatcherStationChildren(acceptWindowMinutes: 30);
      for (final entry in children) {
        final child = entry.child;
        if (child is NumberConfig) child.key = 'Number preview';
        if (child is RatioNumberConfig) {
          child.key1 = 'key1';
          child.key2 = 'key2';
        }
      }
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        tag: 'SB-01',
        children: children,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          // Same parking trick as `buildRunningStation`: the readouts build
          // and paint without a database, which is all a golden needs.
          databaseProvider
              .overrideWith((ref) => Completer<Database?>().future),
        ],
        child: RepaintBoundary(
          key: _key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Colors.white,
              // Machine on the left, clear of the docked pane, the way an
              // operator sees both at once.
              body: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: SizedBox(
                    width: 280,
                    height: 620,
                    child: ThirdPartyEquipment(config: config),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(ThirdPartyEquipment));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_speedBatcher_side_pane.png'),
      );
    });

    // The strapping line ships as SL-15-1, -2 and -3. Head count changes both
    // the number of arches and the machine's proportions, so each variant
    // gets its own golden. (-3 is covered by the per-kind loop above.)
    for (final heads in const [1, 2]) {
      testWidgets('strappingLine — $heads strapper(s)', (tester) async {
        tester.view.physicalSize = const Size(1400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildBody(
          kind: ThirdPartyEquipmentKind.strappingLine,
          strapMachines: heads,
        ));
        await expectLater(
          find.byKey(_key),
          matchesGoldenFile('goldens/third_party_strappingLine_${heads}x.png'),
        );
      });
    }

    // LED states, captured on one kind. The machine drawing is identical
    // across states by design — only the run LED changes — so there is no
    // value in a stopped/unknown pair for all four.
    testWidgets('strappingLine — stopped', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildBody(
        kind: ThirdPartyEquipmentKind.strappingLine,
        ledColor: Colors.red,
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_strappingLine_stopped.png'),
      );
    });

    testWidgets('strappingLine — unknown (no key / stale)', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // A null LED colour is the stale path — `LEDPainter` renders grey with
      // its `!` glyph, the same as every other unresolved LED on the page.
      await tester.pumpWidget(buildBody(
        kind: ThirdPartyEquipmentKind.strappingLine,
        ledColor: null,
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_strappingLine_unknown.png'),
      );
    });

    // The strapping line's Status section off the `ST_StrappingLine_HMI`
    // struct, every diode state at once: the new frustration bit LIT red —
    // the line has run 15 s with a clear way out and a blocked infeed, the
    // one state that says something is wrong — head 1 ready (green) beside
    // head 2 not (white), pinning the 0-based-list-to-1-based-label mapping
    // in pixels, infeed-permitted OFF (white), and outfeed-permitted absent
    // from the struct, rendered as the grey `!` rather than claiming "off".
    // The labels are the `{m}` templates filled with "strapping machine", so
    // this golden also pins the wording that names the strapper as the thing
    // being waited ON.
    testWidgets('strappingLine — status pane diodes', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final status = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
        'p_stat_WaitingFrustration': true,
        'p_stat_StrappingMachines': [
          DynamicValue.fromMap(
              LinkedHashMap<String, dynamic>.from({'p_stat_Rdy': true})),
          DynamicValue.fromMap(
              LinkedHashMap<String, dynamic>.from({'p_stat_Rdy': false})),
        ],
        'p_stat_InfeedPermitted': false,
      }));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: _key,
              child: SizedBox(
                width: 420,
                height: 560,
                child: Material(
                  child: SidePane(
                    title: 'STM-01',
                    subtitle: 'Afak / StrapX strapping line',
                    icon: Icons.precision_manufacturing,
                    // The strapper's header still reads the run key — the
                    // struct override is SpeedBatcher-only (Cleaning).
                    status: const PaneStatus.running(),
                    child: PaneSection(
                      title: 'Status',
                      child: StructStatusDiodes(
                        status: status,
                        bits: strappingLineStatusBits,
                        machine: equipmentShortName(
                            ThirdPartyEquipmentKind.strappingLine),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile(
            'goldens/third_party_strappingLine_status_pane.png'),
      );
    });

    // The box erector's Status section off the enhanced `BER0n.BER0n` struct,
    // a mix of diode states: a red fault LIT (a drive has faulted) while the
    // stopping-line and estop rows are OFF (white), an amber waiting row LIT
    // (waiting for carton bottoms), the green running row LIT, and several
    // members absent from the struct — keys this pumped value does not carry —
    // rendered as the grey `!` unknown rather than claiming "off". The box
    // erector was the last prefix-backed kind; the enhanced FB moved it onto
    // the struct system, so this is now a [StructStatusDiodes] pane like the
    // strapper's, pinning the curated fault-first vocabulary in pixels.
    testWidgets('boxErector — status pane diodes', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final status = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
        'p_stat_WaitingFrustration': false,
        'p_stat_xEstopActive': false,
        'p_stat_xDriveError': true,
        'p_stat_xWaitingBottoms': true,
        'p_stat_xRunning': true,
        // Lit so the manual row's colour is actually IN the golden: it is the
        // same yellow a belt in manual gets, and a row left unset would render
        // the grey unknown and pin nothing. A box erector can be running while
        // an operator jogs it, so both being true is a real state.
        'p_stat_xModeManual': true,
        // The throughput the enhanced FB publishes, shown as a figure above
        // the diodes. Non-zero on purpose: 0 is what a stopped machine reads,
        // and the point of this row is that it is a live rate, not a lamp.
        'bpmCartonsOut': 37.0,
      }));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: _key,
              child: SizedBox(
                width: 420,
                height: 1180,
                child: Material(
                  child: SidePane(
                    title: 'BER-01',
                    subtitle: 'Box erector',
                    icon: Icons.precision_manufacturing,
                    status: const PaneStatus.running(),
                    child: PaneSection(
                      title: 'Status',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The same two blocks `_statusSection` composes for a
                          // box erector: the throughput figure, then the
                          // diodes.
                          PaneDetailRow(
                            label: 'Cartons per minute',
                            child: Builder(
                              builder: (context) => Text(
                                boxErectorBpmOf(status)!.toStringAsFixed(0),
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ),
                          StructStatusDiodes(
                            status: status,
                            bits: boxErectorStatusBits,
                            machine: equipmentShortName(
                                ThirdPartyEquipmentKind.boxErector),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_boxErector_status_pane.png'),
      );
    });


    // The Multivac's Status section as an operator on line 2 actually sees it:
    // the four struct diodes off `SP_Packing_HMI`, and BENEATH them the one
    // loose diode the instance declares — `MVC02.PermitOutfeed`, the outfeed
    // permit that is not a member of the handshake struct and had no way to be
    // shown at all before #381.
    //
    // This is the golden to judge the extra-bit treatment by, and the whole
    // test is whether you can TELL which row is the extra one. You should not
    // be able to: same label column, same 22 px diode, same plain rows, same
    // green a permit gets everywhere else in this file, and the label is the
    // shared `'{m} may send boxes on'` template — the strapping line's
    // `p_stat_OutfeedPermitted` and the box erector's `PermitOutfeed`, character
    // for character — rendered through the same substitution rather than typed
    // out per instance. The operator is not meant to care that this
    // one bit arrives on a separate subscription in a different namespace.
    //
    // The struct is mixed on purpose — ready for fish with a drop waiting
    // (yellow) and the drop not finished — so the extra diode sits against a
    // live-looking section rather than a column of identical dots.
    testWidgets('multivac — status pane with extra outfeed diode',
        (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final status = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
        'p_stat_WaitingFrustration': false,
        'p_stat_DropOk': true,
        'p_stat_DropRequestFeedback': true,
        'p_stat_DropFinished': false,
      }));

      // The template, not the finished sentence — `{m}` becomes "Multivac"
      // through the same `fillMachineLabel` the struct and prefix bits use.
      const extra = ExtraStatusBit(
        key: 'MVC02.PermitOutfeed',
        label: '{m} may send boxes on',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: _key,
              child: SizedBox(
                width: 420,
                height: 560,
                child: Material(
                  child: SidePane(
                    title: 'MVC-02',
                    subtitle: 'Multivac',
                    icon: Icons.precision_manufacturing,
                    status: const PaneStatus.running(),
                    child: PaneSection(
                      title: 'Status',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StructStatusDiodes(
                            status: status,
                            bits: multivacStatusBits,
                            machine: equipmentShortName(
                                ThirdPartyEquipmentKind.multivac),
                          ),
                          ExtraStatusDiodes(
                            bits: const [extra],
                            values: const {'MVC02.PermitOutfeed': true},
                            machine: equipmentShortName(
                                ThirdPartyEquipmentKind.multivac),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_multivac_status_pane.png'),
      );
    });

    // The editor's "Extra status diodes" section with one row populated, the
    // control #385 adds — before it, `extraBits` could only be set through the
    // MCP `update_asset` tool, so an operator could not put the Multivac's
    // outfeed permit on its pane at all.
    //
    // What this golden is for: the LABEL field is a `{m}` TEMPLATE, not the
    // finished sentence, and an operator has no way to know that from a text
    // box. The hint and helper text carrying that ("{m} becomes the machine
    // name") are the whole reason the row is usable, and they are the first
    // thing a later layout change would silently crop or overflow. The colour
    // dropdown sits beside a remove button, and a fresh row comes up GREEN —
    // what a permit is on every machine in this file.
    testWidgets('multivac — editor extra status diodes', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.multivac,
        statusKey: 'SPB02.multivac.hmi',
        extraBits: const [
          ExtraStatusBit(
            key: 'MVC02.PermitOutfeed',
            label: '{m} may send boxes on',
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: _key,
                child: SizedBox(
                  width: 400,
                  height: 1320,
                  child: Material(
                    child: Builder(
                        builder: (context) => config.configure(context)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile(
            'goldens/third_party_multivac_editor_extra_bits.png'),
      );
    });

    // The editor with the box erector selected: the Status Struct Key field and
    // its member-listing help text. The box erector migrated to the struct
    // system with the enhanced `BER0n.BER0n` FB, so its field now names the one
    // node the diodes read rather than the suffixes a prefix appended.
    testWidgets('boxErector — editor status key field', (tester) async {
      await loadRealFont();
      // Taller than the field it is named for needs: #385 added the "Extra
      // status diodes" section below, and at the old 1100 the frame cut
      // through the middle of the Running Color row, which reads as a
      // rendering fault rather than a crop.
      tester.view.physicalSize = const Size(600, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.boxErector,
        statusKey: 'BER02',
      );
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: _key,
                child: SizedBox(
                  width: 400,
                  height: 1420,
                  child: Material(
                    child: Builder(
                        builder: (context) => config.configure(context)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile(
            'goldens/third_party_boxErector_editor_status_key.png'),
      );
    });
  });
}
