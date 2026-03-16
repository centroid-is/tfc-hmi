import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'drawing_upload_service.dart';

/// Dialog widget for uploading electrical drawing PDFs.
///
/// Uses FilePicker to select a PDF file, shows a text field for the drawing
/// name (pre-filled from the filename), and calls [DrawingUploadService]
/// to perform the upload and text extraction.
class DrawingUploadDialog extends StatefulWidget {
  /// Creates a [DrawingUploadDialog].
  ///
  /// [assetKey] identifies the asset this drawing is associated with.
  /// [uploadService] is the service that handles the upload pipeline.
  const DrawingUploadDialog({
    super.key,
    required this.assetKey,
    required this.uploadService,
  });

  /// Asset key identifying the equipment this drawing is associated with.
  final String assetKey;

  /// Service for uploading and indexing drawings.
  final DrawingUploadService uploadService;

  @override
  State<DrawingUploadDialog> createState() => _DrawingUploadDialogState();
}

class _DrawingUploadDialogState extends State<DrawingUploadDialog> {
  final _nameController = TextEditingController();
  String? _selectedFilePath;
  bool _isUploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'Select Drawing PDF',
    );

    if (pick != null && pick.files.single.path != null) {
      setState(() {
        _selectedFilePath = pick.files.single.path!;
        // Pre-fill drawing name from filename without extension
        if (_nameController.text.isEmpty) {
          _nameController.text =
              p.basenameWithoutExtension(_selectedFilePath!);
        }
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedFilePath == null || _nameController.text.trim().isEmpty) {
      return;
    }

    setState(() => _isUploading = true);

    try {
      await widget.uploadService.uploadDrawing(
        sourceFilePath: _selectedFilePath!,
        assetKey: widget.assetKey,
        drawingName: _nameController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Drawing'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(
                _selectedFilePath != null
                    ? p.basename(_selectedFilePath!)
                    : 'Select PDF file...',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Drawing Name',
                hintText: 'e.g. Panel-A Main Wiring',
                border: OutlineInputBorder(),
              ),
              enabled: !_isUploading,
            ),
            const SizedBox(height: 8),
            Text(
              'Asset: ${widget.assetKey}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(
                child: Text('Extracting text and indexing...'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isUploading || _selectedFilePath == null
              ? null
              : _upload,
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
