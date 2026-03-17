/// Web stub for package:pdfrx/pdfrx.dart
///
/// Provides minimal type stubs so files that import pdfrx can compile on web.
/// None of these classes are functional — PDF viewing is not supported on web.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// PdfViewerController
// ---------------------------------------------------------------------------

class PdfViewerController extends ChangeNotifier {
  bool get isReady => false;
  void goToPage({required int pageNumber, Duration? duration}) {}
  void zoomUp() {}
  void zoomDown() {}
}

// ---------------------------------------------------------------------------
// PdfTextSearcher
// ---------------------------------------------------------------------------

class PdfTextSearcher extends ChangeNotifier {
  PdfTextSearcher(PdfViewerController controller);

  List<dynamic> get matches => [];
  int? get currentIndex => null;
  bool get isSearching => false;

  void startTextSearch(String text, {bool caseInsensitive = false}) {}
  void resetTextSearch() {}
  void goToNextMatch() {}
  void goToPrevMatch() {}

  PdfPagePaintCallback get pageTextMatchPaintCallback =>
      (Canvas canvas, Rect pageRect, PdfPage page) {};

  void dispose() {}
}

// ---------------------------------------------------------------------------
// PdfViewerParams
// ---------------------------------------------------------------------------

typedef PdfPagePaintCallback = void Function(
    Canvas canvas, Rect pageRect, PdfPage page);

class PdfViewerParams {
  final List<PdfPagePaintCallback>? pagePaintCallbacks;
  final List<Widget> Function(
      BuildContext context, Size size, void Function(dynamic)? handleLinkTap)? viewerOverlayBuilder;
  final void Function(PdfDocument document, PdfViewerController controller)?
      onViewerReady;
  final void Function(int? pageNumber)? onPageChanged;
  final Widget Function(
      BuildContext context, int bytesDownloaded, int? totalBytes)? loadingBannerBuilder;

  const PdfViewerParams({
    this.pagePaintCallbacks,
    this.viewerOverlayBuilder,
    this.onViewerReady,
    this.onPageChanged,
    this.loadingBannerBuilder,
  });
}

// ---------------------------------------------------------------------------
// PdfViewerScrollThumb
// ---------------------------------------------------------------------------

class PdfViewerScrollThumb extends StatelessWidget {
  final PdfViewerController controller;
  final ScrollbarOrientation orientation;
  final Size thumbSize;
  final double margin;
  final Widget Function(BuildContext context, Size thumbSize, int? pageNumber,
      PdfViewerController controller)? thumbBuilder;

  const PdfViewerScrollThumb({
    super.key,
    required this.controller,
    this.orientation = ScrollbarOrientation.right,
    this.thumbSize = const Size(40, 25),
    this.margin = 2,
    this.thumbBuilder,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// PdfViewer
// ---------------------------------------------------------------------------

class PdfViewer extends StatelessWidget {
  const PdfViewer._();

  static Widget file(
    String filePath, {
    Key? key,
    PdfViewerController? controller,
    PdfViewerParams? params,
    int initialPageNumber = 1,
  }) =>
      const SizedBox.shrink();

  static Widget data(
    Uint8List data, {
    Key? key,
    String? sourceName,
    PdfViewerController? controller,
    PdfViewerParams? params,
    int initialPageNumber = 1,
  }) =>
      const SizedBox.shrink();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// PdfDocument
// ---------------------------------------------------------------------------

class PdfPage {
  final int pageNumber;
  PdfPage({required this.pageNumber});
}

class PdfDocument {
  final List<PdfPage> pages;
  PdfDocument._() : pages = [];

  static Future<PdfDocument> openFile(String filePath) async =>
      throw UnsupportedError('PDF not available on web');

  static Future<PdfDocument> openData(Uint8List data) async =>
      throw UnsupportedError('PDF not available on web');

  Future<PdfPageRawText> getPageRawText(int pageIndex) async =>
      throw UnsupportedError('PDF not available on web');

  void dispose() {}
}

// ---------------------------------------------------------------------------
// PdfPageRawText
// ---------------------------------------------------------------------------

class PdfPageRawText {
  final String fullText;
  final List<PdfPageRawTextChar> chars;

  PdfPageRawText({required this.fullText, required this.chars});
}

class PdfPageRawTextChar {
  final String char;
  final Rect bounds;

  PdfPageRawTextChar({required this.char, required this.bounds});
}
