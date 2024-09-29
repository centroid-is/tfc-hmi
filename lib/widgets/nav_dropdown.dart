// lib/widgets/nav_dropdown.dart
import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import '../models/menu_item.dart';
import '../app_colors.dart';

class NavDropdown extends StatelessWidget {
  final MenuItem menuItem;
  final bool isSelected;
  final VoidCallback onMenuItemSelected;

  const NavDropdown({
    super.key,
    required this.menuItem,
    required this.isSelected,
    required this.onMenuItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MenuItem>(
      icon: Icon(
        menuItem.icon,
        color: isSelected
            ? AppColors.selectedItemColor
            : AppColors.unselectedItemColor,
      ),
      tooltip: menuItem.hoverText,
      onSelected: (MenuItem selectedItem) {
        Beamer.of(context).beamToNamed(selectedItem.path.toString());
        onMenuItemSelected();
      },
      color: AppColors.backgroundColor,
      itemBuilder: (BuildContext context) {
        return menuItem.children?.map((MenuItem child) {
              if (child.children != null && child.children!.isNotEmpty) {
                return PopupMenuItem<MenuItem>(
                  child: ExpansionTile(
                    leading:
                        Icon(child.icon, color: AppColors.primaryIconColor),
                    title: Text(
                      child.label,
                      style: TextStyle(color: AppColors.primaryTextColor),
                    ),
                    children: child.children!.map((MenuItem grandChild) {
                      return ListTile(
                        leading: Icon(grandChild.icon,
                            color: AppColors.primaryIconColor),
                        title: Text(
                          grandChild.label,
                          style: TextStyle(color: AppColors.primaryTextColor),
                        ),
                        onTap: () {
                          context.beamToNamed(grandChild.path.toString());
                          Navigator.pop(context); // Close the popup menu
                          onMenuItemSelected();
                        },
                      );
                    }).toList(),
                  ),
                );
              } else {
                return PopupMenuItem<MenuItem>(
                  value: child,
                  child: ListTile(
                    leading:
                        Icon(child.icon, color: AppColors.primaryIconColor),
                    title: Text(
                      child.label,
                      style: TextStyle(color: AppColors.primaryTextColor),
                    ),
                  ),
                );
              }
            }).toList() ??
            [];
      },
    );
  }
}
