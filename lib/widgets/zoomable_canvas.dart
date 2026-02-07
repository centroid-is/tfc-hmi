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
              InteractiveViewer(
                transformationController: _transformationController,
                minScale: widget.minScale,
                maxScale: widget.maxScale,
                boundaryMargin: EdgeInsets.zero,
                panEnabled: widget.panEnabled,
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
                      backgroundColor: colorScheme.primary,
                      onPressed: _resetZoom,
                      child: const Icon(Icons.zoom_out_map,
                          color: Colors.white),
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
