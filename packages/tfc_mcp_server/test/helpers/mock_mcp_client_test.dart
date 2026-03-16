import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'mock_mcp_client.dart';

void main() {
  group('MockMcpClient', () {
    late McpServer server;
    late MockMcpClient client;

    setUp(() async {
      server = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
          ),
        ),
      );

      // Register a test tool
      server.registerTool(
        'echo',
        description: 'Echo back the input',
        inputSchema: ToolInputSchema(
          properties: {
            'message': JsonSchema.string(description: 'Message to echo'),
          },
          required: ['message'],
        ),
        callback: (args, extra) async {
          final message = args['message'] as String;
          return CallToolResult(
            content: [TextContent(text: 'Echo: $message')],
          );
        },
      );

      client = await MockMcpClient.connect(server);
    });

    tearDown(() async {
      await client.close();
    });

    test('can invoke a registered tool and return result', () async {
      final result = await client.callTool('echo', {'message': 'hello'});
      expect(result.content, hasLength(1));
      expect(result.content.first, isA<TextContent>());
      expect((result.content.first as TextContent).text, equals('Echo: hello'));
    });

    test('can list registered tools', () async {
      final tools = await client.listTools();
      expect(tools, hasLength(1));
      expect(tools.first.name, equals('echo'));
      expect(tools.first.description, equals('Echo back the input'));
    });

    test('throws on unknown tool', () async {
      expect(
        () => client.callTool('nonexistent', {}),
        throwsA(isA<McpError>()),
      );
    });
  });

  group('MockMcpClient resource and prompt methods', () {
    late McpServer server;
    late MockMcpClient client;

    setUp(() async {
      server = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            resources: ServerCapabilitiesResources(),
            prompts: ServerCapabilitiesPrompts(),
          ),
        ),
      );

      // Register a test resource
      server.registerResource(
        'Test Resource',
        'test://example/data',
        (description: 'A test resource', mimeType: 'application/json'),
        (Uri uri, RequestHandlerExtra extra) async {
          return ReadResourceResult(
            contents: [
              TextResourceContents(
                uri: uri.toString(),
                mimeType: 'application/json',
                text: '{"hello": "world"}',
              ),
            ],
          );
        },
      );

      // Register a test prompt
      server.registerPrompt(
        'test_prompt',
        description: 'A test prompt',
        callback: (args, extra) async {
          return GetPromptResult(
            description: 'Test prompt result',
            messages: [
              PromptMessage(
                role: PromptMessageRole.user,
                content: TextContent(text: 'Test prompt content'),
              ),
            ],
          );
        },
      );

      client = await MockMcpClient.connect(server);
    });

    tearDown(() async {
      await client.close();
    });

    test('listResources returns list of registered resources', () async {
      final result = await client.listResources();
      expect(result.resources, hasLength(1));
      expect(result.resources.first.name, equals('Test Resource'));
      expect(result.resources.first.uri, equals('test://example/data'));
    });

    test('readResource returns ReadResourceResult with content', () async {
      final result = await client.readResource('test://example/data');
      expect(result.contents, hasLength(1));
      final textContent = result.contents.first as TextResourceContents;
      expect(textContent.text, equals('{"hello": "world"}'));
    });

    test('listPrompts returns list of registered prompts', () async {
      final result = await client.listPrompts();
      expect(result.prompts, hasLength(1));
      expect(result.prompts.first.name, equals('test_prompt'));
    });

    test('getPrompt returns GetPromptResult with messages', () async {
      final result = await client.getPrompt('test_prompt');
      expect(result.messages, hasLength(1));
      expect(result.messages.first.role, equals(PromptMessageRole.user));
      final textContent = result.messages.first.content as TextContent;
      expect(textContent.text, equals('Test prompt content'));
    });
  });

  group('TfcMcpServer capabilities', () {
    test('server with resources+prompts capabilities declares them', () async {
      // Build a server that declares resources and prompts capabilities
      final server = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(
            tools: ServerCapabilitiesTools(),
            resources: ServerCapabilitiesResources(),
            prompts: ServerCapabilitiesPrompts(),
          ),
        ),
      );

      // Register a dummy resource so listResources works
      server.registerResource(
        'Dummy',
        'test://dummy',
        null,
        (Uri uri, RequestHandlerExtra extra) async {
          return ReadResourceResult(contents: []);
        },
      );

      // Register a dummy prompt so listPrompts works
      server.registerPrompt(
        'dummy_prompt',
        callback: (args, extra) async {
          return GetPromptResult(messages: []);
        },
      );

      final client = await MockMcpClient.connect(server);
      try {
        // Should not throw -- capabilities are declared
        final resources = await client.listResources();
        expect(resources.resources, isNotEmpty);

        final prompts = await client.listPrompts();
        expect(prompts.prompts, isNotEmpty);
      } finally {
        await client.close();
      }
    });
  });
}
