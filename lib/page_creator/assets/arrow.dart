import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/converter/color_converter.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:rxdart/rxdart.dart';

part 'arrow.g.dart';

@JsonSerializable(explicitToJson: true)
class ArrowConfig extends BaseAsset {
  @override
  String get displayName => 'Arrow';
  @override
  String get category => 'Basic Indicators';

  String key;
  String label;

  /// Arrow body / glyph colour. Defaults to `Colors.black` — the prior
  /// hard-coded painter colour. Per-instance configurable via the
  /// configure dialog and JSON round-trips through `@ColorConverter()`.
  @ColorConverter()
  Color color;

  /// Optional per-direction bool input keys.
  ///
  /// When any of these are set, the runtime ignores the legacy single
  /// `key` (which inferred direction from a stringified value) and
  /// instead reads each bound key as a boolean. The first direction
  /// whose bool reads `true` is rendered as the active direction
  /// (priority: up, down, left, right). When none are active, the
  /// arrow renders in its inactive ("lost") state. When all four are
  /// null the asset falls back to the legacy single-key behaviour so
  /// pages saved before this change round-trip bit-perfectly.
  @JsonKey(includeIfNull: false)
  String? upInputKey;
  @JsonKey(includeIfNull: false)
  String? downInputKey;
  @JsonKey(includeIfNull: false)
  String? leftInputKey;
  @JsonKey(includeIfNull: false)
  String? rightInputKey;

  ArrowConfig({
    required this.key,
    required this.label,
    Color? color,
    this.upInputKey,
    this.downInputKey,
    this.leftInputKey,
    this.rightInputKey,
  }) : color = color ?? Colors.black;

  ArrowConfig.preview()
      : key = "",
        label = "Arrow preview",
        color = Colors.black;

  /// True when any per-direction bool input key is configured.
  bool get hasDirectionInputs =>
      (upInputKey != null && upInputKey!.isNotEmpty) ||
      (downInputKey != null && downInputKey!.isNotEmpty) ||
      (leftInputKey != null && leftInputKey!.isNotEmpty) ||
      (rightInputKey != null && rightInputKey!.isNotEmpty);

  factory ArrowConfig.fromJson(Map<String, dynamic> json) =>
      _$ArrowConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$ArrowConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    if (label == "Arrow preview") {
      return const Icon(Icons.arrow_forward, size: 48, color: Colors.grey);
    }
    return ArrowWidget(config: this);
  }

  @override
  Widget configure(BuildContext context) => _ArrowConfigEditor(config: this);
}

class _ArrowConfigEditor extends StatefulWidget {
  final ArrowConfig config;
  const _ArrowConfigEditor({required this.config});

  @override
  State<_ArrowConfigEditor> createState() => _ArrowConfigEditorState();
}

class _ArrowConfigEditorState extends State<_ArrowConfigEditor> {
  late TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.config.label);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _showColorPicker() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Arrow Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: widget.config.color,
            onColorChanged: (c) => setState(() => widget.config.color = c),
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(Color color) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            initialValue: widget.config.key,
            onChanged: (value) => setState(() => widget.config.key = value),
            label: 'Key (string → direction, optional)',
          ),
          const SizedBox(height: 16),
          // -- Per-direction bool input keys --
          //
          // Each direction can be independently driven by a boolean tag.
          // When any of these are set, the runtime prefers them over the
          // legacy single "Key" above (which infers direction by string
          // match). Leaving them all empty preserves the prior behaviour
          // so legacy pages keep working unchanged.
          Text(
            'Per-direction bool inputs (optional)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          KeyField(
            initialValue: widget.config.upInputKey,
            onChanged: (value) => setState(
                () => widget.config.upInputKey = value.isEmpty ? null : value),
            label: 'Up input (bool)',
          ),
          const SizedBox(height: 8),
          KeyField(
            initialValue: widget.config.downInputKey,
            onChanged: (value) => setState(() =>
                widget.config.downInputKey = value.isEmpty ? null : value),
            label: 'Down input (bool)',
          ),
          const SizedBox(height: 8),
          KeyField(
            initialValue: widget.config.leftInputKey,
            onChanged: (value) => setState(() =>
                widget.config.leftInputKey = value.isEmpty ? null : value),
            label: 'Left input (bool)',
          ),
          const SizedBox(height: 8),
          KeyField(
            initialValue: widget.config.rightInputKey,
            onChanged: (value) => setState(() =>
                widget.config.rightInputKey = value.isEmpty ? null : value),
            label: 'Right input (bool)',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => widget.config.label = value),
          ),
          const SizedBox(height: 16),
          // -- Arrow Color --
          GestureDetector(
            onTap: _showColorPicker,
            child: Row(children: [
              _colorSwatch(widget.config.color),
              const SizedBox(width: 8),
              const Text('Arrow Color'),
            ]),
          ),
          const SizedBox(height: 16),
          // -- BaseAsset.text overlay (rendered by page_view's label layer).
          //    Without this control the operator can't enable the standard
          //    text-position label overlay that every other asset surfaces.
          TextFormField(
            initialValue: widget.config.text,
            decoration: const InputDecoration(labelText: 'Text'),
            onChanged: (value) => setState(
                () => widget.config.text = value.isEmpty ? null : value),
          ),
          const SizedBox(height: 8),
          DropdownButton<TextPos>(
            value: widget.config.textPos,
            isExpanded: true,
            hint: const Text('Text position'),
            onChanged: (value) => setState(() => widget.config.textPos = value),
            items: TextPos.values
                .map((e) =>
                    DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
                .toList(),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            initialValue: widget.config.coordinates,
            onChanged: (c) => setState(() => widget.config.coordinates = c),
          ),
          const SizedBox(height: 16),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (value) => setState(() => widget.config.size = value),
            useSingleSize: true,
          ),
        ],
      ),
    );
  }
}

class ArrowWidget extends ConsumerStatefulWidget {
  final ArrowConfig config;
  const ArrowWidget({super.key, required this.config});

  @override
  ConsumerState<ArrowWidget> createState() => _ArrowWidgetState();
}

class _ArrowWidgetState extends ConsumerState<ArrowWidget> {
  double _angleForOperation(String op) {
    switch (op) {
      case "left":
        return -math.pi / 2;
      case "right":
        return math.pi / 2;
      case "down":
        return math.pi;
      case "up":
      default:
        return 0.0;
    }
  }

  IconData _iconForOperation(String op) {
    if (op == "lost") {
      return Icons.question_mark_outlined;
    }
    return Icons.arrow_upward;
  }

  /// Builds the rotated icon at a size derived from its parent constraints.
  ///
  /// `LayoutBuilder` mirrors `IconAsset` (lib/page_creator/assets/icon.dart)
  /// so the arrow consumes the SizedBox the page view gives it
  /// (`asset.size.width * W` × `asset.size.height * H`). A bare
  /// `Icon` without `size:` falls back to `IconTheme.size` (~24 px) and
  /// would ignore the parent — that's the "doesn't scale" bug.
  Widget _buildIcon(String operation, Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasW =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite;
        final hasH =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final double w = hasW ? constraints.maxWidth : 48.0;
        final double h = hasH ? constraints.maxHeight : 48.0;
        final double size = w < h ? w : h;
        return Center(
          child: Transform.rotate(
            angle: _angleForOperation(operation),
            child: Icon(
              _iconForOperation(operation),
              color: color,
              size: size,
            ),
          ),
        );
      },
    );
  }

  /// Per-direction bool path.
  ///
  /// When the operator has wired any of `<dir>InputKey`, each set key is
  /// subscribed and read as a boolean. The first direction whose value
  /// reads `true` (priority up→down→left→right) becomes the active
  /// direction; if none are true the arrow renders in its inactive
  /// "lost" state. Unset directions contribute no stream.
  Widget _buildPerDirection() {
    final cfg = widget.config;
    // Ordered (direction, key) pairs — priority follows list order.
    final entries = <MapEntry<String, String>>[];
    if (cfg.upInputKey != null && cfg.upInputKey!.isNotEmpty) {
      entries.add(MapEntry('up', cfg.upInputKey!));
    }
    if (cfg.downInputKey != null && cfg.downInputKey!.isNotEmpty) {
      entries.add(MapEntry('down', cfg.downInputKey!));
    }
    if (cfg.leftInputKey != null && cfg.leftInputKey!.isNotEmpty) {
      entries.add(MapEntry('left', cfg.leftInputKey!));
    }
    if (cfg.rightInputKey != null && cfg.rightInputKey!.isNotEmpty) {
      entries.add(MapEntry('right', cfg.rightInputKey!));
    }

    final streams = entries.map((e) {
      return ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(e.value)
                .asStream()
                .switchMap((s) => s),
          );
    }).toList();

    return StreamBuilder<List<DynamicValue>>(
      stream: CombineLatestStream.list(streams),
      builder: (context, snapshot) {
        String operation = 'lost';
        if (snapshot.hasData) {
          for (int i = 0; i < entries.length; i++) {
            try {
              if (snapshot.data![i].asBool == true) {
                operation = entries[i].key;
                break;
              }
            } catch (_) {
              // Non-bool value: skip — direction remains inactive.
            }
          }
        }
        return _buildIcon(operation, widget.config.color);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Per-direction bool inputs take priority when any are configured.
    // Falls through to legacy single-key behaviour when none are set so
    // pages saved before this change keep rendering exactly as before.
    if (widget.config.hasDirectionInputs) {
      return _buildPerDirection();
    }

    if (widget.config.key.isEmpty) {
      // No live key — render the configured arrow in its configured colour.
      // The operator's chosen colour applies in both editor and runtime
      // fallback paths so what they see in the configure dialog matches
      // what they see on the page.
      return _buildIcon("up", widget.config.color);
    }

    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
          (stateMan) => stateMan
              .subscribe(widget.config.key)
              .asStream()
              .switchMap((s) => s)),
      builder: (context, snapshot) {
        String operation = "lost";
        if (snapshot.hasData) {
          final str = snapshot.data.toString().toLowerCase();
          if (str.contains("left")) {
            operation = "left";
          } else if (str.contains("right")) {
            operation = "right";
          } else if (str.contains("up")) {
            operation = "up";
          } else if (str.contains("down")) {
            operation = "down";
          } else if (str.contains("lost")) {
            operation = "lost";
          }
        }

        return _buildIcon(operation, widget.config.color);
      },
    );
  }
}
