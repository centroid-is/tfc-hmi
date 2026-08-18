import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';

class ZoomableCanvas extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final double aspectRatio;
  final bool panEnabled;
  final bool scaleEnabled;

  const ZoomableCanvas({
    Key? key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 4.0,
    this.aspectRatio = 16 / 9,
    this.panEnabled = true,
    this.scaleEnabled = true,
  }) : super(key: key);

  @override
  State<ZoomableCanvas> createState() => _ZoomableCanvasState();
}

class _ZoomableCanvasState extends State<ZoomableCanvas> {
  final TransformationController _transformationController =
      TransformationController();

  /// True while a middle-mouse-button drag is in flight. The middle button
  /// always pans, regardless of [ZoomableCanvas.panEnabled]: the page editor
  /// reserves plain drags for its marquee and only enables pan while Space is
  /// held, but a middle-button drag has no other meaning on the canvas.
  /// `InteractiveViewer` consults `panEnabled` on every update, not just at
  /// the start of a gesture, so flipping it on the button's own pointer-down
  /// catches that same drag.
  bool _middleButtonPanning = false;

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRect(
          child: Stack(
            children: [
              Listener(
                onPointerDown: (event) {
                  if (event.buttons & kMiddleMouseButton != 0) {
                    setState(() => _middleButtonPanning = true);
                  }
                },
                onPointerUp: (event) {
                  if (_middleButtonPanning) {
                    setState(() => _middleButtonPanning = false);
                  }
                },
                onPointerCancel: (event) {
                  if (_middleButtonPanning) {
                    setState(() => _middleButtonPanning = false);
                  }
                },
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: widget.minScale,
                  maxScale: widget.maxScale,
                  boundaryMargin: EdgeInsets.zero,
                  panEnabled: widget.panEnabled || _middleButtonPanning,
                  scaleEnabled: widget.scaleEnabled,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: colorScheme.surface,
                      ),
                      widget.child,
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _transformationController,
                  builder: (context, matrix, child) {
                    final scale = matrix.getMaxScaleOnAxis();
                    if (scale <= 1.0) {
                      return const SizedBox.shrink();
                    }
                    return FloatingActionButton(
                      mini: true,
                      heroTag: null,
                      // Zoomed in is the only state where panning is possible
                      // — at 1:1 the child exactly fills the viewport — so
                      // this is where the page editor's pan gestures are worth
                      // mentioning, and this button is the only chrome that
                      // appears exactly then.
                      tooltip:
                          'Reset zoom — middle-click drag or Space+drag to pan',
                      backgroundColor: colorScheme.primary,
                      onPressed: _resetZoom,
                      child:
                          const Icon(Icons.zoom_out_map, color: Colors.white),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
