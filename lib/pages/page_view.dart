import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../page_creator/assets/led.dart';
import '../page_creator/assets/circle_button.dart';
import '../page_creator/assets/common.dart';
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

final Map<Type, Asset Function(Map<String, dynamic>)> assetFactories = {
  LEDConfig: LEDConfig.fromJson,
  CircleButtonConfig: CircleButtonConfig.fromJson,
};

class AssetViewConfig {
  final List<Asset> widgets;

  AssetViewConfig({required this.widgets});

  factory AssetViewConfig.fromJson(Map<String, dynamic> json) {
    final List<Asset> foundWidgets = [];
    _log.d('Starting JSON parsing');
    _log.t('Input JSON: $json');

    void crawlJson(dynamic jsonPart) {
      if (jsonPart is Map<String, dynamic>) {
        _log.t('Crawling object: $jsonPart');
        if (jsonPart.containsKey(constAssetName)) {
          final assetName = jsonPart[constAssetName] as String;
          _log.d('Found potential asset: $assetName');

          for (final factory in assetFactories.entries) {
            if (factory.key.toString() == assetName) {
              try {
                final asset = factory.value(jsonPart);
                foundWidgets.add(asset);
                _log.d('Successfully parsed ${asset.assetName}');
                return; // Found an asset, don't crawl deeper
              } catch (e, stackTrace) {
                _log.e(
                  'Failed to parse asset of type $assetName',
                  error: e,
                  stackTrace: stackTrace,
                );
                rethrow;
              }
            }
          }
        }
        // If not an asset, crawl deeper
        _log.t('No asset found, crawling deeper');
        jsonPart.values.forEach(crawlJson);
      } else if (jsonPart is List) {
        _log.t('Crawling list of length ${jsonPart.length}');
        jsonPart.forEach(crawlJson);
      }
    }

    crawlJson(json);
    _log.d('Found ${foundWidgets.length} widgets');
    return AssetViewConfig(widgets: foundWidgets);
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
