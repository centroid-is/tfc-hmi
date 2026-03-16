import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/page_creator/assets/button.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/drawings/drawing_overlay.dart';
import 'package:tfc/providers/tech_doc.dart';
import 'package:tfc/tech_docs/tech_doc_picker.dart';

part 'drawing_viewer.g.dart';

@JsonSerializable()
class DrawingViewerConfig extends BaseAsset {
  @override
  String get displayName => 'Drawing Viewer';
  @override
  String get category => 'Application';

  String drawingName;
  String filePath;
  int startPage;

  DrawingViewerConfig({
    required this.drawingName,
    required this.filePath,
    this.startPage = 1,
  });

  DrawingViewerConfig.preview()
      : drawingName = '',
        filePath = '',
        startPage = 1;

  factory DrawingViewerConfig.fromJson(Map<String, dynamic> json) =>
      _$DrawingViewerConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$DrawingViewerConfigToJson(this);

  @override
  Widget build(BuildContext context) => DrawingViewerButton(config: this);

  @override
  Widget configure(BuildContext context) =>
      _DrawingViewerConfigEditor(config: this);
}

class DrawingViewerButton extends ConsumerStatefulWidget {
  final DrawingViewerConfig config;
  const DrawingViewerButton({super.key, required this.config});

  @override
  ConsumerState<DrawingViewerButton> createState() =>
      _DrawingViewerButtonState();
}

class _DrawingViewerButtonState extends ConsumerState<DrawingViewerButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed != value) {
      setState(() => _isPressed = value);
    }
  }

  Future<void> _openDrawing() async {
    final config = widget.config;
    final docId = config.techDocId;
    if (docId != null) {
      // Tech doc mode: load PDF bytes from knowledge base.
      final bytes = await ref.read(techDocPdfBytesProvider(docId).future);
      if (bytes == null) return;
      ref.read(activeDrawingTitleProvider.notifier).state =
          config.drawingName.isNotEmpty ? config.drawingName : 'Document';
      ref.read(activeDrawingBytesProvider.notifier).state = bytes;
      ref.read(activeDrawingPathProvider.notifier).state = null;
      ref.read(activeDrawingPageProvider.notifier).state = config.startPage;
      ref.read(activeDrawingHighlightProvider.notifier).state = null;
      ref.read(drawingVisibleProvider.notifier).state = true;
    } else if (config.filePath.isNotEmpty) {
      // Legacy file path mode for backward compatibility.
      ref.read(activeDrawingTitleProvider.notifier).state =
          config.drawingName.isNotEmpty
              ? config.drawingName
              : 'Electrical Drawing';
      ref.read(activeDrawingBytesProvider.notifier).state = null;
      ref.read(activeDrawingPathProvider.notifier).state = config.filePath;
      ref.read(activeDrawingPageProvider.notifier).state = config.startPage;
      ref.read(activeDrawingHighlightProvider.notifier).state = null;
      ref.read(drawingVisibleProvider.notifier).state = true;
    }
    // Neither techDocId nor filePath set -- no-op.
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const RoundedRectangleBorder(),
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) {
          _setPressed(false);
          _openDrawing();
        },
        onTapCancel: () => _setPressed(false),
        child: CustomPaint(
          painter: ButtonPainter(
            color: Theme.of(context).colorScheme.primary,
            isPressed: _isPressed,
            buttonType: ButtonType.square,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    Text(
                      widget.config.drawingName.isNotEmpty
                          ? widget.config.drawingName
                          : 'Drawing',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawingViewerConfigEditor extends ConsumerStatefulWidget {
  final DrawingViewerConfig config;
  const _DrawingViewerConfigEditor({required this.config});

  @override
  ConsumerState<_DrawingViewerConfigEditor> createState() =>
      _DrawingViewerConfigEditorState();
}

class _DrawingViewerConfigEditorState
    extends ConsumerState<_DrawingViewerConfigEditor> {
  late TextEditingController _labelController;
  late TextEditingController _startPageController;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.config.drawingName);
    _startPageController =
        TextEditingController(text: widget.config.startPage.toString());
  }

  @override
  void dispose() {
    _labelController.dispose();
    _startPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TechDocPicker(
            selectedDocId: widget.config.techDocId,
            onChanged: (id) {
              setState(() {
                widget.config.techDocId = id;
              });
            },
          ),
          const SizedBox(height: 16),
          Text('Button Text', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              hintText: 'Label shown on the button',
            ),
            onChanged: (val) {
              setState(() {
                widget.config.drawingName = val;
              });
            },
          ),
          const SizedBox(height: 16),
          Text('Start Page', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _startPageController,
            keyboardType: TextInputType.number,
            onChanged: (val) {
              setState(() {
                widget.config.startPage = int.tryParse(val) ?? 1;
              });
            },
          ),
          const SizedBox(height: 10),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
        ],
      ),
    );
  }
}
