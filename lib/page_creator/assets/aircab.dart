import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/converter/color_converter.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/button.dart';

part 'aircab.g.dart';

@JsonSerializable(explicitToJson: true)
class AirCabConfig extends BaseAsset {
  @override
  String get displayName => 'Air Cabinet';
  @override
  String get category => 'Industrial Equipment';

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

  /// Between a lamp and its caption, and between the two lamp cells.
  static const double _gap = 4;

  /// How much of a lamp cell's height the caption under it may take. The
  /// rest, less [_gap], is the lamp itself.
  static const double _captionFraction = 0.42;

  @override
  Widget build(BuildContext context) {
    // Prepare two LEDs (Pressure, Soft start)
    final ledConfigs = <LEDConfig>[
      LEDConfig(
        key: config.pressureKey,
        onColor: AssetColor.green,
        offColor: AssetColor.grey,
      )
        ..text = "Pressure"
        ..textPos = TextPos.right,
      LEDConfig(
        key: config.softStartKey,
        onColor: AssetColor.green,
        offColor: AssetColor.grey,
      )
        ..text = "Soft start"
        ..textPos = TextPos.right,
    ];

    // Big circular Button + optional feedback
    var buttonConfig = ButtonConfig(
      key: config.buttonKey,
      outwardColor: const AssetColor.literal(Colors.red),
      inwardColor: AssetColor.literal(Colors.red.shade700),
      buttonType: ButtonType.circle,
    )..textPos = TextPos.inside;

    if (config.buttonFeedbackKey != null) {
      buttonConfig.feedback = FeedbackConfig()
        ..color = Colors.green
        ..key = config.buttonFeedbackKey!;
    }

    // Theme roles, not literals: a grey[200] box with a black26 border and
    // white "off" LEDs was a light-theme widget pasted onto the dark page.
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            // ─── Top “label” row ───
            Expanded(
              flex: 2,
              // The font size is computed for the row, the same way the rows
              // below compute theirs -- a FittedBox would have scaled a
              // fixed-size raster instead, which is what left it soft.
              child: AutoSizedText(
                config.label,
                heightFraction: 0.5,
                style: const TextStyle(fontWeight: FontWeight.bold),
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

                  // b) Right side: the two lamps, stacked, each with its
                  //    caption beside it.
                  Expanded(
                    flex: 4,
                    child: LayoutBuilder(
                      builder: (ctx, box) {
                        final cellHeight = math.max(0.0, (box.maxHeight - _gap) / 2);

                        // The caption sits *under* its lamp rather than
                        // beside it, so it gets the column's whole width
                        // instead of what a full-height lamp leaves over.
                        // Beside the lamp there were about 54 logical pixels
                        // for ten monospace characters, which is why
                        // "Pressure" and "Soft start" were being clipped to
                        // "Pr…" and "So…"; underneath there are roughly 117,
                        // and the words fit at nearly twice the size.
                        final captionHeight = cellHeight * _captionFraction;
                        final lamp = math.max(0.0, cellHeight - captionHeight - _gap);
                        final captionBox = Size(box.maxWidth, captionHeight);

                        // One size for both captions, chosen so the longer
                        // one fits: sized independently, "Pressure" would
                        // come out visibly larger than "Soft start" and the
                        // pair would stop reading as one list.
                        final baseStyle = DefaultTextStyle.of(ctx).style;
                        final fontSize = ledConfigs
                            .map((led) => fittedFontSize(
                                  text: led.text!,
                                  style: baseStyle,
                                  box: captionBox,
                                  textScaler: MediaQuery.textScalerOf(ctx),
                                  textDirection: Directionality.of(ctx),
                                ))
                            .reduce(math.min);

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final (i, led) in ledConfigs.indexed) ...[
                              if (i > 0) const SizedBox(height: _gap),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox.square(
                                      dimension: lamp,
                                      child: Led(led),
                                    ),
                                    const SizedBox(height: _gap),
                                    // Sized to the box rather than clipped to
                                    // it: the caption is a whole word an
                                    // operator reads across the hall, and
                                    // `TextOverflow.ellipsis` had been eating
                                    // seven eighths of it.
                                    SizedBox(
                                      height: captionHeight,
                                      child: Center(
                                        child: Text(
                                          led.text!,
                                          style: TextStyle(fontSize: fontSize),
                                          softWrap: false,
                                          overflow: TextOverflow.visible,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
    );
  }
}
