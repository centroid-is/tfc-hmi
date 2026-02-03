import 'dart:collection' show LinkedHashMap;

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'common.dart';
import '../../painter/schneider/atv320.dart';
import 'package:tfc_dart/core/state_man.dart';
import '../../providers/state_man.dart';
import '../../widgets/dynamic_value.dart';

part 'schneider.g.dart';

@JsonSerializable()
class SchneiderATV320Config extends BaseAsset {
  String? label;
  String? hmisKey;
  String? freqKey;
  String? configKey;

  SchneiderATV320Config({
    this.label,
    this.hmisKey,
    this.freqKey,
    this.configKey,
  });

  @override
  Widget build(BuildContext context) {
    return _SchneiderATV320(config: this);
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9;
    final maxHeight = media.height * 0.8;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minWidth: 320,
          minHeight: 200,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: DialogTheme.of(context).backgroundColor ?? Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _ATV320ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  SchneiderATV320Config.preview() : super();

  factory SchneiderATV320Config.fromJson(Map<String, dynamic> json) =>
      _$SchneiderATV320ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$SchneiderATV320ConfigToJson(this);
}

class _ATV320ConfigContent extends StatefulWidget {
  final SchneiderATV320Config config;

  const _ATV320ConfigContent({required this.config});

  @override
  State<_ATV320ConfigContent> createState() => _ATV320ConfigContentState();
}

class _ATV320ConfigContentState extends State<_ATV320ConfigContent> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizeField(
          initialValue: widget.config.size,
          onChanged: (size) => widget.config.size = size,
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (coordinates) => widget.config.coordinates = coordinates,
          enableAngle: true,
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: widget.config.label,
          onChanged: (value) => widget.config.label = value,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.hmisKey,
          onChanged: (value) => widget.config.hmisKey = value,
          label: 'HMIS Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.freqKey,
          onChanged: (value) => widget.config.freqKey = value,
          label: 'Frequency Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.configKey,
          onChanged: (value) => widget.config.configKey = value,
          label: 'Configuration Key',
        ),
      ],
    );
  }
}

class _SchneiderATV320 extends ConsumerWidget {
  final SchneiderATV320Config config;

  const _SchneiderATV320({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snap) {
        final stateMan = snap.data;

        return StreamBuilder<Map<String, DynamicValue>>(
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("hmis", config.hmisKey),
                    MapEntry("freq", config.freqKey),
                  ]),
                  stateMan,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            // Determine display text based on frequency value
            String displayText = '';
            String topLabel = config.label ?? '';

            if (data != null) {
              final freqValue = data["freq"]?.asDouble ?? 0;
              if (freqValue > 0.01) {
                displayText = freqValue.toStringAsFixed(1);
              } else if (data["hmis"]?.asString != null) {
                final hmisValue = data["hmis"]!.asInt;
                final enumFields = data["hmis"]!.enumFields;
                displayText = data["hmis"]!
                        .enumFields?[data["hmis"]!.asInt]
                        ?.displayName
                        .value ??
                    "";
              }
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (stateMan == null || config.configKey == null) return;
                showDialog(
                  context: context,
                  builder: (_) => _configDialog(context, stateMan),
                );
              },
              child: ATV320Widget(
                name: "ATV320",
                displayText: displayText,
                topLabel: topLabel,
              ),
            );
          },
        );
      },
    );
  }

  Widget _configDialog(BuildContext context, StateMan stateMan) {
    return _ATV320ConfigDialog(
      configKey: config.configKey!,
      stateMan: stateMan,
    );
  }
}

class _ATV320ConfigDialog extends StatefulWidget {
  final String configKey;
  final StateMan stateMan;

  const _ATV320ConfigDialog({
    required this.configKey,
    required this.stateMan,
  });

  @override
  State<_ATV320ConfigDialog> createState() => _ATV320ConfigDialogState();
}

class _ATV320ConfigDialogState extends State<_ATV320ConfigDialog> {
  DynamicValue? _pendingConfigValue;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ATV320 Configuration'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: StreamBuilder<DynamicValue>(
          stream: widget.stateMan
              .subscribe(widget.configKey)
              .asStream()
              .asyncExpand((s) => s),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.hasError) {
              return const Center(
                  child: Text('No configuration data available'));
            }

            final configValue = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: DynamicValueWidget(
                      value: configValue,
                      onSubmitted: (newValue) {
                        setState(() {
                          _pendingConfigValue = newValue;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _pendingConfigValue != null
                          ? () async {
                              try {
                                await widget.stateMan.write(
                                    widget.configKey, _pendingConfigValue!);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Configuration updated successfully')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Error updating configuration: $e')),
                                  );
                                }
                              }
                            }
                          : null,
                      child: const Text('Write'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

CombineLatestStream<DynamicValue, Map<String, DynamicValue>> _combinedStream(
    LinkedHashMap<String, String?> keys, StateMan stateMan) {
  return CombineLatestStream([
    for (var entry in keys.entries)
      if (entry.value != null)
        stateMan.subscribe(entry.value!).asStream().asyncExpand((s) => s),
  ], (values) {
    final map = <String, DynamicValue>{};
    int i = 0;
    for (var entry in keys.entries) {
      if (entry.value != null) {
        map[entry.key] = values[i++];
      }
    }
    return map;
  });
}
