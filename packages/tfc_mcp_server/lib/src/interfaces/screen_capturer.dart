import 'dart:typed_data';

/// A PNG of something the HMI drew, plus the geometry it was drawn at.
///
/// [width]/[height] are the pixels actually in [pngBytes]; [logicalWidth]/
/// [logicalHeight] are the logical size of the thing that was rendered. They
/// differ whenever [pixelRatio] is below 1, which is how a capture is kept
/// inside the payload budget.
class CapturedImage {
  const CapturedImage({
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.pixelRatio,
  });

  /// The encoded PNG.
  final Uint8List pngBytes;

  /// Pixel width of [pngBytes].
  final int width;

  /// Pixel height of [pngBytes].
  final int height;

  /// Logical width of the widget subtree that was captured.
  final double logicalWidth;

  /// Logical height of the widget subtree that was captured.
  final double logicalHeight;

  /// Device pixels per logical pixel used for the capture. 1.0 means the PNG
  /// is the layout at its own size; below 1.0 it was rendered smaller.
  final double pixelRatio;
}

/// Raised when the running app cannot produce a picture right now.
///
/// The tools turn this into an ordinary error result: "there is no window"
/// is a state a client should be told about plainly, not a crash.
class ScreenCaptureUnavailableException implements Exception {
  const ScreenCaptureUnavailableException(this.message);

  /// Why no picture could be taken.
  final String message;

  @override
  String toString() => message;
}

/// Raised when a second offscreen render is asked for while one is running.
class ScreenCaptureBusyException implements Exception {
  const ScreenCaptureBusyException(this.message);

  /// What is already in flight.
  final String message;

  @override
  String toString() => message;
}

/// Renders the running HMI to a PNG so an agent can look at it.
///
/// The implementation lives in the Flutter app -- it needs `dart:ui` and the
/// live widget tree -- and this is the seam the server package registers
/// tools against, the same shape as [StateReader]. In standalone /
/// database-only mode there is no app and no capturer, and the screenshot
/// tools do not register at all.
abstract class ScreenCapturer {
  /// Capture what the operator is looking at right now.
  ///
  /// [maxWidth] bounds the returned PNG's width in pixels; the capture is
  /// rendered at a reduced pixel ratio rather than resampled afterwards.
  Future<CapturedImage> captureWindow({required int maxWidth});

  /// The logical size of the app window, or null when nothing is attached.
  ///
  /// Used as the default canvas for [capturePage] so an offscreen render
  /// matches the shape of the screen the operator actually has.
  ({int width, int height})? get windowSize;

  /// Whether [capturePage] can do anything. False when only the window
  /// boundary is wired up.
  bool get canRenderPages;

  /// The page keys [capturePage] will accept.
  List<String> get pageKeys;

  /// Render [pageKey] offscreen at [width] x [height] logical pixels and
  /// capture it, without disturbing what the operator sees.
  ///
  /// Throws [ScreenCaptureBusyException] if another render is in flight and
  /// [ScreenCaptureUnavailableException] if there is no live app to render
  /// in.
  Future<CapturedImage> capturePage({
    required String pageKey,
    required int width,
    required int height,
    required int maxWidth,
  });
}
