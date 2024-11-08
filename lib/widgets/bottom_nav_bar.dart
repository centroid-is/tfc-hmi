// lib/widgets/custom_bottom_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import 'nav_dropdown.dart';
import '../models/menu_item.dart';

class BottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<MenuItem> onItemTapped;
  final List<MenuItem> menuItems;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
    required this.menuItems,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  @override
  Widget build(BuildContext context) {
    List<Widget> navItems = [];

    for (int i = 0; i < widget.menuItems.length; i++) {
      MenuItem menuItem = widget.menuItems[i];
      if (menuItem.children != null) {
        navItems.add(
          NavDropdown(
            menuItem: menuItem,
            isSelected: widget.currentIndex == i,
            onMenuItemSelected: (MenuItem selectedItem) {
              widget.onItemTapped(menuItem);
              context.beamToNamed(selectedItem.path.toString());
            },
          ),
        );
      } else {
        navItems.add(
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Listener(
              child: TopLevelNavIndicator(
                  menuItem.icon, menuItem.label, widget.currentIndex == i),
              onPointerDown: (PointerDownEvent _) {
                context.beamToNamed(menuItem.path.toString());
                widget.onItemTapped(menuItem);
              },
            ),
          ),
        );
      }
    }

    return BottomAppBar(
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
