// lib/widgets/nav_dropdown.dart
import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import '../models/menu_item.dart';
import '../app_colors.dart';

class NavDropdown extends StatefulWidget {
  final MenuItem menuItem;
  final bool isSelected;
  final VoidCallback onMenuItemSelected;

  const NavDropdown({
    Key? key,
    required this.menuItem,
    required this.isSelected,
    required this.onMenuItemSelected,
  }) : super(key: key);

  @override
  State<NavDropdown> createState() => _NavDropdownState();
}

class _NavDropdownState extends State<NavDropdown> {
  bool _isOpen = false;

  void _toggleDropdown() {
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  void _closeDropdown() {
    setState(() {
      _isOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    print('NavDropdown build');
    print('isSelected: ${widget.isSelected}');
    print('menuItem: ${widget.menuItem}');
    print('isOpen: $_isOpen');
    print('children: ${widget.menuItem.children}');

    return Stack(
      children: [
        // Dropdown Button
        IconButton(
          icon: Icon(
            widget.menuItem.icon,
            color: widget.isSelected
                ? AppColors.selectedItemColor
                : AppColors.unselectedItemColor,
          ),
          tooltip: widget.menuItem.hoverText,
          onPressed: _toggleDropdown,
        ),
        // Dropdown Menu
        if (_isOpen)
          Positioned(
            top: 48, // Adjust based on icon size
            child: GestureDetector(
              onTap: _closeDropdown,
              behavior: HitTestBehavior.translucent,
              child: Material(
                elevation: 4,
                color: AppColors.backgroundColor,
                child: Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundColor,
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: _buildMenu(widget.menuItem.children ?? []),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenu(List<MenuItem> items) {
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: items.map(_buildMenuItem).toList(),
    );
  }

  Widget _buildMenuItem(MenuItem item) {
    if (item.children != null && item.children!.isNotEmpty) {
      return ExpansionTile(
        leading: Icon(item.icon, color: AppColors.primaryIconColor),
        title: Text(
          item.label,
          style: TextStyle(color: AppColors.primaryTextColor),
        ),
        tilePadding: EdgeInsets.symmetric(horizontal: 16.0),
        childrenPadding: EdgeInsets.only(left: 32.0),
        children: item.children!.map(_buildMenuItem).toList(),
      );
    } else {
      return ListTile(
        leading: Icon(item.icon, color: AppColors.primaryIconColor),
        title: Text(
          item.label,
          style: TextStyle(color: AppColors.primaryTextColor),
        ),
        hoverColor: AppColors.hoverColor,
        onTap: () {
          Beamer.of(context).beamToNamed(item.path);
          _closeDropdown();
          widget.onMenuItemSelected();
        },
      );
    }
  }
}
