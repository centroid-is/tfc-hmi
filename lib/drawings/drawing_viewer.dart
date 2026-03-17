import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart'
    if (dart.library.js_interop) '../core/pdfrx_stub.dart';

import '../widgets/searchable_pdf_viewer.dart';
import 'drawing_overlay.dart';

/// PDF viewer that bridges overlay providers to [SearchablePdfViewer].
///
/// Watches [activeDrawingPageProvider] and [activeDrawingHighlightProvider]
/// for AI-directed navigation and highlighting. Exposes the
/// [PdfTextSearcher] via [drawingTextSearcherProvider].
class DrawingViewer extends ConsumerStatefulWidget {
  const DrawingViewer({super.key, this.filePath, this.pdfBytes})
      : assert(filePath != null || pdfBytes != null,
            'Either filePath or pdfBytes must be provided');
  final String? filePath;
  final Uint8List? pdfBytes;

  @override
  ConsumerState<DrawingViewer> createState() => DrawingViewerState();
}

class DrawingViewerState extends ConsumerState<DrawingViewer> {
  @override
  void deactivate() {
    // Clear the searcher provider when the widget is removed from the tree.
    // Done in deactivate() rather than dispose() because ref is still usable
    // here but may throw "Cannot use ref after disposed" in dispose().
    ref.read(drawingTextSearcherProvider.notifier).state = null;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final targetPage = ref.watch(activeDrawingPageProvider);
    final highlightText = ref.watch(activeDrawingHighlightProvider);

    return SearchablePdfViewer(
      filePath: widget.filePath,
      pdfBytes: widget.pdfBytes,
      targetPage: targetPage,
      highlightText: highlightText,
      onSearcherCreated: (searcher) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(drawingTextSearcherProvider.notifier).state = searcher;
          }
        });
      },
    );
  }
}
