import 'dart:convert';
import 'dart:math' as math;

import 'package:mcp_dart/mcp_dart.dart';

import '../interfaces/screen_capturer.dart';
import 'tool_registry.dart';

/// Ceiling on the base64 payload of one captured image, in bytes.
///
/// A tool result travels as JSON over one SSE frame and lands whole in a
/// model's context, so the picture has to be bounded by something. 2 MB of
/// base64 is roughly 1.5 MB of PNG -- comfortably a full 1280-wide HMI screen
/// -- and a capture that would exceed it is re-rendered smaller rather than
/// truncated or refused.
const int kMaxScreenshotBase64Bytes = 2 * 1024 * 1024;

/// Default width bound for a capture, in pixels.
const int kDefaultScreenshotMaxWidth = 1280;

/// Narrowest a capture is allowed to be shrunk to while chasing the budget.
///
/// Below this the picture stops being worth looking at, and the honest answer
/// is an error saying so rather than a thumbnail nobody can read.
const int kMinScreenshotMaxWidth = 320;

/// Widest a caller may ask for. Above this the payload budget would decide
/// the width anyway, one wasted render at a time.
const int kMaxScreenshotMaxWidth = 4096;

/// How many times a capture may be re-rendered smaller to fit the budget.
const int kScreenshotShrinkAttempts = 3;

/// Registers the screen-capture MCP tools with the given [ToolRegistry].
///
/// **screenshot_window**: PNG of what the HMI is showing right now.
///
/// **render_page**: PNG of a configured page rendered offscreen, registered
/// only when [capturer] can do it ([ScreenCapturer.canRenderPages]).
///
/// Both are read-only: they draw the widget tree that already exists and
/// change nothing.
void registerScreenshotTools(ToolRegistry registry, ScreenCapturer capturer) {
  registry.registerTool(
    name: 'screenshot_window',
    description:
        'Take a PNG screenshot of the HMI window as the operator sees it '
        'right now -- live theme, fonts, painters and process values. Use it '
        'to judge a layout by eye instead of reconstructing it from the '
        'config. Returns an image content block; the payload is capped at '
        '~2 MB of base64, and a capture that would exceed it is re-rendered '
        'at a smaller pixel ratio (the caption says when that happened). '
        'Optional max_width bounds the PNG width in pixels '
        '(default $kDefaultScreenshotMaxWidth, '
        'clamped to $kMinScreenshotMaxWidth-$kMaxScreenshotMaxWidth).',
    inputSchema: JsonSchema.object(
      properties: {
        'max_width': JsonSchema.integer(
          description: 'Maximum PNG width in pixels '
              '(default $kDefaultScreenshotMaxWidth). The capture is '
              'rendered at a reduced pixel ratio, not resampled.',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final requested = _readMaxWidth(arguments);
      if (requested.error != null) {
        return _error(requested.error!);
      }

      return _captureAsResult(
        capture: (width) => capturer.captureWindow(maxWidth: width),
        maxWidth: requested.value!,
        label: 'The HMI window as the operator sees it now',
      );
    },
  );

  if (!capturer.canRenderPages) return;

  registry.registerTool(
    name: 'render_page',
    description:
        'Render a configured HMI page offscreen and return it as a PNG, '
        'without changing what the operator is looking at. Same live theme, '
        'fonts, painters and process values as the real page. page_key is a '
        'key from list_pages. Optional width/height set the logical canvas '
        '(defaults to the operator window\'s own size), and max_width bounds '
        'the PNG width in pixels (default $kDefaultScreenshotMaxWidth). '
        'The payload is capped at ~2 MB of base64; a capture that would '
        'exceed it is re-rendered smaller. One render runs at a time.',
    inputSchema: JsonSchema.object(
      properties: {
        'page_key': JsonSchema.string(
          description: 'The page to render, as listed by list_pages.',
        ),
        'width': JsonSchema.integer(
          description: 'Logical canvas width. Defaults to the app window.',
        ),
        'height': JsonSchema.integer(
          description: 'Logical canvas height. Defaults to the app window.',
        ),
        'max_width': JsonSchema.integer(
          description: 'Maximum PNG width in pixels '
              '(default $kDefaultScreenshotMaxWidth).',
        ),
      },
      required: ['page_key'],
    ),
    handler: (arguments, extra) async {
      final pageKey = (arguments['page_key'] as String?)?.trim() ?? '';
      if (pageKey.isEmpty) {
        return _error('page_key is required.');
      }

      final known = capturer.pageKeys;
      if (known.isNotEmpty && !known.contains(pageKey)) {
        return _error(
          'No page named "$pageKey". Known pages: ${known.join(', ')}.',
        );
      }

      final requested = _readMaxWidth(arguments);
      if (requested.error != null) {
        return _error(requested.error!);
      }

      final window = capturer.windowSize;
      final canvas = _readCanvas(arguments, window);
      if (canvas.error != null) {
        return _error(canvas.error!);
      }
      final size = canvas.value!;

      return _captureAsResult(
        capture: (width) => capturer.capturePage(
          pageKey: pageKey,
          width: size.width,
          height: size.height,
          maxWidth: width,
        ),
        maxWidth: requested.value!,
        label: 'Page "$pageKey" rendered offscreen at '
            '${size.width}x${size.height} logical px',
      );
    },
  );
}

/// Captures through [capture], shrinking until the base64 fits the budget,
/// and packs the result as an image content block plus a caption.
///
/// Bytes go roughly with area, so each retry scales the width by the square
/// root of how far over budget the last attempt was (with a little slack, so
/// a near-miss does not need a third render). The retry re-captures rather
/// than resampling: the app renders at a lower pixel ratio, which is both
/// cheaper and sharper than shrinking a PNG after the fact. The cost is that
/// a retry photographs a slightly later frame -- acceptable for a picture a
/// human or an agent is going to look at, and not something a screenshot can
/// promise anyway.
Future<CallToolResult> _captureAsResult({
  required Future<CapturedImage> Function(int maxWidth) capture,
  required int maxWidth,
  required String label,
}) async {
  var width = maxWidth;
  var shrinks = 0;

  try {
    while (true) {
      final image = await capture(width);
      final encoded = base64Encode(image.pngBytes);

      if (encoded.length <= kMaxScreenshotBase64Bytes) {
        return CallToolResult(
          content: [
            ImageContent(data: encoded, mimeType: 'image/png'),
            TextContent(
              text: _caption(label, image, encoded.length, shrinks),
            ),
          ],
        );
      }

      if (shrinks >= kScreenshotShrinkAttempts ||
          width <= kMinScreenshotMaxWidth) {
        return _error(
          'The capture is ${_kb(encoded.length)} of base64, over the '
          '${_kb(kMaxScreenshotBase64Bytes)} cap, and could not be shrunk '
          'below it in $kScreenshotShrinkAttempts attempts. Ask again with a '
          'smaller max_width.',
        );
      }

      // Base the next attempt on what actually came back, not on what was
      // asked for: a source narrower than max_width ignores the bound, and
      // scaling the bound instead of the delivered width would loop without
      // shrinking anything.
      final scale =
          math.sqrt(kMaxScreenshotBase64Bytes / encoded.length) * 0.9;
      final next = math.max(
        kMinScreenshotMaxWidth,
        (image.width * scale).floor(),
      );
      // A "shrink" that does not shrink would spin the loop for nothing.
      width = next < width ? next : math.max(kMinScreenshotMaxWidth, width ~/ 2);
      shrinks++;
    }
  } on ScreenCaptureUnavailableException catch (e) {
    return _error('Cannot capture the screen: ${e.message}');
  } on ScreenCaptureBusyException catch (e) {
    return _error('Busy: ${e.message}');
  }
}

String _caption(String label, CapturedImage image, int base64Len, int shrinks) {
  final buffer = StringBuffer()
    ..writeln('$label.')
    ..writeln('PNG ${image.width}x${image.height} px, '
        'laid out at ${image.logicalWidth.round()}x'
        '${image.logicalHeight.round()} logical px '
        '(pixel ratio ${image.pixelRatio.toStringAsFixed(2)}).')
    ..write('Payload ${_kb(base64Len)} of base64, '
        'cap ${_kb(kMaxScreenshotBase64Bytes)}.');
  if (shrinks > 0) {
    buffer.write(' Re-rendered $shrinks time(s) smaller to fit the cap.');
  }
  return buffer.toString();
}

String _kb(int bytes) => '${(bytes / 1024).round()} kB';

CallToolResult _error(String message) => CallToolResult(
      content: [TextContent(text: message)],
      isError: true,
    );

/// A parsed argument, or the message explaining why it was refused.
class _Parsed<T> {
  const _Parsed.ok(this.value) : error = null;
  const _Parsed.bad(this.error) : value = null;

  final T? value;
  final String? error;
}

_Parsed<int> _readMaxWidth(Map<String, dynamic> arguments) {
  final raw = arguments['max_width'];
  if (raw == null) return const _Parsed.ok(kDefaultScreenshotMaxWidth);
  final value = _asInt(raw);
  if (value == null) {
    return _Parsed.bad('max_width must be a number of pixels, got "$raw".');
  }
  if (value <= 0) {
    return _Parsed.bad('max_width must be positive, got $value.');
  }
  return _Parsed.ok(value.clamp(kMinScreenshotMaxWidth, kMaxScreenshotMaxWidth));
}

_Parsed<({int width, int height})> _readCanvas(
  Map<String, dynamic> arguments,
  ({int width, int height})? window,
) {
  // 1920x1080 only when there is no window to ask -- an app that is running
  // always has one, so this is the standalone/test shape.
  final fallback = window ?? (width: 1920, height: 1080);

  final rawWidth = arguments['width'];
  final rawHeight = arguments['height'];
  final width = rawWidth == null ? fallback.width : _asInt(rawWidth);
  final height = rawHeight == null ? fallback.height : _asInt(rawHeight);

  if (width == null || height == null) {
    return const _Parsed.bad('width and height must be numbers of pixels.');
  }
  if (width < 100 || height < 100 || width > 8192 || height > 8192) {
    return _Parsed.bad(
      'width and height must be between 100 and 8192 logical pixels, '
      'got ${width}x$height.',
    );
  }
  return _Parsed.ok((width: width, height: height));
}

/// Accepts what JSON actually delivers: an int, a whole double, or a string.
int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is double) return raw.isFinite ? raw.round() : null;
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}
