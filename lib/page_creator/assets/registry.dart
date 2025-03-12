import 'package:logger/logger.dart';
import 'common.dart';
import 'led.dart';
import 'circle_button.dart';

class AssetRegistry {
  static final Logger _log = Logger();

  static final Map<Type, Asset Function(Map<String, dynamic>)>
      fromJsonFactories = {
    LEDConfig: LEDConfig.fromJson,
    CircleButtonConfig: CircleButtonConfig.fromJson,
  };

  static final Map<Type, Asset Function()> defaultFactories = {
    LEDConfig: LEDConfig.preview,
    CircleButtonConfig: CircleButtonConfig.preview,
  };

  static List<Asset> parse(Map<String, dynamic> json) {
    final List<Asset> foundWidgets = [];
    void crawlJson(dynamic jsonPart) {
      if (jsonPart is Map<String, dynamic>) {
        _log.t('Crawling object: $jsonPart');
        if (jsonPart.containsKey(constAssetName)) {
          final assetName = jsonPart[constAssetName] as String;
          _log.d('Found potential asset: $assetName');

          for (final factory in fromJsonFactories.entries) {
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
    return foundWidgets;
  }

  static Asset createDefaultAsset(Type assetType) {
    final factory = defaultFactories[assetType];
    if (factory == null) {
      throw Exception('Unknown asset type');
    }
    return factory();
  }
}
