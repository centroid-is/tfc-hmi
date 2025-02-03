import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:beamer/beamer.dart';
import 'package:logger/logger.dart';
import 'package:tfc_hmi/widgets/nav_dropdown.dart';
import '../models/menu_item.dart';
import '../route_registry.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:provider/provider.dart';
import 'dart:async';

// ===================
// Provider Abstraction
// ===================

abstract class GlobalAppBarLeftWidgetProvider with ChangeNotifier {
  /// Build the custom left-side widget.
  Widget buildAppBarLeftWidgets(BuildContext context);
}

// ===================
// BaseScaffold Widget
// ===================

class BaseScaffold extends StatelessWidget {
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
      BuildContext context) {
    try {
      return Provider.of<GlobalAppBarLeftWidgetProvider>(context,
          listen: false);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logger = Logger();
    // Retrieve the provider (if any)
    final globalLeftProvider = _tryGetGlobalAppBarLeftWidgetProvider(context);

    return Scaffold(
      appBar: AppBar(
        // Disable default leading so we can build our own.
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        flexibleSpace: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  // LEFT SIDE: Back arrow (if available) + injected widget.
                  Flexible(
                    flex: 1,
                    fit: FlexFit.loose,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (context.canBeamBack)
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => context.beamBack(),
                          ),
                        // The custom left-side widget.
                        globalLeftProvider?.buildAppBarLeftWidgets(context) ??
                            const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  // CENTER: Centered title widget.
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: StreamBuilder(
                        stream:
                            Stream.periodic(const Duration(milliseconds: 250)),
                        builder: (context, snapshot) {
                          final currentTime = DateTime.now();
                          String twoLetter(int value) =>
                              value < 10 ? '0$value' : '$value';
                          final day = twoLetter(currentTime.day);
                          final month = twoLetter(currentTime.month);
                          final year = currentTime.year;
                          final hour = twoLetter(currentTime.hour);
                          final minute = twoLetter(currentTime.minute);
                          final second = twoLetter(currentTime.second);
                          final dateFormatted =
                              '$day-$month-$year $hour:$minute:$second';
                          return Text(
                            dateFormatted,
                            style: Theme.of(context).textTheme.bodyMedium,
                          );
                        },
                      ),
                    ),
                  ),
                  // RIGHT SIDE: Theme toggle and SVG icon.
                  Flexible(
                    flex: 1,
                    fit: FlexFit.tight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16.0),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SvgPicture.asset(
                                'assets/centroid.svg',
                                height: 50,
                                package: 'tfc_hmi',
                                colorFilter: ColorFilter.mode(
                                  Theme.of(context).colorScheme.onSurface,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.brightness_6),
                          onPressed: () {
                            ThemeNotifier themeNotifier =
                                Provider.of<ThemeNotifier>(context,
                                    listen: false);
                            if (themeNotifier.themeMode == ThemeMode.light) {
                              themeNotifier.setTheme(ThemeMode.dark);
                            } else {
                              themeNotifier.setTheme(ThemeMode.light);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
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
