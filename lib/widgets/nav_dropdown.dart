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
  static const double itemHeight = 48.0;
  static const double menuWidth = 260.0;
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

  /// Flattens the menu tree into indented PopupMenuItems.
  /// Sections (items with children) appear as disabled headers;
  /// leaf pages are clickable.
  List<PopupMenuEntry<MenuItem>> buildFlatMenu(MenuItem root, {int depth = 0}) {
    final items = <PopupMenuEntry<MenuItem>>[];
    for (final child in root.children) {
      final indent = EdgeInsets.only(left: depth * 16.0);
      if (child.children.isNotEmpty) {
        // Section header (not clickable)
        items.add(PopupMenuItem<MenuItem>(
          enabled: false,
          height: NavDropdown.itemHeight,
          child: Padding(
            padding: indent,
            child: Row(
              children: [
                Icon(child.icon, size: 20),
                const SizedBox(width: 12),
                Text(child.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ));
        items.addAll(buildFlatMenu(child, depth: depth + 1));
      } else {
        items.add(PopupMenuItem<MenuItem>(
          height: NavDropdown.itemHeight,
          value: child,
          child: Padding(
            padding: indent,
            child: Row(
              children: [
                Icon(child.icon, size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(child.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ));
      }
    }
    return items;
  }

  /// Recursively counts all items (sections + pages) in the tree.
  int _countAllItems(MenuItem item) {
    int count = 0;
    for (final child in item.children) {
      count += 1;
      if (child.children.isNotEmpty) {
        count += _countAllItems(child);
      }
    }
    return count;
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
            final totalItems = _countAllItems(menuItem);
            final menuHeight = totalItems * NavDropdown.itemHeight;
            final RenderBox button =
                innerContext.findRenderObject() as RenderBox;
            final RenderBox overlay = Overlay.of(innerContext)
                .context
                .findRenderObject() as RenderBox;
            final buttonPos =
                button.localToGlobal(Offset.zero, ancestor: overlay);
            final overlaySize = overlay.size;

            // Center the popup horizontally over the nav item
            final buttonCenterX = buttonPos.dx + button.size.width / 2;
            final menuLeft = (buttonCenterX - menuWidth / 2)
                .clamp(0.0, overlaySize.width - menuWidth);
            final menuTop = buttonPos.dy - menuHeight;

            final position = RelativeRect.fromLTRB(
              menuLeft,
              menuTop,
              overlaySize.width - menuLeft - menuWidth,
              overlaySize.height - buttonPos.dy,
            );

            final MenuItem? selectedItem = await showMenu<MenuItem>(
              context: parentContext,
              position: position,
              items: buildFlatMenu(menuItem),
              constraints: const BoxConstraints(
                minWidth: menuWidth,
                maxWidth: menuWidth,
              ),
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
