/// Data models for multi-conversation chat support.
library;

/// Metadata for a single conversation (lightweight, no messages).
class ConversationMeta {
  /// Unique conversation identifier (base-36 microsecond timestamp + counter).
  final String id;

  /// Display title (first user message, truncated to 40 chars).
  final String title;

  /// When the conversation was created.
  final DateTime createdAt;

  const ConversationMeta({
    required this.id,
    required this.title,
    required this.createdAt,
  });

  static int _counter = 0;

  /// Generates a unique ID from the current microsecond timestamp.
  /// Appends an incrementing counter to guarantee uniqueness even on
  /// platforms with coarse timer resolution (e.g. Windows ~15ms).
  static String generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final c = (_counter++).toRadixString(36);
    return '$ts$c';
  }

  /// Extracts a title from a user message.
  ///
  /// For debug-asset messages (starting with "Debug asset:"), extracts the
  /// asset identifier. Otherwise truncates the message to 40 characters.
  static String titleFromMessage(String message) {
    // Debug asset messages: "Debug asset: <identifier>\n..."
    if (message.startsWith('Debug asset:')) {
      final firstLine = message.split('\n').first;
      final identifier = firstLine.replaceFirst('Debug asset:', '').trim();
      if (identifier.isNotEmpty) {
        return identifier.length > 40
            ? '${identifier.substring(0, 37)}...'
            : identifier;
      }
    }
    // General messages: first 40 chars
    final singleLine = message.replaceAll('\n', ' ').trim();
    if (singleLine.length <= 40) return singleLine;
    return '${singleLine.substring(0, 37)}...';
  }

  /// Creates a copy with modified fields.
  ConversationMeta copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
  }) {
    return ConversationMeta(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serializes to JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Deserializes from a JSON map.
  factory ConversationMeta.fromJson(Map<String, dynamic> json) {
    return ConversationMeta(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMeta &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ConversationMeta(id: $id, title: $title)';
}
