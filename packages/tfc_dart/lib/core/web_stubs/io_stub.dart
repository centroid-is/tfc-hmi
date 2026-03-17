/// Web stub for dart:io types used in tfc_dart.

// ignore_for_file: constant_identifier_names

final IOSink stderr = _NoOpIOSink();

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
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<String> readAsString() async =>
      throw UnsupportedError('File not available on web');
}

class IOSink {
  void writeln([Object? object = '']) {}
  void write(Object? object) {}
}

class _NoOpIOSink extends IOSink {}
