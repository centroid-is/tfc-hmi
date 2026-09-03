import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/vtug.dart';
import 'package:tfc/painter/festo/vtug.dart';
import 'package:tfc/theme.dart';

/// Goldens of the Festo VTUG-14 terminal and its pane.
///
/// The drawing is of a real part and no widget test can say whether it looks
/// like one: whether eight 14 mm slices and a CTEU-EC read as the assembly
/// bolted to ST303, whether the coil lamps land where the LEDs land on the
/// valve, whether a blanked position is visibly a gap in the row rather than
/// a valve that happens to be off. These images are how that gets checked.
///
/// They also pin the honest bits, which are the ones easiest to "fix" into a
/// lie:
///
///  * A **blank** position draws no lamps at all. A dark lamp there would
///    invent a coil the manifold does not have.
///  * A **dark** bus node draws every LED unknown, including ERROR. Drawing
///    ERROR dark because no error arrived reads a silence as an all-clear.
///  * A **held** valve wears an orange bar. Orange is forced everywhere in
///    this repo, and a hand-held valve that looked like an automatic one is
///    a valve somebody forgets to give back.
Future<void> loadRealFont() async {
  Future<void> loadFont(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
  }

  await loadFont('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
  await loadFont(
      'roboto-mono', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  for (final candidate in <String>[
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
  ]) {
    if (File(candidate).existsSync()) {
      await loadFont('MaterialIcons', candidate);
      break;
    }
  }
}

void main() {
  setUpAll(loadRealFont);

  /// The real station themes, not a hand-rolled one.
  ///
  /// A pane golden built on a bare `ThemeData` cannot catch the thing dark
  /// goldens exist to catch: neither Solarized scheme sets
  /// `colorScheme.outline`, so a widget that borrows it draws an edge that
  /// is invisible on base03 and perfectly fine in the light image.
  final (lightTheme, darkTheme) = solarized();

  Widget host(Widget child, {bool dark = false, Color? background}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: (dark ? darkTheme : lightTheme).copyWith(
          textTheme: (dark ? darkTheme : lightTheme)
              .textTheme
              .apply(fontFamily: 'roboto-mono'),
        ),
        home: Scaffold(
          backgroundColor: background ??
              (dark
                  ? const Color(0xFF002B36)
                  : const Color(0xFFEEE8D5)),
          body: Center(child: child),
        ),
      );

  List<VtugValveKind> kinds({
    Set<int> blanks = const {},
    Set<int> singles = const {},
  }) =>
      [
        for (var i = 1; i <= vtugPositionCount; i++)
          blanks.contains(i)
              ? VtugValveKind.blank
              : singles.contains(i)
                  ? VtugValveKind.singleSolenoid
                  : VtugValveKind.doubleSolenoid,
      ];

  DynamicValue struct({
    int coils = 0,
    int forceMask = 0,
    int forceValue = 0,
  }) {
    final dv = DynamicValue();
    dv['p_stat_Coils'] = coils;
    dv['p_stat_Forced'] = 0;
    dv['p_cmd_Force'] = forceMask;
    dv['p_cmd_Value'] = forceValue;
    return dv;
  }

  /// The drawing, built from a decoded terminal the same way the live widget
  /// builds it — so a change to how the asset maps valves onto slices shows
  /// up here rather than only on a running station.
  Widget drawing(VtugTerminal terminal, CteuLink link, {String name = ''}) =>
      Builder(
        builder: (context) => VtugWidget(
          height: 200,
          slices: [
            for (final valve in terminal.valves)
              VtugSliceView(
                coils: [
                  for (final coil in VtugCoil.values)
                    if (valve.hasCoil(coil)) valve.coilState(coil),
                ],
                held: valve.force != VtugForce.auto,
              ),
          ],
          leds: link.leds,
          litColor: HmiStateColors.of(context).yellow,
          name: name,
          disconnected: link == CteuLink.dark,
        ),
      );

  group('the drawing', () {
    testWidgets('eight doubles, nothing energised', (tester) async {
      await tester.pumpWidget(host(drawing(
        VtugTerminal.read(struct(), kinds: kinds()),
        CteuLink.live,
        name: 'ST303.A1',
      )));
      await expectLater(
        find.byType(VtugWidget),
        matchesGoldenFile('goldens/festo/vtug_idle.png'),
      );
    }, skip: !Platform.isMacOS);

    testWidgets('coils energised across both bytes', (tester) async {
      // Position 1 coil 14 (bit 0), position 4 coil 12 (bit 7), position 5
      // coil 14 (bit 8), position 8 coil 12 (bit 15) — one lamp at each
      // corner of the map, so a transposed byte or a flipped coil is
      // visible rather than plausible.
      const coils = (1 << 0) | (1 << 7) | (1 << 8) | (1 << 15);
      await tester.pumpWidget(host(drawing(
        VtugTerminal.read(struct(coils: coils), kinds: kinds()),
        CteuLink.live,
        name: 'ST303.A1',
      )));
      await expectLater(
        find.byType(VtugWidget),
        matchesGoldenFile('goldens/festo/vtug_energised.png'),
      );
    }, skip: !Platform.isMacOS);

    testWidgets('a mixed manifold — blanks and a single solenoid',
        (tester) async {
      await tester.pumpWidget(host(drawing(
        VtugTerminal.read(
          struct(coils: 1 << 2),
          kinds: kinds(blanks: {6, 7, 8}, singles: {2}),
        ),
        CteuLink.live,
        name: 'ST303.A1',
      )));
      await expectLater(
        find.byType(VtugWidget),
        matchesGoldenFile('goldens/festo/vtug_mixed.png'),
      );
    }, skip: !Platform.isMacOS);

    testWidgets('two valves held by hand', (tester) async {
      // Position 2 open, position 5 closed.
      final open = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.doubleSolenoid,
        position: 2,
        force: VtugForce.open,
      );
      final both = vtugApplyForce(
        forceMask: open.mask,
        forceValue: open.value,
        kind: VtugValveKind.doubleSolenoid,
        position: 5,
        force: VtugForce.closed,
      );
      await tester.pumpWidget(host(drawing(
        VtugTerminal.read(
          struct(
            coils: both.value,
            forceMask: both.mask,
            forceValue: both.value,
          ),
          kinds: kinds(),
        ),
        CteuLink.live,
        name: 'ST303.A1',
      )));
      await expectLater(
        find.byType(VtugWidget),
        matchesGoldenFile('goldens/festo/vtug_held.png'),
      );
    }, skip: !Platform.isMacOS);

    testWidgets('nothing arriving — every lamp unknown, node included',
        (tester) async {
      await tester.pumpWidget(host(drawing(
        VtugTerminal.read(null, kinds: kinds()),
        CteuLink.dark,
        name: 'ST303.A1',
      )));
      await expectLater(
        find.byType(VtugWidget),
        matchesGoldenFile('goldens/festo/vtug_dark.png'),
      );
    }, skip: !Platform.isMacOS);
  });

  group('the pane', () {
    Widget pane(
      VtugTerminal terminal, {
      bool commandable = true,
      bool dark = false,
    }) =>
        host(
          SizedBox(
            width: 380,
            // Keyed and given the theme's own surface: the golden captures
            // this box, so the image carries the background a pane actually
            // sits on. Capturing the body alone put a dark-theme pane on
            // white, which is exactly the image a dark golden exists to
            // avoid.
            child: Builder(
              builder: (context) => ColoredBox(
                key: const Key('pane-golden'),
                color: Theme.of(context).colorScheme.surface,
                child: SingleChildScrollView(
                  child: Material(
                    color: Colors.transparent,
                    child: VtugPaneBody(
                      terminal: terminal,
                      onForce: commandable ? (_, __) {} : null,
                      onPush: commandable ? (_, __, ___) {} : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          dark: dark,
        );

    VtugTerminal populated() => VtugTerminal.read(
          struct(coils: 0x5, forceMask: 0x3, forceValue: 0x1),
          kinds: kinds(blanks: {8}, singles: {3}),
          descriptions: const [
            'Gate 1 lift',
            'Gate 1 clamp',
            'Blow-off',
            'Pusher extend',
            'Pusher lift',
            'Reject flap',
            'Lane divert',
          ],
        );

    testWidgets('a named manifold with two valves held', (tester) async {
      await tester.pumpWidget(pane(populated()));
      await expectLater(
        find.byKey(const Key('pane-golden')),
        matchesGoldenFile('goldens/festo/vtug_pane.png'),
      );
    }, skip: !Platform.isMacOS);

    testWidgets('the same pane on a dark station', (tester) async {
      // The dark variant is not decoration. Every low-emphasis edge in this
      // pane — the push buttons' borders, the segmented button's divider —
      // is the kind of detail that vanishes on base03 while the light image
      // stays perfectly readable.
      await tester.pumpWidget(pane(populated(), dark: true));
      await expectLater(
        find.byKey(const Key('pane-golden')),
        matchesGoldenFile('goldens/festo/vtug_pane_dark.png'),
      );
    }, skip: !Platform.isMacOS);

    testWidgets('no command keys — the force section says so', (tester) async {
      await tester.pumpWidget(pane(
        VtugTerminal.read(struct(), kinds: kinds()),
        commandable: false,
      ));
      await expectLater(
        find.byKey(const Key('pane-golden')),
        matchesGoldenFile('goldens/festo/vtug_pane_read_only.png'),
      );
    }, skip: !Platform.isMacOS);
  });

  group('the bus node section', () {
    testWidgets('live and dark', (tester) async {
      await tester.pumpWidget(host(
        SizedBox(
          width: 380,
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CteuPaneSection(link: CteuLink.live),
                Divider(),
                CteuPaneSection(link: CteuLink.dark),
              ],
            ),
          ),
        ),
      ));
      await expectLater(
        find.byType(Column).first,
        matchesGoldenFile('goldens/festo/cteu_section.png'),
      );
    }, skip: !Platform.isMacOS);
  });
}
