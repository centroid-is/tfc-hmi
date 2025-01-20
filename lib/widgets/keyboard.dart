// keyboard.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported languages for our custom keyboard
enum KeyboardLanguage {
  english,
  icelandic,
  spanish,
}

/// A helper class to store/load the user's preferred keyboard language from
/// SharedPreferences.
class KeyboardPreferenceManager {
  static const _prefKey = 'preferredKeyboardLanguage';

  static Future<void> setPreferredLanguage(KeyboardLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, language.index);
  }

  static Future<KeyboardLanguage> getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_prefKey);
    if (index == null) {
      return KeyboardLanguage.english; // Default
    }
    return KeyboardLanguage.values[index];
  }
}

/// A full custom keyboard widget that can display either
/// a normal QWERTY-like layout (with Icelandic/English/Spanish)
/// or optionally show a numeric keypad if [numeric] = true.
class CustomKeyboard extends StatefulWidget {
  /// Called whenever a key is tapped.
  /// You will get the exact string that was pressed (e.g., "a", "ñ", "ð", "4", etc.).
  final ValueChanged<String> onKeyTap;

  /// If true, shows only the numeric keypad.
  /// If false (default), shows the normal language keyboard.
  final bool numeric;

  const CustomKeyboard({
    Key? key,
    required this.onKeyTap,
    this.numeric = false,
  }) : super(key: key);

  @override
  State<CustomKeyboard> createState() => _CustomKeyboardState();
}

class _CustomKeyboardState extends State<CustomKeyboard> {
  KeyboardLanguage _currentLanguage = KeyboardLanguage.english;

  @override
  void initState() {
    super.initState();
    _loadPreferredLanguage();
  }

  Future<void> _loadPreferredLanguage() async {
    final lang = await KeyboardPreferenceManager.getPreferredLanguage();
    setState(() {
      _currentLanguage = lang;
    });
  }

  Future<void> _changeLanguage(KeyboardLanguage newLang) async {
    setState(() {
      _currentLanguage = newLang;
    });
    await KeyboardPreferenceManager.setPreferredLanguage(newLang);
  }

  void _onKeyPressed(String value) {
    // Send the pressed key "up" to whoever is using this widget
    widget.onKeyTap(value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.numeric) {
      // Show numeric keypad
      return NumpadKeyboard(onKeyTap: _onKeyPressed);
    } else {
      // Show normal language keyboard
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLanguageToggleRow(),
          const SizedBox(height: 4),
          _buildNormalKeyboard(),
        ],
      );
    }
  }

  Widget _buildLanguageToggleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PopupMenuButton<KeyboardLanguage>(
          initialValue: _currentLanguage,
          onSelected: _changeLanguage,
          itemBuilder: (BuildContext context) => [
            PopupMenuItem(
              value: KeyboardLanguage.english,
              child: Row(
                children: [
                  Text('EN'),
                  if (_currentLanguage == KeyboardLanguage.english)
                    const Icon(Icons.check, size: 16),
                ],
              ),
            ),
            PopupMenuItem(
              value: KeyboardLanguage.icelandic,
              child: Row(
                children: [
                  Text('IS'),
                  if (_currentLanguage == KeyboardLanguage.icelandic)
                    const Icon(Icons.check, size: 16),
                ],
              ),
            ),
            PopupMenuItem(
              value: KeyboardLanguage.spanish,
              child: Row(
                children: [
                  Text('ES'),
                  if (_currentLanguage == KeyboardLanguage.spanish)
                    const Icon(Icons.check, size: 16),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getLanguageCode(_currentLanguage)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getLanguageCode(KeyboardLanguage lang) {
    switch (lang) {
      case KeyboardLanguage.english:
        return 'EN';
      case KeyboardLanguage.icelandic:
        return 'IS';
      case KeyboardLanguage.spanish:
        return 'ES';
    }
  }

  /// Builds the normal QWERTY keyboard (3 rows + a backspace row)
  /// according to the currently selected language.
  Widget _buildNormalKeyboard() {
    // We define the layout for each language
    // For simplicity, all lower-case. You can expand with SHIFT, punctuation, etc.

    // Common number row for all layouts
    final numberRow = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

    // English
    final englishLayout = <List<String>>[
      numberRow,
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.'],
    ];

    // Spanish (includes ñ)
    final spanishLayout = <List<String>>[
      numberRow,
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ñ'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.']
    ];

    // Icelandic (includes ð, þ, æ, ö)
    final icelandicLayout = <List<String>>[
      [...numberRow, 'ö'],
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 'ð'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'æ'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', 'þ']
    ];

    // Select which layout to show
    List<List<String>> selectedLayout;
    switch (_currentLanguage) {
      case KeyboardLanguage.icelandic:
        selectedLayout = icelandicLayout;
        break;
      case KeyboardLanguage.spanish:
        selectedLayout = spanishLayout;
        break;
      case KeyboardLanguage.english:
      default:
        selectedLayout = englishLayout;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Build each row
        for (final row in selectedLayout) _buildKeyRow(row),
        // A final row with space, backspace, etc. if desired
        _buildSpecialRow(),
      ],
    );
  }

  Widget _buildKeyRow(List<String> chars) {
    return ShiftBuilder(
      builder: (context, isShifted) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: chars.map((ch) {
              return _KeyButton(
                label: ShiftBuilder.applyShift(ch, isShifted, _currentLanguage),
                onTap: () {
                  _onKeyPressed(
                      ShiftBuilder.applyShift(ch, isShifted, _currentLanguage));
                  if (isShifted) {
                    ShiftBuilder.toggleShift();
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Builds a special row with Space and Backspace
  /// You can add SHIFT, ENTER, etc. as needed
  Widget _buildSpecialRow() {
    return ShiftBuilder(
      builder: (context, isShifted) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shift
              _KeyButton(
                label: 'SHIFT',
                icon: Icons.keyboard_arrow_up,
                onTap: ShiftBuilder.toggleShift,
                isActive: isShifted,
              ),
              // Space
              _KeyButton(
                label: 'SPACE',
                flex: 4,
                onTap: () => _onKeyPressed(' '),
              ),
              // Backspace
              _KeyButton(
                label: '<-',
                icon: Icons.backspace_outlined,
                onTap: () => _onKeyPressed('\b'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A separate widget for a numeric keypad (7,8,9 / 4,5,6 / 1,2,3 / 0, ., backspace)
class NumpadKeyboard extends StatelessWidget {
  final ValueChanged<String> onKeyTap;

  const NumpadKeyboard({Key? key, required this.onKeyTap}) : super(key: key);

  void _onPressed(String value) => onKeyTap(value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNumberRow(['7', '8', '9']),
        _buildNumberRow(['4', '5', '6']),
        _buildNumberRow(['1', '2', '3']),
        _buildNumberRow(['0', '.', '<-']), // <-
      ],
    );
  }

  Widget _buildNumberRow(List<String> values) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: values.map((val) {
          if (val == '<-') {
            // backspace
            return _KeyButton(
              label: '<-',
              icon: Icons.backspace_outlined,
              onTap: () => _onPressed('\b'),
            );
          }
          return _KeyButton(
            label: val,
            onTap: () => _onPressed(val),
          );
        }).toList(),
      ),
    );
  }
}

/// A reusable button widget for each key on the keyboard or numpad.
///
/// - [label] is the text shown on the button.
/// - [icon] is optional; if provided, we show an Icon instead of [label].
/// - [flex] can be used to let the button take more horizontal space (e.g., "SPACE").
class _KeyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool isActive;

  const _KeyButton({
    Key? key,
    required this.label,
    required this.onTap,
    this.icon,
    this.flex = 1,
    this.isActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: isActive ? Colors.blue : null,
          ),
          child: icon == null
              ? Text(label,
                  style: const TextStyle(fontSize: 16, color: Colors.white))
              : Icon(icon),
        ),
      ),
    );
  }
}

class ShiftBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool isShifted) builder;

  const ShiftBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _shiftNotifier,
      builder: (context, isShifted, _) => builder(context, isShifted),
    );
  }

  static final ValueNotifier<bool> _shiftNotifier = ValueNotifier(false);

  static void toggleShift() {
    _shiftNotifier.value = !_shiftNotifier.value;
  }

  static String applyShift(String char, bool isShifted,
      [KeyboardLanguage? language]) {
    if (!isShifted) return char;

    // Handle special characters first
    switch (char) {
      case 'æ':
        return 'Æ';
      case 'ö':
        return 'Ö';
      case 'ð':
        return 'Ð';
      case 'þ':
        return 'Þ';
      case 'ñ':
        return 'Ñ';
      case ',':
        return language == KeyboardLanguage.icelandic ? ';' : '<';
      case '.':
        return language == KeyboardLanguage.icelandic ? ':' : '>';
    }

    // Handle numbers based on language
    switch (char) {
      case '1':
        return language == KeyboardLanguage.icelandic ? '!' : '!';
      case '2':
        return language == KeyboardLanguage.icelandic ? '"' : '@';
      case '3':
        return language == KeyboardLanguage.icelandic ? '#' : '#';
      case '4':
        return language == KeyboardLanguage.icelandic ? '\$' : '\$';
      case '5':
        return language == KeyboardLanguage.icelandic ? '%' : '%';
      case '6':
        return language == KeyboardLanguage.icelandic ? '&' : '^';
      case '7':
        return language == KeyboardLanguage.icelandic ? '/' : '&';
      case '8':
        return language == KeyboardLanguage.icelandic ? '(' : '*';
      case '9':
        return language == KeyboardLanguage.icelandic ? ')' : '(';
      case '0':
        return language == KeyboardLanguage.icelandic ? '=' : ')';
      default:
        return char.toUpperCase();
    }
  }
}
