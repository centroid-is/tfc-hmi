// lib/widgets/custom_bottom_nav_bar.dart
import 'package:flutter/material.dart';
import 'nav_dropdown.dart';
import '../models/menu_item.dart';
import '../app_colors.dart';
import 'package:beamer/beamer.dart';

class CustomBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onItemTapped;
  final List<MenuItem> dropdownMenuItems;
  final List<MenuItem> standardMenuItems;

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onItemTapped,
    required this.dropdownMenuItems,
    required this.standardMenuItems,
  }) : super(key: key);

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar> {
  @override
  Widget build(BuildContext context) {
    List<Widget> navItems = [];

    // Add NavDropdown items
    for (int i = 0; i < widget.dropdownMenuItems.length; i++) {
      navItems.add(
        NavDropdown(
          menuItem: widget.dropdownMenuItems[i],
          isSelected: widget.currentIndex == i,
          onMenuItemSelected: () {
            widget.onItemTapped(i);
          },
        ),
      );
    }

    // Add standard IconButton items
    for (int i = 0; i < widget.standardMenuItems.length; i++) {
      int index = widget.dropdownMenuItems.length + i;
      MenuItem menuItem = widget.standardMenuItems[i];
      navItems.add(
        IconButton(
          icon: Icon(
            menuItem.icon,
            color: widget.currentIndex == index
                ? AppColors.selectedItemColor
                : AppColors.unselectedItemColor,
          ),
          tooltip: menuItem.hoverText,
          onPressed: () {
            Beamer.of(context).beamToNamed(menuItem.path);
            widget.onItemTapped(index);
          },
        ),
      );
    }

    return BottomAppBar(
      color: AppColors.backgroundColor,
      elevation: 8.0,
      shape: const CircularNotchedRectangle(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: navItems,
        ),
      ),
    );
  }
}
