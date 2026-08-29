import 'dart:collection' show LinkedHashMap;

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:tfc/widgets/panes/standard_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'common.dart';
import '../../painter/beckhoff/cx5010.dart';
import '../../painter/beckhoff/ek1100.dart';
import '../../painter/beckhoff/io8.dart';
import 'package:tfc_dart/core/state_man.dart';
import '../../providers/state_man.dart';
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'el9222.dart';
import 'io_pane.dart';
import '../page.dart';
import '../../page_creator/assets/graph.dart';
import '../../widgets/graph.dart';
import '../../widgets/memo_stream_builder.dart';

part 'beckhoff.g.dart';

const Map<String, Asset Function()> _availableSubdevices = {
  "EL1008": BeckhoffEL1008Config.preview,
  "EL2008": BeckhoffEL2008Config.preview,
  "EL3054": BeckhoffEL3054Config.preview,
  "EL9222": BeckhoffEL9222Config.preview,
  "EL9187": BeckhoffEL9187Config.preview,
  "EL9186": BeckhoffEL9186Config.preview,
};

/// A Beckhoff CX embedded PC carrying a rack of subdevices.
///
/// The `CXxxxx` painter has always taken the model name as a parameter — its
/// own comment says the label is "actually whatever `name` is" — so the CX
/// variants on this plant differ in exactly one string. Everything that is
/// not that string lives here, once.
///
/// A variant is a concrete `@JsonSerializable` subclass rather than a `model`
/// field on one class, because the page editor picks assets by type: the
/// palette, `assetRegistry`, and the saved `asset_name` in a page's JSON all
/// key off the class. A CX5010 and a CX5340 are different pieces of hardware
/// and an operator should be able to place the right one.
///
/// The drawing is a CX50xx front: the CX53xx is a wider box with a different
/// port complement, so a CX5340 renders as the right label on approximately
/// the right shape, not a photograph. That is the same bargain every mimic on
/// this page makes — the asset is there to be identified and clicked, and the
/// label is what identifies it.
abstract class BeckhoffCXConfig extends BaseAsset {
  BeckhoffCXConfig();

  @override
  String get category => 'Beckhoff Devices';

  /// The name printed down the red stripe, e.g. `CX5340`.
  String get model;

  @override
  String get displayName => 'Beckhoff $model';

  @AssetListConverter()
  List<Asset> subdevices = [];

  @override
  List<String> get allKeys {
    final keys = <String>{};
    for (final sub in subdevices) {
      if (sub is BaseAsset) {
        keys.addAll(sub.allKeys);
      }
    }
    return keys.toList();
  }

  /// Native painter size for the CX drawing (keeps 105.5:100 aspect).
  static const Size cxNativeSize = Size(1055, 1000);

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
            // Main CX device at native size; outer FittedBox scales it.
            CustomPaint(
              size: cxNativeSize,
              painter: CXxxxx(
                name: model,
                pwrColor: Colors.green,
                tcColor: Colors.green,
              ),
            ),
            // Subdevices to the right, normalized to match CX height
            if (subdevices.isNotEmpty) ...[
              for (final sub in subdevices)
                _SubdeviceNormalized(
                  child: sub.build(context),
                  targetHeight: cxNativeSize.height,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget configure(BuildContext context) {
    return SizedBox(
      width: 800,
      height: 500,
      child: _CXxxxxConfigContent(config: this),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class BeckhoffCX5010Config extends BeckhoffCXConfig {
  @override
  String get model => 'CX5010';

  BeckhoffCX5010Config();

  static const previewStr = 'Baader221 preview';

  BeckhoffCX5010Config.preview() : super();

  factory BeckhoffCX5010Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffCX5010ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffCX5010ConfigToJson(this);
}

/// The CX5340 that heads ST101. Same asset as the [BeckhoffCX5010Config] in
/// every respect but the label — see [BeckhoffCXConfig].
@JsonSerializable(explicitToJson: true)
class BeckhoffCX5340Config extends BeckhoffCXConfig {
  @override
  String get model => 'CX5340';

  BeckhoffCX5340Config();

  BeckhoffCX5340Config.preview() : super();

  factory BeckhoffCX5340Config.fromJson(Map<String, dynamic> json) =>
      _$BeckhoffCX5340ConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$BeckhoffCX5340ConfigToJson(this);
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
  final BeckhoffCXConfig config;

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
                Text(widget.config.model,
                    style: Theme.of(context).textTheme.titleMedium),
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
                // No "Done" button here. It used to pop the navigator, which
                // dismissed the config dialog this editor was shown in; the
                // editor now embeds it in a side pane that is not a route, so
                // the same tap would navigate out of the page editor
                // altogether. The pane's own action bar owns dismissal.
                Text('Subdevices',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // Long subdevice names must ellipsize, not push the field
                  // wider than the column it sits in.
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Add Subdevice',
                  ),
                  value: null,
                  hint: const Text('Select a subdevice to add',
                      overflow: TextOverflow.ellipsis),
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
                            onTap: () => showStandardDialog<void>(
                              context: context,
                              title: sub.runtimeType.toString(),
                              subtitle: 'Configuration',
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

@JsonSerializable(explicitToJson: true)
class BeckhoffEK1100Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EK1100';
  @override
  String get category => 'Beckhoff Devices';

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
    return SizedBox(
      width: 800,
      height: 500,
      child: _EK1100ConfigContent(config: this),
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
                // No "Done" button here. It used to pop the navigator, which
                // dismissed the config dialog this editor was shown in; the
                // editor now embeds it in a side pane that is not a route, so
                // the same tap would navigate out of the page editor
                // altogether. The pane's own action bar owns dismissal.
                Text('Subdevices',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // Long subdevice names must ellipsize, not push the field
                  // wider than the column it sits in.
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Add Subdevice',
                  ),
                  value: null,
                  hint: const Text('Select a subdevice to add',
                      overflow: TextOverflow.ellipsis),
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
                            onTap: () => showStandardDialog<void>(
                              context: context,
                              title: sub.runtimeType.toString(),
                              subtitle: 'Configuration',
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

@JsonSerializable(explicitToJson: true)
class BeckhoffEL1008Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EL1008';
  @override
  String get category => 'Beckhoff Devices';

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
    return FittedBox(
      fit: BoxFit.contain,
      child: _BeckhoffEL1008(config: this),
    );
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

@JsonSerializable(explicitToJson: true)
class BeckhoffEL2008Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EL2008';
  @override
  String get category => 'Beckhoff Devices';

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
    return FittedBox(
      fit: BoxFit.contain,
      child: _BeckhoffEL2008(config: this),
    );
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

  /// Identity of this module's docked pane — tapping it again toggles it.
  String get _paneId => 'el2008:${identityHashCode(config)}';

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

        return MemoStreamBuilder<Map<String, DynamicValue>>(
          keys: [stateMan, config],
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("raw", config.rawStateKey),
                    MapEntry("force", config.forceValuesKey),
                  ]),
                  ref,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            // The pane lives in the root overlay, so it must be closed when
            // this module leaves the page — see [SidePaneOwner].
            return SidePaneOwner(
              paneId: _paneId,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (stateMan == null) return;
                  showIoModulePane(
                    context: context,
                    id: _paneId,
                    title: config.nameOrId,
                    subtitle: 'Beckhoff · 8 DO',
                    highLabel: 'On',
                    summaryStream: _combinedStream(
                      LinkedHashMap.fromEntries([
                        MapEntry("raw", config.rawStateKey),
                        MapEntry("force", config.forceValuesKey),
                      ]),
                      ref,
                    ),
                    statesOf: (data) => data == null
                        ? List.filled(8, IOState.low)
                        : _ledStates(data),
                    gridSummary: 'Force and descriptions for all 8 channels',
                    gridSize: const Size(940, 460),
                    gridBuilder: (_) => IoGridViewport(
                      child: _channelGrid(context, ref, stateMan),
                    ),
                  );
                },
                child: buildBody(data),
              ),
            );
          },
        );
      },
    );
  }

  /// The per-channel grid, lifted out of the `AlertDialog` this used to be.
  /// Force writes and descriptions are unchanged — only the host moved.
  Widget _channelGrid(
      BuildContext context, WidgetRef ref, StateMan stateMan) {
    return MemoStreamBuilder<Map<String, DynamicValue>>(
      keys: [stateMan, config],
      stream: _combinedStream(
        LinkedHashMap.fromEntries([
          MapEntry("raw", config.rawStateKey),
          MapEntry("force", config.forceValuesKey),
          MapEntry("descriptions", config.descriptionsKey),
        ]),
        ref,
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
    );
  }
}

@JsonSerializable(explicitToJson: true)
class BeckhoffEL9222Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EL9222';
  @override
  String get category => 'Beckhoff Devices';

  String nameOrId;

  /// Key of the terminal's `ST_EL9222_5500` struct. Without it the module is
  /// a picture: the face has nothing to light and the pane has nothing to
  /// reset.
  String? stateKey;

  /// Optional array of what each channel feeds, one entry per channel. The
  /// pane names the load instead of leaving the operator to count terminals.
  String? descriptionsKey;

  BeckhoffEL9222Config({
    required this.nameOrId,
    this.stateKey,
    this.descriptionsKey,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: _BeckhoffEL9222(config: this),
    );
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
        stateKey = null,
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
          initialValue: widget.config.stateKey,
          onChanged: (value) => widget.config.stateKey = value,
          label: 'State Key',
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

/// The overcurrent protection terminal, live.
///
/// Until this read its struct it was a drawing: six lamps hardcoded to
/// `IOState.low`, no subscription, no tap target. A tripped breaker looked
/// exactly like a healthy one, and the only way to put a channel back on was
/// to walk to the cabinet and press the button on the terminal.
///
/// The face now says which channel is out ([el9222FaceLeds]) and a tap opens
/// the pane that resets it. See `el9222.dart` for the decode and the
/// operator surface.
class _BeckhoffEL9222 extends ConsumerWidget {
  static const String name = 'EL9222';
  final BeckhoffEL9222Config config;

  const _BeckhoffEL9222({required this.config});

  /// Identity of this module's docked pane — tapping it again toggles it.
  String get _paneId => 'el9222:${identityHashCode(config)}';

  /// The keys behind both the face and the pane: the struct, plus the
  /// optional per-channel load names.
  LinkedHashMap<String, String?> get _keys => LinkedHashMap.fromEntries([
        MapEntry("state", config.stateKey),
        MapEntry("descriptions", config.descriptionsKey),
      ]);

  /// The face's stream, off the shared providers.
  Stream<({List<El9222ChannelStatus> channels, List<String> loads})> _faceStream(
          WidgetRef ref) =>
      _combinedStream(_keys, ref).map(_decode);

  /// The pane's own stream.
  ///
  /// Deliberately NOT the face's: a `CombineLatestStream` takes one listener,
  /// and the pane needs a subscription with the pane's lifetime anyway — it
  /// is built into the root overlay and must release what it opened when it
  /// closes. Going through [StateMan] rather than `ref` also keeps the tap
  /// handler out of the provider container it is no longer building in.
  Stream<({List<El9222ChannelStatus> channels, List<String> loads})> _paneStream(
          StateMan stateMan) =>
      _combinedStreamVia(_keys, stateMan).map(_decode);

  static ({List<El9222ChannelStatus> channels, List<String> loads}) _decode(
      Map<String, DynamicValue> data) {
    final struct = data["state"];
    final descriptions = data["descriptions"];
    return (
      channels: [
        El9222ChannelStatus.read(struct, 1),
        El9222ChannelStatus.read(struct, 2),
      ],
      loads: (descriptions != null && descriptions.isArray)
          ? descriptions.asArray.map((d) => d.asString).toList()
          : const <String>[],
    );
  }

  /// Pulses `p_cmd_Reset` for [channel].
  ///
  /// The terminal acknowledges a trip on a RISING EDGE and no PLC code ever
  /// clears the bit, so both halves of the edge are ours. Each write clones
  /// the value as it stands at that moment rather than one captured up
  /// front, so resetting one channel cannot undo a reset the operator
  /// started on the other in between.
  ///
  /// The falling edge runs in a `finally`: a `p_cmd_Reset` left high is a
  /// latched switch where the terminal expects an edge, and the next trip
  /// would never be acknowledged. A clear that fails is reported rather than
  /// swallowed for the same reason — it is a real maintenance condition, not
  /// a cosmetic one.
  Future<void> _reset(
    BuildContext context,
    StateMan stateMan,
    int channel,
  ) async {
    final key = config.stateKey;
    if (key == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final member = el9222ResetMember(channel);

    // Bounded so a server that stops answering cannot leave the button
    // saying 'Resetting…' forever. The same length `key_repository` reads
    // with.
    const readTimeout = Duration(seconds: 5);

    Future<void> set(bool level) async {
      final latest = await stateMan.read(key).timeout(readTimeout);
      final next = DynamicValue.from(latest);
      next[member] = level;
      await stateMan.write(key, next);
    }

    try {
      await set(true);
      await Future<void>.delayed(kEl9222ResetPulse);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Reset of channel $channel failed: $e')),
      );
    } finally {
      try {
        await set(false);
      } catch (e) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Channel $channel reset is stuck on — clear it before the next '
              'trip: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snap) {
        final stateMan = snap.data;
        // Resolved in build, not in the tap handler: `ref.watch` belongs to a
        // build, and the pane needs the same stream the face is already on.
        final stream = (stateMan == null || config.stateKey == null)
            ? null
            : _faceStream(ref);

        return MemoStreamBuilder<
            ({List<El9222ChannelStatus> channels, List<String> loads})>(
          keys: [stateMan, config],
          stream: stream ?? const Stream.empty(),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data : null;
            final channels = data?.channels ??
                [
                  El9222ChannelStatus.read(null, 1),
                  El9222ChannelStatus.read(null, 2),
                ];

            // The pane lives in the root overlay, so it must be closed when
            // this module leaves the page — see [SidePaneOwner].
            return SidePaneOwner(
              paneId: _paneId,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (stateMan == null || config.stateKey == null) return;
                  showEl9222Pane(
                    context: context,
                    id: _paneId,
                    title: config.nameOrId,
                    stream: _paneStream(stateMan),
                    onReset: (channel) => _reset(context, stateMan, channel),
                  );
                },
                child: IO8Widget(
                  ledStates: el9222FaceLeds(channels[0], channels[1]),
                  name: name,
                  // The `!` on the face is the honest answer to "is this
                  // terminal telling me anything?" — six dark lamps are not,
                  // since dark is also what a healthy switched-off channel
                  // looks like.
                  disconnected: data == null,
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
                ),
              ),
            );
          },
        );
      },
    );
  }
}

@JsonSerializable(explicitToJson: true)
class BeckhoffEL9187Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EL9187';
  @override
  String get category => 'Beckhoff Devices';

  BeckhoffEL9187Config();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: _BeckhoffEL9187(config: this),
    );
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

@JsonSerializable(explicitToJson: true)
class BeckhoffEL9186Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EL9186';
  @override
  String get category => 'Beckhoff Devices';

  BeckhoffEL9186Config();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: _BeckhoffEL9186(config: this),
    );
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

/// The named keys of one module, combined.
///
/// Reads each key through [keyStreamProvider] rather than subscribing here.
/// These modules are page assets, so this runs on every rebuild — and a fresh
/// `subscribe` per rebuild is a monitored-item create-and-cancel per frame
/// while a window is being dragged. The per-key streams are shared and stable
/// now; only the combination of them is rebuilt, which costs nothing.
/// The same, for a side pane.
///
/// A pane outlives the build that opened it, so it has no build to hold a
/// `ref.watch` in — and a watch that lapses would let the shared stream be
/// disposed underneath it. A pane is opened deliberately and one at a time,
/// so subscribing directly costs nothing worth the plumbing.
CombineLatestStream<DynamicValue, Map<String, DynamicValue>> _combinedStreamVia(
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

CombineLatestStream<DynamicValue, Map<String, DynamicValue>> _combinedStream(
    LinkedHashMap<String, String?> keys, WidgetRef ref) {
  return CombineLatestStream([
    for (var entry in keys.entries)
      if (entry.value != null) ref.watch(keyStreamProvider(entry.value!)),
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

  /// Identity of this module's docked pane — tapping it again toggles it.
  String get _paneId => 'el1008:${identityHashCode(config)}';

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

        return MemoStreamBuilder<Map<String, DynamicValue>>(
          keys: [stateMan, config],
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("raw", config.rawStateKey),
                    MapEntry("force", config.forceValuesKey),
                  ]),
                  ref,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            // The pane lives in the root overlay, so it must be closed when
            // this module leaves the page — see [SidePaneOwner].
            return SidePaneOwner(
              paneId: _paneId,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (stateMan == null) return;
                  showIoModulePane(
                    context: context,
                    id: _paneId,
                    title: config.nameOrId,
                    subtitle: 'Beckhoff · 8 DI',
                    highLabel: 'High',
                    summaryStream: _combinedStream(
                      LinkedHashMap.fromEntries([
                        MapEntry("raw", config.rawStateKey),
                        MapEntry("force", config.forceValuesKey),
                      ]),
                      ref,
                    ),
                    statesOf: (data) => data == null
                        ? List.filled(8, IOState.low)
                        : _ledStates(data),
                    gridSummary: 'Force and descriptions for all 8 channels',
                    gridSize: const Size(940, 460),
                    gridBuilder: (_) => IoGridViewport(
                      child: _channelGrid(context, ref, stateMan),
                    ),
                  );
                },
                child: buildBody(data),
              ),
            );
          },
        );
      },
    );
  }

  /// The per-channel grid, lifted out of the `AlertDialog` this used to be.
  /// Force writes and descriptions are unchanged — only the host moved.
  Widget _channelGrid(
      BuildContext context, WidgetRef ref, StateMan stateMan) {
    return MemoStreamBuilder<Map<String, DynamicValue>>(
      keys: [stateMan, config],
      stream: _combinedStream(
        LinkedHashMap.fromEntries([
          MapEntry("raw", config.rawStateKey),
          MapEntry("processed", config.processedStateKey),
          MapEntry("force", config.forceValuesKey),
          MapEntry("descriptions", config.descriptionsKey),
          MapEntry("on_filters", config.onFiltersKey),
          MapEntry("off_filters", config.offFiltersKey),
        ]),
        ref,
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
            ? List.generate(8, (i) => (map["processed"]!.asInt & (1 << i)) != 0)
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
                    await stateMan.write(config.forceValuesKey!, map["force"]!);
                  },
                  rightOnChanged: (value) async {
                    map["force"]![i + 1].value = value;
                    await stateMan.write(config.forceValuesKey!, map["force"]!);
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
    // Not DurationFields: two of these sit side by side in the IO pane's
    // channel grid, and a unit dropdown does not fit the row. Filter times
    // are 1-3 digit millisecond figures, so there are no zeros to count —
    // the field just needs to not throw on junk, which the old bare
    // int.parse did.
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
                keyboardType: TextInputType.number,
                initialValue: onFilter.toString(),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed >= 0) {
                    onChangedOnFilter(parsed);
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
                keyboardType: TextInputType.number,
                initialValue: offFilter.toString(),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed >= 0) {
                    onChangedOffFilter(parsed);
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
  bool shouldRepaint(TriangleBoxPainter oldDelegate) =>
      oldDelegate.colorLeft != colorLeft ||
      oldDelegate.colorRight != colorRight ||
      oldDelegate.animationValue != animationValue;
}

@JsonSerializable(explicitToJson: true)
class BeckhoffEL3054Config extends BaseAsset {
  @override
  String get displayName => 'Beckhoff EL3054';
  @override
  String get category => 'Beckhoff Devices';

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
    return FittedBox(
      fit: BoxFit.contain,
      child: _BeckhoffEL3054(config: this),
    );
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

  /// Identity of this module's docked pane — tapping it again toggles it.
  String get _paneId => 'el3054:${identityHashCode(config)}';

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

        return MemoStreamBuilder<Map<String, DynamicValue>>(
          keys: [stateMan, config],
          stream: (stateMan == null)
              ? const Stream.empty()
              : _combinedStream(
                  LinkedHashMap.fromEntries([
                    MapEntry("errors", config.errorsKey),
                    MapEntry("states", config.stateKey),
                  ]),
                  ref,
                ),
          builder: (context, s) {
            final data = (s.hasData && !s.hasError) ? s.data! : null;

            // The pane lives in the root overlay, so it must be closed when
            // this module leaves the page — see [SidePaneOwner].
            return SidePaneOwner(
              paneId: _paneId,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (stateMan == null) return;
                  _showEl3054Pane(context, stateMan);
                },
                child: buildBody(data),
              ),
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

  /// The EL3054's operator pane: the four analog readings as tiles, with the
  /// history behind a chart tile.
  ///
  /// The old dialog was 70%×75% of the screen and put the trend *inside* it,
  /// so reading a value meant covering the plant view with a window that was
  /// mostly chart. Split the pane way round: numbers at a glance, the chart
  /// in a floating window that can be dragged aside and left running.
  void _showEl3054Pane(BuildContext context, StateMan stateMan) {
    showSidePane(
      context: context,
      id: _paneId,
      builder: (paneContext) => MemoStreamBuilder<Map<String, DynamicValue>>(
        keys: [stateMan, config],
        stream: _combinedStreamVia(
          LinkedHashMap.fromEntries([
            MapEntry("states", config.stateKey),
            MapEntry("descriptions", config.descriptionsKey),
          ]),
          stateMan,
        ),
        builder: (context, snapshot) {
          final map =
              (snapshot.hasData && !snapshot.hasError) ? snapshot.data : null;

          // The state key carries either an array of four readings or a
          // single integer (nothing useful yet) — same parse as before.
          final states = map?["states"];
          final values = List<double?>.generate(4, (i) {
            if (states == null || !states.isArray) return null;
            final v = states[i];
            return (v.isDouble || v.isInteger) ? v.asDouble : null;
          });

          return SidePane(
            title: config.nameOrId,
            subtitle: 'Beckhoff · 4 AI',
            icon: Icons.linear_scale,
            status: map == null
                ? const PaneStatus.stale('No data')
                : const PaneStatus.running('Live'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                PaneSection(
                  title: 'Inputs',
                  child: PaneTileRow(
                    children: [
                      for (int i = 0; i < 4; i++)
                        PaneMetricTile(
                          label:
                              map?["descriptions"]?[i].asString ?? 'I${i + 1}',
                          value: values[i]?.toStringAsFixed(2) ?? '—',
                          icon: Icons.input,
                        ),
                    ],
                  ),
                ),
                if (config.stateKey != null) ...[
                  const Divider(height: 1),
                  PaneSection(
                    title: 'Trend',
                    child: PaneGraphTile(
                      label: 'Analog inputs',
                      height: 130,
                      // Compact in the tile, full chart behind the tap: the
                      // legend column and the pan/zoom row belong in the
                      // dialog, not in 130px of pane.
                      preview: _el3054Graph(compact: true),
                      expandedTitle: '${config.nameOrId} — history',
                      expandedSize: const Size(820, 520),
                      expandedBuilder: (_) => _el3054Graph(),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _el3054Graph({bool compact = false}) => GraphAsset(
        GraphAssetConfig(
          graphType: GraphType.timeseries,
          primarySeries: [
            GraphSeriesConfig(key: config.stateKey!, label: 'Analog Input'),
          ],
          yAxis: GraphAxisConfig(title: 'Value', unit: 'relative'),
          timeWindowMinutes: const Duration(minutes: 10),
        ),
        compact: compact,
      );
}
