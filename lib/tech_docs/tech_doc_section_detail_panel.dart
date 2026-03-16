import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tech_doc.dart';
import '../widgets/searchable_pdf_viewer.dart';

/// Detail side panel shown when a document is selected.
///
/// Renders the PDF inline using [SearchablePdfViewer] with Cmd+F search.
class TechDocSectionDetailPanel extends ConsumerWidget {
  const TechDocSectionDetailPanel({super.key, required this.docId});

  final int docId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdfBytesAsync = ref.watch(techDocPdfBytesProvider(docId));
    final docListAsync = ref.watch(techDocListProvider);

    final docName = docListAsync.whenOrNull(
          data: (docs) => docs.where((d) => d.id == docId).firstOrNull?.name,
        ) ??
        'Document';

    return ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    docName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ref.read(selectedTechDocProvider.notifier).state = null;
                  },
                  tooltip: 'Close panel',
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // PDF viewer with Cmd+F search
          Expanded(
            child: pdfBytesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading PDF: $e',
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.fade,
                    maxLines: 5,
                  ),
                ),
              ),
              data: (bytes) {
                if (bytes == null) {
                  return const Center(
                    child: Text(
                      'PDF not available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return SearchablePdfViewer(
                  key: ValueKey('tech-doc-$docId'),
                  pdfBytes: bytes,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
