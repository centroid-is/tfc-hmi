import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:rxdart/rxdart.dart';

part 'arrow.g.dart';

@JsonSerializable()
class ArrowConfig extends BaseAsset {
  String key;
  String label;

  ArrowConfig({
    required this.key,
    required this.label,
  });

  ArrowConfig.preview()
      : key = "",
        label = "Arrow preview";

  factory ArrowConfig.fromJson(Map<String, dynamic> json) =>
      _$ArrowConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ArrowConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    if (label == "Arrow preview") {
      return const Text("Arrow preview");
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            initialValue: widget.config.key,
            onChanged: (value) => setState(() => widget.config.key = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => widget.config.label = value),
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

class _ArrowWidgetState extends ConsumerState<ArrowWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _angleForOperation(String op) {
    switch (op) {
      case "up":
        return -math.pi / 2;
      case "down":
        return math.pi / 2;
      case "left":
        return math.pi;
      case "right":
      default:
        return 0.0;
    }
  }

  IconData _iconForOperation(String op) {
    // You can use different icons if you want
    return Icons.arrow_upward;
  }

  @override
  Widget build(BuildContext context) {
    final containerSize = MediaQuery.of(context).size;
    final iconSize = widget.config.size.toSize(containerSize);

    if (widget.config.key.isEmpty) {
      return Icon(Icons.arrow_upward,
          size: iconSize.shortestSide, color: Colors.grey);
    }

    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
          (stateMan) => stateMan
              .subscribe(widget.config.key)
              .asStream()
              .switchMap((s) => s)),
      builder: (context, snapshot) {
        String operation = "right";
        if (snapshot.hasData) {
          final str = snapshot.data.toString().toLowerCase() ?? "";
          if (str.contains("left")) {
            operation = "left";
          } else if (str.contains("right")) {
            operation = "right";
          } else if (str.contains("up")) {
            operation = "up";
          } else if (str.contains("down")) {
            operation = "down";
          } else if (str.contains("spin")) {
            operation = "spin";
          }
        }

        if (operation == "spin") {
          _controller.repeat();
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * math.pi,
                child: Icon(
                  _iconForOperation("up"),
                  size: iconSize.shortestSide,
                  color: Colors.black,
                ),
              );
            },
          );
        } else {
          _controller.stop();
          return Transform.rotate(
            angle: _angleForOperation(operation),
            child: Icon(
              _iconForOperation(operation),
              size: iconSize.shortestSide,
              color: Colors.black,
            ),
          );
        }
      },
    );
  }
}
