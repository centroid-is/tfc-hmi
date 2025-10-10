import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:beamer/beamer.dart';
import 'package:logger/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'nav_dropdown.dart';
import '../models/menu_item.dart';
import '../route_registry.dart';
import '../providers/theme.dart';
import '../providers/alarm.dart';
import '../core/alarm.dart';
// ===================
// Provider Abstraction
// ===================

abstract class GlobalAppBarLeftWidgetProvider with ChangeNotifier {
  /// Build the custom left-side widget.
  Widget buildAppBarLeftWidgets(BuildContext context);
}

final globalAppBarLeftWidgetProvider =
    Provider<GlobalAppBarLeftWidgetProvider?>((ref) => null);

// ===================
// BaseScaffold Widget
// ===================

String formatTimestamp(DateTime timestamp) {
  String twoLetter(int value) => value < 10 ? '0$value' : '$value';
  final day = twoLetter(timestamp.day);
  final month = twoLetter(timestamp.month);
  final year = timestamp.year;
  final hour = twoLetter(timestamp.hour);
  final minute = twoLetter(timestamp.minute);
  final second = twoLetter(timestamp.second);
  return '$day-$month-$year $hour:$minute:$second';
}

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

class _BaseScaffoldState extends ConsumerState<BaseScaffold> {
  bool _isFullscreen = false;

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  findTopLevelIndexForBeamer(MenuItem node, int? base, String path) {
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

  Widget _buildClockOrAlarm(BuildContext context, WidgetRef ref) {
    return StreamBuilder<(AlarmMan, List<AlarmActive>)>(
        stream: Stream.fromFuture(ref.watch(alarmManProvider.future))
            .asyncExpand((alarmMan) => alarmMan
                .activeAlarms()
                .map((activeAlarms) => (alarmMan, activeAlarms.toList()))),
        builder: (context, snapshot) {
          if (!snapshot.hasError &&
              snapshot.hasData &&
              snapshot.data!.$2.isNotEmpty) {
            final (alarmMan, activeAlarms) = snapshot.data!;
            final filteredAlarms = alarmMan.filterAlarms(activeAlarms, '');
            final highestPriorAlarms =
                filteredAlarms.sublist(0, math.min(2, filteredAlarms.length));

            return Column(
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
                    text: TextSpan(
                      style: TextStyle(
                        color: textColor,
                        fontSize:
                            Theme.of(context).textTheme.bodySmall!.fontSize,
                      ),
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
            );
          }
          return StreamBuilder(
            stream: Stream.periodic(const Duration(milliseconds: 250)),
            builder: (context, snapshot) {
              final currentTime = DateTime.now();
              return Text(
                formatTimestamp(currentTime),
                style: Theme.of(context).textTheme.bodyMedium,
              );
            },
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final logger = Logger();
    // Retrieve the provider (if any)
    final globalLeftProvider = _tryGetGlobalAppBarLeftWidgetProvider(context);

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
                    // CENTER: Always centered title widget.
                    Align(
                      alignment: Alignment.center,
                      child: _buildClockOrAlarm(context, ref),
                    ),
                    // LEFT SIDE: Back arrow (if available) + injected custom widget + fullscreen button.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (context.canBeamBack)
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => context.beamBack(),
                            ),
                          globalLeftProvider?.buildAppBarLeftWidgets(context) ??
                              const SizedBox.shrink(),
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
              selectedIndex: findTopLevelIndexForBeamer(
                RouteRegistry().root,
                null,
                (context.currentBeamLocation.state as BeamState).uri.path,
              ),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                ...RouteRegistry().menuItems.map<Widget>((item) {
                  if (item.children.isEmpty) {
                    return NavigationDestination(
                        icon: Icon(item.icon), label: item.label);
                  }
                  return NavDropdown(
                    menuItem: item,
                  );
                }),
              ],
              onDestinationSelected: (int index) {
                logger.d('Item tapped: $index');
                final item = RouteRegistry().menuItems[index];
                beamSafelyKids(context, item);
              },
            ),
    );
  }
}
