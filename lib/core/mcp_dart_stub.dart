/// Stubs for mcp_dart native-only classes used on web.
///
/// These types are only available in mcp_dart on non-web platforms
/// (StdioClientTransport, IOStreamTransport, StreamableMcpServer, etc.).
/// On web, mcp_dart conditionally excludes them. This stub provides
/// minimal definitions so files that reference them can compile on web.
///
/// Loaded via conditional import:
///   import 'package:mcp_dart/mcp_dart.dart'
///       if (dart.library.js_interop) '../core/mcp_dart_stub.dart';
library;

// Re-export everything mcp_dart provides on web (types, client, shared).
export 'package:mcp_dart/mcp_dart.dart';

import 'package:mcp_dart/mcp_dart.dart' show Transport;

// ── Native-only stubs ────────────────────────────────────────────────

/// Stub for [StdioClientTransport] which spawns a subprocess on native.
class StdioClientTransport implements Transport {
  StdioClientTransport(StdioServerParameters params) {
    throw UnsupportedError('StdioClientTransport is not available on web');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('StdioClientTransport is not available on web');
}

/// Stub for [StdioServerParameters] used to configure subprocess launch.
class StdioServerParameters {
  final String command;
  final List<String> args;
  final Map<String, String>? environment;

  const StdioServerParameters({
    required this.command,
    this.args = const [],
    this.environment,
  });
}

/// Stub for [IOStreamTransport] which uses dart:io streams.
class IOStreamTransport implements Transport {
  IOStreamTransport({required dynamic stream, required dynamic sink}) {
    throw UnsupportedError('IOStreamTransport is not available on web');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('IOStreamTransport is not available on web');
}

/// Stub for [StreamableMcpServer] which runs an HTTP server on native.
class StreamableMcpServer {
  StreamableMcpServer({
    required dynamic serverFactory,
    String host = 'localhost',
    int port = 3000,
    String path = '/mcp',
  });

  Future<void> start() async {
    throw UnsupportedError('StreamableMcpServer is not available on web');
  }

  Future<void> stop() async {}
}
