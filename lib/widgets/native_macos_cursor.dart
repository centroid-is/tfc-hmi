import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// Thin wrapper around the `com.centroid.native_cursor` platform channel.
///
/// On macOS this invokes the Swift [NativeCursorPlugin] to push/pop private
/// `NSCursor` diagonal-resize cursors (`_windowResizeNorthWestSouthEastCursor`
/// and `_windowResizeNorthEastSouthWestCursor`).
///
/// On all other platforms the calls are silently no-ops.
class NativeMacosCursor {
  NativeMacosCursor._();

  static const _channel = MethodChannel('com.centroid.native_cursor');

  /// Whether we are running on macOS and the channel is expected to exist.
  static bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  /// NW-SE diagonal resize cursor (for top-left / bottom-right corners).
  static const resizeNWSE = 'resizeNWSE';

  /// NE-SW diagonal resize cursor (for top-right / bottom-left corners).
  static const resizeNESW = 'resizeNESW';

  /// Pushes the native diagonal resize cursor identified by [cursorType]
  /// onto the macOS cursor stack. Use [resizeNWSE] or [resizeNESW].
  ///
  /// No-op on non-macOS platforms.
  static Future<void> setCursor(String cursorType) async {
    if (!_isMacOS) return;
    try {
      await _channel.invokeMethod<void>('setCursor', cursorType);
    } on MissingPluginException {
      // Plugin not available (e.g. running in tests or on a different runner).
    }
  }

  /// Pops the most recently pushed native cursor from the macOS cursor stack.
  ///
  /// No-op on non-macOS platforms.
  static Future<void> resetCursor() async {
    if (!_isMacOS) return;
    try {
      await _channel.invokeMethod<void>('resetCursor');
    } on MissingPluginException {
      // Plugin not available.
    }
  }
}
