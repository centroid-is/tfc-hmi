/// Thin facade over the system clipboard for the page editor.
///
/// Flutter's built-in [Clipboard] only speaks `text/plain`, so image reads go
/// through the `pasteboard` plugin. Everything is funneled through one
/// swappable [EditorClipboard.instance] so tests can substitute a fake without
/// mocking two different platform channels.
library;

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

class EditorClipboard {
  /// The clipboard the editor talks to. Tests may replace it; production code
  /// never should.
  static EditorClipboard instance = EditorClipboard();

  /// Image bytes on the system clipboard, or null when there is no image (or
  /// the platform has no image-clipboard support).
  Future<Uint8List?> readImage() async {
    try {
      return await Pasteboard.image;
    } catch (_) {
      // MissingPluginException in tests / unsupported platforms.
      return null;
    }
  }

  /// Plain text on the system clipboard, or null.
  Future<String?> readText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  /// Puts [text] on the system clipboard.
  Future<void> writeText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // Clipboard writes are best-effort; the editor keeps its in-memory
      // copy buffer regardless.
    }
  }
}
