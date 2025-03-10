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
    _log.d('Building AssetView with ${config.widgets.length} widgets');
    return BaseScaffold(
      title: 'Asset View',
      body: Stack(
        fit: StackFit.expand,
        children: [
          ...config.widgets.map((widget) {
            _log.t('Building widget of type ${widget.runtimeType}');
            return widget.build(context);
          }),
        ],
      ),
    );
  }
}
