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

/// Abstract provider for app bar left widgets.
/// In your app’s widget tree you can wrap your app (or part of it)
/// with a ChangeNotifierProvider<GlobalAppBarLeftWidgetProvider> to inject
/// your custom left-side app bar widgets.
abstract class GlobalAppBarLeftWidgetProvider with ChangeNotifier {
  /// Called to build the widget(s) that should be shown at the left side
  /// of the top app bar.
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

  final NavigationDestinationLabelBehavior labelBehavior =
      NavigationDestinationLabelBehavior.alwaysShow;

  /// Tries to retrieve the global left-side widget provider.
  /// If not found, returns null.
  GlobalAppBarLeftWidgetProvider? _tryGetGlobalAppBarLeftWidgetProvider(
      BuildContext context) {
    try {
      return Provider.of<GlobalAppBarLeftWidgetProvider>(context,
          listen: false);
    } catch (e) {
      return null;
    }
  }

  /// Builds a leading widget for the AppBar that combines the optional
  /// back arrow (if available) and the injected global left widget.
  Widget? _buildLeading(BuildContext context) {
    final bool canBeamBack = context.canBeamBack;
    final provider = _tryGetGlobalAppBarLeftWidgetProvider(context);
    final Widget injectedWidget =
        provider?.buildAppBarLeftWidgets(context) ?? const SizedBox.shrink();

    // If there is no injected widget and no back arrow, return null.
    if (!canBeamBack &&
        injectedWidget is SizedBox &&
        (injectedWidget as SizedBox).width == 0) {
      return null;
    }

    // If both a back arrow and injected widget are available,
    // combine them in a Row.
    if (canBeamBack) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.beamBack(),
          ),
          injectedWidget,
        ],
      );
    } else {
      // Otherwise, return the injected widget.
      return injectedWidget;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logger = Logger();
    // Determine a suitable leadingWidth if multiple widgets are present.
    final bool hasExtraLeftWidgets =
        _tryGetGlobalAppBarLeftWidgetProvider(context) != null;
    final double leadingWidth =
        context.canBeamBack || hasExtraLeftWidgets ? 120.0 : kToolbarHeight;

    return Scaffold(
      appBar: AppBar(
        // Use the custom built leading widget.
        leading: _buildLeading(context),
        leadingWidth: leadingWidth,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              ThemeNotifier themeNotifier =
                  Provider.of<ThemeNotifier>(context, listen: false);
              if (themeNotifier.themeMode == ThemeMode.light) {
                themeNotifier.setTheme(ThemeMode.dark);
              } else {
                themeNotifier.setTheme(ThemeMode.light);
              }
            },
          ),
        ],
        title: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: StreamBuilder(
                stream: Stream.periodic(const Duration(milliseconds: 250)),
                builder: (context, snapshot) {
                  final currentTime = DateTime.now();
                  twoLetterMin(value) {
                    if (value < 10) {
                      return '0$value';
                    }
                    return value;
                  }

                  final day = twoLetterMin(currentTime.day);
                  final month = twoLetterMin(currentTime.month);
                  final year = currentTime.year;
                  final hour = twoLetterMin(currentTime.hour);
                  final minute = twoLetterMin(currentTime.minute);
                  final second = twoLetterMin(currentTime.second);
                  final dateFormatted =
                      '$day-$month-$year $hour:$minute:$second';
                  return Text(dateFormatted,
                      style: Theme.of(context).textTheme.bodyMedium);
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                child: SvgPicture.asset(
                  'assets/centroid.svg',
                  height: 50,
                  package: 'tfc_hmi',
                  colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.onSurface, BlendMode.srcIn),
                ),
              ),
            ),
          ],
        ),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
        labelBehavior: labelBehavior,
        selectedIndex: findTopLevelIndexForBeamer(RouteRegistry().root, null,
            (context.currentBeamLocation.state as BeamState).uri.path),
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
