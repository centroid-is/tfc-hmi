import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:tfc/page_creator/assets/button.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/common.dart';

part 'checklists.g.dart';

@JsonSerializable()
class ChecklistsConfig extends BaseAsset {
  @override
  String get displayName => 'Checklists';
  @override
  String get category => 'Application';

  List<LEDConfig> line1;
  List<LEDConfig> line2;
  List<LEDConfig> line3;

  ChecklistsConfig({required this.line1, required this.line2, required this.line3});

  factory ChecklistsConfig.fromJson(Map<String, dynamic> json) => _$ChecklistsConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$ChecklistsConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return Checklists(config: this);
  }

  static const previewStr = 'Checklists preview';

  ChecklistsConfig.preview()
      : line1 = [LEDConfig.preview()],
        line2 = [LEDConfig.preview()],
        line3 = [LEDConfig.preview()];

  /// Returns a widget for configuring this checklist config.
  @override
  Widget configure(BuildContext context) {
    return _ChecklistsConfigEditor(config: this);
  }
}

class _ChecklistsConfigEditor extends StatefulWidget {
  final ChecklistsConfig config;
  const _ChecklistsConfigEditor({required this.config});

  @override
  State<_ChecklistsConfigEditor> createState() => _ChecklistsConfigEditorState();
}

class _ChecklistsConfigEditorState extends State<_ChecklistsConfigEditor> {
  late List<List<LEDConfig>> lines;

  @override
  void initState() {
    super.initState();
    lines = [widget.config.line1, widget.config.line2, widget.config.line3];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizeField(initialValue: widget.config.size, onChanged: (size) => setState(() => widget.config.size = size)),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(3, (lineIdx) {
                  return Container(
                    width: 400,
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SizedBox(
                          height: 800,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Line ${lineIdx + 1}', style: Theme.of(context).textTheme.titleMedium),
                                ...List.generate(lines[lineIdx].length, (ledIdx) {
                                  final ledConfig = lines[lineIdx][ledIdx];
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      ledConfig.configure(context),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          icon: Icon(Icons.delete),
                                          onPressed: () {
                                            setState(() {
                                              lines[lineIdx].removeAt(ledIdx);
                                            });
                                          },
                                        ),
                                      ),
                                      const Divider(),
                                    ],
                                  );
                                }),
                                TextButton.icon(
                                  icon: Icon(Icons.add),
                                  label: Text('Add LED'),
                                  onPressed: () {
                                    setState(() {
                                      lines[lineIdx].add(LEDConfig.preview());
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Checklists extends StatefulWidget {
  final ChecklistsConfig config;

  const Checklists({super.key, required this.config});

  @override
  State<Checklists> createState() => _ChecklistsState();
}

class _ChecklistsState extends State<Checklists> {
  void _showChecklistDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1200,
            maxHeight: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Title ───
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  "Checklists",
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // ─── Three‐column area ───
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(3, (lineIdx) {
                  final List<LEDConfig> line = [
                    widget.config.line1,
                    widget.config.line2,
                    widget.config.line3,
                  ][lineIdx];

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ─── "Line X" header ───
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                'Line ${lineIdx + 1}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),

                            // ─── Each LED row ───
                            for (final ledConfig in line)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                                child: Row(
                                  children: [
                                    // LED icon, with a relative size
                                    Expanded(
                                      flex: 1,
                                      child: AspectRatio(
                                        aspectRatio: 1, // Make it square
                                        child: Led(
                                          ledConfig..size = RelativeSize(width: 0.03, height: 0.03),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    // LED text
                                    Expanded(
                                      flex: 6,
                                      child: Text(
                                        ledConfig.text ?? '',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showChecklistDialog(context),
      child: CustomPaint(
        painter: ButtonPainter(
          color: Theme.of(context).colorScheme.primary,
          isPressed: false,
          buttonType: ButtonType.square,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "Checklists",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
