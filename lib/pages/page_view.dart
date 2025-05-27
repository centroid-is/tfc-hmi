import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/core/preferences.dart';

import '../page_creator/assets/common.dart'; // your Asset, Coordinates, RelativeSize, etc.
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';

part 'page_view.g.dart';

final _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

@JsonSerializable()
class AssetStackConfig {
  bool xMirror;
  bool yMirror;
  AssetStackConfig({this.xMirror = false, this.yMirror = false});
  factory AssetStackConfig.fromJson(Map<String, dynamic> json) =>
      _$AssetStackConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AssetStackConfigToJson(this);
}

/// A helper widget that measures its child’s laid-out Size
/// and calls `onChange(Size)` whenever it changes.
typedef OnWidgetSizeChange = void Function(Size size);

class MeasureSize extends StatefulWidget {
  final Widget child;
  final OnWidgetSizeChange onChange;
  const MeasureSize({required this.child, required this.onChange, Key? key})
      : super(key: key);
  @override
  _MeasureSizeState createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final newSize = (context.findRenderObject() as RenderBox).size;
      if (_oldSize != newSize) {
        _oldSize = newSize;
        widget.onChange(newSize);
      }
    });
    return widget.child;
  }
}

class AssetStack extends StatefulWidget {
  final List<Asset> assets;
  final BoxConstraints constraints;
  final void Function(Asset asset)? onTap;
  final void Function(Asset asset, DragUpdateDetails details)? onPanUpdate;
  final bool absorb;

  const AssetStack({
    Key? key,
    required this.assets,
    required this.constraints,
    this.onTap,
    this.onPanUpdate,
    this.absorb = false,
  }) : super(key: key);

  @override
  State<AssetStack> createState() => _AssetStackState();
}

class _AssetStackState extends State<AssetStack> {
  final prefs = SharedPreferencesWrapper(SharedPreferencesAsync());
  final Map<Asset, Size> _measuredSizes = {};

  @override
  Widget build(BuildContext context) {
    final W = widget.constraints.maxWidth;
    final H = widget.constraints.maxHeight;

    return FutureBuilder<AssetStackConfig>(
      future: prefs.getString('asset_stack_config').then((value) {
        if (value == null) {
          final cfg = AssetStackConfig();
          prefs.setString('asset_stack_config', jsonEncode(cfg.toJson()));
          return cfg;
        }
        return AssetStackConfig.fromJson(jsonDecode(value));
      }),
      builder: (context, snap) {
        final cfg = snap.data ?? AssetStackConfig();

        return Stack(
          fit: StackFit.expand,
          children: widget.assets.map((asset) {
            // 1) Compute normalized coords (with optional mirroring)
            final fx =
                cfg.xMirror ? 1 - asset.coordinates.x : asset.coordinates.x;
            final fy =
                cfg.yMirror ? 1 - asset.coordinates.y : asset.coordinates.y;

            // 2) Canvas‐pixel center point
            final cx = fx * W;
            final cy = fy * H;

            // 3) Determine half‐size: either measured or fallback to config.size
            final measured = _measuredSizes[asset];
            final halfW = (measured?.width ?? (asset.size.width * W)) / 2;
            final halfH = (measured?.height ?? (asset.size.height * H)) / 2;

            return Stack(children: [
              // A) The asset itself, wrapped in MeasureSize + GestureDetector
              Positioned(
                left: cx - halfW,
                top: cy - halfH,
                child: Row(
                  children: [
                    buildWithText(
                        MeasureSize(
                          onChange: (s) {
                            // store and re‐layout
                            setState(() => _measuredSizes[asset] = s);
                          },
                          child: GestureDetector(
                            onTap: widget.onTap != null
                                ? () => widget.onTap!(asset)
                                : null,
                            onPanUpdate: widget.onPanUpdate != null
                                ? (d) => widget.onPanUpdate!(asset, d)
                                : null,
                            child: AbsorbPointer(
                              absorbing: widget.absorb,
                              child: asset.build(context),
                            ),
                          ),
                        ),
                        asset.text,
                        asset.textPos),
                  ],
                ),
              ),

              // B) The red dot at the *exact* center on the canvas
              Positioned(
                left: cx - 4, // dot is 8×8 → half = 4
                top: cy - 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ]);
          }).toList(),
        );
      },
    );
  }
}

class AssetViewConfig {
  final List<Asset> widgets;
  AssetViewConfig({required this.widgets});
  factory AssetViewConfig.fromJson(Map<String, dynamic> json) {
    final widgets = AssetRegistry.parse(json);
    _log.d('Found ${widgets.length} widgets');
    return AssetViewConfig(widgets: widgets);
  }
}

class AssetView extends StatelessWidget {
  final AssetViewConfig config;
  const AssetView({Key? key, required this.config}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Asset View',
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
            builder: (context, constraints) => AssetStack(
              assets: config.widgets,
              constraints: constraints,
              absorb: false,
            ),
          ),
        ),
      ),
    );
  }
}
