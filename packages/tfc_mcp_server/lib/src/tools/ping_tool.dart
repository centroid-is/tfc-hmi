import 'package:mcp_dart/mcp_dart.dart';

import 'tool_registry.dart';

/// Registers the ping tool with the given [ToolRegistry].
///
/// The ping tool is a placeholder demonstrating domain-oriented design
/// (CORE-03): it uses human-readable names and descriptions, not
/// technical IDs like OPC UA node paths.
///
/// Input: optional "message" string
/// Output: server name, version, and echoed message
void registerPingTool(ToolRegistry registry) {
  registry.registerTool(
    name: 'ping',
    description: 'Check server status and connectivity',
    inputSchema: JsonSchema.object(
      properties: {
        'message': JsonSchema.string(
          description: 'Optional message to echo back',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final message = arguments['message'] as String? ?? 'pong';
      return CallToolResult(
        content: [
          TextContent(
            text: 'tfc-mcp-server v0.1.0 is running. '
                'Echo: $message',
          ),
        ],
      );
    },
  );
}
