import 'package:logger/logger.dart';
import 'common.dart';
import 'led.dart';
import 'button.dart';
import 'conveyor.dart';
import 'arrow.dart';
import 'led_column.dart';
import 'drawn_box.dart';
import 'number.dart';
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
import 'aircab.dart';
import 'checklists.dart';
import 'elcab.dart';
import 'recipes.dart';
import 'bpm.dart';
import 'rate_value.dart';
import 'speedbatcher.dart';
import 'conveyor_gate.dart';
import 'drawing_viewer.dart';
import 'image_feed.dart';
import 'inference_log.dart';

class AssetRegistry {
  static final Logger _log = Logger();

  /// Type-keyed factory map (kept for registerFromJsonFactory<T> API).
  static final Map<Type, Asset Function(Map<String, dynamic>)>
      _fromJsonFactories = {
    LEDConfig: LEDConfig.fromJson,
    ButtonConfig: ButtonConfig.fromJson,
    ConveyorConfig: ConveyorConfig.fromJson,
    ConveyorGateConfig: ConveyorGateConfig.fromJson,
    ConveyorColorPaletteConfig: ConveyorColorPaletteConfig.fromJson,
    ArrowConfig: ArrowConfig.fromJson,
    LEDColumnConfig: LEDColumnConfig.fromJson,
    DrawnBoxConfig: DrawnBoxConfig.fromJson,
    NumberConfig: NumberConfig.fromJson,
    GraphAssetConfig: GraphAssetConfig.fromJson,
    RatioNumberConfig: RatioNumberConfig.fromJson,
    BpmConfig: BpmConfig.fromJson,
    RateValueConfig: RateValueConfig.fromJson,
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
    AirCabConfig: AirCabConfig.fromJson,
    ChecklistsConfig: ChecklistsConfig.fromJson,
    ElCabConfig: ElCabConfig.fromJson,
    RecipesConfig: RecipesConfig.fromJson,
    SpeedBatcherConfig: SpeedBatcherConfig.fromJson,
    GateStatusConfig: GateStatusConfig.fromJson,
    DrawingViewerConfig: DrawingViewerConfig.fromJson,
    ImageFeedConfig: ImageFeedConfig.fromJson,
    InferenceLogConfig: InferenceLogConfig.fromJson,
  };

  /// String-keyed factory map used by [parse] and [createDefaultAssetByName].
  /// Type.toString() is minified in dart2js release builds, so we need
  /// explicit string keys for matching against JSON asset_name values.
  static final Map<String, Asset Function(Map<String, dynamic>)>
      _namedFromJsonFactories = {
    'LEDConfig': LEDConfig.fromJson,
    'ButtonConfig': ButtonConfig.fromJson,
    'ConveyorConfig': ConveyorConfig.fromJson,
    'ConveyorGateConfig': ConveyorGateConfig.fromJson,
    'ConveyorColorPaletteConfig': ConveyorColorPaletteConfig.fromJson,
    'ArrowConfig': ArrowConfig.fromJson,
    'LEDColumnConfig': LEDColumnConfig.fromJson,
    'DrawnBoxConfig': DrawnBoxConfig.fromJson,
    'NumberConfig': NumberConfig.fromJson,
    'GraphAssetConfig': GraphAssetConfig.fromJson,
    'RatioNumberConfig': RatioNumberConfig.fromJson,
    'BpmConfig': BpmConfig.fromJson,
    'RateValueConfig': RateValueConfig.fromJson,
    'Baader221Config': Baader221Config.fromJson,
    'AnalogBoxConfig': AnalogBoxConfig.fromJson,
    'OptionVariableConfig': OptionVariableConfig.fromJson,
    'TextAssetConfig': TextAssetConfig.fromJson,
    'BeckhoffCX5010Config': BeckhoffCX5010Config.fromJson,
    'BeckhoffEL1008Config': BeckhoffEL1008Config.fromJson,
    'BeckhoffEL2008Config': BeckhoffEL2008Config.fromJson,
    'BeckhoffEL9222Config': BeckhoffEL9222Config.fromJson,
    'BeckhoffEL9186Config': BeckhoffEL9186Config.fromJson,
    'BeckhoffEL9187Config': BeckhoffEL9187Config.fromJson,
    'BeckhoffEK1100Config': BeckhoffEK1100Config.fromJson,
    'BeckhoffEL3054Config': BeckhoffEL3054Config.fromJson,
    'SchneiderATV320Config': SchneiderATV320Config.fromJson,
    'IconConfig': IconConfig.fromJson,
    'TableAssetConfig': TableAssetConfig.fromJson,
    'StartStopPillButtonConfig': StartStopPillButtonConfig.fromJson,
    'AirCabConfig': AirCabConfig.fromJson,
    'ChecklistsConfig': ChecklistsConfig.fromJson,
    'ElCabConfig': ElCabConfig.fromJson,
    'RecipesConfig': RecipesConfig.fromJson,
    'SpeedBatcherConfig': SpeedBatcherConfig.fromJson,
    'GateStatusConfig': GateStatusConfig.fromJson,
    'DrawingViewerConfig': DrawingViewerConfig.fromJson,
    'ImageFeedConfig': ImageFeedConfig.fromJson,
    'InferenceLogConfig': InferenceLogConfig.fromJson,
  };

  static final Map<Type, Asset Function()> defaultFactories = {
    LEDConfig: LEDConfig.preview,
    LEDColumnConfig: LEDColumnConfig.preview,
    ButtonConfig: ButtonConfig.preview,
    ArrowConfig: ArrowConfig.preview,
    ConveyorConfig: ConveyorConfig.preview,
    ConveyorGateConfig: ConveyorGateConfig.preview,
    ConveyorColorPaletteConfig: ConveyorColorPaletteConfig.preview,
    NumberConfig: NumberConfig.preview,
    RatioNumberConfig: RatioNumberConfig.preview,
    BpmConfig: BpmConfig.preview,
    RateValueConfig: RateValueConfig.preview,
    TableAssetConfig: TableAssetConfig.preview,
    GraphAssetConfig: GraphAssetConfig.preview,
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
    DrawnBoxConfig: DrawnBoxConfig.preview,
    StartStopPillButtonConfig: StartStopPillButtonConfig.preview,
    AirCabConfig: AirCabConfig.preview,
    ChecklistsConfig: ChecklistsConfig.preview,
    ElCabConfig: ElCabConfig.preview,
    RecipesConfig: RecipesConfig.preview,
    SpeedBatcherConfig: SpeedBatcherConfig.preview,
    GateStatusConfig: GateStatusConfig.preview,
    DrawingViewerConfig: DrawingViewerConfig.preview,
    ImageFeedConfig: ImageFeedConfig.preview,
    InferenceLogConfig: InferenceLogConfig.preview,
  };

  static final Map<String, Asset Function()> _namedDefaultFactories = {
    'LEDConfig': LEDConfig.preview,
    'LEDColumnConfig': LEDColumnConfig.preview,
    'ButtonConfig': ButtonConfig.preview,
    'ArrowConfig': ArrowConfig.preview,
    'ConveyorConfig': ConveyorConfig.preview,
    'ConveyorGateConfig': ConveyorGateConfig.preview,
    'ConveyorColorPaletteConfig': ConveyorColorPaletteConfig.preview,
    'NumberConfig': NumberConfig.preview,
    'RatioNumberConfig': RatioNumberConfig.preview,
    'BpmConfig': BpmConfig.preview,
    'RateValueConfig': RateValueConfig.preview,
    'TableAssetConfig': TableAssetConfig.preview,
    'GraphAssetConfig': GraphAssetConfig.preview,
    'Baader221Config': Baader221Config.preview,
    'AnalogBoxConfig': AnalogBoxConfig.preview,
    'OptionVariableConfig': OptionVariableConfig.preview,
    'TextAssetConfig': TextAssetConfig.preview,
    'BeckhoffCX5010Config': BeckhoffCX5010Config.preview,
    'BeckhoffEL1008Config': BeckhoffEL1008Config.preview,
    'BeckhoffEL2008Config': BeckhoffEL2008Config.preview,
    'BeckhoffEL9222Config': BeckhoffEL9222Config.preview,
    'BeckhoffEL9186Config': BeckhoffEL9186Config.preview,
    'BeckhoffEL9187Config': BeckhoffEL9187Config.preview,
    'BeckhoffEK1100Config': BeckhoffEK1100Config.preview,
    'BeckhoffEL3054Config': BeckhoffEL3054Config.preview,
    'SchneiderATV320Config': SchneiderATV320Config.preview,
    'IconConfig': IconConfig.preview,
    'DrawnBoxConfig': DrawnBoxConfig.preview,
    'StartStopPillButtonConfig': StartStopPillButtonConfig.preview,
    'AirCabConfig': AirCabConfig.preview,
    'ChecklistsConfig': ChecklistsConfig.preview,
    'ElCabConfig': ElCabConfig.preview,
    'RecipesConfig': RecipesConfig.preview,
    'SpeedBatcherConfig': SpeedBatcherConfig.preview,
    'GateStatusConfig': GateStatusConfig.preview,
    'DrawingViewerConfig': DrawingViewerConfig.preview,
    'ImageFeedConfig': ImageFeedConfig.preview,
    'InferenceLogConfig': InferenceLogConfig.preview,
  };

  static void registerFromJsonFactory<T extends Asset>(
      Asset Function(Map<String, dynamic>) fromJson) {
    _fromJsonFactories[T] = fromJson;
    // Also register in the string-keyed map for web compatibility.
    _namedFromJsonFactories[T.toString()] = fromJson;
  }

  static void registerDefaultFactory<T extends Asset>(
      Asset Function() preview) {
    defaultFactories[T] = preview;
    _namedDefaultFactories[T.toString()] = preview;
  }

  static List<Asset> parse(Map<String, dynamic> json) {
    final List<Asset> foundWidgets = [];
    void crawlJson(dynamic jsonPart) {
      if (jsonPart is Map<String, dynamic>) {
        if (jsonPart.containsKey(constAssetName)) {
          final assetName = jsonPart[constAssetName] as String;

          final factory = _namedFromJsonFactories[assetName];
          if (factory != null) {
            try {
              final asset = factory(jsonPart);
              foundWidgets.add(asset);
              _log.d('Successfully parsed ${asset.assetName}');
              return;
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
        // If not an asset, crawl deeper
        jsonPart.values.forEach(crawlJson);
      } else if (jsonPart is List) {
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

  /// Creates a default asset by its string name (e.g., "ButtonConfig").
  ///
  /// Returns null if no factory matches the given name. This is used by the
  /// proposal system where asset type names arrive as strings from the MCP
  /// server, and the full JSON for [parse] is not available (missing required
  /// fields like colors, sizes, etc.).
  static Asset? createDefaultAssetByName(String assetName) {
    return _namedDefaultFactories[assetName]?.call();
  }
}
