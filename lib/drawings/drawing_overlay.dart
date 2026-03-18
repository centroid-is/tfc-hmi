import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../widgets/resizable_overlay_frame.dart';
import 'drawing_viewer.dart';

/// Provider controlling drawing overlay visibility.
final drawingVisibleProvider = StateProvider<bool>((ref) => false);

/// Provider for the currently displayed drawing file path.
final activeDrawingPathProvider = StateProvider<String?>((ref) => null);

/// Provider for the target page number to navigate to (1-based).
final activeDrawingPageProvider = StateProvider<int>((ref) => 1);

/// Provider for highlight text to find on the active page.
final activeDrawingHighlightProvider = StateProvider<String?>((ref) => null);

/// Provider for PDF bytes to display (alternative to file path for blob storage).
///
/// When non-null, the DrawingViewer uses PdfViewer.data() instead of
/// PdfViewer.file(). Set by tech doc library when opening blob-stored PDFs.
final activeDrawingBytesProvider = StateProvider<Uint8List?>((ref) => null);

/// Provider for the overlay title (changes based on what's being viewed).
final activeDrawingTitleProvider =
    StateProvider<String>((ref) => 'Electrical Drawing');

/// Provider exposing the active PdfTextSearcher from the DrawingViewer.
///
/// Set by DrawingViewerState when the searcher is created; cleared on dispose.
final drawingTextSearcherProvider =
    StateProvider<PdfTextSearcher?>((ref) => null);

/// A floating, draggable, resizable drawing overlay window.
///
/// Positioned above the main HMI content (not inside BaseScaffold).
/// Contains the [DrawingViewer] with drag and resize functionality.
/// Follows the exact same pattern as [ChatOverlay] from Phase 5.
class DrawingOverlay extends ConsumerStatefulWidget {
  const DrawingOverlay({super.key});

  @override
  ConsumerState<DrawingOverlay> createState() => DrawingOverlayState();
}

/// Visible for testing to allow access to position/size.
class DrawingOverlayState extends ConsumerState<DrawingOverlay> {
  /// Current position of the overlay (top-left corner).
  Offset position = const Offset(-1, -1); // sentinel for uninitialized
  bool _initialized = false;

  /// Current size of the overlay.
  /// Initialized to zero; set to a window-relative size on first build.
  Size size = Size.zero;

  /// Minimum allowed size.
  static const Size minSize = Size(400, 500);

  /// Cached screen size from the latest build, used by gesture handlers.
  Size _screenSize = Size.zero;

  /// True while a resize drag gesture is active. When true, the content is
  /// frozen at [_preResizeSize] inside a [ClipRect] so the expensive
  /// PdfViewer does not re-layout on every frame.
  bool _isResizing = false;

  /// The overlay size captured at the moment a resize drag begins. Used to
  /// keep the content at a fixed layout size during the drag.
  Size? _preResizeSize;

  /// Cached content widget — rebuilt only when content dependencies change
  /// (active drawing path/bytes), NOT on position/size changes during
  /// drag/resize.
  Widget? _cachedContent;

  /// Clamps [position] so the overlay stays fully within the screen.
  void _clampPosition() {
    final maxX = (_screenSize.width - size.width).clamp(0.0, double.infinity);
    final maxY = (_screenSize.height - size.height).clamp(0.0, double.infinity);
    position = Offset(
      position.dx.clamp(0.0, maxX),
      position.dy.clamp(0.0, maxY),
    );
  }

  /// Called by [_DrawingTitleBar] when the title bar is dragged.
  void handleDrag(Offset delta) {
    setState(() {
      position += delta;
      _clampPosition();
    });
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.sizeOf(context);

    // On first build compute size as 50% width × 70% height of the window,
    // clamped to minSize, then position bottom-left with an 80px margin.
    // (opposite side from ChatOverlay which defaults to bottom-right)
    if (!_initialized) {
      final w = (_screenSize.width * 0.50).clamp(minSize.width, double.infinity);
      final h = (_screenSize.height * 0.70).clamp(minSize.height, double.infinity);
      size = Size(w, h);
      position = Offset(
        80,
        _screenSize.height - size.height - 80,
      );
      _initialized = true;
    }

    // On every build, clamp size so it never exceeds the current window
    // (e.g. after the user resizes the macOS window smaller).
    // Size only shrinks here — it does not grow back automatically.
    const margin = 16.0;
    final maxW = (_screenSize.width - margin).clamp(minSize.width, double.infinity);
    final maxH = (_screenSize.height - margin).clamp(minSize.height, double.infinity);
    final clampedW = size.width.clamp(minSize.width, maxW);
    final clampedH = size.height.clamp(minSize.height, maxH);

    // Early-out: skip state mutation if clamped values match current.
    if (clampedW != size.width || clampedH != size.height) {
      size = Size(clampedW, clampedH);
    }
    // Clamp position so the overlay stays fully on-screen after size change.
    _clampPosition();

    // Cache the content widget so it is reused across position/size-only
    // rebuilds (drag/resize). Flutter's element tree reuses the subtree.
    _cachedContent ??= const _DrawingOverlayContent(
      key: ValueKey('drawing-content'),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: ResizableOverlayFrame(
          position: position,
          size: size,
          minSize: minSize,
          screenSize: _screenSize,
          onResizeStart: () {
            setState(() {
              _isResizing = true;
              _preResizeSize = size;
            });
          },
          onResizeEnd: () {
            setState(() {
              _isResizing = false;
              _preResizeSize = null;
            });
          },
          onResize: (newPosition, newSize) {
            setState(() {
              position = newPosition;
              size = newSize;
            });
          },
          child: RepaintBoundary(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // Navigator wraps the ENTIRE overlay content (title bar +
                // viewer) so that every widget — including IconButton
                // tooltips in SearchablePdfViewer — has a
                // Navigator/Overlay ancestor.  The overlay sits inside
                // MaterialApp.builder, which is *above* the app Navigator.
                //
                // During a resize drag, freeze the content at its
                // pre-resize size so the PdfViewer does not re-layout on
                // every frame. The outer container still tracks the drag,
                // so the user sees the window edges moving. When the drag
                // ends the content snaps to the final size.
                child: _isResizing && _preResizeSize != null
                    ? ClipRect(
                        child: SizedBox(
                          width: _preResizeSize!.width,
                          height: _preResizeSize!.height,
                          child: _cachedContent!,
                        ),
                      )
                    : _cachedContent!,
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// The heavy content subtree of the drawing overlay (Navigator + title bar +
/// DrawingViewer). Extracted as a separate [ConsumerWidget] so that
/// position/size-only changes in [DrawingOverlayState] (drag, resize, window
/// resize clamping) do NOT rebuild this subtree.
class _DrawingOverlayContent extends ConsumerWidget {
  const _DrawingOverlayContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawingPath = ref.watch(activeDrawingPathProvider);
    final drawingBytes = ref.watch(activeDrawingBytesProvider);

    // Determine the viewer widget: prefer bytes over path.
    // ValueKey ensures switching documents creates a new widget (fresh controller).
    Widget viewerWidget;
    if (drawingBytes != null) {
      viewerWidget = DrawingViewer(
        key: ValueKey(drawingBytes.hashCode),
        pdfBytes: drawingBytes,
      );
    } else if (drawingPath != null) {
      viewerWidget = DrawingViewer(
        key: ValueKey(drawingPath),
        filePath: drawingPath,
      );
    } else {
      viewerWidget = const Center(
        child: Text(
          'No drawing loaded',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return HeroControllerScope.none(
      child: Navigator(
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          pageBuilder: (innerContext, __, ___) => Column(
            children: [
              const _DrawingTitleBar(
                key: ValueKey('drawing-title-bar'),
              ),
              Expanded(child: viewerWidget),
            ],
          ),
        ),
      ),
    );
  }
}

/// The draggable title bar for [DrawingOverlay], extracted so it can
/// independently rebuild when provider state changes without coupling to
/// position/size state.
class _DrawingTitleBar extends ConsumerWidget {
  const _DrawingTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onPanUpdate: (details) {
        context.findAncestorStateOfType<DrawingOverlayState>()
            ?.handleDrag(details.delta);
      },
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(
              Icons.electrical_services,
              size: 20,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ref.watch(activeDrawingTitleProvider),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('drawing-close-button'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                ref.read(drawingVisibleProvider.notifier).state = false;
              },
              tooltip: null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
