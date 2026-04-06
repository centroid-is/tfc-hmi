/// Platform-safe re-export of dart:io.
/// On web, provides stub implementations of Platform, File, etc.
export 'dart:io' if (dart.library.js_interop) 'io_stub.dart';
