import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:beamer/beamer.dart';
import 'package:logger/logger.dart';
import 'bottom_nav_bar.dart';
import '../app_colors.dart';
import '../route_registry.dart';

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
                icon: const Icon(Icons.arrow_back,
                    color: AppColors.primaryTextColor),
                onPressed: () => context.beamBack(),
              )
            : null,
        title: SvgPicture.asset(
          'assets/centroid.svg',
          // width: 24,
          height: 200,
          package: 'tfc_hmi',
        ),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
