import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'common.dart';
import '../../providers/state_man.dart';

part 'image_feed.g.dart';

// ---------------------------------------------------------------------------
// Data model for a single image entry in the feed
// ---------------------------------------------------------------------------

class ImageEntry {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String label;
  final double confidence;
  final int latencyMs;
  final DateTime timestamp;

  ImageEntry({
    this.imageBytes,
    this.imageUrl,
    required this.label,
    required this.confidence,
    required this.latencyMs,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// ImageFeedConfig — asset config
// ---------------------------------------------------------------------------

@JsonSerializable(explicitToJson: true)
class ImageFeedConfig extends BaseAsset {
  @override
  String get displayName => 'Image Feed';
  @override
  String get category => 'Monitoring';

  String key;

  @JsonKey(name: 'control_key')
  String? controlKey;

  @JsonKey(name: 'max_images', defaultValue: 9)
  int maxImages;

  @JsonKey(name: 'grid_columns', defaultValue: 3)
  int gridColumns;

  @JsonKey(name: 'show_confidence', defaultValue: true)
  bool showConfidence;

  @JsonKey(name: 'show_label', defaultValue: true)
  bool showLabel;

  @JsonKey(name: 'show_new_badge', defaultValue: true)
  bool showNewBadge;

  ImageFeedConfig({
    required this.key,
    this.controlKey,
    this.maxImages = 9,
    this.gridColumns = 3,
    this.showConfidence = true,
    this.showLabel = true,
    this.showNewBadge = true,
  });

  ImageFeedConfig.preview()
      : key = 'Image Feed preview',
        controlKey = null,
        maxImages = 9,
        gridColumns = 3,
        showConfidence = true,
        showLabel = true,
        showNewBadge = true;

  factory ImageFeedConfig.fromJson(Map<String, dynamic> json) =>
      _$ImageFeedConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ImageFeedConfigToJson(this);

  @override
  Widget build(BuildContext context) => ImageFeedWidget(config: this);

  @override
  Widget configure(BuildContext context) =>
      _ImageFeedConfigEditor(config: this);
}

// ---------------------------------------------------------------------------
// Config editor
// ---------------------------------------------------------------------------

class _ImageFeedConfigEditor extends StatefulWidget {
  final ImageFeedConfig config;
  const _ImageFeedConfigEditor({required this.config});

  @override
  State<_ImageFeedConfigEditor> createState() => _ImageFeedConfigEditorState();
}

class _ImageFeedConfigEditorState extends State<_ImageFeedConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            initialValue: widget.config.key,
            onChanged: (v) => setState(() => widget.config.key = v),
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.controlKey,
            label: 'Control Key (pause/resume)',
            onChanged: (v) =>
                setState(() => widget.config.controlKey = v.isEmpty ? null : v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.maxImages.toString(),
            decoration: const InputDecoration(labelText: 'Max Images'),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) {
                setState(() => widget.config.maxImages = n);
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.gridColumns.toString(),
            decoration: const InputDecoration(labelText: 'Grid Columns'),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) {
                setState(() => widget.config.gridColumns = n);
              }
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Show Confidence'),
            value: widget.config.showConfidence,
            onChanged: (v) =>
                setState(() => widget.config.showConfidence = v),
          ),
          SwitchListTile(
            title: const Text('Show Label'),
            value: widget.config.showLabel,
            onChanged: (v) => setState(() => widget.config.showLabel = v),
          ),
          SwitchListTile(
            title: const Text('Show New Badge'),
            value: widget.config.showNewBadge,
            onChanged: (v) =>
                setState(() => widget.config.showNewBadge = v),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            initialValue: widget.config.coordinates,
            onChanged: (c) =>
                setState(() => widget.config.coordinates = c),
          ),
          const SizedBox(height: 16),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (s) => setState(() => widget.config.size = s),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ImageFeedWidget — displays a grid of recent inference images
// ---------------------------------------------------------------------------

class ImageFeedWidget extends ConsumerStatefulWidget {
  final ImageFeedConfig config;
  const ImageFeedWidget({super.key, required this.config});

  @override
  ConsumerState<ImageFeedWidget> createState() => _ImageFeedWidgetState();
}

class _ImageFeedWidgetState extends ConsumerState<ImageFeedWidget> {
  static final Logger _log = Logger();

  final List<ImageEntry> _entries = [];
  bool _paused = false;

  StreamSubscription<DynamicValue>? _feedSub;
  StreamSubscription<DynamicValue>? _controlSub;

  @override
  void initState() {
    super.initState();
    _subscribeToStreams();
  }

  @override
  void dispose() {
    _feedSub?.cancel();
    _controlSub?.cancel();
    super.dispose();
  }

  Future<void> _subscribeToStreams() async {
    final stateMan = await ref.read(stateManProvider.future);

    // Subscribe to image feed key
    final feedStream = await stateMan.subscribe(widget.config.key);
    _feedSub = feedStream.listen(_onFeedData);

    // Subscribe to control key if present
    final controlKey = widget.config.controlKey;
    if (controlKey != null && controlKey.isNotEmpty) {
      final controlStream = await stateMan.subscribe(controlKey);
      _controlSub = controlStream.listen(_onControlData);
    }
  }

  void _onFeedData(DynamicValue dv) {
    if (_paused) return;

    try {
      final jsonStr = dv.asString;
      final Map<String, dynamic> payload = jsonDecode(jsonStr);

      final imageData = payload['image'] as String?;
      final label = payload['label'] as String? ?? '';
      final confidence = (payload['confidence'] as num?)?.toDouble() ?? 0.0;
      final latencyMs = (payload['latency_ms'] as num?)?.toInt() ?? 0;

      Uint8List? imageBytes;
      String? imageUrl;

      if (imageData != null) {
        if (imageData.startsWith('http://') ||
            imageData.startsWith('https://')) {
          imageUrl = imageData;
        } else {
          // Treat as base64
          try {
            imageBytes = base64Decode(imageData);
          } catch (_) {
            _log.w('Failed to decode base64 image data');
          }
        }
      }

      final entry = ImageEntry(
        imageBytes: imageBytes,
        imageUrl: imageUrl,
        label: label,
        confidence: confidence,
        latencyMs: latencyMs,
      );

      if (mounted) {
        setState(() {
          _entries.add(entry);
          while (_entries.length > widget.config.maxImages) {
            _entries.removeAt(0);
          }
        });
      }
    } catch (e) {
      _log.w('Malformed image feed payload: $e');
    }
  }

  void _onControlData(DynamicValue dv) {
    final value = dv.value;
    bool shouldPause;

    if (value is bool) {
      shouldPause = !value; // false = pause, true = resume
    } else if (value is num) {
      shouldPause = value == 0; // 0 = pause, 1 = resume
    } else {
      return;
    }

    if (mounted) {
      setState(() => _paused = shouldPause);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Semantics(
          label: 'image-feed-grid',
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.config.gridColumns,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: _entries.length,
            itemBuilder: (context, index) =>
                _ImageCell(entry: _entries[index], config: widget.config),
          ),
        ),
        if (_paused)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Text(
                'PAUSED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Individual image cell in the grid
// ---------------------------------------------------------------------------

class _ImageCell extends StatefulWidget {
  final ImageEntry entry;
  final ImageFeedConfig config;

  const _ImageCell({required this.entry, required this.config});

  @override
  State<_ImageCell> createState() => _ImageCellState();
}

class _ImageCellState extends State<_ImageCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badgeController;
  late final Animation<double> _badgeOpacity;

  @override
  void initState() {
    super.initState();
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _badgeOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _badgeController, curve: Curves.easeOut),
    );
    if (widget.config.showNewBadge) {
      _badgeController.forward();
    }
  }

  @override
  void dispose() {
    _badgeController.dispose();
    super.dispose();
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.80) return Colors.green;
    if (confidence >= 0.50) return Colors.yellow.shade700;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final config = widget.config;

    Widget imageWidget;
    if (entry.imageBytes != null) {
      imageWidget = Image.memory(
        entry.imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    } else if (entry.imageUrl != null) {
      imageWidget = Image.network(
        entry.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    } else {
      imageWidget = const Center(child: Icon(Icons.image_not_supported));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageWidget,
          // Label overlay at bottom
          if (config.showLabel && entry.label.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  entry.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          // Confidence percentage
          if (config.showConfidence)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _confidenceColor(entry.confidence),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(entry.confidence * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // "NEW" badge that fades after 1.2s
          if (config.showNewBadge)
            Positioned(
              top: 2,
              left: 2,
              child: FadeTransition(
                opacity: _badgeOpacity,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
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
