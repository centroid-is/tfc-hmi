/// Shared constants for the _drawing_action JSON protocol between
/// the MCP server's get_drawing_page tool and the Flutter chat UI.
///
/// The server emits these fields in tool result JSON; the chat UI
/// detects and parses them to open the drawing overlay.
class DrawingAction {
  DrawingAction._();

  /// Marker field indicating this JSON is a drawing navigation action.
  static const String marker = '_drawing_action';

  /// String: the drawing name for display.
  static const String drawingName = 'drawingName';

  /// String: filesystem path to the PDF file.
  static const String filePath = 'filePath';

  /// int: 1-based page number to navigate to.
  static const String pageNumber = 'pageNumber';

  /// String (optional): text to highlight on the target page.
  static const String highlightText = 'highlightText';

  /// Parses a decoded JSON map, returning null if not a drawing action.
  static Map<String, dynamic>? tryParse(Map<String, dynamic> json) {
    if (json[marker] != true) return null;
    return json;
  }
}
