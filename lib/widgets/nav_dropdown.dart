// lib/widgets/nav_dropdown.dart
import 'package:flutter/material.dart';
import '../models/menu_item.dart';

class TopLevelNavIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const TopLevelNavIndicator(this.icon, this.label, this.active, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSecondary;
    return Row(
      children: [
        Icon(icon, color: color),
        Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 0, 0),
            child: Text(label, style: TextStyle(color: color)))
      ],
    );
  }
}

class NavDropdown extends StatelessWidget {
  final MenuItem menuItem;
  final bool isSelected;
  final Function(MenuItem) onMenuItemSelected;

  const NavDropdown({
    super.key,
    required this.menuItem,
    required this.isSelected,
    required this.onMenuItemSelected,
  });

  PopupMenuItem<MenuItem> buildMenu(MenuItem root, BuildContext context) {
    final itemColor = Theme.of(context).colorScheme.onSecondary;
    if (root.children != null && root.children!.isNotEmpty) {
      // Allow each child to build it's own list
      final children =
          root.children!.map((child) => buildMenu(child, context)).toList();
      return PopupMenuItem<MenuItem>(
        child: ExpansionTile(
          leading: Icon(root.icon, color: itemColor),
          title: Text(
            root.label,
            style: TextStyle(color: itemColor),
          ),
          children: children,
        ),
      );
    } else {
      // Node has no children. Return simple listtile
      return PopupMenuItem<MenuItem>(
        value: root,
        child: ListTile(
          leading: Icon(root.icon, color: itemColor),
          title: Text(
            root.label,
            style: TextStyle(color: itemColor),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MenuItem>(
      onSelected: (MenuItem selectedItem) {
        onMenuItemSelected(selectedItem);
      },
      color: Theme.of(context).colorScheme.surface,
      tooltip: '',
      itemBuilder: (BuildContext context) {
        return menuItem.children!
            .map((node) => buildMenu(node, context))
            .toList();
      },
      child: TopLevelNavIndicator(menuItem.icon, menuItem.label, isSelected),
    );
  }
}
