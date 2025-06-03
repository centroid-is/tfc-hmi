import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/core/preferences.dart';

import '../page_creator/assets/common.dart'; // your Asset, Coordinates, RelativeSize, TextPos, etc.
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';
import '../widgets/zoomable_canvas.dart';

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

Matrix4 _buildTransform(AssetStackConfig cfg) {
  return Matrix4.identity()
    ..scale(cfg.xMirror ? -1.0 : 1.0, cfg.yMirror ? -1.0 : 1.0);
}

/// Computes the top-left offset for the label given the asset center, its size,
/// the label size, and the desired position.
Offset _labelOffset(
  Offset center,
  Size assetSize,
  Size textSize,
  TextPos pos, [
  double spacing = 8,
]) {
  final halfW = assetSize.width / 2;
  final halfH = assetSize.height / 2;
  switch (pos) {
    case TextPos.above:
      return Offset(
        center.dx - textSize.width / 2,
        center.dy - halfH - spacing - textSize.height,
      );
    case TextPos.below:
      return Offset(
        center.dx - textSize.width / 2,
        center.dy + halfH + spacing,
      );
    case TextPos.left:
      return Offset(
        center.dx - halfW - spacing - textSize.width,
        center.dy - textSize.height / 2,
      );
    case TextPos.right:
    default:
      return Offset(
        center.dx + halfW + spacing,
        center.dy - textSize.height / 2,
      );
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

        // We'll accumulate all Positioned children here
        final positionedChildren = <Widget>[];

        for (final asset in widget.assets) {
          // 1) normalized coords with optional mirroring
          final fx =
              cfg.xMirror ? 1 - asset.coordinates.x : asset.coordinates.x;
          final fy =
              cfg.yMirror ? 1 - asset.coordinates.y : asset.coordinates.y;

          // 2) canvas-pixel center point
          final cx = fx * W;
          final cy = fy * H;
          final center = Offset(cx, cy);

          final assetW = asset.size.width * W;
          final assetH = asset.size.height * H;
          final assetSize = Size(assetW, assetH);
          final halfW = assetW / 2;
          final halfH = assetH / 2;

          final textScaler = TextScaler.linear(
              math.min(asset.size.width * W, asset.size.height * H) / 25);
          final labelStyle = DefaultTextStyle.of(context).style.copyWith(
                fontSize: textScaler
                    .scale(DefaultTextStyle.of(context).style.fontSize ?? 16),
              );

          // 4) measure text size if any
          Size textSize = Size.zero;
          if (asset.text != null && asset.text!.isNotEmpty) {
            final tp = TextPainter(
              text: TextSpan(
                text: asset.text,
                style: labelStyle,
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            textSize = tp.size;
          }

          // A) add the asset widget itself
          positionedChildren.add(
            Positioned(
              left: cx - halfW,
              top: cy - halfH,
              child: Transform(
                alignment: Alignment.center,
                transform: asset.coordinates.angle != null
                    ? _buildTransform(cfg)
                    : Matrix4.identity(),
                child: GestureDetector(
                  onTap:
                      widget.onTap != null ? () => widget.onTap!(asset) : null,
                  onPanUpdate: widget.onPanUpdate != null
                      ? (d) => widget.onPanUpdate!(asset, d)
                      : null,
                  child: AbsorbPointer(
                    absorbing: widget.absorb,
                    child: SizedBox(
                      width: asset.size.width * W,
                      height: asset.size.height * H,
                      child: asset.build(context),
                    ),
                  ),
                ),
              ),
            ),
          );

          // B) add the label (if any)
          if (asset.text != null && asset.text!.isNotEmpty) {
            var pos = asset.textPos ?? TextPos.right;
            if (cfg.xMirror && (pos == TextPos.left || pos == TextPos.right)) {
              pos = pos == TextPos.left ? TextPos.right : TextPos.left;
            }
            if (cfg.yMirror && (pos == TextPos.above || pos == TextPos.below)) {
              pos = pos == TextPos.above ? TextPos.below : TextPos.above;
            }
            final labelOff = _labelOffset(center, assetSize, textSize, pos);
            positionedChildren.add(
              Positioned(
                left: labelOff.dx,
                top: labelOff.dy,
                child: Text(
                  asset.text!,
                  style: labelStyle,
                ),
              ),
            );
          }

          // C) add the red center dot
          positionedChildren.add(
            Positioned(
              left: cx - 4,
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
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: positionedChildren,
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
      body: ZoomableCanvas(
        child: LayoutBuilder(
          builder: (context, constraints) => AssetStack(
            assets: config.widgets,
            constraints: constraints,
            absorb: false,
          ),
        ),
      ),
    );
  }
}
