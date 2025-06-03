import 'package:flutter/material.dart';

class ZoomableCanvas extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final double aspectRatio;

  const ZoomableCanvas({
    Key? key,
    required this.child,
    this.minScale = 0.5,
    this.maxScale = 4.0,
    this.aspectRatio = 16 / 9,
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
                boundaryMargin: EdgeInsets.all(double.infinity),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
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
                    if (matrix == Matrix4.identity()) {
                      return const SizedBox.shrink();
                    }
                    return FloatingActionButton(
                      mini: true,
                      heroTag: null, // Allow multiple instances
                      backgroundColor: Theme.of(context).colorScheme.primary,
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
