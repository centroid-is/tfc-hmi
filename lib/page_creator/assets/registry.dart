import 'package:logger/logger.dart';
import 'common.dart';
import 'led.dart';
import 'button.dart';
import 'conveyor.dart';
import 'arrow.dart';
import 'led_column.dart';
import 'drawn_box.dart';
import 'number.dart';
import 'checkweigher.dart';
import 'graph.dart';
import 'ratio_number.dart';
import 'baader.dart';
import 'analog_box.dart';
import 'option_variable.dart';
import 'text.dart';
import 'beckhoff.dart';
import 'schneider.dart';
import 'icon.dart';
import 'table.dart';
import 'start_stop_button.dart';

class AssetRegistry {
  static final Logger _log = Logger();

  static final Map<Type, Asset Function(Map<String, dynamic>)>
      _fromJsonFactories = {
    LEDConfig: LEDConfig.fromJson,
    ButtonConfig: ButtonConfig.fromJson,
    ConveyorConfig: ConveyorConfig.fromJson,
    ConveyorColorPaletteConfig: ConveyorColorPaletteConfig.fromJson,
    ArrowConfig: ArrowConfig.fromJson,
    LEDColumnConfig: LEDColumnConfig.fromJson,
    DrawnBoxConfig: DrawnBoxConfig.fromJson,
    NumberConfig: NumberConfig.fromJson,
    CheckweigherConfig: CheckweigherConfig.fromJson,
    GraphAssetConfig: GraphAssetConfig.fromJson,
    RatioNumberConfig: RatioNumberConfig.fromJson,
    Baader221Config: Baader221Config.fromJson,
    AnalogBoxConfig: AnalogBoxConfig.fromJson,
    OptionVariableConfig: OptionVariableConfig.fromJson,
    TextAssetConfig: TextAssetConfig.fromJson,
    BeckhoffCX5010Config: BeckhoffCX5010Config.fromJson,
    BeckhoffEL1008Config: BeckhoffEL1008Config.fromJson,
    BeckhoffEL2008Config: BeckhoffEL2008Config.fromJson,
    BeckhoffEL9222Config: BeckhoffEL9222Config.fromJson,
    BeckhoffEL9186Config: BeckhoffEL9186Config.fromJson,
    BeckhoffEL9187Config: BeckhoffEL9187Config.fromJson,
    BeckhoffEK1100Config: BeckhoffEK1100Config.fromJson,
    BeckhoffEL3054Config: BeckhoffEL3054Config.fromJson,
    SchneiderATV320Config: SchneiderATV320Config.fromJson,
    IconConfig: IconConfig.fromJson,
    TableAssetConfig: TableAssetConfig.fromJson,
    StartStopPillButtonConfig: StartStopPillButtonConfig.fromJson,
  };

  static final Map<Type, Asset Function()> defaultFactories = {
    LEDConfig: LEDConfig.preview,
    ButtonConfig: ButtonConfig.preview,
    ConveyorConfig: ConveyorConfig.preview,
    ConveyorColorPaletteConfig: ConveyorColorPaletteConfig.preview,
    ArrowConfig: ArrowConfig.preview,
    LEDColumnConfig: LEDColumnConfig.preview,
    DrawnBoxConfig: DrawnBoxConfig.preview,
    NumberConfig: NumberConfig.preview,
    CheckweigherConfig: CheckweigherConfig.preview,
    GraphAssetConfig: GraphAssetConfig.preview,
    RatioNumberConfig: RatioNumberConfig.preview,
    Baader221Config: Baader221Config.preview,
    AnalogBoxConfig: AnalogBoxConfig.preview,
    OptionVariableConfig: OptionVariableConfig.preview,
    TextAssetConfig: TextAssetConfig.preview,
    BeckhoffCX5010Config: BeckhoffCX5010Config.preview,
    BeckhoffEL1008Config: BeckhoffEL1008Config.preview,
    BeckhoffEL2008Config: BeckhoffEL2008Config.preview,
    BeckhoffEL9222Config: BeckhoffEL9222Config.preview,
    BeckhoffEL9186Config: BeckhoffEL9186Config.preview,
    BeckhoffEL9187Config: BeckhoffEL9187Config.preview,
    BeckhoffEK1100Config: BeckhoffEK1100Config.preview,
    BeckhoffEL3054Config: BeckhoffEL3054Config.preview,
    SchneiderATV320Config: SchneiderATV320Config.preview,
    IconConfig: IconConfig.preview,
    TableAssetConfig: TableAssetConfig.preview,
    StartStopPillButtonConfig: StartStopPillButtonConfig.preview,
  };

  static void registerFromJsonFactory<T extends Asset>(
      Asset Function(Map<String, dynamic>) fromJson) {
    _fromJsonFactories[T] = fromJson;
  }

  static void registerDefaultFactory<T extends Asset>(
      Asset Function() preview) {
    defaultFactories[T] = preview;
  }

  static List<Asset> parse(Map<String, dynamic> json) {
    final List<Asset> foundWidgets = [];
    void crawlJson(dynamic jsonPart) {
      if (jsonPart is Map<String, dynamic>) {
        _log.t('Crawling object: $jsonPart');
        if (jsonPart.containsKey(constAssetName)) {
          final assetName = jsonPart[constAssetName] as String;
          _log.d('Found potential asset: $assetName');

          for (final factory in _fromJsonFactories.entries) {
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
