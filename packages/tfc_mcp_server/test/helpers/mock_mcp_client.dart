import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';

/// A mock MCP client that connects to an [McpServer] in-process for testing.
///
/// Uses [IOStreamTransport] pairs to create an in-memory bidirectional
/// channel between a real [McpClient] and the server under test, avoiding
/// the need for stdio or network transports.
///
/// Usage:
/// ```dart
/// final server = McpServer(Implementation(name: 'test', version: '0.1.0'));
/// server.registerTool('ping', callback: (args, extra) async {
///   return CallToolResult(content: [TextContent(text: 'pong')]);
/// });
/// final mockClient = await MockMcpClient.connect(server);
/// final result = await mockClient.callTool('ping', {});
/// expect(result.content.first, isA<TextContent>());
/// await mockClient.close();
/// ```
class MockMcpClient {
  MockMcpClient._(this._client, this._serverTransport, this._clientTransport);

  final McpClient _client;
  final IOStreamTransport _serverTransport;
  final IOStreamTransport _clientTransport;

  /// Connect a new mock client to the given [McpServer].
  ///
  /// This creates an in-memory transport pair (two [IOStreamTransport]s
  /// wired back-to-back) and initializes both the server and client
  /// connections.
  static Future<MockMcpClient> connect(McpServer server) async {
    // Create two stream controllers to wire client <-> server
    final clientToServer = StreamController<List<int>>();
    final serverToClient = StreamController<List<int>>();

    // Server reads from clientToServer, writes to serverToClient
    final serverTransport = IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    );

    // Client reads from serverToClient, writes to clientToServer
    final clientTransport = IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    );

    // Connect the server to its transport
    await server.connect(serverTransport);

    // Create and connect the client
    final client = McpClient(
      const Implementation(name: 'mock-test-client', version: '1.0.0'),
      options: McpClientOptions(
        capabilities: const ClientCapabilities(),
      ),
    );
    await client.connect(clientTransport);

    return MockMcpClient._(client, serverTransport, clientTransport);
  }

  /// Connect a mock client with elicitation support to the given [McpServer].
  ///
  /// The [onElicit] callback is invoked when the server calls
  /// [McpServer.elicitInput()]. Tests can control the response by
  /// returning an [ElicitResult] with the desired action and content.
  ///
  /// Example:
  /// ```dart
  /// final mockClient = await MockMcpClient.connectWithElicitation(
  ///   server,
  ///   onElicit: (request) async => ElicitResult(
  ///     action: 'accept',
  ///     content: {'confirm': true},
  ///   ),
  /// );
  /// ```
  static Future<MockMcpClient> connectWithElicitation(
    McpServer server, {
    required Future<ElicitResult> Function(ElicitRequest) onElicit,
  }) async {
    final clientToServer = StreamController<List<int>>();
    final serverToClient = StreamController<List<int>>();

    final serverTransport = IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    );

    final clientTransport = IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    );

    await server.connect(serverTransport);

    final client = McpClient(
      const Implementation(name: 'mock-test-client', version: '1.0.0'),
      options: McpClientOptions(
        capabilities: const ClientCapabilities(
          elicitation: ClientElicitation.formOnly(),
        ),
      ),
    );

    // Wire up the elicitation callback
    client.onElicitRequest = onElicit;

    await client.connect(clientTransport);

    return MockMcpClient._(client, serverTransport, clientTransport);
  }

  /// Call a tool registered on the server by name.
  Future<CallToolResult> callTool(
      String name, Map<String, dynamic> arguments) async {
    return _client.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
  }

  /// List all tools registered on the server.
  Future<List<Tool>> listTools() async {
    final result = await _client.listTools();
    return result.tools;
  }

  /// List all resources registered on the server.
  Future<ListResourcesResult> listResources() async {
    return _client.listResources();
  }

  /// Read a resource by URI.
  Future<ReadResourceResult> readResource(String uri) async {
    return _client.readResource(ReadResourceRequest(uri: uri));
  }

  /// List all prompts registered on the server.
  Future<ListPromptsResult> listPrompts() async {
    return _client.listPrompts();
  }

  /// Get a prompt by name with optional arguments.
  Future<GetPromptResult> getPrompt(String name,
      {Map<String, String>? arguments}) async {
    return _client.getPrompt(
        GetPromptRequest(name: name, arguments: arguments));
  }

  /// Close both client and server transports.
  Future<void> close() async {
    await _clientTransport.close();
    await _serverTransport.close();
  }
}
