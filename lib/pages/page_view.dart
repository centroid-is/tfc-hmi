import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tfc/core/preferences.dart';

import '../page_creator/assets/common.dart';
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

  AssetStackConfig({
    this.xMirror = false,
    this.yMirror = false,
  });

  factory AssetStackConfig.fromJson(Map<String, dynamic> json) =>
      _$AssetStackConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AssetStackConfigToJson(this);
}

class AssetStack extends StatelessWidget {
  final List<Asset> assets;
  final BoxConstraints constraints;
  final void Function(Asset asset)? onTap;
  final void Function(Asset asset, DragUpdateDetails details)? onPanUpdate;
  final bool absorb;

  AssetStack({
    Key? key,
    required this.assets,
    required this.constraints,
    this.onTap,
    this.onPanUpdate,
    this.absorb = false,
  }) : super(key: key);
  final prefs = SharedPreferencesWrapper(SharedPreferencesAsync());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetStackConfig>(
        future: prefs.getString('asset_stack_config').then((value) {
          if (value == null) {
            prefs.setString(
                'asset_stack_config', jsonEncode(AssetStackConfig().toJson()));
            return AssetStackConfig();
          }
          return AssetStackConfig.fromJson(jsonDecode(value));
        }),
        builder: (context, snapshot) {
          return Stack(
            fit: StackFit.expand,
            children: assets.map((asset) {
              final x = (snapshot.data?.xMirror ?? false)
                  ? 1 - asset.coordinates.x
                  : asset.coordinates.x;
              final y = (snapshot.data?.yMirror ?? false)
                  ? 1 - asset.coordinates.y
                  : asset.coordinates.y;
              return Align(
                // FractionalOffset(0,0) is top‐left, (1,1) bottom‐right,
                // and Align positions the CHILD’S CENTER there.
                alignment: FractionalOffset(x, y),
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
          );
        });
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
