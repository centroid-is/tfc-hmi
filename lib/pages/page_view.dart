import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';

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

class AssetStack extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ...assets.map((asset) {
          return Positioned(
            left: asset.coordinates.x * constraints.maxWidth,
            top: asset.coordinates.y * constraints.maxHeight,
            child: GestureDetector(
              onTap: onTap != null ? () => onTap!(asset) : null,
              onPanUpdate: onPanUpdate != null
                  ? (details) => onPanUpdate!(asset, details)
                  : null,
              child: AbsorbPointer(
                absorbing: absorb,
                child: asset.build(context),
              ),
            ),
          );
        }).toList(),
      ],
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

  const AssetView({
    super.key,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Asset View',
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AssetStack(
                assets: config.widgets,
                constraints: constraints,
                absorb: false, // allow interaction in view mode
              );
            },
          ),
        ),
      ),
    );
  }
}
