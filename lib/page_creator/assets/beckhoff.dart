import 'dart:math' as math;
import 'dart:collection' show LinkedHashMap;

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'common.dart';
import '../../painter/beckhoff/cx5010.dart';
import '../../painter/beckhoff/ek1100.dart';
import '../../painter/beckhoff/io8.dart';
import '../../core/state_man.dart';
import '../../providers/state_man.dart';
import '../page.dart';
import '../../providers/collector.dart';
import '../../core/collector.dart';
import '../../core/database.dart';
import '../../widgets/graph.dart';

part 'beckhoff.g.dart';

const Map<String, Asset Function()> _availableSubdevices = {
  "EL1008": BeckhoffEL1008Config.preview,
  "EL2008": BeckhoffEL2008Config.preview,
  "EL3054": BeckhoffEL3054Config.preview,
  "EL9222": BeckhoffEL9222Config.preview,
  "EL9187": BeckhoffEL9187Config.preview,
  "EL9186": BeckhoffEL9186Config.preview,
};

@JsonSerializable()
class BeckhoffCX5010Config extends BaseAsset {
  @AssetListConverter()
  List<Asset> subdevices = [];
  BeckhoffCX5010Config();

  /// Native painter size for the CX5010 drawing (keeps 105.5:100 aspect).
  static const Size _cxNativeSize = Size(1055, 1000);

  @override
  Widget build(BuildContext context) {
    final targetSize = size.toSize(MediaQuery.of(context).size);

    // **Important**: the entire asset is bounded to `targetSize`.
    // Everything inside is laid out at its "native" size and then
    // uniformly scaled by FittedBox to fit exactly within targetSize.
    return SizedBox.fromSize(
      size: targetSize,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Main CX5010 device at native size; outer FittedBox scales it.
            CustomPaint(
              size: _cxNativeSize,
              painter: CXxxxx(
                name: "CX5010",
                pwrColor: Colors.green,
                tcColor: Colors.green,
              ),
            ),
            // Subdevices to the right, normalized to match CX height
            if (subdevices.isNotEmpty) ...[
              for (final sub in subdevices)
                _SubdeviceNormalized(
                  child: sub.build(context),
                  targetHeight: _cxNativeSize.height,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9;
    final maxHeight = media.height * 0.8;

    final dialogW = math.min(maxWidth, 960.0);
    final dialogH = math.min(maxHeight, 600.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 560,
          minHeight: 360,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: SizedBox(
          width: dialogW,
          height: dialogH,
          child: _CXxxxxConfigContent(
              config: this), // unchanged name, refactored below
        ),
      ),
    );
  }

  static const previewStr = 'Baader221 preview';

  BeckhoffCX5010Config.preview() : super();

  factory BeckhoffCX5010Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffCX5010ConfigFromJson(json);
  Map<String, dynamic> toJson() => _$BeckhoffCX5010ConfigToJson(this);
}

/// Wraps a subdevice widget and normalizes its visual height so it lines up
/// with the CX5010. The outer FittedBox (in build()) then scales the *whole row*.
class _SubdeviceNormalized extends StatelessWidget {
  final double targetHeight;
  final Widget child;
  const _SubdeviceNormalized({
    required this.targetHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: targetHeight,
      // Fit the subdevice to the same height as the CX painter.
      child: FittedBox(
        fit: BoxFit.fitHeight,
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}

class _CXxxxxConfigContent extends StatefulWidget {
  final BeckhoffCX5010Config config;

  const _CXxxxxConfigContent({required this.config});

  @override
  State<_CXxxxxConfigContent> createState() => _CXxxxxConfigContentState();
}

class _CXxxxxConfigContentState extends State<_CXxxxxConfigContent> {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT: fields (independent scroll)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CX5010', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizeField(
                  initialValue: widget.config.size,
                  onChanged: (size) => widget.config.size = size,
                ),
                const SizedBox(height: 16),
                CoordinatesField(
                  initialValue: widget.config.coordinates,
                  onChanged: (c) => widget.config.coordinates = c,
                  enableAngle: true,
                ),
              ],
            ),
          ),
        ),

        const VerticalDivider(width: 1),

        // RIGHT: subdevice manager
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Subdevices',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Add Subdevice',
                  ),
                  value: null,
                  hint: const Text('Select a subdevice to add'),
                  items: _availableSubdevices.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      final mk = _availableSubdevices[v]!;
                      widget.config.subdevices.add(mk());
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (widget.config.subdevices.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No subdevices yet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Text('Current Subdevices',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(width: 8),
                      Chip(label: Text('${widget.config.subdevices.length}')),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Take remaining height of the dialog
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        buildDefaultDragHandles: false,
                        itemCount: widget.config.subdevices.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item =
                                widget.config.subdevices.removeAt(oldIndex);
                            widget.config.subdevices.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final sub = widget.config.subdevices[index];
                          return ListTile(
                            key: ObjectKey(sub),
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_indicator),
                            ),
                            title: Text(sub.runtimeType.toString()),
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => sub.configure(context),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setState(() =>
                                    widget.config.subdevices.removeAt(index));
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

@JsonSerializable()
class BeckhoffEK1100Config extends BaseAsset {
  @AssetListConverter()
  List<Asset> subdevices = [];
  BeckhoffEK1100Config();

  /// Native painter size for the EK1100 drawing (keeps 44:100 aspect).
  static const Size _ekNativeSize = Size(440, 1000);

  @override
  Widget build(BuildContext context) {
    final targetSize = size.toSize(MediaQuery.of(context).size);

    // **Important**: the entire asset is bounded to `targetSize`.
    // Everything inside is laid out at its "native" size and then
    // uniformly scaled by FittedBox to fit exactly within targetSize.
    return SizedBox.fromSize(
      size: targetSize,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Main EK1100 device at native size; outer FittedBox scales it.
            CustomPaint(
              size: _ekNativeSize,
              painter: EK1100(
                name: "EK1100",
              ),
            ),
            // Subdevices to the right, normalized to match EK height
            if (subdevices.isNotEmpty) ...[
              for (final sub in subdevices)
                _SubdeviceNormalized(
                  child: sub.build(context),
                  targetHeight: _ekNativeSize.height,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9;
    final maxHeight = media.height * 0.8;

    final dialogW = math.min(maxWidth, 960.0);
    final dialogH = math.min(maxHeight, 600.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 560,
          minHeight: 360,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: SizedBox(
          width: dialogW,
          height: dialogH,
          child: _EK1100ConfigContent(config: this),
        ),
      ),
    );
  }

  static const previewStr = 'EK1100 preview';

  BeckhoffEK1100Config.preview() : super();

  factory BeckhoffEK1100Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEK1100ConfigFromJson(json);
  Map<String, dynamic> toJson() => _$BeckhoffEK1100ConfigToJson(this);
}

class _EK1100ConfigContent extends StatefulWidget {
  final BeckhoffEK1100Config config;

  const _EK1100ConfigContent({required this.config});

  @override
  State<_EK1100ConfigContent> createState() => _EK1100ConfigContentState();
}

class _EK1100ConfigContentState extends State<_EK1100ConfigContent> {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT: fields (independent scroll)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EK1100', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizeField(
                  initialValue: widget.config.size,
                  onChanged: (size) => widget.config.size = size,
                ),
                const SizedBox(height: 16),
                CoordinatesField(
                  initialValue: widget.config.coordinates,
                  onChanged: (c) => widget.config.coordinates = c,
                  enableAngle: true,
                ),
              ],
            ),
          ),
        ),

        const VerticalDivider(width: 1),

        // RIGHT: subdevice manager
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Subdevices',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Add Subdevice',
                  ),
                  value: null,
                  hint: const Text('Select a subdevice to add'),
                  items: _availableSubdevices.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      final mk = _availableSubdevices[v]!;
                      widget.config.subdevices.add(mk());
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (widget.config.subdevices.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No subdevices yet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Text('Current Subdevices',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(width: 8),
                      Chip(label: Text('${widget.config.subdevices.length}')),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Take remaining height of the dialog
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        buildDefaultDragHandles: false,
                        itemCount: widget.config.subdevices.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item =
                                widget.config.subdevices.removeAt(oldIndex);
                            widget.config.subdevices.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final sub = widget.config.subdevices[index];
                          return ListTile(
                            key: ObjectKey(sub),
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_indicator),
                            ),
                            title: Text(sub.runtimeType.toString()),
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => sub.configure(context),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setState(() =>
                                    widget.config.subdevices.removeAt(index));
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

@JsonSerializable()
class BeckhoffEL1008Config extends BaseAsset {
  String nameOrId;
  String? descriptionsKey;
  String? rawStateKey;
  String? processedStateKey;
  String? forceValuesKey;
  String? onFiltersKey;
  String? offFiltersKey;

  BeckhoffEL1008Config({
    required this.nameOrId,
    this.descriptionsKey,
    this.rawStateKey,
    this.processedStateKey,
    this.forceValuesKey,
    this.onFiltersKey,
    this.offFiltersKey,
  });

  @override
  Widget build(BuildContext context) {
    return _BeckhoffEL1008(config: this);
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9; // Use 90% of screen width
    final maxHeight = media.height * 0.8; // Use 80% of screen height

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
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _EL1008ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  BeckhoffEL1008Config.preview()
      : nameOrId = "1",
        descriptionsKey = null,
        rawStateKey = null,
        processedStateKey = null,
        forceValuesKey = null,
        onFiltersKey = null,
        offFiltersKey = null,
        super();

  factory BeckhoffEL1008Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEL1008ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffEL1008ConfigToJson(this);
}

class _EL1008ConfigContent extends StatefulWidget {
  final BeckhoffEL1008Config config;

  const _EL1008ConfigContent({required this.config});

  @override
  State<_EL1008ConfigContent> createState() => _EL1008ConfigContentState();
}

class _EL1008ConfigContentState extends State<_EL1008ConfigContent> {
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
          enableAngle: false,
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Name or ID',
            border: OutlineInputBorder(),
          ),
          initialValue: widget.config.nameOrId,
          onChanged: (value) => widget.config.nameOrId = value,
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.descriptionsKey,
          onChanged: (value) => widget.config.descriptionsKey = value,
          label: 'Descriptions Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.rawStateKey,
          onChanged: (value) => widget.config.rawStateKey = value,
          label: 'Raw State Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.processedStateKey,
          onChanged: (value) => widget.config.processedStateKey = value,
          label: 'Processed State Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.forceValuesKey,
          onChanged: (value) => widget.config.forceValuesKey = value,
          label: 'Force Values Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.onFiltersKey,
          onChanged: (value) => widget.config.onFiltersKey = value,
          label: 'On Filters Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.offFiltersKey,
          onChanged: (value) => widget.config.offFiltersKey = value,
          label: 'Off Filters Key',
        ),
      ],
    );
  }
}

@JsonSerializable()
class BeckhoffEL2008Config extends BaseAsset {
  String nameOrId;
  String? descriptionsKey;
  String? rawStateKey;
  String? forceValuesKey;

  BeckhoffEL2008Config({
    required this.nameOrId,
    this.descriptionsKey,
    this.rawStateKey,
    this.forceValuesKey,
  });

  @override
  Widget build(BuildContext context) {
    return _BeckhoffEL2008(config: this);
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9; // Use 90% of screen width
    final maxHeight = media.height * 0.8; // Use 80% of screen height

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
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _EL2008ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  BeckhoffEL2008Config.preview()
      : nameOrId = "1",
        descriptionsKey = null,
        rawStateKey = null,
        forceValuesKey = null,
        super();

  factory BeckhoffEL2008Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEL2008ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffEL2008ConfigToJson(this);
}

class _EL2008ConfigContent extends StatefulWidget {
  final BeckhoffEL2008Config config;

  const _EL2008ConfigContent({required this.config});

  @override
  State<_EL2008ConfigContent> createState() => _EL2008ConfigContentState();
}

class _EL2008ConfigContentState extends State<_EL2008ConfigContent> {
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
          enableAngle: false,
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Name or ID',
            border: OutlineInputBorder(),
          ),
          initialValue: widget.config.nameOrId,
          onChanged: (value) => widget.config.nameOrId = value,
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.descriptionsKey,
          onChanged: (value) => widget.config.descriptionsKey = value,
          label: 'Descriptions Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.rawStateKey,
          onChanged: (value) => widget.config.rawStateKey = value,
          label: 'Raw State Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.forceValuesKey,
          onChanged: (value) => widget.config.forceValuesKey = value,
          label: 'Force Values Key',
        ),
      ],
    );
  }
}

class _BeckhoffEL2008 extends ConsumerWidget {
  static const String name = 'EL2008';
  final BeckhoffEL2008Config config;
  final Animation<int> animation = const AlwaysStoppedAnimation(0);

  const _BeckhoffEL2008({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snap) {
        final stateMan = snap.data;

        // Helper to build the current LEDs (works even before data arrives)
        Widget buildBody(Map<String, DynamicValue>? data) {
          final leds =
              (data == null) ? List.filled(8, IOState.low) : _ledStates(data);
          return IO8Widget(
            ledStates: leds,
            name: name,
            animation: animation,
            ioLabels: const ['O1', 'O2', 'O3', 'O4', 'O5', 'O6', 'O7', 'O8'],
          );
        }

        return StreamBuilder<Map<String, DynamicValue>>(
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("raw", config.rawStateKey),
                    MapEntry("force", config.forceValuesKey),
                  ]),
                  stateMan,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (stateMan == null) return;
                showDialog(
                  context: context,
                  builder: (_) => _statusDialog(context, stateMan),
                );
              },
              child: buildBody(data),
            );
          },
        );
      },
    );
  }

  Widget _statusDialog(BuildContext context, StateMan stateMan) {
    return AlertDialog(
      title: Text(config.nameOrId),
      content: StreamBuilder<Map<String, DynamicValue>>(
        stream: _combinedStream(
          LinkedHashMap.fromEntries([
            MapEntry("raw", config.rawStateKey),
            MapEntry("force", config.forceValuesKey),
            MapEntry("descriptions", config.descriptionsKey),
          ]),
          stateMan,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final map = snapshot.data!;
          List<bool>? rawStates = map["raw"] != null
              ? List.generate(8, (i) => (map["raw"]!.asInt & (1 << i)) != 0)
              : null;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 8; i = i + 2)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RowIOView(
                      leftRaw: rawStates?[i] ?? false,
                      rightRaw: rawStates?[i + 1] ?? false,
                      leftProcessed: null,
                      rightProcessed: null,
                      leftSelected: map["force"]?[i].asInt ?? 0,
                      rightSelected: map["force"]?[i + 1].asInt ?? 0,
                      animationValue: animation,
                      leftOnChanged: (value) async {
                        map["force"]![i].value = value;
                        await stateMan.write(
                            config.forceValuesKey!, map["force"]!);
                      },
                      rightOnChanged: (value) async {
                        map["force"]![i + 1].value = value;
                        await stateMan.write(
                            config.forceValuesKey!, map["force"]!);
                      },
                      leftDescription: map["descriptions"]?[i].asString,
                      rightDescription: map["descriptions"]?[i + 1].asString,
                      leftFilterEdit: null,
                      rightFilterEdit: null,
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

@JsonSerializable()
class BeckhoffEL9222Config extends BaseAsset {
  String nameOrId;
  String? descriptionsKey;

  BeckhoffEL9222Config({
    required this.nameOrId,
    this.descriptionsKey,
  });

  @override
  Widget build(BuildContext context) {
    return _BeckhoffEL9222(config: this);
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
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _EL9222ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  BeckhoffEL9222Config.preview()
      : nameOrId = "1",
        descriptionsKey = null,
        super();

  factory BeckhoffEL9222Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEL9222ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffEL9222ConfigToJson(this);
}

class _EL9222ConfigContent extends StatefulWidget {
  final BeckhoffEL9222Config config;

  const _EL9222ConfigContent({required this.config});

  @override
  State<_EL9222ConfigContent> createState() => _EL9222ConfigContentState();
}

class _EL9222ConfigContentState extends State<_EL9222ConfigContent> {
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
          enableAngle: false,
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Name or ID',
            border: OutlineInputBorder(),
          ),
          initialValue: widget.config.nameOrId,
          onChanged: (value) => widget.config.nameOrId = value,
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.descriptionsKey,
          onChanged: (value) => widget.config.descriptionsKey = value,
          label: 'Descriptions Key',
        ),
      ],
    );
  }
}

class _BeckhoffEL9222 extends StatelessWidget {
  static const String name = 'EL9222';
  final BeckhoffEL9222Config config;

  const _BeckhoffEL9222({required this.config});

  @override
  Widget build(BuildContext context) {
    final leds = List.filled(6, IOState.low);

    return IO8Widget(
      ledStates: leds,
      name: name,
      animation: const AlwaysStoppedAnimation(0),
      ioLabels: const ['I1', 'O1', '+', '+', '-', '-', 'I2', 'O2'],
      ioLabelColors: const [
        ioLabelColor,
        ioLabelColor,
        Colors.red,
        Colors.red,
        Colors.blue,
        Colors.blue,
        ioLabelColor,
        ioLabelColor,
      ],
    );
  }
}

@JsonSerializable()
class BeckhoffEL9187Config extends BaseAsset {
  BeckhoffEL9187Config();

  @override
  Widget build(BuildContext context) {
    return _BeckhoffEL9187(config: this);
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
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _EL9187ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  BeckhoffEL9187Config.preview() : super();

  factory BeckhoffEL9187Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEL9187ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffEL9187ConfigToJson(this);
}

class _EL9187ConfigContent extends StatefulWidget {
  final BeckhoffEL9187Config config;

  const _EL9187ConfigContent({required this.config});

  @override
  State<_EL9187ConfigContent> createState() => _EL9187ConfigContentState();
}

class _EL9187ConfigContentState extends State<_EL9187ConfigContent> {
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
          enableAngle: false,
        ),
      ],
    );
  }
}

class _BeckhoffEL9187 extends StatelessWidget {
  static const String name = 'EL9187';
  final BeckhoffEL9187Config config;

  const _BeckhoffEL9187({required this.config});

  @override
  Widget build(BuildContext context) {
    final leds = List.filled(8, IOState.low);

    return IO8Widget(
      ledStates: leds,
      name: name,
      animation: const AlwaysStoppedAnimation(0),
      ioLabels: const ['OV', 'OV', 'OV', 'OV', 'OV', 'OV', 'OV', 'OV'],
      ioLabelColors: const [
        Colors.blue,
        Colors.blue,
        Colors.blue,
        Colors.blue,
        Colors.blue,
        Colors.blue,
        Colors.blue,
        Colors.blue,
      ],
    );
  }
}

@JsonSerializable()
class BeckhoffEL9186Config extends BaseAsset {
  BeckhoffEL9186Config();

  @override
  Widget build(BuildContext context) {
    return _BeckhoffEL9186(config: this);
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
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _EL9186ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  BeckhoffEL9186Config.preview() : super();

  factory BeckhoffEL9186Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEL9186ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffEL9186ConfigToJson(this);
}

class _EL9186ConfigContent extends StatefulWidget {
  final BeckhoffEL9186Config config;

  const _EL9186ConfigContent({required this.config});

  @override
  State<_EL9186ConfigContent> createState() => _EL9186ConfigContentState();
}

class _EL9186ConfigContentState extends State<_EL9186ConfigContent> {
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
          enableAngle: false,
        ),
      ],
    );
  }
}

class _BeckhoffEL9186 extends StatelessWidget {
  static const String name = 'EL9186';
  final BeckhoffEL9186Config config;

  const _BeckhoffEL9186({required this.config});

  @override
  Widget build(BuildContext context) {
    final leds = List.filled(8, IOState.low);

    return IO8Widget(
      ledStates: leds,
      name: name,
      animation: const AlwaysStoppedAnimation(0),
      ioLabels: const ['24V', '24V', '24V', '24V', '24V', '24V', '24V', '24V'],
      ioLabelColors: const [
        Colors.red,
        Colors.red,
        Colors.red,
        Colors.red,
        Colors.red,
        Colors.red,
        Colors.red,
        Colors.red,
      ],
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

List<IOState> _ledStates(Map<String, DynamicValue> data) {
  return List.generate(8, (i) {
    final forceValue = data["force"]?.asInt;
    if (forceValue == 1) return IOState.forcedLow;
    if (forceValue == 2) return IOState.forcedHigh;
    if (data["raw"]?.asInt == null) {
      return IOState.low;
    }
    return (data["raw"]!.asInt & (1 << i)) != 0 ? IOState.high : IOState.low;
  });
}

class _BeckhoffEL1008 extends ConsumerWidget {
  static const String name = 'EL1008';
  final BeckhoffEL1008Config config;
  final Animation<int> animation = const AlwaysStoppedAnimation(0);

  const _BeckhoffEL1008({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snap) {
        final stateMan = snap.data;

        // Helper to build the current LEDs (works even before data arrives)
        Widget buildBody(Map<String, DynamicValue>? data) {
          final leds =
              (data == null) ? List.filled(8, IOState.low) : _ledStates(data);
          return IO8Widget(ledStates: leds, name: name, animation: animation);
        }

        return StreamBuilder<Map<String, DynamicValue>>(
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("raw", config.rawStateKey),
                    MapEntry("force", config.forceValuesKey),
                  ]),
                  stateMan,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (stateMan == null) return;
                showDialog(
                  context: context,
                  builder: (_) => _statusDialog(context, stateMan),
                );
              },
              child: buildBody(data),
            );
          },
        );
      },
    );
  }

  Widget _statusDialog(BuildContext context, StateMan stateMan) {
    return AlertDialog(
      title: Text(config.nameOrId),
      content: StreamBuilder<Map<String, DynamicValue>>(
        stream: _combinedStream(
          LinkedHashMap.fromEntries([
            MapEntry("raw", config.rawStateKey),
            MapEntry("processed", config.processedStateKey),
            MapEntry("force", config.forceValuesKey),
            MapEntry("descriptions", config.descriptionsKey),
            MapEntry("on_filters", config.onFiltersKey),
            MapEntry("off_filters", config.offFiltersKey),
          ]),
          stateMan,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final map = snapshot.data!;
          List<bool>? rawStates = map["raw"] != null
              ? List.generate(8, (i) => (map["raw"]!.asInt & (1 << i)) != 0)
              : null;
          List<bool>? processedStates = map["processed"] != null
              ? List.generate(
                  8, (i) => (map["processed"]!.asInt & (1 << i)) != 0)
              : null;

          return Column(
            children: [
              for (int i = 0; i < 8; i = i + 2)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: i < 6
                          ? 2.0
                          : 0.0), // Reduced spacing, no padding on last item
                  child: RowIOView(
                    leftRaw: rawStates?[i] ?? false,
                    rightRaw: rawStates?[i + 1] ?? false,
                    leftProcessed: null,
                    rightProcessed: null,
                    leftSelected: map["force"]?[i].asInt ?? 0,
                    rightSelected: map["force"]?[i + 1].asInt ?? 0,
                    animationValue: animation,
                    leftOnChanged: (value) async {
                      map["force"]![i].value = value;
                      await stateMan.write(
                          config.forceValuesKey!, map["force"]!);
                    },
                    rightOnChanged: (value) async {
                      map["force"]![i + 1].value = value;
                      await stateMan.write(
                          config.forceValuesKey!, map["force"]!);
                    },
                    leftDescription: map["descriptions"]?[i].asString,
                    rightDescription: map["descriptions"]?[i + 1].asString,
                    leftFilterEdit: map.containsKey("on_filters") &&
                            map.containsKey("off_filters")
                        ? FilterEdit(
                            onFilter: map["on_filters"]?[i].asInt ?? 0,
                            offFilter: map["off_filters"]?[i].asInt ?? 0,
                            onChangedOnFilter: (value) async {
                              map["on_filters"]![i].value = value;
                              await stateMan.write(
                                  config.onFiltersKey!, map["on_filters"]!);
                            },
                            onChangedOffFilter: (value) async {
                              map["off_filters"]![i].value = value;
                              await stateMan.write(
                                  config.offFiltersKey!, map["off_filters"]!);
                            },
                          )
                        : null,
                    rightFilterEdit: map.containsKey("on_filters") &&
                            map.containsKey("off_filters")
                        ? FilterEdit(
                            onFilter: map["on_filters"]?[i + 1].asInt ?? 0,
                            offFilter: map["off_filters"]?[i + 1].asInt ?? 0,
                            onChangedOnFilter: (value) async {
                              map["on_filters"]![i + 1].value = value;
                              await stateMan.write(
                                  config.onFiltersKey!, map["on_filters"]!);
                            },
                            onChangedOffFilter: (value) async {
                              map["off_filters"]![i + 1].value = value;
                              await stateMan.write(
                                  config.offFiltersKey!, map["off_filters"]!);
                            },
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class IOForceButton extends StatelessWidget {
  const IOForceButton(
      {super.key, required this.onChanged, required this.selected});
  final void Function(int) onChanged;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: SegmentedButton(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: 0,
            label: Text('Auto'),
          ),
          ButtonSegment(
            value: 1,
            label: Text('Low '),
          ),
          ButtonSegment(
            value: 2,
            label: Text('High'),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (value) {
          onChanged(value.first);
        },
      ),
    );
  }
}

class FilterEdit extends StatelessWidget {
  final int onFilter;
  final int offFilter;
  final void Function(int) onChangedOnFilter;
  final void Function(int) onChangedOffFilter;
  const FilterEdit(
      {super.key,
      required this.onFilter,
      required this.offFilter,
      required this.onChangedOnFilter,
      required this.onChangedOffFilter});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'On filter',
                  suffixText: 'ms',
                ),
                initialValue: onFilter.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    onChangedOnFilter(int.parse(value));
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 100,
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Off filter',
                  suffixText: 'ms',
                ),
                initialValue: offFilter.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    onChangedOffFilter(int.parse(value));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RowControl extends StatelessWidget {
  final String? description;
  final int selected;
  final void Function(int) onChanged;
  final FilterEdit? filterEdit;
  const RowControl(
      {super.key,
      required this.description,
      required this.selected,
      required this.onChanged,
      this.filterEdit});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                description!.isNotEmpty
                    ? description![0].toUpperCase() + description!.substring(1)
                    : description!,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          IOForceButton(
            selected: selected,
            onChanged: onChanged,
          ),
          if (filterEdit != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: filterEdit!,
            ),
        ],
      ),
    );
  }
}

class RowIOView extends AnimatedWidget {
  const RowIOView({
    super.key,
    required this.leftRaw,
    required this.rightRaw,
    required this.leftProcessed,
    required this.rightProcessed,
    required this.leftSelected,
    required this.rightSelected,
    required this.leftOnChanged,
    required this.rightOnChanged,
    this.leftDescription,
    this.rightDescription,
    this.leftFilterEdit,
    this.rightFilterEdit,
    required Animation<int> animationValue,
  }) : super(listenable: animationValue);
  final int leftSelected;
  final int rightSelected;
  final bool leftRaw;
  final bool rightRaw;
  final bool? leftProcessed;
  final bool? rightProcessed;
  final void Function(int) leftOnChanged;
  final void Function(int) rightOnChanged;
  final String? leftDescription;
  final String? rightDescription;
  final FilterEdit? leftFilterEdit;
  final FilterEdit? rightFilterEdit;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<int>;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LEFT COLUMN: description + button
        RowControl(
          description: leftDescription,
          selected: leftSelected,
          onChanged: leftOnChanged,
          filterEdit: leftFilterEdit,
        ),
        const SizedBox(width: 16),
        // MIDDLE: the three boxes in a row
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CustomPaint(
              size: const Size(120, 120),
              painter: TriangleBoxPainter(
                colorLeft: leftRaw ? Colors.green : Colors.grey,
                colorRight:
                    (leftProcessed ?? leftRaw) ? Colors.green : Colors.grey,
                animationValue: leftSelected == 0 ? 0 : animation.value,
              ),
            ),
            Container(
              width: 120,
              height: 120,
              color: Colors.grey,
            ),
            CustomPaint(
              size: const Size(120, 120),
              painter: TriangleBoxPainter(
                colorLeft: rightRaw ? Colors.green : Colors.grey,
                colorRight:
                    (rightProcessed ?? rightRaw) ? Colors.green : Colors.grey,
                animationValue: rightSelected == 0 ? 0 : animation.value,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        // RIGHT COLUMN: description + button
        RowControl(
          description: rightDescription,
          selected: rightSelected,
          onChanged: rightOnChanged,
          filterEdit: rightFilterEdit,
        ),
      ],
    );
  }
}

class TriangleBoxPainter extends CustomPainter {
  final Color colorLeft;
  final Color colorRight;
  final int animationValue;

  TriangleBoxPainter({
    required this.colorLeft,
    required this.colorRight,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLeft = Paint()
      ..color = colorLeft
      ..style = PaintingStyle.fill;
    final paintRight = Paint()
      ..color = colorRight
      ..style = PaintingStyle.fill;

    // Draw first triangle
    final path1 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path1, paintLeft);

    // Draw second triangle
    final path2 = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, paintRight);

    const strokeWidth = 3.0;
    final rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
        size.width - strokeWidth, size.height - strokeWidth);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.red.withAlpha(animationValue);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(TriangleBoxPainter oldDelegate) => true;
}

@JsonSerializable()
class BeckhoffEL3054Config extends BaseAsset {
  String nameOrId;
  String? descriptionsKey;
  String? stateKey;
  String? errorsKey;

  BeckhoffEL3054Config({
    required this.nameOrId,
    this.descriptionsKey,
    this.stateKey,
    this.errorsKey,
  });

  @override
  Widget build(BuildContext context) {
    return _BeckhoffEL3054(config: this);
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
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _EL3054ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  BeckhoffEL3054Config.preview()
      : nameOrId = "1",
        descriptionsKey = null,
        stateKey = null,
        errorsKey = null,
        super();

  factory BeckhoffEL3054Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffEL3054ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffEL3054ConfigToJson(this);
}

class _EL3054ConfigContent extends StatefulWidget {
  final BeckhoffEL3054Config config;

  const _EL3054ConfigContent({required this.config});

  @override
  State<_EL3054ConfigContent> createState() => _EL3054ConfigContentState();
}

class _EL3054ConfigContentState extends State<_EL3054ConfigContent> {
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
          enableAngle: false,
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Name or ID',
            border: OutlineInputBorder(),
          ),
          initialValue: widget.config.nameOrId,
          onChanged: (value) => widget.config.nameOrId = value,
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.descriptionsKey,
          onChanged: (value) => widget.config.descriptionsKey = value,
          label: 'Descriptions Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.stateKey,
          onChanged: (value) => widget.config.stateKey = value,
          label: 'State Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.errorsKey,
          onChanged: (value) => widget.config.errorsKey = value,
          label: 'Errors Key',
        ),
      ],
    );
  }
}

class _BeckhoffEL3054 extends ConsumerWidget {
  static const String name = 'EL3054';
  final BeckhoffEL3054Config config;
  final Animation<int> animation = const AlwaysStoppedAnimation(0);

  const _BeckhoffEL3054({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snap) {
        final stateMan = snap.data;

        // Helper to build the current LEDs (works even before data arrives)
        Widget buildBody(Map<String, DynamicValue>? data) {
          final leds =
              (data == null) ? List.filled(8, IOState.low) : _ledStates(data);
          return IO8Widget(
            ledStates: leds,
            name: name,
            animation: animation,
            ioLabels: const ['+', '+', 'I1', 'I2', 'I3', 'I4', '+', '+'],
            ioLabelColors: const [
              Colors.red,
              Colors.red,
              ioLabelColor,
              ioLabelColor,
              ioLabelColor,
              ioLabelColor,
              Colors.red,
              Colors.red,
            ],
          );
        }

        return StreamBuilder<Map<String, DynamicValue>>(
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("errors", config.errorsKey),
                    MapEntry("states", config.stateKey),
                  ]),
                  stateMan,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (stateMan == null) return;
                showDialog(
                  context: context,
                  builder: (_) => _el3054StatusDialog(context, stateMan),
                );
              },
              child: buildBody(data),
            );
          },
        );
      },
    );
  }

  List<IOState> _ledStates(Map<String, DynamicValue> data) {
    // For analog inputs, we show error state if there are errors
    // Otherwise show low state (no LED) since these are analog, not digital
    return List.generate(8, (i) {
      if (i >= 2 && i < 6) {
        // Only first 4 positions are actual inputs
        if (data["errors"] != null &&
            data["errors"]!.isArray &&
            data["errors"]![i - 2].asInt != 0) {
          return IOState.error;
        }

        return IOState.low; // No LED for analog inputs
      }
      return IOState.low; // Red + positions
    });
  }

  Widget _el3054StatusDialog(BuildContext context, StateMan stateMan) {
    return AlertDialog(
      title: Text(config.nameOrId),
      content: StreamBuilder<Map<String, DynamicValue>>(
        stream: _combinedStream(
          LinkedHashMap.fromEntries([
            MapEntry("states", config.stateKey),
            MapEntry("descriptions", config.descriptionsKey),
          ]),
          stateMan,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final map = snapshot.data!;

          // Extract analog values for each input
          List<double?> analogValues = [];
          final states = map["states"];
          if (states != null) {
            // Assuming states contains an array of analog values
            if (states.isArray) {
              analogValues = List.generate(4, (i) {
                final val = states[i];
                if (val.isDouble || val.isInteger) {
                  return val.asDouble;
                }
                return null;
              });
            } else if (states.isInteger) {
              // If it's a single integer, we might need to decode it differently
              // For now, just show the raw value
              analogValues = List.filled(4, null);
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Current values section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.input,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Current Values',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Replace Wrap with Column for 2x2 grid layout
                      Column(
                        children: [
                          // First row: I1 and I2
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              SizedBox(
                                width: 200, // Fixed width for all cards
                                child: _InputValueCard(
                                  inputNumber: 1,
                                  value: analogValues[0],
                                  description: map["descriptions"]?[0].asString,
                                ),
                              ),
                              SizedBox(
                                width: 200, // Fixed width for all cards
                                child: _InputValueCard(
                                  inputNumber: 2,
                                  value: analogValues[1],
                                  description: map["descriptions"]?[1].asString,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12), // Spacing between rows
                          // Second row: I3 and I4
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              SizedBox(
                                width: 200, // Fixed width for all cards
                                child: _InputValueCard(
                                  inputNumber: 3,
                                  value: analogValues[2],
                                  description: map["descriptions"]?[2].asString,
                                ),
                              ),
                              SizedBox(
                                width: 200, // Fixed width for all cards
                                child: _InputValueCard(
                                  inputNumber: 4,
                                  value: analogValues[3],
                                  description: map["descriptions"]?[3].asString,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Graph section
              if (config.stateKey != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.show_chart,
                                color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              'Historical Data',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 600,
                          height: 280,
                          child: _EL3054Graph(
                            keyName: config.stateKey!,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _InputValueCard extends StatelessWidget {
  final int inputNumber;
  final double? value;
  final String? description;

  const _InputValueCard({
    required this.inputNumber,
    required this.value,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.input,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'I$inputNumber',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value != null ? value!.toStringAsFixed(3) : '---',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: value != null ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EL3054Graph extends ConsumerWidget {
  final String keyName;

  const _EL3054Graph({required this.keyName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Collector?>(
      future: ref.watch(collectorProvider.future),
      builder: (context, collectorSnapshot) {
        if (!collectorSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final collector = collectorSnapshot.data!;
        return StreamBuilder<List<TimeseriesData<dynamic>>>(
          stream:
              collector.collectStream(keyName, since: const Duration(hours: 2)),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No data'));
            }
            final samples = snapshot.data!;

            // Create separate series for each array element
            final seriesMap = <int, List<List<double>>>{};
            double vmin = double.infinity, vmax = -double.infinity;

            for (final s in samples) {
              final v = s.value;
              List<double>? values;
              if (v is List) {
                // Handle array data like [0,28829,0,0]
                values = v.whereType<num>().map((e) => e.toDouble()).toList();
              } else if (v is num) {
                values = [v.toDouble()];
              } else if (v is DynamicValue && v.isInteger) {
                values = [v.asInt.toDouble()];
              }
              if (values == null || values.isEmpty) continue;

              final t = s.time.millisecondsSinceEpoch.toDouble();
              // Add each value from the array to its own series
              for (int i = 0; i < values.length; i++) {
                final val = values[i];
                seriesMap.putIfAbsent(i, () => <List<double>>[]);
                seriesMap[i]!.add([t, val]);
                if (val < vmin) vmin = val;
                if (val > vmax) vmax = val;
              }
            }

            if (vmin == double.infinity) {
              return const Center(child: Text('No numeric data'));
            }
            if (vmin == vmax) vmax = vmin + 1;

            final cfg = GraphConfig(
              type: GraphType.timeseries,
              xAxis: GraphAxisConfig(unit: 'Time'),
              yAxis: GraphAxisConfig(unit: 'Value', min: vmin, max: vmax),
              xSpan: const Duration(minutes: 15),
            );

            // Convert seriesMap to the expected format
            int i = 1;
            final data = seriesMap.entries.map((entry) {
              return {
                GraphDataConfig(
                  label: 'I${i++}',
                  mainAxis: true,
                  color:
                      GraphConfig.colors[entry.key % GraphConfig.colors.length],
                ): entry.value
              };
            }).toList();

            return Graph(config: cfg, data: data);
          },
        );
      },
    );
  }
}
