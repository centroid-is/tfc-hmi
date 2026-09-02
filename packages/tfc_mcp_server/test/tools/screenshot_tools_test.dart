import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/screen_capturer.dart';
import 'package:tfc_mcp_server/src/server.dart';
import 'package:tfc_mcp_server/src/tools/screenshot_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import 'package:tfc_mcp_server/src/tools/tool_toggles.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

/// A [ScreenCapturer] that draws nothing and reports exactly what it was
/// asked for, so the tools' own behaviour -- argument handling, the payload
/// budget, the error paths -- can be tested without a Flutter engine.
class FakeScreenCapturer implements ScreenCapturer {
  FakeScreenCapturer({
    this.pages = const ['home', 'wet-area'],
    this.canRenderPages = true,
    this.window = (width: 1920, height: 1080),
  });

  /// Every maxWidth the tools asked for, in order. A second entry means the
  /// payload budget forced a re-render.
  final List<int> requestedWidths = <int>[];

  /// Every capturePage call's arguments.
  final List<Map<String, Object?>> pageCalls = <Map<String, Object?>>[];

  /// Thrown instead of capturing, when set.
  Exception? failure;

  /// How many PNG bytes a capture at the given width produces.
  int Function(int maxWidth) byteCount = (maxWidth) => maxWidth * 4;

  final List<String> pages;

  @override
  final bool canRenderPages;

  final ({int width, int height}) window;

  @override
  ({int width, int height})? get windowSize => window;

  @override
  List<String> get pageKeys => pages;

  CapturedImage _render(int maxWidth) {
    requestedWidths.add(maxWidth);
    final failure = this.failure;
    if (failure != null) throw failure;
    final bytes = Uint8List(byteCount(maxWidth));
    return CapturedImage(
      pngBytes: bytes,
      width: maxWidth,
      height: (maxWidth * 9) ~/ 16,
      logicalWidth: 1920,
      logicalHeight: 1080,
      pixelRatio: maxWidth / 1920,
    );
  }

  @override
  Future<CapturedImage> captureWindow({required int maxWidth}) async =>
      _render(maxWidth);

  @override
  Future<CapturedImage> capturePage({
    required String pageKey,
    required int width,
    required int height,
    required int maxWidth,
  }) async {
    pageCalls.add({'pageKey': pageKey, 'width': width, 'height': height});
    return _render(maxWidth);
  }
}

void main() {
  late ServerDatabase db;
  late FakeScreenCapturer capturer;

  setUp(() async {
    db = ServerDatabase.inMemory();
    await db.customStatement('SELECT 1');
    capturer = FakeScreenCapturer();
  });

  tearDown(() async {
    await db.close();
  });

  Future<MockMcpClient> clientWithTools() async {
    final mcpServer = McpServer(
      const Implementation(name: 'test-server', version: '0.1.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    final registry = ToolRegistry(
      mcpServer: mcpServer,
      identity: EnvOperatorIdentity(
        environmentProvider: () => {'TFC_USER': 'op1'},
      ),
      auditLogService: AuditLogService(db),
    );
    registerScreenshotTools(registry, capturer);
    return MockMcpClient.connect(mcpServer);
  }

  ImageContent imageOf(CallToolResult result) =>
      result.content.whereType<ImageContent>().single;

  String textOf(CallToolResult result) =>
      result.content.whereType<TextContent>().map((c) => c.text).join('\n');

  group('screenshot_window', () {
    test('returns the PNG as an image content block plus a caption', () async {
      final client = await clientWithTools();
      try {
        final result = await client.callTool('screenshot_window', {});

        expect(result.isError, isNot(true));
        final image = imageOf(result);
        expect(image.mimeType, 'image/png');
        expect(base64Decode(image.data),
            hasLength(kDefaultScreenshotMaxWidth * 4));

        final text = textOf(result);
        expect(text, contains('1280x720 px'));
        expect(text, contains('1920x1080 logical px'));
        expect(text, contains('cap 2048 kB'));
      } finally {
        await client.close();
      }
    });

    test('defaults to 1280 px wide and honours an explicit max_width',
        () async {
      final client = await clientWithTools();
      try {
        await client.callTool('screenshot_window', {});
        await client.callTool('screenshot_window', {'max_width': 640});
        expect(capturer.requestedWidths, [kDefaultScreenshotMaxWidth, 640]);
      } finally {
        await client.close();
      }
    });

    test('clamps max_width into the range the tool can actually serve',
        () async {
      final client = await clientWithTools();
      try {
        await client.callTool('screenshot_window', {'max_width': 10});
        await client.callTool('screenshot_window', {'max_width': 100000});
        expect(capturer.requestedWidths,
            [kMinScreenshotMaxWidth, kMaxScreenshotMaxWidth]);
      } finally {
        await client.close();
      }
    });

    test('a non-positive max_width is an error result, not a capture',
        () async {
      final client = await clientWithTools();
      try {
        final result =
            await client.callTool('screenshot_window', {'max_width': 0});
        expect(result.isError, isTrue);
        expect(textOf(result), contains('positive'));
        expect(capturer.requestedWidths, isEmpty);
      } finally {
        await client.close();
      }
    });

    test('no window to photograph is reported, not thrown', () async {
      capturer.failure =
          const ScreenCaptureUnavailableException('no capture boundary');
      final client = await clientWithTools();
      try {
        final result = await client.callTool('screenshot_window', {});
        expect(result.isError, isTrue);
        expect(textOf(result), contains('no capture boundary'));
      } finally {
        await client.close();
      }
    });

    test('an over-budget capture is re-rendered smaller until it fits',
        () async {
      // Anything wider than 600 px comes back at 3 MB, which is 4 MB of
      // base64 -- twice the cap.
      capturer.byteCount = (w) => w > 600 ? 3 * 1024 * 1024 : 1024;

      final client = await clientWithTools();
      try {
        final result = await client.callTool('screenshot_window', {});

        expect(result.isError, isNot(true));
        expect(capturer.requestedWidths.length, greaterThan(1),
            reason: 'the first attempt was over budget');
        expect(capturer.requestedWidths.first, kDefaultScreenshotMaxWidth);
        expect(capturer.requestedWidths.last, lessThan(600));
        expect(base64Decode(imageOf(result).data), hasLength(1024));
        expect(textOf(result), contains('Re-rendered'));
      } finally {
        await client.close();
      }
    });

    test('a capture that will not fit at any size is an error, not a stub',
        () async {
      capturer.byteCount = (_) => 3 * 1024 * 1024;

      final client = await clientWithTools();
      try {
        final result = await client.callTool('screenshot_window', {});

        expect(result.isError, isTrue);
        expect(textOf(result), contains('2048 kB'));
        expect(textOf(result), contains('smaller max_width'));
        expect(capturer.requestedWidths,
            hasLength(kScreenshotShrinkAttempts + 1));
      } finally {
        await client.close();
      }
    });

    test('the call is audited like every other tool', () async {
      final client = await clientWithTools();
      try {
        await client.callTool('screenshot_window', {});
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.tool, 'screenshot_window');
        expect(records.first.operatorId, 'op1');
        expect(records.first.status, 'success');
      } finally {
        await client.close();
      }
    });
  });

  group('render_page', () {
    test('renders at the operator window size by default', () async {
      final client = await clientWithTools();
      try {
        final result =
            await client.callTool('render_page', {'page_key': 'home'});

        expect(result.isError, isNot(true));
        expect(capturer.pageCalls, [
          {'pageKey': 'home', 'width': 1920, 'height': 1080}
        ]);
        expect(textOf(result), contains('Page "home"'));
      } finally {
        await client.close();
      }
    });

    test('an explicit canvas overrides the window size', () async {
      final client = await clientWithTools();
      try {
        await client.callTool('render_page', {
          'page_key': 'wet-area',
          'width': 1024,
          'height': 768,
        });
        expect(capturer.pageCalls.single['width'], 1024);
        expect(capturer.pageCalls.single['height'], 768);
      } finally {
        await client.close();
      }
    });

    test('an unknown page names the pages that do exist', () async {
      final client = await clientWithTools();
      try {
        final result =
            await client.callTool('render_page', {'page_key': 'nope'});
        expect(result.isError, isTrue);
        expect(textOf(result), contains('wet-area'));
        expect(capturer.pageCalls, isEmpty);
      } finally {
        await client.close();
      }
    });

    test('an absurd canvas is refused before anything is rendered', () async {
      final client = await clientWithTools();
      try {
        final result = await client.callTool('render_page', {
          'page_key': 'home',
          'width': 20,
          'height': 20,
        });
        expect(result.isError, isTrue);
        expect(textOf(result), contains('between 100 and 8192'));
        expect(capturer.pageCalls, isEmpty);
      } finally {
        await client.close();
      }
    });

    test('a render already in flight is reported, not queued', () async {
      capturer.failure =
          const ScreenCaptureBusyException('another render is in flight');
      final client = await clientWithTools();
      try {
        final result =
            await client.callTool('render_page', {'page_key': 'home'});
        expect(result.isError, isTrue);
        expect(textOf(result), contains('another render is in flight'));
      } finally {
        await client.close();
      }
    });

    test('is absent when the capturer cannot render pages offscreen',
        () async {
      capturer = FakeScreenCapturer(canRenderPages: false);
      final client = await clientWithTools();
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, contains('screenshot_window'));
        expect(names, isNot(contains('render_page')));
      } finally {
        await client.close();
      }
    });
  });

  group('registration on the real server', () {
    TfcMcpServer server({
      ScreenCapturer? screenCapturer,
      McpToolToggles toggles = McpToolToggles.allEnabled,
    }) {
      return TfcMcpServer(
        identity: EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        ),
        database: db,
        stateReader: MockStateReader(),
        alarmReader: MockAlarmReader(),
        screenCapturer: screenCapturer,
        toggles: toggles,
      );
    }

    test('absent with no capturer -- a standalone server has no window',
        () async {
      final client = await MockMcpClient.connect(server().mcpServer);
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, isNot(contains('screenshot_window')));
        expect(names, isNot(contains('render_page')));
      } finally {
        await client.close();
      }
    });

    test('present when the app supplies one', () async {
      final client = await MockMcpClient.connect(
          server(screenCapturer: capturer).mcpServer);
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, contains('screenshot_window'));
        expect(names, contains('render_page'));
      } finally {
        await client.close();
      }
    });

    test('absent when the screen-capture group is turned off', () async {
      final client = await MockMcpClient.connect(server(
        screenCapturer: capturer,
        toggles: const McpToolToggles(screenshotsEnabled: false),
      ).mcpServer);
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, isNot(contains('screenshot_window')));
      } finally {
        await client.close();
      }
    });
  });
}
