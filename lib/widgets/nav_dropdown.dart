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

class NavDropdown extends StatefulWidget {
  static const double itemHeight = 48.0;
  static const double menuWidth = 260.0;

  /// Notifies listeners when any [NavDropdown] popup menu is open.
  /// Used by the app shell to hide overlapping widgets (e.g. chat FAB)
  /// that are rendered above the Navigator's Overlay in the widget tree.
  static final ValueNotifier<bool> isAnyMenuOpen = ValueNotifier<bool>(false);

  final MenuItem menuItem;

  const NavDropdown({
    super.key,
    required this.menuItem,
  });

  @override
  State<NavDropdown> createState() => NavDropdownState();
}

class NavDropdownState extends State<NavDropdown> {
  /// Guard that prevents [showMenu] from being called while a popup menu is
  /// already open. Without this, rapid tapping can push a second popup route
  /// while the Navigator is still transitioning, throwing
  /// `'!_debugLocked': is not true`.
  bool _isMenuOpen = false;

  /// Whether the popup menu is currently open. Exposed for testing.
  @visibleForTesting
  bool get isMenuOpen => _isMenuOpen;

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
  ///
  /// Navigation is performed in [PopupMenuItem.onTap] (which fires before
  /// Flutter's internal `Navigator.pop(null)`), so the pop value is always
  /// `void` — compatible with any route type on the root Navigator stack.
  List<PopupMenuEntry<void>> buildFlatMenu(MenuItem root,
      {required BuildContext parentContext, int depth = 0}) {
    final items = <PopupMenuEntry<void>>[];
    for (final child in root.children) {
      final indent = EdgeInsets.only(left: depth * 16.0);
      if (child.children.isNotEmpty) {
        // Section header (not clickable)
        items.add(PopupMenuItem<void>(
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
        items.addAll(buildFlatMenu(child,
            parentContext: parentContext, depth: depth + 1));
      } else {
        items.add(PopupMenuItem<void>(
          height: NavDropdown.itemHeight,
          onTap: () => beamSafelyKids(parentContext, child),
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
          key: ValueKey<String>('nav-${widget.menuItem.label.toLowerCase()}'),
          onTap: () async {
            // BUG-001 fix: prevent re-entrant showMenu calls during
            // Navigator transitions from rapid tapping.
            if (_isMenuOpen) return;
            _isMenuOpen = true;
            NavDropdown.isAnyMenuOpen.value = true;

            final totalItems = _countAllItems(widget.menuItem);
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
            final menuLeft = (buttonCenterX - NavDropdown.menuWidth / 2)
                .clamp(0.0, overlaySize.width - NavDropdown.menuWidth);

            // BUG-005 fix: clamp the menu top so it never extends above
            // the screen and cap the height so the popup scrolls when
            // there are too many items.
            const double menuPadding = 8.0; // vertical padding inside popup
            final availableHeight =
                (buttonPos.dy - menuPadding).clamp(0.0, double.infinity);
            final effectiveMenuHeight =
                menuHeight < availableHeight ? menuHeight : availableHeight;
            final menuTop =
                (buttonPos.dy - effectiveMenuHeight).clamp(0.0, buttonPos.dy);

            final position = RelativeRect.fromLTRB(
              menuLeft,
              menuTop,
              overlaySize.width - menuLeft - NavDropdown.menuWidth,
              overlaySize.height - buttonPos.dy,
            );

            try {
              await showMenu<void>(
                context: parentContext,
                position: position,
                // BUG-002 fix: use root navigator so the popup route does not
                // share a HeroController with Beamer's nested Navigator.
                useRootNavigator: true,
                items: buildFlatMenu(widget.menuItem,
                    parentContext: parentContext),
                constraints: BoxConstraints(
                  minWidth: NavDropdown.menuWidth,
                  maxWidth: NavDropdown.menuWidth,
                  // BUG-005: cap height so the popup scrolls instead of
                  // extending off-screen when there are many items.
                  maxHeight: effectiveMenuHeight + menuPadding * 2,
                ),
              );
            } finally {
              _isMenuOpen = false;
              NavDropdown.isAnyMenuOpen.value = false;
            }
          },
          child: TopLevelNavIndicator(
            widget.menuItem.icon,
            widget.menuItem.label,
            widget.menuItem == activeRoot,
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
