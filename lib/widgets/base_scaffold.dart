import 'dart:io';
import 'dart:async';

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

class BaseScaffold extends ConsumerWidget {
  final Widget body;
  final String title;
  final Widget? floatingActionButton;

  const BaseScaffold({
    super.key,
    required this.body,
    required this.title,
    this.floatingActionButton,
  });

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

    return StreamBuilder(
        stream: Stream.fromFuture(ref.watch(alarmManProvider.future))
            .asyncExpand((alarmMan) => alarmMan.activeAlarms()),
        builder: (context, snapshot) {
          if (!snapshot.hasError &&
              snapshot.hasData &&
              snapshot.data!.isNotEmpty) {
            // Get 3 highest priority alarms
            final highestPriorAlarms = <AlarmActive>[];
            for (final alarm in snapshot.data!) {
              if (highestPriorAlarms.length < 3) {
                highestPriorAlarms.add(alarm);
              } else {
                if (alarm.notification.rule.level.index >
                    highestPriorAlarms.last.notification.rule.level.index) {
                  highestPriorAlarms.removeLast();
                  highestPriorAlarms.add(alarm);
                }
              }
              highestPriorAlarms.sort((a, b) => b.notification.rule.level.index
                  .compareTo(a.notification.rule.level.index));
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: highestPriorAlarms.map((e) {
                Color backgroundColor;
                Color textColor;
                switch (e.notification.rule.level) {
                  case AlarmLevel.info:
                    backgroundColor =
                        Theme.of(context).colorScheme.primaryContainer;
                    textColor =
                        Theme.of(context).colorScheme.onPrimaryContainer;
                    break;
                  case AlarmLevel.warning:
                    backgroundColor =
                        Theme.of(context).colorScheme.tertiaryContainer;
                    textColor =
                        Theme.of(context).colorScheme.onTertiaryContainer;
                    break;
                  case AlarmLevel.error:
                    backgroundColor =
                        Theme.of(context).colorScheme.errorContainer;
                    textColor = Theme.of(context).colorScheme.onErrorContainer;
                    break;
                }
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
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = Logger();
    // Retrieve the provider (if any)
    final globalLeftProvider = _tryGetGlobalAppBarLeftWidgetProvider(context);

    return Scaffold(
      appBar: AppBar(
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
              // LEFT SIDE: Back arrow (if available) + injected custom widget.
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
                  ],
                ),
              ),
              // RIGHT SIDE: Theme toggle and SVG icon.
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
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
