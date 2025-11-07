import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/button.dart';

part 'aircab.g.dart';

@JsonSerializable()
class AirCabConfig extends BaseAsset {
  String label;
  String pressureKey;
  String softStartKey;
  String buttonKey;
  String? buttonFeedbackKey;

  AirCabConfig({
    required this.label,
    required this.pressureKey,
    required this.softStartKey,
    required this.buttonKey,
    this.buttonFeedbackKey,
  });

  static const previewStr = "AirCab preview";

  // Preview constructor
  AirCabConfig.preview()
      : label = previewStr,
        pressureKey = "",
        softStartKey = "",
        buttonKey = "";

  factory AirCabConfig.fromJson(Map<String, dynamic> json) => _$AirCabConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$AirCabConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    if (label == previewStr && pressureKey.isEmpty && softStartKey.isEmpty && buttonKey.isEmpty) {
      return const Text(previewStr);
    }
    return AirCab(config: this);
  }

  @override
  Widget configure(BuildContext context) => _AirCabConfigEditor(config: this);
}

class _AirCabConfigEditor extends StatefulWidget {
  final AirCabConfig config;
  const _AirCabConfigEditor({required this.config});

  @override
  State<_AirCabConfigEditor> createState() => _AirCabConfigEditorState();
}

class _AirCabConfigEditorState extends State<_AirCabConfigEditor> {
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
          TextFormField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => widget.config.label = value),
          ),
          const SizedBox(height: 16),
          KeyField(
            label: 'Pressure key',
            initialValue: widget.config.pressureKey,
            onChanged: (v) => setState(() => widget.config.pressureKey = v),
          ),
          const SizedBox(height: 8),
          KeyField(
            label: 'Soft start key',
            initialValue: widget.config.softStartKey,
            onChanged: (v) => setState(() => widget.config.softStartKey = v),
          ),
          const SizedBox(height: 8),
          KeyField(
            label: 'Button key',
            initialValue: widget.config.buttonKey,
            onChanged: (v) => setState(() => widget.config.buttonKey = v),
          ),
          const SizedBox(height: 16),
          KeyField(
            label: 'Button feedback key',
            initialValue: widget.config.buttonFeedbackKey,
            onChanged: (value) => setState(() => widget.config.buttonFeedbackKey = value),
          ),
          const SizedBox(height: 16),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (v) => setState(() => widget.config.size = v),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            initialValue: widget.config.coordinates,
            onChanged: (v) => setState(() => widget.config.coordinates = v),
          ),
        ],
      ),
    );
  }
}

class AirCab extends StatelessWidget {
  final AirCabConfig config;
  const AirCab({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    // Prepare two LEDs (Pressure, Soft start)
    final ledConfigs = <LEDConfig>[
      LEDConfig(
        key: config.pressureKey,
        onColor: Colors.green,
        offColor: Colors.white,
      )
        ..text = "Pressure"
        ..textPos = TextPos.right,
      LEDConfig(
        key: config.softStartKey,
        onColor: Colors.green,
        offColor: Colors.white,
      )
        ..text = "Soft start"
        ..textPos = TextPos.right,
    ];

    // Big circular Button + optional feedback
    var buttonConfig = ButtonConfig(
      key: config.buttonKey,
      outwardColor: Colors.red,
      inwardColor: Colors.red.shade700,
      buttonType: ButtonType.circle,
    )..textPos = TextPos.inside;

    if (config.buttonFeedbackKey != null) {
      buttonConfig.feedback = FeedbackConfig()
        ..color = Colors.green
        ..key = config.buttonFeedbackKey!;
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
        ),
        child: Column(
          children: [
            // ─── Top “label” row ───
            Expanded(
              flex: 2,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    config.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      // We leave fontSize unspecified; FittedBox will scale it.
                    ),
                  ),
                ),
              ),
            ),

            // ─── Bottom “content” row ───
            Expanded(
              flex: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // a) Left side: big circular button (flex = 2)
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.8,
                        heightFactor: 0.8,
                        child: Button(buttonConfig),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // b) Right side: Two LEDs stacked vertically (flex = 3)
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ─── LED Row #1 (“Pressure”) ───
                        Expanded(
                          child: LayoutBuilder(
                            builder: (ctx, rowConstraints) {
                              // Compute fontSize as a fraction of row’s height:
                              final double fontSize = rowConstraints.maxHeight * 0.5;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 1) Icon: keep it square using AspectRatio(1)
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: FractionallySizedBox(
                                      widthFactor: 0.8,
                                      heightFactor: 0.8,
                                      child: Led(ledConfigs[0]),
                                    ),
                                  ),

                                  const SizedBox(width: 4),

                                  // 2) Text “Pressure” at exactly the computed fontSize
                                  Expanded(
                                    child: Text(
                                      ledConfigs[0].text!,
                                      style: TextStyle(
                                        fontSize: fontSize,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 4),

                        // ─── LED Row #2 (“Soft start”) ───
                        Expanded(
                          child: LayoutBuilder(
                            builder: (ctx, rowConstraints) {
                              // We use the same formula for fontSize (same fraction of height).
                              // Because both rows have the same Expanded(flex:1), rowConstraints.maxHeight is identical.
                              final double fontSize = rowConstraints.maxHeight * 0.5;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: FractionallySizedBox(
                                      widthFactor: 0.8,
                                      heightFactor: 0.8,
                                      child: Led(ledConfigs[1]),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      ledConfigs[1].text!,
                                      style: TextStyle(
                                        fontSize: fontSize,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
