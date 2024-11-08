import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:beamer/beamer.dart';
import 'package:logger/logger.dart';
import 'bottom_nav_bar.dart';
import '../route_registry.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:provider/provider.dart';

class BaseScaffold extends StatelessWidget {
  final Widget body;
  final String title;

  const BaseScaffold({super.key, required this.body, required this.title});

  @override
  Widget build(BuildContext context) {
    final logger = Logger();
    final beamer = Beamer.of(context);
    int currentIndex = 0;
    if (beamer.currentConfiguration != null) {
      final currentPath = beamer.currentConfiguration?.uri;
      if (currentPath != null) {
        currentIndex = RouteRegistry().menuItems.indexWhere((item) {
          if (item.path == currentPath) {
            return true;
          }
          if (item.path.pathSegments.isEmpty ||
              currentPath.pathSegments.isEmpty) {
            return false;
          }
          return item.path.pathSegments.first == currentPath.pathSegments.first;
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: context.canBeamBack
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => context.beamBack(),
              )
            : null,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.brightness_6),
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
      body: Container(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: body,
      ),
      bottomNavigationBar: BottomNavBar(
          onItemTapped: (item) {
            logger.d('Item tapped: ${item.label}');
          },
          menuItems: RouteRegistry().menuItems,
          currentIndex: currentIndex),
    );
  }
}
