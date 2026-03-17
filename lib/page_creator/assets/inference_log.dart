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

part 'inference_log.g.dart';

// ---------------------------------------------------------------------------
// Data model for a single log entry
// ---------------------------------------------------------------------------

class LogEntry {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String label;
  final double confidence;
  final int latencyMs;
  final int? id;
  final DateTime timestamp;

  LogEntry({
    this.imageBytes,
    this.imageUrl,
    required this.label,
    required this.confidence,
    required this.latencyMs,
    this.id,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// InferenceLogConfig — asset config
// ---------------------------------------------------------------------------

@JsonSerializable(explicitToJson: true)
class InferenceLogConfig extends BaseAsset {
  @override
  String get displayName => 'Inference Log';
  @override
  String get category => 'Monitoring';

  String key;

  @JsonKey(name: 'control_key')
  String? controlKey;

  @JsonKey(name: 'max_entries', defaultValue: 30)
  int maxEntries;

  @JsonKey(name: 'show_thumbnail', defaultValue: true)
  bool showThumbnail;

  @JsonKey(name: 'show_confidence_bar', defaultValue: true)
  bool showConfidenceBar;

  @JsonKey(name: 'show_latency', defaultValue: true)
  bool showLatency;

  InferenceLogConfig({
    required this.key,
    this.controlKey,
    this.maxEntries = 30,
    this.showThumbnail = true,
    this.showConfidenceBar = true,
    this.showLatency = true,
  });

  InferenceLogConfig.preview()
      : key = 'Inference Log preview',
        controlKey = null,
        maxEntries = 30,
        showThumbnail = true,
        showConfidenceBar = true,
        showLatency = true;

  factory InferenceLogConfig.fromJson(Map<String, dynamic> json) =>
      _$InferenceLogConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$InferenceLogConfigToJson(this);

  @override
  Widget build(BuildContext context) => InferenceLogWidget(config: this);

  @override
  Widget configure(BuildContext context) =>
      _InferenceLogConfigEditor(config: this);
}

// ---------------------------------------------------------------------------
// Config editor
// ---------------------------------------------------------------------------

class _InferenceLogConfigEditor extends StatefulWidget {
  final InferenceLogConfig config;
  const _InferenceLogConfigEditor({required this.config});

  @override
  State<_InferenceLogConfigEditor> createState() =>
      _InferenceLogConfigEditorState();
}

class _InferenceLogConfigEditorState extends State<_InferenceLogConfigEditor> {
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
            initialValue: widget.config.maxEntries.toString(),
            decoration: const InputDecoration(labelText: 'Max Entries'),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) {
                setState(() => widget.config.maxEntries = n);
              }
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Show Thumbnail'),
            value: widget.config.showThumbnail,
            onChanged: (v) =>
                setState(() => widget.config.showThumbnail = v),
          ),
          SwitchListTile(
            title: const Text('Show Confidence Bar'),
            value: widget.config.showConfidenceBar,
            onChanged: (v) =>
                setState(() => widget.config.showConfidenceBar = v),
          ),
          SwitchListTile(
            title: const Text('Show Latency'),
            value: widget.config.showLatency,
            onChanged: (v) => setState(() => widget.config.showLatency = v),
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
// InferenceLogWidget — displays a scrolling feed of inference results
// ---------------------------------------------------------------------------

class InferenceLogWidget extends ConsumerStatefulWidget {
  final InferenceLogConfig config;
  const InferenceLogWidget({super.key, required this.config});

  @override
  ConsumerState<InferenceLogWidget> createState() => _InferenceLogWidgetState();
}

class _InferenceLogWidgetState extends ConsumerState<InferenceLogWidget> {
  static final Logger _log = Logger();

  final List<LogEntry> _entries = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
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

    final feedStream = await stateMan.subscribe(widget.config.key);
    _feedSub = feedStream.listen(_onFeedData);

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
      final id = (payload['id'] as num?)?.toInt();

      Uint8List? imageBytes;
      String? imageUrl;

      if (imageData != null) {
        if (imageData.startsWith('http://') ||
            imageData.startsWith('https://')) {
          imageUrl = imageData;
        } else {
          try {
            imageBytes = base64Decode(imageData);
          } catch (_) {
            _log.w('Failed to decode base64 image data');
          }
        }
      }

      final entry = LogEntry(
        imageBytes: imageBytes,
        imageUrl: imageUrl,
        label: label,
        confidence: confidence,
        latencyMs: latencyMs,
        id: id,
      );

      if (mounted) {
        _entries.insert(0, entry);
        _listKey.currentState?.insertItem(
          0,
          duration: const Duration(milliseconds: 300),
        );
        while (_entries.length > widget.config.maxEntries) {
          final removedIndex = _entries.length - 1;
          final removed = _entries.removeAt(removedIndex);
          _listKey.currentState?.removeItem(
            removedIndex,
            (context, animation) => SizeTransition(
              sizeFactor: animation,
              child: _LogRow(
                entry: removed,
                config: widget.config,
                confidenceBarColor: _confidenceBarColor,
                statusBadgeText: _statusBadgeText,
                statusBadgeColor: _statusBadgeColor,
              ),
            ),
            duration: const Duration(milliseconds: 200),
          );
        }
        setState(() {}); // Update empty state overlay
      }
    } catch (e) {
      _log.w('Malformed inference log payload: $e');
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

  Color _confidenceBarColor(double confidence) {
    if (confidence >= 0.80) return Colors.green;
    if (confidence >= 0.50) return Colors.yellow.shade700;
    return Colors.red;
  }

  String _statusBadgeText(double confidence) {
    if (confidence >= 0.75) return 'ok';
    if (confidence >= 0.50) return 'low';
    return 'error';
  }

  Color _statusBadgeColor(double confidence) {
    if (confidence >= 0.75) return Colors.green;
    if (confidence >= 0.50) return Colors.yellow.shade700;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedList(
          key: _listKey,
          initialItemCount: _entries.length,
          itemBuilder: (context, index, animation) {
            return SlideTransition(
              position: animation.drive(
                Tween<Offset>(
                  begin: const Offset(-1.0, 0.0),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOut)),
              ),
              child: _LogRow(
                entry: _entries[index],
                config: widget.config,
                confidenceBarColor: _confidenceBarColor,
                statusBadgeText: _statusBadgeText,
                statusBadgeColor: _statusBadgeColor,
              ),
            );
          },
        ),
        if (_entries.isEmpty)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'No entries yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
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
// Individual log row
// ---------------------------------------------------------------------------

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final InferenceLogConfig config;
  final Color Function(double) confidenceBarColor;
  final String Function(double) statusBadgeText;
  final Color Function(double) statusBadgeColor;

  const _LogRow({
    required this.entry,
    required this.config,
    required this.confidenceBarColor,
    required this.statusBadgeText,
    required this.statusBadgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Thumbnail
          if (config.showThumbnail) ...[
            SizedBox(
              width: 32,
              height: 32,
              child: _buildThumbnail(),
            ),
            const SizedBox(width: 8),
          ],
          // Label + subtext
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (config.showLatency)
                  Text(
                    '${entry.latencyMs}ms${entry.id != null ? ' #${entry.id}' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          // Confidence bar
          if (config.showConfidenceBar) ...[
            SizedBox(
              width: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: entry.confidence,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        confidenceBarColor(entry.confidence),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(entry.confidence * 100).round()}%',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusBadgeColor(entry.confidence),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusBadgeText(entry.confidence),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (entry.imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          entry.imageBytes!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, size: 16)),
        ),
      );
    }
    if (entry.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          entry.imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, size: 16)),
        ),
      );
    }
    return const Center(child: Icon(Icons.image_not_supported, size: 16));
  }
}
