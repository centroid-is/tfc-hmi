import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:beamer/beamer.dart';
import 'package:logger/logger.dart';
import 'package:tfc_hmi/widgets/nav_dropdown.dart';
import '../models/menu_item.dart';
import '../route_registry.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:provider/provider.dart';

class BaseScaffold extends StatelessWidget {
  final Widget body;
  final String title;

  const BaseScaffold({super.key, required this.body, required this.title});

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

  @override
  Widget build(BuildContext context) {
    final logger = Logger();

    return Scaffold(
      appBar: AppBar(
        leading: context.canBeamBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.beamBack(),
              )
            : null,
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
                  final dateFormated =
                      '$day-$month-$year $hour:$minute:$second';
                  return Text(dateFormated,
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
