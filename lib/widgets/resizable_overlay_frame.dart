import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'native_macos_cursor.dart';

/// The eight resize directions supported by [ResizableOverlayFrame].
enum _ResizeEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Returns the native macOS cursor type string for a diagonal corner, or
/// `null` for non-corner edges.
String? _nativeCursorType(_ResizeEdge edge) {
  switch (edge) {
    case _ResizeEdge.topLeft:
    case _ResizeEdge.bottomRight:
      return NativeMacosCursor.resizeNWSE;
    case _ResizeEdge.topRight:
    case _ResizeEdge.bottomLeft:
      return NativeMacosCursor.resizeNESW;
    default:
      return null;
  }
}

/// Returns the [MouseCursor] for a corner resize handle.
///
/// On macOS the native diagonal cursor is applied via a platform channel
/// (see [NativeMacosCursor]), so we return [SystemMouseCursors.basic] to
/// avoid Flutter's engine overriding it with an arrow. The native cursor is
/// pushed/popped by the [MouseRegion] enter/exit callbacks in [_buildHandle].
///
/// On other platforms (Windows, Linux) the diagonal cursors work natively
/// via Flutter's engine, so we return the requested cursor directly.
///
/// See: https://github.com/flutter/flutter/issues/138887
///      https://github.com/flutter/flutter/issues/92894
MouseCursor _cornerCursor(MouseCursor desiredCursor) {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    // Let the native cursor take over -- don't set a Flutter cursor that
    // would compete with it.
    return SystemMouseCursors.basic;
  }
  return desiredCursor;
}

/// Whether the current platform is macOS.
bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

/// A transparent frame of resize handles that wraps overlay content.
///
/// Provides edge and corner drag-to-resize with appropriate mouse cursors
/// for all 8 directions (N, S, E, W, NE, NW, SE, SW). Used by both
/// [ChatOverlay] and [DrawingOverlay] to provide native-window-style resizing.
///
/// The frame renders invisible hit-test regions along each edge and at each
/// corner. When the mouse hovers over them the cursor changes to the
/// appropriate resize arrow. Dragging adjusts the overlay size and position
/// accordingly.
///
/// On macOS, corner handles use native diagonal resize cursors via a platform
/// channel ([NativeMacosCursor]) because Flutter's engine does not support
/// the private `NSCursor` diagonal selectors.
class ResizableOverlayFrame extends StatefulWidget {
  /// The content displayed inside the frame.
  final Widget child;

  /// Current overlay position (top-left corner in parent coordinates).
  final Offset position;

  /// Current overlay size.
  final Size size;

  /// Minimum allowed size.
  final Size minSize;

  /// Available screen area for clamping.
  final Size screenSize;

  /// Called whenever a drag gesture changes the overlay geometry.
  /// Receives the new position and size.
  final void Function(Offset newPosition, Size newSize) onResize;

  /// Called when a resize drag gesture begins.
  final VoidCallback? onResizeStart;

  /// Called when a resize drag gesture ends (or is cancelled).
  final VoidCallback? onResizeEnd;

  /// Width of the invisible hit-test region along each edge.
  static const double edgeWidth = 6.0;

  /// Size of the invisible hit-test region at each corner.
  static const double cornerSize = 12.0;

  const ResizableOverlayFrame({
    super.key,
    required this.child,
    required this.position,
    required this.size,
    required this.minSize,
    required this.screenSize,
    required this.onResize,
    this.onResizeStart,
    this.onResizeEnd,
  });

  @override
  State<ResizableOverlayFrame> createState() => _ResizableOverlayFrameState();
}

class _ResizableOverlayFrameState extends State<ResizableOverlayFrame> {
  /// The global pointer position at drag start. Used with the current
  /// global position to compute a total offset — avoiding frame-by-frame
  /// delta accumulation that drifts when build() clamping modifies values
  /// between frames.
  Offset? _dragStartGlobalPosition;

  /// The overlay position and size captured at drag start. All subsequent
  /// drag updates compute new geometry relative to these anchors, ensuring
  /// the corner tracks the mouse pointer exactly.
  Offset? _dragStartPosition;
  Size? _dragStartSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main content fills the entire area
        Positioned.fill(child: widget.child),

        // ---- Edge handles ----
        // Top edge
        _buildHandle(
          edge: _ResizeEdge.top,
          cursor: SystemMouseCursors.resizeUp,
          left: ResizableOverlayFrame.cornerSize,
          top: 0,
          right: ResizableOverlayFrame.cornerSize,
          height: ResizableOverlayFrame.edgeWidth,
        ),
        // Bottom edge
        _buildHandle(
          edge: _ResizeEdge.bottom,
          cursor: SystemMouseCursors.resizeDown,
          left: ResizableOverlayFrame.cornerSize,
          bottom: 0,
          right: ResizableOverlayFrame.cornerSize,
          height: ResizableOverlayFrame.edgeWidth,
        ),
        // Left edge
        _buildHandle(
          edge: _ResizeEdge.left,
          cursor: SystemMouseCursors.resizeLeft,
          left: 0,
          top: ResizableOverlayFrame.cornerSize,
          bottom: ResizableOverlayFrame.cornerSize,
          width: ResizableOverlayFrame.edgeWidth,
        ),
        // Right edge
        _buildHandle(
          edge: _ResizeEdge.right,
          cursor: SystemMouseCursors.resizeRight,
          right: 0,
          top: ResizableOverlayFrame.cornerSize,
          bottom: ResizableOverlayFrame.cornerSize,
          width: ResizableOverlayFrame.edgeWidth,
        ),

        // ---- Corner handles ----
        // Top-left
        _buildHandle(
          edge: _ResizeEdge.topLeft,
          cursor: _cornerCursor(SystemMouseCursors.resizeUpLeftDownRight),
          left: 0,
          top: 0,
          width: ResizableOverlayFrame.cornerSize,
          height: ResizableOverlayFrame.cornerSize,
        ),
        // Top-right
        _buildHandle(
          edge: _ResizeEdge.topRight,
          cursor: _cornerCursor(SystemMouseCursors.resizeUpRightDownLeft),
          right: 0,
          top: 0,
          width: ResizableOverlayFrame.cornerSize,
          height: ResizableOverlayFrame.cornerSize,
        ),
        // Bottom-left
        _buildHandle(
          edge: _ResizeEdge.bottomLeft,
          cursor: _cornerCursor(SystemMouseCursors.resizeUpRightDownLeft),
          left: 0,
          bottom: 0,
          width: ResizableOverlayFrame.cornerSize,
          height: ResizableOverlayFrame.cornerSize,
        ),
        // Bottom-right
        _buildHandle(
          edge: _ResizeEdge.bottomRight,
          cursor: _cornerCursor(SystemMouseCursors.resizeUpLeftDownRight),
          right: 0,
          bottom: 0,
          width: ResizableOverlayFrame.cornerSize,
          height: ResizableOverlayFrame.cornerSize,
        ),
      ],
    );
  }

  /// Builds a single invisible resize handle positioned along an edge or corner.
  Widget _buildHandle({
    required _ResizeEdge edge,
    required MouseCursor cursor,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    // Corner handles use opaque hit-testing so they fully absorb pointer events
    // and prevent the underlying content's MouseRegion from overriding the
    // diagonal cursor.  Edge handles keep translucent so clicks pass through
    // to content beneath (only the thin strip along the edge needs to be
    // captured, not everything under it).
    final isCorner = edge == _ResizeEdge.topLeft ||
        edge == _ResizeEdge.topRight ||
        edge == _ResizeEdge.bottomLeft ||
        edge == _ResizeEdge.bottomRight;

    // On macOS, corner handles use native diagonal resize cursors pushed via
    // the platform channel. We determine the cursor type string once here.
    final nativeCursor = _isMacOS ? _nativeCursorType(edge) : null;

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        opaque: true,
        onEnter: nativeCursor != null
            ? (_) => NativeMacosCursor.setCursor(nativeCursor)
            : null,
        onExit: nativeCursor != null
            ? (_) => NativeMacosCursor.resetCursor()
            : null,
        child: GestureDetector(
          behavior: isCorner
              ? HitTestBehavior.opaque
              : HitTestBehavior.translucent,
          onPanStart: (details) {
            _dragStartGlobalPosition = details.globalPosition;
            _dragStartPosition = widget.position;
            _dragStartSize = widget.size;
            widget.onResizeStart?.call();
          },
          onPanUpdate: (details) {
            final startGlobal = _dragStartGlobalPosition;
            final startPos = _dragStartPosition;
            final startSize = _dragStartSize;
            if (startGlobal != null &&
                startPos != null &&
                startSize != null) {
              final totalDelta = details.globalPosition - startGlobal;
              _onDragAbsolute(edge, totalDelta, startPos, startSize);
            }
          },
          onPanEnd: (_) {
            _dragStartGlobalPosition = null;
            _dragStartPosition = null;
            _dragStartSize = null;
            widget.onResizeEnd?.call();
          },
          onPanCancel: () {
            _dragStartGlobalPosition = null;
            _dragStartPosition = null;
            _dragStartSize = null;
            widget.onResizeEnd?.call();
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Computes new geometry from the total mouse offset since drag start,
  /// applied to the original [startPos] and [startSize]. This avoids
  /// frame-by-frame delta accumulation that drifts when build() clamping
  /// modifies values between frames.
  void _onDragAbsolute(
    _ResizeEdge edge,
    Offset totalDelta,
    Offset startPos,
    Size startSize,
  ) {
    final minSize = widget.minSize;
    final screenSize = widget.screenSize;

    var newLeft = startPos.dx;
    var newTop = startPos.dy;
    var newWidth = startSize.width;
    var newHeight = startSize.height;

    switch (edge) {
      case _ResizeEdge.top:
        newTop += totalDelta.dy;
        newHeight -= totalDelta.dy;
      case _ResizeEdge.bottom:
        newHeight += totalDelta.dy;
      case _ResizeEdge.left:
        newLeft += totalDelta.dx;
        newWidth -= totalDelta.dx;
      case _ResizeEdge.right:
        newWidth += totalDelta.dx;
      case _ResizeEdge.topLeft:
        newLeft += totalDelta.dx;
        newWidth -= totalDelta.dx;
        newTop += totalDelta.dy;
        newHeight -= totalDelta.dy;
      case _ResizeEdge.topRight:
        newWidth += totalDelta.dx;
        newTop += totalDelta.dy;
        newHeight -= totalDelta.dy;
      case _ResizeEdge.bottomLeft:
        newLeft += totalDelta.dx;
        newWidth -= totalDelta.dx;
        newHeight += totalDelta.dy;
      case _ResizeEdge.bottomRight:
        newWidth += totalDelta.dx;
        newHeight += totalDelta.dy;
    }

    // Enforce minimum size.
    if (newWidth < minSize.width) {
      if (edge == _ResizeEdge.left ||
          edge == _ResizeEdge.topLeft ||
          edge == _ResizeEdge.bottomLeft) {
        newLeft = startPos.dx + startSize.width - minSize.width;
      }
      newWidth = minSize.width;
    }
    if (newHeight < minSize.height) {
      if (edge == _ResizeEdge.top ||
          edge == _ResizeEdge.topLeft ||
          edge == _ResizeEdge.topRight) {
        newTop = startPos.dy + startSize.height - minSize.height;
      }
      newHeight = minSize.height;
    }

    // Clamp to screen bounds.
    if (newLeft < 0) {
      if (edge == _ResizeEdge.left ||
          edge == _ResizeEdge.topLeft ||
          edge == _ResizeEdge.bottomLeft) {
        newWidth += newLeft;
        if (newWidth < minSize.width) newWidth = minSize.width;
      }
      newLeft = 0;
    }
    if (newTop < 0) {
      if (edge == _ResizeEdge.top ||
          edge == _ResizeEdge.topLeft ||
          edge == _ResizeEdge.topRight) {
        newHeight += newTop;
        if (newHeight < minSize.height) newHeight = minSize.height;
      }
      newTop = 0;
    }

    final maxWidth = screenSize.width - newLeft;
    final maxHeight = screenSize.height - newTop;
    if (newWidth > maxWidth) newWidth = maxWidth;
    if (newHeight > maxHeight) newHeight = maxHeight;
    if (newWidth < minSize.width) newWidth = minSize.width;
    if (newHeight < minSize.height) newHeight = minSize.height;

    widget.onResize(Offset(newLeft, newTop), Size(newWidth, newHeight));
  }
}
