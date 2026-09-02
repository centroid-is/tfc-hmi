import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'panes/side_pane.dart';
import 'panes/standard_dialog.dart';
import 'leave_guard.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:beamer/beamer.dart';
import 'package:logger/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'nav_dropdown.dart';
import '../models/menu_item.dart';
import '../route_registry.dart';
import '../providers/theme.dart';
import '../providers/alarm.dart';
import '../providers/nav_alarm.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'alarm.dart';
import 'nav_alarm_badge.dart';
import '../routes.dart';
// ===================
// Provider Abstraction
// ===================

abstract class GlobalAppBarLeftWidgetProvider with ChangeNotifier {
  /// Build the custom left-side widget.
  Widget buildAppBarLeftWidgets(BuildContext context);
}

final globalAppBarLeftWidgetProvider =
    Provider<GlobalAppBarLeftWidgetProvider?>((ref) => null);

/// The path Beamer is currently showing, or null when the location state isn't
/// a [BeamState] (e.g. before the first route resolves). This is the same
/// current-path source the bottom-nav selected-index logic reads, so the two
/// stay consistent.
String? currentBeamPath(BuildContext context) {
  final state = context.currentBeamLocation.state;
  if (state is! BeamState) return null;
  return state.uri.path;
}

/// Whether [path] is one of the registered top-level destinations.
///
/// Top-level menu items live directly in [RouteRegistry.menuItems]; Advanced
/// sub-pages (`/advanced/...`) are nested children and are therefore NOT
/// top-level. `/` is always treated as top-level so a deleted Home (a
/// RouteRedirect with no menu item) still suppresses the back-arrow instead of
/// throwing. A null path (no [BeamState] yet) counts as top-level so we default
/// to no arrow.
bool isTopLevelDestinationPath(String? path) {
  if (path == null) return true;
  if (path == '/') return true;
  for (final item in RouteRegistry().menuItems) {
    if (item.path == path) return true;
  }
  return false;
}

// ===================
// BaseScaffold Widget
// ===================

String _twoLetter(int value) => value < 10 ? '0$value' : '$value';

/// `dd.MM.yy` -- the local written convention, and two digits of year keep
/// the top-bar clock narrow beside the alarm banner.
String formatDate(DateTime timestamp) =>
    '${_twoLetter(timestamp.day)}.${_twoLetter(timestamp.month)}.${_twoLetter(timestamp.year % 100)}';

/// `HH:mm:ss`.
String formatTimeOfDay(DateTime timestamp) =>
    '${_twoLetter(timestamp.hour)}:${_twoLetter(timestamp.minute)}:${_twoLetter(timestamp.second)}';

String formatTimestamp(DateTime timestamp) =>
    '${formatDate(timestamp)} ${formatTimeOfDay(timestamp)}';

class BaseScaffold extends ConsumerStatefulWidget {
  final Widget body;
  final String title;
  final Widget? floatingActionButton;

  const BaseScaffold({
    super.key,
    required this.body,
    required this.title,
    this.floatingActionButton,
  });

  @override
  ConsumerState<BaseScaffold> createState() => _BaseScaffoldState();
}

/// Width reserved for the app-bar clock.
///
/// roboto-mono advances 0.6em, so the widest line -- the 14pt `dd-MM-yyyy`, 10
/// chars at 8.4px -- is 84px, and the 20pt time is 8 * 12 = 96px. 100 of text
/// plus an 8px gutter on each side makes 116, which is also the centred alarm
/// banner's left inset: one fixed number rather than two that can drift apart.
/// The gutter matters on a top-level page, where there is no back arrow and the
/// time would otherwise sit flush against the window edge.
const double _clockWidth = 116;

class _BaseScaffoldState extends ConsumerState<BaseScaffold> {
  // Static, not per-build: `Logger()` constructs a filter, a printer and an
  // output every time (~4.3us), and this rebuilds on every navigation-alarm
  // tick. The scaffold logs one line, from a tap handler.
  static final Logger _logger = Logger();

  bool _isFullscreen = false;

  /// The top bar's alarm stream, subscribed once. Built inline it was a new
  /// stream on every scaffold rebuild -- every navigation, every pane inset
  /// change -- and the banner blinked back to the clock for a frame each
  /// time while the new StreamBuilder waited for its first value.
  late final Stream<(AlarmMan, List<AlarmActive>)> _alarmStream =
      Stream.fromFuture(ref.read(alarmManProvider.future)).asyncExpand(
          (alarmMan) => alarmMan
              .activeAlarms()
              .map((activeAlarms) => (alarmMan, activeAlarms.toList())));

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  int? findTopLevelIndexForBeamer(MenuItem node, int? base, String path) {
    if (node.path != null) {
      if (node.path! == path) {
        return base ?? RouteRegistry().getNodeIndex(node);
      }
    }
    final int? myBase = base ?? RouteRegistry().getNodeIndex(node);
    for (final child in node.children) {
      final int? index = findTopLevelIndexForBeamer(child, myBase, path);
      if (index != null) return index;
    }
    return null;
  }

  /// Attempt to get a global left widget provider.
  GlobalAppBarLeftWidgetProvider? _tryGetGlobalAppBarLeftWidgetProvider(
    BuildContext context,
  ) {
    try {
      final container = ProviderScope.containerOf(context);
      return container.read(globalAppBarLeftWidgetProvider);
    } catch (e) {
      return null;
    }
  }

  /// The date over the time, on the left of the bar.
  ///
  /// Two lines rather than one: a 14pt date over a 20pt time. The time is what
  /// an operator reads from across the packing hall, so it is the half that
  /// grows over the 14pt single line this replaces; the date stays where it was
  /// rather than the pair dominating the 56px toolbar. Explicit sizes rather
  /// than text-theme ones for that reason: the clock is sized against the bar,
  /// not against body copy.
  ///
  /// It also no longer shares a slot with the alarm banner. The clock used to
  /// be the banner's `else` branch, so an active alarm took the time away.
  Widget _buildClock(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        // clock.now(), not DateTime.now(): a golden that renders the
        // scaffold otherwise churns every run on the ticking header
        // clock. Tests pin it with withClock(); in the app this is
        // DateTime.now().
        final currentTime = clock.now();
        // scaleDown, and both lines unwrappable: the sizes below are picked
        // for roboto-mono in a 56px toolbar, but a wider fallback font or an
        // operator's text scaling would otherwise wrap `dd.MM.yy` onto two
        // lines and overflow the bar. Shrinking to fit is the graceful
        // failure; a yellow-and-black overflow stripe is not.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formatDate(currentTime),
                maxLines: 1,
                softWrap: false,
                style:
                    textTheme.titleMedium?.copyWith(fontSize: 14, height: 1.1),
              ),
              Text(
                formatTimeOfDay(currentTime),
                maxLines: 1,
                softWrap: false,
                style: textTheme.titleLarge?.copyWith(
                    fontSize: 20, height: 1.1, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlarmBanner(BuildContext context, WidgetRef ref) {
    return StreamBuilder<(AlarmMan, List<AlarmActive>)>(
        stream: _alarmStream,
        builder: (context, snapshot) {
          if (!snapshot.hasError &&
              snapshot.hasData &&
              snapshot.data!.$2.isNotEmpty) {
            final (alarmMan, activeAlarms) = snapshot.data!;
            final filteredAlarms = alarmMan.filterAlarms(activeAlarms, '');
            final highestPriorAlarms =
                filteredAlarms.sublist(0, math.min(2, filteredAlarms.length));

            return GestureDetector(
              onTap: () => context.beamToNamed(AppRoutes.alarmView),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: highestPriorAlarms.map((e) {
                  final (backgroundColor, textColor) =
                      e.notification.getColors(context);
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      text: TextSpan(
                        // bodyLarge, not a bare TextStyle: RichText does not
                        // read the ambient DefaultTextStyle, so a hand-rolled
                        // style left the banner in the Material default font
                        // while the rest of the HMI is roboto-mono. Taking the
                        // theme style also takes its 16pt -- the old 12pt
                        // bodySmall was too small to read at a glance.
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge!
                            .copyWith(color: textColor),
                        children: [
                          TextSpan(
                            text:
                                '${formatTimestamp(e.notification.timestamp)}: ',
                          ),
                          TextSpan(
                            text: '${e.alarm.config.title}: ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: (() {
                              final description = e.alarm.config.description
                                  .replaceAll('\n', ' ')
                                  .trim();
                              return description.length > 100
                                  ? description.substring(0, 97) + '...'
                                  : description;
                            })(),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          }
          return const SizedBox.shrink();
        });
  }

  @override
  Widget build(BuildContext context) {
    // Retrieve the provider (if any)
    final globalLeftProvider = _tryGetGlobalAppBarLeftWidgetProvider(context);

    // Which navigation entries are pulsing. Watched once here and handed down,
    // so the bar holds one alarm subscription rather than one per destination.
    //
    // No alarm service — the page-editor harness, tests, a dropped connection —
    // reads as quiet, the same way the beacon asset treats a stream error as
    // idle. A broken alarm connection must not light up the navigation bar.
    final navAlarmLevels =
        ref.watch(navigationAlarmsProvider).valueOrNull ?? const {};
    final navCurrentPath = currentBeamPath(context);

    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              // Disable default leading so we can build our own.
              automaticallyImplyLeading: false,
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              flexibleSpace: SafeArea(
                child: Stack(
                  children: [
                    // CENTER: Constrained so alarm text cannot overlap the
                    // right-aligned logo or left-side controls.
                    // Right margin calculation: SVG logo rendered at height:50
                    // with aspect ratio ~4.2 => ~210px wide, plus 16px right
                    // padding, plus ~48px theme toggle IconButton = ~274px.
                    // Use 280 for a small safety buffer.
                    // Left margin: ~48px back-arrow IconButton plus the clock,
                    // which is [_clockWidth] wide.
                    Positioned.fill(
                      left: 48 + _clockWidth,
                      right: 280,
                      child: Align(
                        alignment: Alignment.center,
                        child: _buildAlarmBanner(context, ref),
                      ),
                    ),
                    // LEFT SIDE: Back arrow (if available) + injected custom widget + fullscreen button.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The back-arrow is gated on route depth, not on
                          // beaming history: history accumulates and stays
                          // non-empty after landing back on a top-level page,
                          // which used to leave a stale arrow on Home. On a
                          // top-level destination there is nothing to go back
                          // to, so hide it there and only show it deeper in.
                          if (!isTopLevelDestinationPath(
                                  currentBeamPath(context)) &&
                              context.canBeamBack)
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              // The page may object (the editor with
                              // unsaved edits); ask before anything moves.
                              // LeaveGuard.then runs the body synchronously
                              // when no guard is set -- see its comment.
                              onPressed: () => LeaveGuard.then(() {
                                if (!context.mounted) return;
                                // Same reason as the navigation bar below:
                                // take the pane away the moment the operator
                                // asks to leave, rather than a few frames
                                // later when the router listener notices.
                                closeSidePane(immediate: true);
                                closeAllFloatingDialogs();
                                context.beamBack();
                              }),
                            ),
                          SizedBox(
                            width: _clockWidth,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: _buildClock(context),
                            ),
                          ),
                          globalLeftProvider?.buildAppBarLeftWidgets(context) ??
                              const SizedBox.shrink(),
                          if (Platform.isAndroid || Platform.isIOS)
                            IconButton(
                              icon: const Icon(Icons.fullscreen),
                              onPressed: _toggleFullscreen,
                              tooltip: 'Toggle Fullscreen',
                            ),
                        ],
                      ),
                    ),
                    // RIGHT SIDE: Theme toggle and SVG icon.
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Only show SVG if not in mobile portrait mode
                          if (!(MediaQuery.of(context).orientation ==
                                  Orientation.portrait &&
                              MediaQuery.of(context).size.width < 600))
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: GestureDetector(
                                onDoubleTap: () {
                                  exit(0);
                                },
                                child: SvgPicture.asset(
                                  'assets/centroid.svg',
                                  height: 50,
                                  package: 'tfc',
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(context).colorScheme.onSurface,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          Consumer(
                            builder: (context, ref, child) {
                              final notifier =
                                  ref.read(themeNotifierProvider.notifier);
                              return FutureBuilder(
                                future: ref.watch(themeNotifierProvider.future),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    final currentTheme = snapshot.data!;
                                    return IconButton(
                                      icon: const Icon(Icons.brightness_6),
                                      onPressed: () {
                                        if (currentTheme == ThemeMode.light) {
                                          notifier.setTheme(ThemeMode.dark);
                                        } else {
                                          notifier.setTheme(ThemeMode.light);
                                        }
                                      },
                                    );
                                  }
                                  return const SizedBox();
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: widget.body,
      floatingActionButton: _isFullscreen
          ? FloatingActionButton(
              mini: true,
              onPressed: _toggleFullscreen,
              child: const Icon(Icons.fullscreen_exit),
            )
          : widget.floatingActionButton,
      floatingActionButtonLocation:
          _isFullscreen ? FloatingActionButtonLocation.startFloat : null,
      bottomNavigationBar: _isFullscreen
          ? null
          : NavigationBar(
              // Same null-safe path source as the back-arrow gate: an
              // unguarded `as BeamState` here would defeat currentBeamPath's
              // guard — both run in the same build pass, so the scaffold
              // would fail to build anyway if this threw.
              selectedIndex: findTopLevelIndexForBeamer(
                    RouteRegistry().root,
                    null,
                    currentBeamPath(context) ?? '/',
                  ) ??
                  0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                ...RouteRegistry().menuItems.map<Widget>((item) {
                  if (item.children.isEmpty) {
                    return NavigationDestination(
                        icon: NavAlarmBadge(
                          level: navigationAlarmLevelFor(item, navAlarmLevels,
                              currentPath: navCurrentPath),
                          child: Icon(item.icon),
                        ),
                        label: item.label);
                  }
                  return NavDropdown(
                    menuItem: item,
                    alarmLevels: navAlarmLevels,
                    currentPath: navCurrentPath,
                  );
                }),
              ],
              onDestinationSelected: (int index) => LeaveGuard.then(() {
                _logger.d('Item tapped: $index');
                // The page may object (the editor with unsaved edits); the
                // guard is asked once, here, synchronously when none is set.
                // beamSafelyKids is told not to ask again.
                if (!context.mounted) return;
                // Closed on the tap, not left to the router listener in
                // MyApp. That listener is the guarantee -- it catches the back
                // button, beamBack, deep links and the route guards -- but it
                // fires once the new location has been resolved, so the pane
                // lingers for those frames. Closing here as well takes it away
                // the moment the operator asks to leave. close() is a no-op
                // when nothing is open, so the two never fight.
                closeSidePane(immediate: true);
                closeAllFloatingDialogs();
                final item = RouteRegistry().menuItems[index];
                beamSafelyKids(context, item, askGuard: false);
              }),
            ),
    );
  }
}
