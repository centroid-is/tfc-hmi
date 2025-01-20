import 'package:flutter/material.dart';
import 'keyboard.dart';

class KeyboardInputDialog extends StatefulWidget {
  final String initialValue;
  final String title;
  final bool numeric;

  const KeyboardInputDialog({
    super.key,
    required this.initialValue,
    required this.title,
    this.numeric = false,
  });

  @override
  State<KeyboardInputDialog> createState() => _KeyboardInputDialogState();
}

class _KeyboardInputDialogState extends State<KeyboardInputDialog> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyTap(String value) {
    final currentText = _controller.text;
    final selection = _controller.selection;

    if (value == '\b') {
      // Handle backspace
      if (currentText.isEmpty) return;
      if (selection.isCollapsed && selection.start == 0) return;

      final newText = selection.isCollapsed && selection.start > 0
          ? currentText.replaceRange(selection.start - 1, selection.start, '')
          : currentText.replaceRange(selection.start, selection.end, '');

      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.isCollapsed ? selection.start - 1 : selection.start,
        ),
      );
    } else {
      // Handle normal key press
      final newText =
          currentText.replaceRange(selection.start, selection.end, value);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + value.length,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              readOnly: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 16),
            CustomKeyboard(
              onKeyTap: _handleKeyTap,
              numeric: widget.numeric,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                  child: Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
