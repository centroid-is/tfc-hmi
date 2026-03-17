/// Stubs for `dart:io` classes used on web where dart:io is unavailable.
/// Loaded via conditional import:
///   import 'dart:io' if (dart.library.js_interop) '../core/io_stub.dart';
library;

class Platform {
  static const bool isLinux = false;
  static const bool isWindows = false;
  static const bool isMacOS = false;
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const Map<String, String> environment = {};
  static const String localeName = '';
}

class File {
  File(String path) {
    throw UnsupportedError('File is not available on web');
  }
}

/// Stub for dart:io stderr — should never be called on web.
final stderr = _StderrStub();

class _StderrStub {
  void writeln([Object? object]) {}
  void write(Object? object) {}
}
