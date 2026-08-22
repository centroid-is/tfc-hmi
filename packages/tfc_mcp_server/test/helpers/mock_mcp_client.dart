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

    final mock = MockMcpClient._(client, serverTransport, clientTransport);
    // Installed before connect so nothing pushed during the handshake is
    // missed.
    client.fallbackNotificationHandler = (notification) async {
      mock._recordNotification(notification);
    };
    await client.connect(clientTransport);

    return mock;
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

    final mock = MockMcpClient._(client, serverTransport, clientTransport);
    client.fallbackNotificationHandler = (notification) async {
      mock._recordNotification(notification);
    };

    await client.connect(clientTransport);

    return mock;
  }

  /// Every notification the server pushed that had no specific handler,
  /// oldest first.
  ///
  /// Server-initiated notifications are otherwise invisible to a test: they
  /// carry no request id and nothing awaits them, so a broken one looks
  /// exactly like a working one. [nextNotification] is the way to wait for
  /// a particular method to arrive.
  final List<JsonRpcNotification> notifications = [];

  final _notificationController =
      StreamController<JsonRpcNotification>.broadcast();

  /// Completes with the first notification matching [method], or throws on
  /// [timeout].
  ///
  /// Checks what has already arrived before waiting, so a notification that
  /// landed between connecting and calling this is not missed.
  Future<JsonRpcNotification> nextNotification(
    String method, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    for (final n in notifications) {
      if (n.method == method) return Future.value(n);
    }
    return _notificationController.stream
        .firstWhere((n) => n.method == method)
        .timeout(timeout,
            onTimeout: () => throw StateError(
                'no "$method" notification arrived within $timeout; '
                'saw: ${notifications.map((n) => n.method).toList()}'));
  }

  void _recordNotification(JsonRpcNotification notification) {
    notifications.add(notification);
    if (!_notificationController.isClosed) {
      _notificationController.add(notification);
    }
  }

  /// The capabilities the server advertised during the initialize handshake.
  ServerCapabilities? get serverCapabilities =>
      _client.getServerCapabilities();

  /// The `instructions` string the server returned from `initialize`.
  ///
  /// This is how a real client receives the server's operating manual, so it
  /// is how the tests check that one is actually being sent.
  String? get instructions => _client.getInstructions();

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
    await _notificationController.close();
    await _clientTransport.close();
    await _serverTransport.close();
  }
}
