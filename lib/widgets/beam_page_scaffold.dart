// lib/widgets/beam_page_scaffold.dart
import 'package:flutter/material.dart';
import 'bottom_nav_bar.dart';
import '../models/menu_item.dart';

class BeamPageScaffold extends StatefulWidget {
  final Widget child;
  final int currentIndex;
  final List<MenuItem> dropdownMenuItems;
  final List<MenuItem> standardMenuItems;
  final String title;

  const BeamPageScaffold({
    Key? key,
    required this.child,
    required this.currentIndex,
    required this.dropdownMenuItems,
    required this.standardMenuItems,
    required this.title,
  }) : super(key: key);

  @override
  _BeamPageScaffoldState createState() => _BeamPageScaffoldState();
}

class _BeamPageScaffoldState extends State<BeamPageScaffold> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
  }

  void _onBottomNavItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    // Additional logic if needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: widget.child,
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onItemTapped: _onBottomNavItemTapped,
        dropdownMenuItems: widget.dropdownMenuItems,
        standardMenuItems: widget.standardMenuItems,
      ),
    );
  }
}
