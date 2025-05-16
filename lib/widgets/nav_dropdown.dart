import 'dart:io';

import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import '../models/menu_item.dart';
import '../route_registry.dart';

class TopLevelNavIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const TopLevelNavIndicator(this.icon, this.label, this.active, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 25),
          Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0, 0, 0),
              child:
                  Text(label, style: Theme.of(context).textTheme.labelMedium)),
        ],
      ),
    );
  }
}

class NavDropdown extends StatelessWidget {
  static const double itemHeight = 56.0;
  final MenuItem menuItem;

  const NavDropdown({
    super.key,
    required this.menuItem,
  });

  // From a given page path. Find the topmost node that holds
  // the ownership path of the node
  MenuItem? findRootNodeOfLeaf(MenuItem node, MenuItem? base, String path) {
    if (node.path != null && node.path! == path) return base ?? node;
    for (final child in node.children) {
      MenuItem? foundBase = findRootNodeOfLeaf(
          child, node != RouteRegistry().root ? base ?? node : null, path);
      if (foundBase != null) return foundBase;
    }
    return null;
  }

  PopupMenuItem<MenuItem> buildMenu(MenuItem root, BuildContext context) {
    if (root.children.isNotEmpty) {
      // Allow each child to build it's own list
      final children =
          root.children.map((child) => buildMenu(child, context)).toList();
      return PopupMenuItem<MenuItem>(
        height: NavDropdown.itemHeight,
        child: ExpansionTile(
          leading: Icon(root.icon),
          title: Text(
            root.label,
          ),
          children: children,
        ),
      );
    } else {
      // Node has no children. Return simple listtile
      return PopupMenuItem<MenuItem>(
        height: NavDropdown.itemHeight,
        value: root,
        child: ListTile(
          leading: Icon(root.icon),
          title: Text(
            root.label,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capture the parent context so we can safely navigate after the popup closes
    final parentContext = context;
    final activeRoot = findRootNodeOfLeaf(RouteRegistry().root, null,
        (context.currentBeamLocation.state as BeamState).uri.path);
    if (activeRoot != null) {
      // print('I am here ${activeRoot.label}');
    }
    return Builder(
      builder: (innerContext) {
        return InkWell(
          onTap: () async {
            // Calculate dynamic upward offset so menu appears above nav bar
            final totalItems = menuItem.children.length;
            final menuHeight = totalItems * NavDropdown.itemHeight;
            final RenderBox button =
                innerContext.findRenderObject() as RenderBox;
            final RenderBox overlay = Overlay.of(innerContext)
                .context
                .findRenderObject() as RenderBox;
            final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
            final bottomRight = button.localToGlobal(
              button.size.bottomRight(Offset.zero),
              ancestor: overlay,
            );
            final shiftedRect =
                Rect.fromPoints(origin, bottomRight).translate(0, -menuHeight);
            final RelativeRect position = RelativeRect.fromRect(
              shiftedRect,
              Offset.zero & overlay.size,
            );
            // Show the menu and wait until it's fully closed
            final MenuItem? selectedItem = await showMenu<MenuItem>(
              context: parentContext,
              position: position,
              items: menuItem.children
                  .map((node) => buildMenu(node, innerContext))
                  .toList(),
            );
            if (selectedItem != null) {
              // todo get rid of the warning
              beamSafelyKids(parentContext, selectedItem);
            }
          },
          child: TopLevelNavIndicator(
            menuItem.icon,
            menuItem.label,
            menuItem == activeRoot,
          ),
        );
      },
    );
  }
}

void beamSafelyKids(BuildContext context, MenuItem item) {
  if (item.path != null) {
    context.beamToNamed(item.path.toString());
  } else {
    stderr.writeln('Item pressed and navigated does not have a page $item');
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
              title: Text('Page does not exist!',
                  style: Theme.of(context).textTheme.titleMedium!),
              icon:
                  Icon(Icons.error, color: Theme.of(context).colorScheme.error),
              actions: [
                TextButton(
                    child: const Text('Close'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    }),
              ]);
        });
  }
}
