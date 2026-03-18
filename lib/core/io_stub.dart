/// Stubs for `dart:io` classes used on web where dart:io is unavailable.
/// Loaded via conditional import:
///   import 'dart:io' if (dart.library.js_interop) '../core/io_stub.dart';
library;

import 'dart:typed_data' show Uint8List;

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

  Future<File> copy(String newPath) async =>
      throw UnsupportedError('File.copy is not available on web');

  Future<Uint8List> readAsBytes() async =>
      throw UnsupportedError('File.readAsBytes is not available on web');

  Future<String> readAsString() async =>
      throw UnsupportedError('File.readAsString is not available on web');

  Future<File> writeAsString(String contents) async =>
      throw UnsupportedError('File.writeAsString is not available on web');
}

class Directory {
  final String path;
  Directory(this.path);

  Future<Directory> create({bool recursive = false}) async =>
      throw UnsupportedError('Directory.create is not available on web');
}

class Process {
  static Future<ProcessResult> run(String command, List<String> args) async =>
      throw UnsupportedError('Process.run is not available on web');

  static bool killPid(int pid, [dynamic signal]) =>
      throw UnsupportedError('Process.killPid is not available on web');
}

class ProcessResult {
  final dynamic stdout;
  final dynamic stderr;
  final int exitCode;
  ProcessResult(this.exitCode, this.stdout, this.stderr);
}

/// Stub for dart:io stderr — should never be called on web.
final stderr = _StderrStub();

class _StderrStub {
  void writeln([Object? object]) {}
  void write(Object? object) {}
}

// ---------------------------------------------------------------------------
// HttpClient — used by gemini_provider.dart for REST API calls
// ---------------------------------------------------------------------------
class HttpClient {
  Future<HttpClientRequest> postUrl(Uri url) async =>
      throw UnsupportedError('HttpClient.postUrl is not available on web');

  void close({bool force = false}) {}
}

class HttpClientRequest {
  late HttpHeaders headers;

  void write(Object? obj) =>
      throw UnsupportedError('HttpClientRequest.write is not available on web');

  Future<HttpClientResponse> close() async =>
      throw UnsupportedError('HttpClientRequest.close is not available on web');
}

class HttpClientResponse {
  int get statusCode =>
      throw UnsupportedError('HttpClientResponse not available on web');

  Stream<List<int>> transform<S>(dynamic converter) =>
      throw UnsupportedError('HttpClientResponse not available on web');
}

class HttpHeaders {
  ContentType? contentType;
}

class ContentType {
  final String mimeType;
  final String primaryType;
  final String subType;

  const ContentType._(this.primaryType, this.subType)
      : mimeType = '$primaryType/$subType';

  static const ContentType json = ContentType._('application', 'json');
  static const ContentType text = ContentType._('text', 'plain');
  static const ContentType html = ContentType._('text', 'html');
  static const ContentType binary =
      ContentType._('application', 'octet-stream');
}
