/// Static catalog of all HMI asset types available in the AssetRegistry.
///
/// This catalog mirrors the Flutter-side `AssetRegistry` (which depends on
/// Flutter widgets) as a pure-Dart data structure suitable for the MCP server.
/// It provides the LLM with a complete inventory of asset types, their
/// categories, descriptions, and configurable properties so it can create
/// accurate proposals without guessing.
///
/// **Maintenance:** When a new asset type is added to the Flutter-side
/// `AssetRegistry` (in `lib/page_creator/assets/registry.dart`), a
/// corresponding entry should be added here.
library;

/// Metadata for a single configurable property of an asset type.
class AssetPropertyInfo {
  /// The JSON key name for this property.
  final String name;

  /// The data type (e.g., "String", "Color", "bool", "int", "double").
  final String type;

  /// Human-readable description of what this property controls.
  final String description;

  /// Whether this property is required when creating the asset.
  final bool required;

  const AssetPropertyInfo({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'description': description,
        'required': required,
      };
}

/// Metadata for a single asset type in the HMI system.
class AssetTypeInfo {
  /// The Dart class name used as the `asset_name` key in JSON configs.
  /// Example: "LEDConfig", "ButtonConfig".
  final String assetName;

  /// Human-readable display name shown in the page editor UI.
  final String displayName;

  /// Category for grouping in the editor palette.
  final String category;

  /// Description of what this asset does, for the LLM's context.
  final String description;

  /// Configurable properties beyond the base properties
  /// (coordinates, size, text, textPos) that all assets share.
  final List<AssetPropertyInfo> properties;

  const AssetTypeInfo({
    required this.assetName,
    required this.displayName,
    required this.category,
    required this.description,
    this.properties = const [],
  });

  Map<String, dynamic> toJson() => {
        'assetName': assetName,
        'displayName': displayName,
        'category': category,
        'description': description,
        'properties': properties.map((p) => p.toJson()).toList(),
      };
}

/// The complete catalog of asset types available in the TFC HMI.
///
/// Use [AssetTypeCatalog.all] for the full list, [AssetTypeCatalog.categories]
/// for distinct category names, or [AssetTypeCatalog.byCategory] to filter.
class AssetTypeCatalog {
  AssetTypeCatalog._();

  /// All registered asset types, ordered by category then display name.
  static const List<AssetTypeInfo> all = [
    // ── Basic Indicators ──────────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'LEDConfig',
      displayName: 'LED',
      category: 'Basic Indicators',
      description:
          'A status indicator light (circle or square) that subscribes to '
          'a boolean key. Shows on_color when true, off_color when false.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Boolean tag key to subscribe to',
            required: true),
        AssetPropertyInfo(
            name: 'on_color',
            type: 'Color',
            description: 'Color when the key value is true'),
        AssetPropertyInfo(
            name: 'off_color',
            type: 'Color',
            description: 'Color when the key value is false'),
        AssetPropertyInfo(
            name: 'led_type',
            type: 'LEDType',
            description: 'Shape of the LED: "circle" or "square"'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'LEDColumnConfig',
      displayName: 'LED Column',
      category: 'Basic Indicators',
      description:
          'A vertical stack of LED indicators, each with its own key '
          'and color settings. Useful for multi-channel status displays.',
      properties: [
        AssetPropertyInfo(
            name: 'leds',
            type: 'List<LEDConfig>',
            description: 'Array of LED configurations in the column',
            required: true),
        AssetPropertyInfo(
            name: 'spacing',
            type: 'double',
            description: 'Vertical spacing between LEDs'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'ArrowConfig',
      displayName: 'Arrow',
      category: 'Basic Indicators',
      description:
          'A directional arrow indicator bound to a key. Shows flow '
          'direction or state with a label.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key to subscribe to',
            required: true),
        AssetPropertyInfo(
            name: 'label',
            type: 'String',
            description: 'Text label for the arrow',
            required: true),
      ],
    ),
    AssetTypeInfo(
      assetName: 'DrawnBoxConfig',
      displayName: 'Drawn Box',
      category: 'Basic Indicators',
      description:
          'A decorative box with configurable borders (solid or dashed), '
          'color, and line width. Individual sides can be hidden. Used for '
          'visual grouping on pages.',
      properties: [
        AssetPropertyInfo(
            name: 'color',
            type: 'Color',
            description: 'Border color of the box'),
        AssetPropertyInfo(
            name: 'lineWidth',
            type: 'double',
            description: 'Width of the border lines'),
        AssetPropertyInfo(
            name: 'isDashed',
            type: 'bool',
            description: 'Whether the border is dashed'),
        AssetPropertyInfo(
            name: 'showTop',
            type: 'bool',
            description: 'Whether to draw the top border'),
        AssetPropertyInfo(
            name: 'showRight',
            type: 'bool',
            description: 'Whether to draw the right border'),
        AssetPropertyInfo(
            name: 'showBottom',
            type: 'bool',
            description: 'Whether to draw the bottom border'),
        AssetPropertyInfo(
            name: 'showLeft',
            type: 'bool',
            description: 'Whether to draw the left border'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'IconConfig',
      displayName: 'Icon',
      category: 'Basic Indicators',
      description:
          'A Material Design icon with optional color and conditional '
          'states. Can change icon and color based on boolean expressions '
          'over tag values.',
      properties: [
        AssetPropertyInfo(
            name: 'iconData',
            type: 'IconData',
            description: 'The Material icon to display',
            required: true),
        AssetPropertyInfo(
            name: 'color', type: 'Color', description: 'Icon color'),
        AssetPropertyInfo(
            name: 'conditional_states',
            type: 'List<ConditionalIconState>',
            description:
                'Rules that change icon/color based on boolean expressions'),
      ],
    ),

    // ── Interactive Controls ──────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'ButtonConfig',
      displayName: 'Button',
      category: 'Interactive Controls',
      description:
          'A pressable button (circle or square) that writes to an OPC UA '
          'tag on press/release. Supports toggle mode, feedback indicators, '
          'and optional icon overlay.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key to write to on press',
            required: true),
        AssetPropertyInfo(
            name: 'outward_color',
            type: 'Color',
            description: 'Button color in released state'),
        AssetPropertyInfo(
            name: 'inward_color',
            type: 'Color',
            description: 'Button color in pressed state'),
        AssetPropertyInfo(
            name: 'button_type',
            type: 'ButtonType',
            description: 'Shape: "circle" or "square"'),
        AssetPropertyInfo(
            name: 'is_toggle',
            type: 'bool',
            description: 'Whether the button stays pressed (toggle mode)'),
        AssetPropertyInfo(
            name: 'feedback',
            type: 'FeedbackConfig',
            description:
                'Live feedback indicator (key + color) from a separate tag'),
        AssetPropertyInfo(
            name: 'icon',
            type: 'IconConfig',
            description: 'Optional icon rendered on the button'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'StartStopPillButtonConfig',
      displayName: 'Start/Stop Button',
      category: 'Interactive Controls',
      description:
          'A pill-shaped run/clean/stop button cluster. Writes pulse '
          'signals on press/release and shows live feedback from running/'
          'stopped/cleaning state keys.',
      properties: [
        AssetPropertyInfo(
            name: 'runKey',
            type: 'String',
            description: 'Tag key pulsed to start',
            required: true),
        AssetPropertyInfo(
            name: 'stopKey',
            type: 'String',
            description: 'Tag key pulsed to stop',
            required: true),
        AssetPropertyInfo(
            name: 'cleanKey',
            type: 'String',
            description:
                'Tag key pulsed for clean mode (optional, hides segment if null)'),
        AssetPropertyInfo(
            name: 'runningKey',
            type: 'String',
            description: 'Boolean feedback key for running state',
            required: true),
        AssetPropertyInfo(
            name: 'stoppedKey',
            type: 'String',
            description: 'Boolean feedback key for stopped state',
            required: true),
        AssetPropertyInfo(
            name: 'cleaningKey',
            type: 'String',
            description: 'Boolean feedback key for cleaning state'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'OptionVariableConfig',
      displayName: 'Option Variable',
      category: 'Interactive Controls',
      description:
          'A dropdown selector that sets a StateMan variable from a '
          'predefined list of options. Used for mode selection, recipe '
          'picking, or configuration switching.',
      properties: [
        AssetPropertyInfo(
            name: 'variableName',
            type: 'String',
            description: 'The StateMan variable name to set',
            required: true),
        AssetPropertyInfo(
            name: 'options',
            type: 'List<OptionItem>',
            description: 'Available options (value + label + description)',
            required: true),
        AssetPropertyInfo(
            name: 'defaultValue',
            type: 'String',
            description: 'Default selected value'),
        AssetPropertyInfo(
            name: 'showSearch',
            type: 'bool',
            description: 'Whether to show a search/filter field'),
        AssetPropertyInfo(
            name: 'customLabel',
            type: 'String',
            description: 'Custom label for the dropdown'),
      ],
    ),

    // ── Text & Numbers ────────────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'NumberConfig',
      displayName: 'Number',
      category: 'Text & Numbers',
      description:
          'Displays a live numeric value from a tag key. Configurable '
          'decimal places, units, scale factor, color, and optional '
          'inline graph. Can be made writable for operator input.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key to subscribe to',
            required: true),
        AssetPropertyInfo(
            name: 'showDecimalPoint',
            type: 'bool',
            description: 'Whether to show decimal point'),
        AssetPropertyInfo(
            name: 'decimalPlaces',
            type: 'int',
            description: 'Number of decimal places to display'),
        AssetPropertyInfo(
            name: 'scale',
            type: 'double',
            description: 'Scale factor applied to the raw value'),
        AssetPropertyInfo(
            name: 'units',
            type: 'String',
            description: 'Unit suffix displayed after the number'),
        AssetPropertyInfo(
            name: 'textColor',
            type: 'Color',
            description: 'Color of the displayed text'),
        AssetPropertyInfo(
            name: 'writable',
            type: 'bool',
            description: 'Whether the operator can tap to edit the value'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'TextAssetConfig',
      displayName: 'Text',
      category: 'Text & Numbers',
      description:
          'A static or dynamic text label. Supports variable substitution '
          'using \$key syntax (e.g., "Temp: \$pump3.temp") where keys are '
          'resolved from live tag values.',
      properties: [
        AssetPropertyInfo(
            name: 'textContent',
            type: 'String',
            description: 'Text content, optionally with \$variable placeholders',
            required: true),
        AssetPropertyInfo(
            name: 'textColor',
            type: 'Color',
            description: 'Text color'),
        AssetPropertyInfo(
            name: 'enableVariableSubstitution',
            type: 'bool',
            description: 'Enable \$key variable substitution in text'),
        AssetPropertyInfo(
            name: 'decimalPlaces',
            type: 'int',
            description: 'Decimal places for substituted numeric values'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'AnalogBoxConfig',
      displayName: 'Analog Box',
      category: 'Text & Numbers',
      description:
          'A compact analog value display with bar indicator, setpoints, '
          'hysteresis bands, and error state. Shows live analog value with '
          'min/max range and optional setpoint controls.',
      properties: [
        AssetPropertyInfo(
            name: 'analog_key',
            type: 'String',
            description: 'Tag key for the live analog value',
            required: true),
        AssetPropertyInfo(
            name: 'setpoint1_key',
            type: 'String',
            description: 'Tag key for first setpoint (writable)'),
        AssetPropertyInfo(
            name: 'setpoint1_hysteresis_key',
            type: 'String',
            description: 'Tag key for setpoint 1 hysteresis'),
        AssetPropertyInfo(
            name: 'setpoint2_key',
            type: 'String',
            description: 'Tag key for second setpoint'),
        AssetPropertyInfo(
            name: 'error_key',
            type: 'String',
            description: 'Tag key for error indicator'),
        AssetPropertyInfo(
            name: 'min_value',
            type: 'double',
            description: 'Minimum scale value'),
        AssetPropertyInfo(
            name: 'max_value',
            type: 'double',
            description: 'Maximum scale value'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'RatioNumberConfig',
      displayName: 'Ratio Number',
      category: 'Text & Numbers',
      description:
          'Displays the ratio between two timeseries values (key1/key2) '
          'with an interactive bar chart over configurable time windows.',
      properties: [
        AssetPropertyInfo(
            name: 'key1',
            type: 'String',
            description: 'Numerator tag key',
            required: true),
        AssetPropertyInfo(
            name: 'key2',
            type: 'String',
            description: 'Denominator tag key',
            required: true),
        AssetPropertyInfo(
            name: 'key1_label',
            type: 'String',
            description: 'Label for the numerator',
            required: true),
        AssetPropertyInfo(
            name: 'key2_label',
            type: 'String',
            description: 'Label for the denominator',
            required: true),
        AssetPropertyInfo(
            name: 'text_color',
            type: 'Color',
            description: 'Text color'),
        AssetPropertyInfo(
            name: 'how_many',
            type: 'int',
            description: 'Number of time windows to display'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BpmConfig',
      displayName: 'BPM Counter',
      category: 'Text & Numbers',
      description:
          'Counts events per minute from a timeseries key with a bar '
          'chart. Configurable time window, poll interval, and presets. '
          'Can also show events per hour.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Timeseries key to count events from',
            required: true),
        AssetPropertyInfo(
            name: 'text_color',
            type: 'Color',
            description: 'Text color'),
        AssetPropertyInfo(
            name: 'default_interval',
            type: 'int',
            description: 'Default time window in minutes'),
        AssetPropertyInfo(
            name: 'how_many',
            type: 'int',
            description: 'Number of bars in the chart'),
        AssetPropertyInfo(
            name: 'unit',
            type: 'String',
            description: 'Unit label (e.g., "bpm")'),
        AssetPropertyInfo(
            name: 'show_bph',
            type: 'bool',
            description: 'Whether to show beats per hour'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'RateValueConfig',
      displayName: 'Rate Value',
      category: 'Text & Numbers',
      description:
          'Computes and displays the rate (per minute or per hour) from '
          'a cumulative timeseries value with a bar chart history.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Timeseries key to compute rate from',
            required: true),
        AssetPropertyInfo(
            name: 'text_color',
            type: 'Color',
            description: 'Text color'),
        AssetPropertyInfo(
            name: 'default_interval',
            type: 'int',
            description: 'Default time window in minutes'),
        AssetPropertyInfo(
            name: 'how_many',
            type: 'int',
            description: 'Number of bars in the chart'),
        AssetPropertyInfo(
            name: 'unit',
            type: 'String',
            description: 'Unit label (e.g., "kg/min")'),
        AssetPropertyInfo(
            name: 'show_per_hour',
            type: 'bool',
            description: 'Show rate per hour instead of per minute'),
      ],
    ),

    // ── Visualization ─────────────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'ConveyorConfig',
      displayName: 'Conveyor',
      category: 'Visualization',
      description:
          'An animated conveyor belt/auger visualization bound to a '
          'running state key. Shows motion when the key is true. Supports '
          'angle rotation and configurable appearance.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Boolean tag key indicating running state',
            required: true),
      ],
    ),
    AssetTypeInfo(
      assetName: 'ConveyorColorPaletteConfig',
      displayName: 'Conveyor Palette',
      category: 'Visualization',
      description:
          'A color-coded conveyor visualization that changes appearance '
          'based on status. Used alongside regular conveyors for visual '
          'differentiation.',
      properties: [],
    ),
    AssetTypeInfo(
      assetName: 'GraphAssetConfig',
      displayName: 'Graph',
      category: 'Visualization',
      description:
          'A real-time or historical line/bar/area chart displaying one '
          'or more timeseries. Supports dual Y axes (primary + secondary '
          'series), configurable time range, aggregation, and live mode.',
      properties: [
        AssetPropertyInfo(
            name: 'graph_type',
            type: 'GraphType',
            description: 'Chart type: line, bar, etc.',
            required: true),
        AssetPropertyInfo(
            name: 'primary_series',
            type: 'List<GraphSeriesConfig>',
            description: 'Primary Y-axis series (key + label + color)',
            required: true),
        AssetPropertyInfo(
            name: 'secondary_series',
            type: 'List<GraphSeriesConfig>',
            description: 'Secondary Y-axis series'),
        AssetPropertyInfo(
            name: 'x_axis',
            type: 'GraphAxisConfig',
            description: 'X-axis (time) configuration'),
        AssetPropertyInfo(
            name: 'y_axis',
            type: 'GraphAxisConfig',
            description: 'Primary Y-axis configuration'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'TableAssetConfig',
      displayName: 'Table',
      category: 'Visualization',
      description:
          'A data table showing the most recent N entries from a collected '
          'timeseries key. Configurable row count, colors, and header.',
      properties: [
        AssetPropertyInfo(
            name: 'entryKey',
            type: 'String',
            description: 'Timeseries key to display',
            required: true),
        AssetPropertyInfo(
            name: 'entryCount',
            type: 'int',
            description: 'Number of rows to display'),
        AssetPropertyInfo(
            name: 'headerText',
            type: 'String',
            description: 'Table header text'),
        AssetPropertyInfo(
            name: 'showTimestamps',
            type: 'bool',
            description: 'Whether to show timestamp column'),
        AssetPropertyInfo(
            name: 'text_color',
            type: 'Color',
            description: 'Text color'),
        AssetPropertyInfo(
            name: 'background_color',
            type: 'Color',
            description: 'Background color'),
      ],
    ),

    // ── Beckhoff Devices ──────────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'BeckhoffCX5010Config',
      displayName: 'Beckhoff CX5010',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff CX5010 embedded PC with power and '
          'TwinCAT status LEDs. Can contain subdevices (EL terminals) '
          'displayed in a rack layout.',
      properties: [
        AssetPropertyInfo(
            name: 'subdevices',
            type: 'List<Asset>',
            description:
                'Attached I/O terminals (EL1008, EL2008, EL3054, etc.)'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEK1100Config',
      displayName: 'Beckhoff EK1100',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EK1100 EtherCAT coupler. Shows '
          'run/error status LEDs and can contain attached subdevices.',
      properties: [
        AssetPropertyInfo(
            name: 'subdevices',
            type: 'List<Asset>',
            description: 'Attached I/O terminals'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEL1008Config',
      displayName: 'Beckhoff EL1008',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EL1008 8-channel digital input '
          'terminal. Each channel shows live status from mapped keys.',
      properties: [
        AssetPropertyInfo(
            name: 'keys',
            type: 'List<String>',
            description: 'Tag keys for each of the 8 digital input channels'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEL2008Config',
      displayName: 'Beckhoff EL2008',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EL2008 8-channel digital output '
          'terminal. Each channel shows live status from mapped keys.',
      properties: [
        AssetPropertyInfo(
            name: 'keys',
            type: 'List<String>',
            description: 'Tag keys for each of the 8 digital output channels'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEL3054Config',
      displayName: 'Beckhoff EL3054',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EL3054 4-channel analog input '
          'terminal (4-20mA). Shows live values with optional inline graphs.',
      properties: [
        AssetPropertyInfo(
            name: 'keys',
            type: 'List<String>',
            description:
                'Tag keys for each of the 4 analog input channels'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEL9222Config',
      displayName: 'Beckhoff EL9222',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EL9222 2-channel overcurrent '
          'protection terminal. Shows channel status and trip state.',
      properties: [
        AssetPropertyInfo(
            name: 'keys',
            type: 'List<String>',
            description: 'Tag keys for channel status'),
      ],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEL9186Config',
      displayName: 'Beckhoff EL9186',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EL9186 potential distribution '
          'terminal (0V). Shows connection status.',
      properties: [],
    ),
    AssetTypeInfo(
      assetName: 'BeckhoffEL9187Config',
      displayName: 'Beckhoff EL9187',
      category: 'Beckhoff Devices',
      description:
          'Visualization of a Beckhoff EL9187 potential distribution '
          'terminal (24V). Shows connection status.',
      properties: [],
    ),

    // ── Schneider Devices ─────────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'SchneiderATV320Config',
      displayName: 'Schneider ATV320',
      category: 'Schneider Devices',
      description:
          'Visualization of a Schneider Electric ATV320 variable frequency '
          'drive (VFD). Shows HMIS status, frequency, and configuration '
          'from mapped OPC UA keys.',
      properties: [
        AssetPropertyInfo(
            name: 'label',
            type: 'String',
            description: 'Display label for the drive'),
        AssetPropertyInfo(
            name: 'hmisKey',
            type: 'String',
            description: 'Tag key for HMIS (status word)'),
        AssetPropertyInfo(
            name: 'freqKey',
            type: 'String',
            description: 'Tag key for output frequency'),
        AssetPropertyInfo(
            name: 'configKey',
            type: 'String',
            description: 'Tag key for drive configuration'),
      ],
    ),

    // ── Industrial Equipment ──────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'Baader221Config',
      displayName: 'Baader 221',
      category: 'Industrial Equipment',
      description:
          'Visualization of a Baader 221 fish processing machine. Shows '
          'operational status from mapped tag keys.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key for machine status',
            required: true),
      ],
    ),
    AssetTypeInfo(
      assetName: 'AirCabConfig',
      displayName: 'Air Cabinet',
      category: 'Industrial Equipment',
      description:
          'Visualization of a pneumatic air cabinet showing valve '
          'and pressure status from mapped tag keys.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key for cabinet status',
            required: true),
      ],
    ),
    AssetTypeInfo(
      assetName: 'ElCabConfig',
      displayName: 'Electrical Cabinet',
      category: 'Industrial Equipment',
      description:
          'Visualization of an electrical cabinet showing breaker and '
          'component status from mapped tag keys.',
      properties: [
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key for cabinet status',
            required: true),
      ],
    ),

    // ── Application ───────────────────────────────────────────────────
    AssetTypeInfo(
      assetName: 'ChecklistsConfig',
      displayName: 'Checklists',
      category: 'Application',
      description:
          'An interactive checklist widget for operator task tracking. '
          'Items can be checked off and progress is persisted.',
      properties: [],
    ),
    AssetTypeInfo(
      assetName: 'RecipesConfig',
      displayName: 'Recipes',
      category: 'Application',
      description:
          'A recipe management widget for configuring and applying '
          'predefined parameter sets to the process.',
      properties: [],
    ),
    AssetTypeInfo(
      assetName: 'SpeedBatcherConfig',
      displayName: 'Speed Batcher',
      category: 'Application',
      description:
          'A speed batcher control widget showing batch count and '
          'status with a label. Used for batching/dosing processes.',
      properties: [
        AssetPropertyInfo(
            name: 'label',
            type: 'String',
            description: 'Display label',
            required: true),
        AssetPropertyInfo(
            name: 'key',
            type: 'String',
            description: 'Tag key for batcher data',
            required: true),
      ],
    ),
    AssetTypeInfo(
      assetName: 'GateStatusConfig',
      displayName: 'Gate Status',
      category: 'Application',
      description:
          'A gate status indicator widget showing open/closed state. '
          'Used alongside speed batcher for gate-controlled processes.',
      properties: [],
    ),
    AssetTypeInfo(
      assetName: 'DrawingViewerConfig',
      displayName: 'Drawing Viewer',
      category: 'Application',
      description:
          'A button that opens a PDF technical drawing in the floating '
          'overlay viewer. Configured with drawing name, file path, '
          'and optional start page.',
      properties: [
        AssetPropertyInfo(
            name: 'drawingName',
            type: 'String',
            description: 'Display name for the drawing',
            required: true),
        AssetPropertyInfo(
            name: 'filePath',
            type: 'String',
            description: 'Path to the PDF file',
            required: true),
        AssetPropertyInfo(
            name: 'startPage',
            type: 'int',
            description: 'Initial page number to display (1-based)'),
      ],
    ),
  ];

  /// All distinct category names, sorted alphabetically.
  static List<String> get categories {
    final cats = all.map((e) => e.category).toSet().toList();
    cats.sort();
    return cats;
  }

  /// Filter asset types by category name (exact match).
  static List<AssetTypeInfo> byCategory(String category) {
    return all.where((e) => e.category == category).toList();
  }
}
