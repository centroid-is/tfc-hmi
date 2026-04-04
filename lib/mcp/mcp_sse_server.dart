import 'package:tfc/core/platform_io.dart' as io;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mcp_dart/mcp_dart.dart'
    if (dart.library.js_interop) '../core/mcp_dart_stub.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart'
    show
        TfcMcpServer,
        McpDatabase,
        StateReader,
        AlarmReader,
        OperatorIdentity,
        DrawingIndex,
        PlcCodeIndex,
        TechDocIndex,
        McpToolToggles,
        ProposalCallback;

/// Hosts an MCP server using Streamable HTTP transport.
///
/// Claude Desktop (or any MCP client) connects via `http://localhost:<port>/mcp`.
/// Uses [StreamableMcpServer] from mcp_dart 2.0 to handle session routing and
/// multi-client connections automatically.
class McpSseServer {
  StreamableMcpServer? _streamableServer;
  int _port = 0;

  /// Whether the server is currently running.
  bool get isRunning => _streamableServer != null;

  /// The port the server is listening on (0 if not running).
  int get port => _port;

  /// Start the Streamable HTTP MCP server on [port].
  Future<void> start(
    int port, {
    required StateReader stateReader,
    required AlarmReader alarmReader,
    required McpDatabase database,
    required OperatorIdentity identity,
    McpToolToggles toggles = McpToolToggles.allEnabled,
    DrawingIndex? drawingIndex,
    PlcCodeIndex? plcCodeIndex,
    TechDocIndex? techDocIndex,
    ProposalCallback? onProposal,
  }) async {
    if (isRunning) return;

    // Try to kill any stale process holding the port from a previous crash
    try {
      final result = await io.Process.run('lsof', ['-ti:$port']);
      final pids = result.stdout.toString().trim();
      if (pids.isNotEmpty) {
        for (final pid in pids.split('\n')) {
          final trimmed = pid.trim();
          if (trimmed.isNotEmpty) {
            debugPrint(
              'McpSseServer: killing stale process $trimmed on port $port',
            );
            io.Process.killPid(int.parse(trimmed));
          }
        }
        // Brief delay to let the OS release the port
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {
      // lsof may not exist on all platforms; ignore errors
    }


    final server = StreamableMcpServer(
      serverFactory: (sessionId) {
        final tfcServer = TfcMcpServer(
          identity: identity,
          database: database,
          stateReader: stateReader,
          alarmReader: alarmReader,
          drawingIndex: drawingIndex,
          plcCodeIndex: plcCodeIndex,
          techDocIndex: techDocIndex,
          toggles: toggles,
          onProposal: onProposal,
        );
        return tfcServer.mcpServer;
      },
      host: 'localhost',
      port: port,
      path: '/mcp',
    );

    await server.start();
    // Only set fields after successful start — otherwise isRunning
    // returns true on a failed bind and the server becomes unrecoverable.
    _streamableServer = server;
    _port = port;

    debugPrint('McpSseServer: listening on http://localhost:$_port/mcp');
  }

  /// Stop the server and clean up resources.
  Future<void> stop() async {
    final server = _streamableServer;
    _streamableServer = null;
    _port = 0;

    if (server != null) {
      await server.stop();
      debugPrint('McpSseServer: stopped');
    }
  }
}
