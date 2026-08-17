/// Content-addressed storage for page-editor images.
///
/// Image bytes never live inside the page JSON: the editor re-encodes the
/// whole page tree on every edit, so a multi-megabyte base64 blob inline in an
/// asset would be re-serialized on every drag. Instead each image is stored
/// once, base64-encoded, under its own preference key
/// (`page_editor_image:<id>`), and the asset carries only the `<id>`.
///
/// The id is a prefix of the SHA-256 of the bytes, so storing the same image
/// twice (paste, copy/paste of the asset, re-pick of the same file) dedupes to
/// a single blob, and a given image always gets the same id — which also keeps
/// tests and goldens deterministic.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:tfc_dart/core/preferences.dart';

/// The raster/vector formats the image asset accepts.
enum PageImageFormat { png, jpeg, bmp, svg }

/// Identifies [bytes] by magic numbers (or leading XML for SVG); null when the
/// bytes are none of the supported formats.
PageImageFormat? sniffImageFormat(Uint8List bytes) {
  if (bytes.length < 4) return null;
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) {
    return PageImageFormat.png;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return PageImageFormat.jpeg;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return PageImageFormat.bmp;
  }
  // SVG is XML text: skip BOM and whitespace, accept `<?xml`, `<!--`/DOCTYPE
  // preambles or a direct `<svg` root.
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  String head;
  try {
    head = utf8.decode(bytes.sublist(start, bytes.length.clamp(0, start + 512)),
        allowMalformed: false);
  } on FormatException {
    return null;
  }
  final trimmed = head.trimLeft();
  if (trimmed.startsWith('<svg') ||
      ((trimmed.startsWith('<?xml') ||
              trimmed.startsWith('<!--') ||
              trimmed.startsWith('<!DOCTYPE')) &&
          head.contains('<svg'))) {
    return PageImageFormat.svg;
  }
  return null;
}

/// Thrown by [PageImageStore.save] for images over [PageImageStore.maxBytes].
class PageImageTooLargeException implements Exception {
  final int size;
  PageImageTooLargeException(this.size);

  @override
  String toString() =>
      'Image is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB; the page '
      'editor stores at most '
      '${PageImageStore.maxBytes ~/ (1024 * 1024)} MB per image.';
}

class PageImageStore {
  /// Every stored image key starts with this; the suffix is the image id.
  static const String keyPrefix = 'page_editor_image:';

  /// Preferences ride along with everything else in one Postgres-backed
  /// cache, so a hard cap keeps a stray screenshot from ballooning it.
  static const int maxBytes = 5 * 1024 * 1024;

  final PreferencesApi prefs;
  PageImageStore(this.prefs);

  /// Stores [bytes] and returns the content-derived image id. Idempotent for
  /// identical bytes.
  Future<String> save(Uint8List bytes) async {
    if (bytes.length > maxBytes) {
      throw PageImageTooLargeException(bytes.length);
    }
    final id = await imageIdFor(bytes);
    final key = '$keyPrefix$id';
    if (!await prefs.containsKey(key)) {
      await prefs.setString(key, base64Encode(bytes));
    }
    return id;
  }

  /// The bytes stored under [id], or null when no such image exists (e.g. it
  /// was garbage-collected while an undo snapshot still referenced it).
  Future<Uint8List?> load(String id) async {
    final encoded = await prefs.getString('$keyPrefix$id');
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  /// Ids of every stored image.
  Future<Set<String>> storedIds() async {
    final keys = await prefs.getKeys();
    return {
      for (final key in keys)
        if (key.startsWith(keyPrefix)) key.substring(keyPrefix.length),
    };
  }

  /// Deletes every stored image whose id is not in [referenced]; returns how
  /// many were removed. The caller decides what counts as referenced — the
  /// editor includes its undo history and copy buffer, not just saved pages.
  Future<int> removeUnreferenced(Set<String> referenced) async {
    var removed = 0;
    for (final id in await storedIds()) {
      if (!referenced.contains(id)) {
        await prefs.remove('$keyPrefix$id');
        removed++;
      }
    }
    return removed;
  }

  /// The content-derived id [save] would assign to [bytes].
  static Future<String> imageIdFor(Uint8List bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes
        .take(12)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Every image id referenced anywhere in [jsonTree] (decoded page/asset
  /// JSON). Keys off the `image_id` field rather than the asset type, so it
  /// also finds references inside undo snapshots and copied-asset JSON.
  static Set<String> referencedImageIds(Object? jsonTree) {
    final ids = <String>{};
    void crawl(Object? node) {
      if (node is Map) {
        final id = node['image_id'];
        if (id is String && id.isNotEmpty) ids.add(id);
        node.values.forEach(crawl);
      } else if (node is List) {
        node.forEach(crawl);
      }
    }

    crawl(jsonTree);
    return ids;
  }
}
