import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// A self-contained PDF viewer with built-in Cmd+F / Ctrl+F search.
///
/// Supports file path or byte data. Keyboard shortcuts:
/// - Cmd+F (macOS) / Ctrl+F: Toggle search bar
/// - Escape: Close search bar
/// - Enter: Next match
/// - Cmd+scroll wheel (macOS) / Ctrl+scroll wheel: Zoom in/out
///
/// Note: Ctrl+scroll zoom is handled natively by pdfrx on all platforms.
/// Cmd+scroll zoom on macOS is handled by a [Listener] wrapper since
/// pdfrx only checks for Ctrl, not Meta/Cmd.
///
/// Optional [targetPage] and [highlightText] support AI-directed
/// navigation and highlighting (used by [DrawingOverlay]).
class SearchablePdfViewer extends StatefulWidget {
  const SearchablePdfViewer({
    super.key,
    this.filePath,
    this.pdfBytes,
    this.targetPage,
    this.highlightText,
    this.onPageChanged,
    this.onSearcherCreated,
    this.showZoomControls = true,
  }) : assert(filePath != null || pdfBytes != null,
            'Either filePath or pdfBytes must be provided');

  final String? filePath;
  final Uint8List? pdfBytes;

  /// AI-directed page navigation (1-based).
  final int? targetPage;

  /// AI-directed text highlighting.
  final String? highlightText;

  /// Called when the visible page changes.
  final ValueChanged<int>? onPageChanged;

  /// Called when the [PdfTextSearcher] is created (for external match access).
  final ValueChanged<PdfTextSearcher>? onSearcherCreated;

  /// Whether to show zoom in/out controls below the PDF viewer.
  final bool showZoomControls;

  @override
  State<SearchablePdfViewer> createState() => SearchablePdfViewerState();
}

/// State exposed for testing (search visibility, toggle).
class SearchablePdfViewerState extends State<SearchablePdfViewer> {
  final _controller = PdfViewerController();
  PdfTextSearcher? _textSearcher;

  bool _searchVisible = false;
  String _searchQuery = '';
  int _currentPage = 1;
  int _pageCount = 0;
  bool _scrollThumbDragging = false;
  String? _lastHighlightText;
  String _lastSearchQuery = '';
  int? _lastTargetPage;

  /// Whether the search bar is currently visible.
  bool get searchVisible => _searchVisible;

  /// Toggle the search bar visibility.
  void toggleSearch() {
    setState(() => _searchVisible = !_searchVisible);
  }

  PdfTextSearcher _getOrCreateSearcher() {
    if (_textSearcher == null) {
      _textSearcher = PdfTextSearcher(_controller);
      widget.onSearcherCreated?.call(_textSearcher!);
    }
    return _textSearcher!;
  }

  @override
  void dispose() {
    _textSearcher?.dispose();
    super.dispose();
  }

  /// Handles Cmd+scroll wheel zoom on macOS.
  ///
  /// On macOS, users expect Cmd+scroll to zoom. The pdfrx package only
  /// checks for Ctrl+scroll (via [HardwareKeyboard.instance.isControlPressed]).
  /// This handler fills the gap by detecting Meta (Cmd) + scroll on macOS
  /// and calling [PdfViewerController.zoomUp]/[zoomDown] accordingly.
  ///
  /// On Linux/Windows, Ctrl+scroll is already handled by pdfrx natively,
  /// so this handler is a no-op when Meta is not pressed.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_controller.isReady) return;

    // On macOS, Cmd (Meta) + scroll wheel = zoom.
    // On all platforms, Ctrl + scroll is already handled by pdfrx.
    final isMacOsCmdScroll =
        defaultTargetPlatform == TargetPlatform.macOS && HardwareKeyboard.instance.isMetaPressed;

    if (!isMacOsCmdScroll) return;

    // Scroll up (negative dy) = zoom in, scroll down (positive dy) = zoom out.
    if (event.scrollDelta.dy < 0) {
      _controller.zoomUp();
    } else if (event.scrollDelta.dy > 0) {
      _controller.zoomDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle targetPage changes.
    final targetPage = widget.targetPage;
    if (targetPage != null && targetPage != _lastTargetPage) {
      _lastTargetPage = targetPage;
      if (targetPage != _currentPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controller.isReady) return;
          _controller.goToPage(pageNumber: targetPage, duration: Duration.zero);
          _currentPage = targetPage;
        });
      }
    }

    // Handle AI-directed highlight text changes.
    final highlightText = widget.highlightText;
    if (highlightText != _lastHighlightText) {
      _lastHighlightText = highlightText;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.isReady) return;
        final searcher = _getOrCreateSearcher();
        if (highlightText != null && highlightText.isNotEmpty) {
          searcher.startTextSearch(highlightText, caseInsensitive: true);
        } else if (_searchQuery.isEmpty) {
          searcher.resetTextSearch();
        }
      });
    }

    // Handle user search query changes.
    if (_searchQuery != _lastSearchQuery) {
      _lastSearchQuery = _searchQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.isReady) return;
        final searcher = _getOrCreateSearcher();
        if (_searchQuery.isNotEmpty) {
          searcher.startTextSearch(_searchQuery, caseInsensitive: true);
        } else if (highlightText == null || highlightText.isEmpty) {
          searcher.resetTextSearch();
        }
      });
    }

    final params = PdfViewerParams(
      pagePaintCallbacks: _textSearcher != null
          ? [_textSearcher!.pageTextMatchPaintCallback]
          : null,
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        PdfViewerScrollThumb(
          key: const ValueKey<String>('pdf-scroll-thumb'),
          controller: _controller,
          orientation: ScrollbarOrientation.right,
          thumbSize: const Size(28, 48),
          margin: 0,
          thumbBuilder: (context, thumbSize, pageNumber, controller) {
            return Listener(
              key: const ValueKey<String>('pdf-scroll-thumb-listener'),
              onPointerDown: (_) {
                if (!_scrollThumbDragging) {
                  setState(() => _scrollThumbDragging = true);
                }
              },
              onPointerUp: (_) {
                if (_scrollThumbDragging) {
                  setState(() => _scrollThumbDragging = false);
                }
              },
              onPointerCancel: (_) {
                if (_scrollThumbDragging) {
                  setState(() => _scrollThumbDragging = false);
                }
              },
              child: _PdfScrollThumbWidget(
                thumbSize: thumbSize,
                pageNumber: pageNumber,
                pageCount: _pageCount,
                isDragging: _scrollThumbDragging,
              ),
            );
          },
        ),
      ],
      onViewerReady: (document, controller) {
        if (mounted) {
          setState(() {
            _pageCount = document.pages.length;
            // If a target page was requested but the controller wasn't ready
            // when the post-frame callback fired, navigate now.
            final tp = widget.targetPage;
            if (tp != null && tp != _currentPage) {
              _controller.goToPage(
                  pageNumber: tp, duration: Duration.zero);
              _currentPage = tp;
            }
          });
        }
      },
      onPageChanged: (pageNumber) {
        if (pageNumber != null) {
          setState(() => _currentPage = pageNumber);
          widget.onPageChanged?.call(pageNumber);
        }
      },
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    Widget pdfViewer;
    if (widget.pdfBytes != null) {
      pdfViewer = PdfViewer.data(
        widget.pdfBytes!,
        sourceName: 'pdf-viewer',
        controller: _controller,
        params: params,
        initialPageNumber: widget.targetPage ?? 1,
      );
    } else {
      pdfViewer = PdfViewer.file(
        widget.filePath!,
        controller: _controller,
        params: params,
        initialPageNumber: widget.targetPage ?? 1,
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyF &&
            (HardwareKeyboard.instance.isMetaPressed && defaultTargetPlatform == TargetPlatform.macOS ||
                HardwareKeyboard.instance.isControlPressed &&
                    defaultTargetPlatform != TargetPlatform.macOS)) {
          setState(() => _searchVisible = !_searchVisible);
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _searchVisible) {
          setState(() {
            _searchVisible = false;
            _searchQuery = '';
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          if (_searchVisible)
            _PdfSearchBar(
              searcher: _textSearcher,
              onQueryChanged: (query) {
                setState(() => _searchQuery = query);
              },
              onClose: () {
                setState(() {
                  _searchVisible = false;
                  _searchQuery = '';
                });
              },
            ),
          Expanded(
            child: Stack(
              children: [
                Listener(
                  key: const ValueKey<String>('pdf-scroll-zoom-listener'),
                  onPointerSignal: _handlePointerSignal,
                  child: pdfViewer,
                ),
                ],
            ),
          ),
          if (widget.showZoomControls)
            _PdfZoomToolbar(
              controller: _controller,
              currentPage: _currentPage,
              pageCount: _pageCount,
              onPreviousPage: () {
                if (_controller.isReady && _currentPage > 1) {
                  _controller.goToPage(pageNumber: _currentPage - 1);
                }
              },
              onNextPage: () {
                if (_controller.isReady && _currentPage < _pageCount) {
                  _controller.goToPage(pageNumber: _currentPage + 1);
                }
              },
            ),
        ],
      ),
    );
  }
}

/// Compact search bar for PDF text search.
class _PdfSearchBar extends StatefulWidget {
  const _PdfSearchBar({
    required this.searcher,
    required this.onQueryChanged,
    required this.onClose,
  });

  final PdfTextSearcher? searcher;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClose;

  @override
  State<_PdfSearchBar> createState() => _PdfSearchBarState();
}

class _PdfSearchBarState extends State<_PdfSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searcher = widget.searcher;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search in document...',
                hintStyle: TextStyle(fontSize: 13),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: widget.onQueryChanged,
              onSubmitted: (_) => searcher?.goToNextMatch(),
            ),
          ),
          if (searcher != null) _SearchMatchCount(searcher: searcher),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: () => searcher?.goToPrevMatch(),
            tooltip: 'Previous match',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            onPressed: () => searcher?.goToNextMatch(),
            tooltip: 'Next match',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              _controller.clear();
              widget.onQueryChanged('');
              widget.onClose();
            },
            tooltip: 'Close search',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

/// Displays the current match index and total count.
class _SearchMatchCount extends StatelessWidget {
  const _SearchMatchCount({required this.searcher});

  final PdfTextSearcher searcher;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: searcher,
      builder: (context, _) {
        final count = searcher.matches.length;
        final current = searcher.currentIndex;

        if (count == 0 && !searcher.isSearching) {
          return const SizedBox.shrink();
        }

        final text = searcher.isSearching
            ? 'Searching...'
            : current != null
                ? '${current + 1}/$count'
                : '$count matches';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: count == 0 && !searcher.isSearching
                  ? Colors.red
                  : Colors.grey,
            ),
          ),
        );
      },
    );
  }
}


/// Visual thumb widget for the PDF scroll position indicator.
///
/// Shows a subtle rounded handle on the right edge of the PDF viewer.
/// When dragging, displays the current page number prominently via
/// a floating label to the left of the thumb.
class _PdfScrollThumbWidget extends StatelessWidget {
  const _PdfScrollThumbWidget({
    required this.thumbSize,
    required this.pageNumber,
    required this.pageCount,
    required this.isDragging,
  });

  final Size thumbSize;
  final int? pageNumber;
  final int pageCount;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Thumb colors — subtle when idle, more visible when dragging.
    final thumbColor = isDragging
        ? (isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.4))
        : (isDark ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.2));

    final labelBg = isDark
        ? Colors.grey.shade800.withOpacity(0.95)
        : Colors.grey.shade700.withOpacity(0.95);

    return SizedBox(
      width: thumbSize.width,
      height: thumbSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The thumb handle itself — a thin rounded pill.
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: isDragging ? 8 : 6,
                height: isDragging ? thumbSize.height : thumbSize.height * 0.7,
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),

          // Floating page label — shown only while dragging.
          if (isDragging && pageNumber != null)
            Positioned(
              right: thumbSize.width + 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: labelBg,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    '$pageNumber / $pageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact toolbar with zoom controls and page navigation.
class _PdfZoomToolbar extends StatelessWidget {
  const _PdfZoomToolbar({
    required this.controller,
    required this.currentPage,
    required this.pageCount,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final PdfViewerController controller;
  final int currentPage;
  final int pageCount;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimColor = theme.colorScheme.onSurfaceVariant;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zoom out
          IconButton(
            key: const ValueKey<String>('pdf-zoom-out'),
            icon: const Icon(Icons.remove, size: 18),
            onPressed: () {
              if (controller.isReady) {
                controller.zoomDown();
              }
            },
            tooltip: 'Zoom out',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          // Zoom in
          IconButton(
            key: const ValueKey<String>('pdf-zoom-in'),
            icon: const Icon(Icons.add, size: 18),
            onPressed: () {
              if (controller.isReady) {
                controller.zoomUp();
              }
            },
            tooltip: 'Zoom in',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          // Divider between zoom and page nav
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              height: 18,
              child: VerticalDivider(width: 1, color: theme.dividerColor),
            ),
          ),
          // Previous page
          IconButton(
            key: const ValueKey<String>('pdf-page-prev'),
            icon: Icon(Icons.keyboard_arrow_up, size: 18, color: currentPage > 1 ? null : dimColor.withOpacity(0.3)),
            onPressed: currentPage > 1 ? onPreviousPage : null,
            tooltip: 'Previous page',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
          ),
          // Page indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              pageCount > 0 ? '$currentPage / $pageCount' : '–',
              style: TextStyle(
                fontSize: 12,
                color: dimColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // Next page
          IconButton(
            key: const ValueKey<String>('pdf-page-next'),
            icon: Icon(Icons.keyboard_arrow_down, size: 18, color: currentPage < pageCount ? null : dimColor.withOpacity(0.3)),
            onPressed: currentPage < pageCount ? onNextPage : null,
            tooltip: 'Next page',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
