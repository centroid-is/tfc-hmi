/// Golden images of the standard popup surfaces, for design review.
///
/// Each golden renders a full 1920×1080 "HMI screen" — an app bar, a mock
/// plant view and a bottom navigation bar — with the pane or dialog on top,
/// so what is under review is how the popup sits in the app, not just the
/// widget in isolation. That is the point of the non-modal design: the plant
/// view stays visible and live beside it.
///
/// The three device shapes are the ones the standard has to cover:
///   * conveyor        — commands (jog), live numbers, setpoints, a trend
///   * elevator / lift — read-only position and configuration
///   * 3rd party I/O   — a channel overview whose bulk detail lives in a
///                       floating dialog
///
/// To update: flutter test test/widgets/panes_golden_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/theme.dart';
import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc/widgets/panes/standard_dialog.dart';

// ---------------------------------------------------------------------------
// Screen scaffolding — a stand-in for a real HMI page
// ---------------------------------------------------------------------------

/// A 1080p operator panel — the size the plant actually runs.
const Size _screen = Size(1920, 1080);

/// A mock plant view: a belt line with a lift, drawn flat so the goldens stay
/// stable. It exists to show what the pane covers and what it leaves visible.
class _MockPlantView extends StatelessWidget {
  const _MockPlantView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget belt(double width, {bool running = true}) => Container(
          width: width,
          height: 26,
          decoration: BoxDecoration(
            color: running ? Colors.green.shade700 : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black54),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 60, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INFEED — LINE 1', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 24),
          Row(children: [
            belt(220),
            const SizedBox(width: 12),
            belt(160),
            const SizedBox(width: 12),
            belt(120, running: false),
          ]),
          const SizedBox(height: 40),
          Row(children: [
            belt(140),
            const SizedBox(width: 12),
            Container(
              width: 60,
              height: 90,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.onSurface, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.bottomCenter,
              child: Container(height: 14, color: Colors.green.shade700),
            ),
            const SizedBox(width: 12),
            belt(180),
          ]),
        ],
      ),
    );
  }
}

/// The app chrome the panes are designed to sit inside: `BaseScaffold`'s
/// AppBar on top and NavigationBar at the bottom — the pane insets exist so
/// an operator can still read alarms and navigate with a pane open.
Widget _screenApp({required ThemeData theme, required Widget body}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(
      appBar: AppBar(
        title: const Text('SVN — Infeed'),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: Text('11-08-2026 09:14:22')),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.factory), label: 'Line'),
          NavigationDestination(icon: Icon(Icons.warning), label: 'Alarms'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Setup'),
        ],
        onDestinationSelected: (_) {},
      ),
      body: body,
    ),
  );
}

/// Pumps the screen, opens [pane] docked, and settles.
Future<void> _pumpWithPane(
  WidgetTester tester, {
  required ThemeData theme,
  required Widget Function(BuildContext context) pane,
  void Function(BuildContext context)? afterOpen,
}) async {
  await tester.binding.setSurfaceSize(_screen);
  // 1:1 pixels: the goldens are for reading, and a 3× capture would put
  // multi-megabyte PNGs in the repo for every review round.
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(closeSidePane);

  late BuildContext pageContext;
  await tester.pumpWidget(_screenApp(
    theme: theme,
    body: Builder(builder: (context) {
      pageContext = context;
      return const _MockPlantView();
    }),
  ));
  showSidePane(context: pageContext, id: 'golden', builder: pane);
  await tester.pumpAndSettle();
  if (afterOpen != null) {
    afterOpen(pageContext);
    await tester.pumpAndSettle();
  }
}

// ---------------------------------------------------------------------------
// Pane bodies — one per device shape
// ---------------------------------------------------------------------------

/// A stand-in sparkline, drawn from fixed points so goldens stay stable.
class _Sparkline extends StatelessWidget {
  const _Sparkline();

  @override
  Widget build(BuildContext context) {
    const samples = [
      0.35, 0.42, 0.38, 0.55, 0.61, 0.58, 0.72, 0.68,
      0.75, 0.71, 0.80, 0.77, 0.83, 0.79, 0.86, 0.84,
    ];
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final s in samples)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: FractionallySizedBox(
                heightFactor: s,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.75),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _jogButton(BuildContext context, IconData icon, String label,
    {bool active = false}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      RawMaterialButton(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        onPressed: () {},
        child: Icon(
          icon,
          size: 36,
          color: active ? Colors.green : Theme.of(context).disabledColor,
        ),
      ),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// Conveyor: the busiest shape — commands, live numbers, a trend and
/// setpoints, all still inside one screen of pane.
SidePane _conveyorPane(BuildContext context) {
  return SidePane(
    title: 'CN-04',
    subtitle: 'Infeed conveyor',
    icon: Icons.conveyor_belt,
    status: const PaneStatus.running(),
    actions: [
      PaneAction.destructive(
        label: 'Fault reset',
        icon: Icons.restart_alt,
        onPressed: () {},
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneSection(
          title: 'Jog',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _jogButton(context, Icons.arrow_back, 'Reverse'),
                  _jogButton(context, Icons.arrow_forward, 'Forward',
                      active: true),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Runs only while held',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Switch(value: true, onChanged: (_) {}),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        PaneSection(
          title: 'Status',
          trailing: TextButton(onPressed: () {}, child: const Text('Reset hours')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: const [
              PaneTileRow(children: [
                PaneMetricTile(
                    label: 'Frequency',
                    value: '48.20',
                    unit: 'Hz',
                    icon: Icons.speed),
                PaneMetricTile(
                    label: 'Current',
                    value: '3.14',
                    unit: 'A',
                    icon: Icons.bolt),
                PaneMetricTile(
                    label: 'Run hours',
                    value: '412:35',
                    unit: 'h:m',
                    icon: Icons.schedule),
              ]),
              SizedBox(height: 8),
              PaneDetailRow(label: 'HMIS', value: 'Running'),
              PaneDetailRow(label: 'Last fault', value: 'None'),
            ],
          ),
        ),
        const Divider(height: 1),
        PaneSection(
          title: 'Trend',
          child: PaneGraphTile(
            label: 'CN-04 statistics',
            preview: const _Sparkline(),
            expandedBuilder: (_) => const _Sparkline(),
          ),
        ),
        const Divider(height: 1),
        PaneSection(
          title: 'Setpoints',
          child: PaneExpandTile(
            label: 'Frequencies',
            summary: 'Auto 50.00 Hz · Cleaning 25.00 Hz · Manual 30.00 Hz',
            icon: Icons.tune,
            expandedBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );
}

/// Elevator / lift: read-only, dominated by one number.
SidePane _elevatorPane(BuildContext context) {
  return const SidePane(
    title: 'Elevator',
    subtitle: 'ST201.EL01.POS',
    icon: Icons.elevator,
    status: PaneStatus.running('Live'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneSection(
          title: 'Position',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PaneTileRow(children: [
                PaneMetricTile(
                    label: 'Travel',
                    value: '64',
                    unit: '%',
                    icon: Icons.height),
                PaneMetricTile(
                    label: 'Tween',
                    value: '250',
                    unit: 'ms',
                    icon: Icons.timer_outlined),
              ]),
              SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(value: 0.64, minHeight: 8),
              ),
            ],
          ),
        ),
        Divider(height: 1),
        PaneSection(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PaneDetailRow(label: 'Position key', value: 'ST201.EL01.POS'),
              PaneDetailRow(label: 'Current position', value: '64%'),
              PaneDetailRow(label: 'Tween duration', value: '250 ms'),
              PaneDetailRow(label: 'Out-of-range', value: 'no'),
              PaneDetailRow(label: 'Stale', value: 'no'),
              PaneDetailRow(label: 'Simulate motion', value: 'off'),
              PaneDetailRow(label: 'Children', value: '2 attached'),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A 16-square channel read-out, the same shape the Advantys pane renders.
class _ChannelStripDemo extends StatelessWidget {
  const _ChannelStripDemo();

  @override
  Widget build(BuildContext context) {
    const high = [
      true, false, true, true, false, false, true, false,
      true, true, false, true, false, true, false, false,
    ];
    const forced = {2, 11};
    final theme = Theme.of(context);

    Widget cell(int i) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: (high[i] ? Colors.green : theme.disabledColor)
                        .withValues(alpha: high[i] ? 0.85 : 0.25),
                    borderRadius: BorderRadius.circular(4),
                    border: forced.contains(i)
                        ? Border.all(color: Colors.orange, width: 2)
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text('${i + 1}', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        );

    return Column(
      children: [
        Row(children: [for (int i = 0; i < 8; i++) cell(i)]),
        const SizedBox(height: 6),
        Row(children: [for (int i = 8; i < 16; i++) cell(i)]),
      ],
    );
  }
}

/// A stand-in for the wide per-channel grid that opens in a floating dialog.
class _ChannelGridDemo extends StatelessWidget {
  const _ChannelGridDemo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget channel(int i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 44, child: Text('Ch${i + 1}')),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i.isEven ? Colors.green : theme.disabledColor,
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Auto')),
                  ButtonSegment(value: 1, label: Text('Low')),
                  ButtonSegment(value: 2, label: Text('High')),
                ],
                selected: {i == 2 ? 1 : 0},
                showSelectedIcon: false,
                onSelectionChanged: (_) {},
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: TextField(
                  decoration: InputDecoration(
                      labelText: 'Description', isDense: true),
                ),
              ),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (int i = 0; i < 6; i++) channel(i)],
    );
  }
}

/// 3rd party equipment: a whole-module glance, detail behind a tile.
SidePane _thirdPartyPane(BuildContext context) {
  return const SidePane(
    title: 'DI-3725-A',
    subtitle: 'Advantys STB · 16 DI',
    icon: Icons.developer_board,
    status: PaneStatus.warning('2 forced'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneSection(
          title: 'Channels',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChannelStripDemo(),
              SizedBox(height: 10),
              PaneTileRow(children: [
                PaneMetricTile(
                    label: 'High',
                    value: '8',
                    unit: '/ 16',
                    icon: Icons.input),
                PaneMetricTile(
                    label: 'Forced',
                    value: '2',
                    unit: '/ 16',
                    icon: Icons.pan_tool),
              ]),
            ],
          ),
        ),
        Divider(height: 1),
        PaneSection(
          title: 'Detail',
          child: PaneExpandTile(
            label: 'Channel detail',
            summary: 'Force, filters and descriptions for all 16',
            icon: Icons.grid_on,
            expandedBuilder: _channelGridBuilder,
          ),
        ),
      ],
    ),
  );
}

Widget _channelGridBuilder(BuildContext context) => const _ChannelGridDemo();

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  final (light, dark) = solarized();

  // `flutter_test_config.dart` registers the font as 'Roboto' (Material's
  // default). The app themes ask for 'roboto-mono' by name, so register it
  // under that family too — otherwise these goldens render as Ahem blocks.
  setUpAll(() async {
    Future<void> loadFont(String family, String path) async {
      final bytes = File(path).readAsBytesSync();
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }

    await loadFont('roboto-mono', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

    // Icons are load-bearing in these goldens (every header and tile carries
    // one), and the test environment does not register MaterialIcons. Pull it
    // out of the Flutter SDK cache; if the layout of the SDK ever changes,
    // fall back to boxes rather than failing the suite.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        (Platform.resolvedExecutable.contains('flutter')
            ? null
            : File(Platform.resolvedExecutable).parent.path);
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
  });

  group('SidePane goldens', () {
    testWidgets('conveyor — light', (tester) async {
      await _pumpWithPane(tester, theme: light, pane: _conveyorPane);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/side_pane_conveyor_light.png'),
      );
    });

    testWidgets('conveyor — dark', (tester) async {
      await _pumpWithPane(tester, theme: dark, pane: _conveyorPane);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/side_pane_conveyor_dark.png'),
      );
    });

    testWidgets('elevator — dark', (tester) async {
      await _pumpWithPane(tester, theme: dark, pane: _elevatorPane);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/side_pane_elevator_dark.png'),
      );
    });

    testWidgets('third party I/O — dark', (tester) async {
      await _pumpWithPane(tester, theme: dark, pane: _thirdPartyPane);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/side_pane_third_party_dark.png'),
      );
    });
  });

  group('StandardDialog goldens', () {
    testWidgets('floating dialog opened from a pane tile — dark',
        (tester) async {
      // The pairing the standard is built around: pane on the right, the
      // detail it could not hold floating over the plant view, nothing
      // blocked or dimmed.
      await _pumpWithPane(
        tester,
        theme: dark,
        pane: _thirdPartyPane,
        afterOpen: (context) => showFloatingDialog(
          context: context,
          id: 'golden-dialog',
          title: 'DI-3725-A — channels',
          subtitle: 'Force, filters and descriptions',
          icon: Icons.grid_on,
          status: const PaneStatus.warning('2 forced'),
          size: const Size(720, 420),
          position: const Offset(60, 140),
          builder: _channelGridBuilder,
        ),
      );
      addTearDown(() => closeFloatingDialog('golden-dialog'));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/floating_dialog_dark.png'),
      );
    });

    testWidgets('modal dialog — dark', (tester) async {
      await tester.binding.setSurfaceSize(_screen);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late BuildContext pageContext;
      await tester.pumpWidget(_screenApp(
        theme: dark,
        body: Builder(builder: (context) {
          pageContext = context;
          return const _MockPlantView();
        }),
      ));
      showStandardDialog<bool>(
        context: pageContext,
        title: 'Reset run hours',
        subtitle: 'CN-04 · Infeed conveyor',
        icon: Icons.timer_off_outlined,
        builder: (_) => const Text(
          'Run hours for this drive will be set to zero. '
          'The counter cannot be restored afterwards.',
        ),
        actionsBuilder: (ctx) => [
          PaneAction.destructive(
            label: 'Reset',
            icon: Icons.restart_alt,
            onPressed: () {},
          ),
        ],
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/standard_dialog_modal_dark.png'),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
    });
  });
}
