import 'package:flutter/material.dart';

export 'package:tfc_dart/core/fuzzy_match.dart';

class FuzzySearchBar extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;

  const FuzzySearchBar({
    super.key,
    this.hintText = 'Search...',
    required this.onChanged,
    this.decoration,
  });

  @override
  State<FuzzySearchBar> createState() => FuzzySearchBarState();
}

class FuzzySearchBarState extends State<FuzzySearchBar> {
  final TextEditingController controller = TextEditingController();

  void clear() {
    controller.clear();
    widget.onChanged('');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: widget.decoration ??
          InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
      onChanged: widget.onChanged,
    );
  }
}
