import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'common.dart';
import '../../providers/collector.dart';
import '../../core/database.dart';
import '../../converter/color_converter.dart';

part 'table.g.dart';

@JsonSerializable()
class TableAssetConfig extends BaseAsset {
  /// The key to collect data from
  String entryKey;

  /// Number of entries to show in the table
  int entryCount;

  /// Table header text
  String? headerText;

  /// Whether to show timestamps
  bool showTimestamps;

  /// Text color for the table
  @JsonKey(name: 'text_color')
  @OptionalColorConverter()
  Color? textColor;

  /// Background color for the table
  @JsonKey(name: 'background_color')
  @OptionalColorConverter()
  Color? backgroundColor;

  /// Border color for the table
  @JsonKey(name: 'border_color')
  @OptionalColorConverter()
  Color? borderColor;

  TableAssetConfig({
    required this.entryKey,
    this.entryCount = 10,
    this.headerText,
    this.showTimestamps = true,
    this.textColor,
    this.backgroundColor,
    this.borderColor,
  });

  factory TableAssetConfig.fromJson(Map<String, dynamic> json) =>
      _$TableAssetConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$TableAssetConfigToJson(this);

  static const String exampleKey = '__example_key';

  TableAssetConfig.preview()
      : entryKey = exampleKey,
        entryCount = 5,
        headerText = 'Data Table',
        showTimestamps = true,
        textColor = null,
        backgroundColor = null,
        borderColor = null {
    textPos = TextPos.above;
    size = const RelativeSize(width: 0.3, height: 0.4);
  }

  @override
  Widget build(BuildContext context) => TableAssetWidget(this);

  /// Make configure() consistent with your other assets:
  /// SingleChildScrollView → Container(width: 300) → _TableConfigContent
  @override
  Widget configure(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: _TableConfigContent(config: this),
      ),
    );
  }
}

class TableAssetWidget extends ConsumerStatefulWidget {
  final TableAssetConfig config;

  const TableAssetWidget(this.config, {super.key});

  @override
  ConsumerState<TableAssetWidget> createState() => _TableAssetWidgetState();
}

class _TableAssetWidgetState extends ConsumerState<TableAssetWidget> {
  @override
  Widget build(BuildContext context) {
    if (widget.config.entryKey == TableAssetConfig.exampleKey) {
      return _buildPreview();
    }

    final collectorAsync = ref.watch(collectorProvider);

    return collectorAsync.when(
      data: (collector) {
        if (collector == null) {
          return const Center(child: Text('No collector available'));
        }

        return StreamBuilder<List<TimeseriesData<dynamic>>>(
          stream: collector.collectStream(
            widget.config.entryKey,
            since: const Duration(hours: 24), // Show last 24 hours of data
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorWidget(snapshot.error.toString());
            }

            if (!snapshot.hasData) {
              return _buildLoadingWidget();
            }

            final data = snapshot.data!;
            return _buildTable(data);
          },
        );
      },
      loading: () => _buildLoadingWidget(),
      error: (error, stackTrace) => _buildErrorWidget(error.toString()),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: widget.config.borderColor ?? Colors.grey,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundColor ?? Colors.white,
        border: Border.all(
          color: widget.config.borderColor ?? Colors.grey,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          'Error: $error',
          style: TextStyle(
            color: Colors.red,
            fontSize: 12.0,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(List<TimeseriesData<dynamic>> data) {
    // Take only the latest entries based on entryCount
    final recentData = data.take(widget.config.entryCount).toList();

    if (recentData.isEmpty) {
      return _buildEmptyTable();
    }

    // Determine columns based on the first data point
    final columns = _determineColumns(recentData.first.value);

    return Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: widget.config.borderColor ?? Theme.of(context).dividerColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.config.headerText != null) _buildHeader(),
          _buildTableContent(recentData, columns),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base =
            (constraints.hasBoundedHeight && constraints.maxHeight.isFinite)
                ? constraints.maxHeight
                : 40.0; // sensible default
        final fontSize = (base * 0.6).clamp(10.0, 28.0);

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            border: Border(
              bottom: BorderSide(
                color: widget.config.borderColor ?? Colors.grey,
                width: 1,
              ),
            ),
          ),
          child: Text(
            widget.config.headerText!,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              color: widget.config.textColor ?? Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  Widget _buildTableContent(
    List<TimeseriesData<dynamic>> data,
    List<String> columns,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasFiniteH =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

        final double rowHeight;
        final double fontSize;

        if (hasFiniteH) {
          final availableHeight = constraints.maxHeight;
          rowHeight = (availableHeight / (data.length + 1))
              .clamp(28.0, 80.0); // header + rows
          fontSize = (rowHeight * 0.6).clamp(8.0, 24.0);
        } else {
          // Unbounded (e.g., inside SliverList/Draggable/etc.)
          rowHeight = 36.0;
          fontSize = 14.0;
        }

        final table = DataTable(
          columns: columns
              .map((column) => DataColumn(
                    label: Text(
                      column,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                        color: widget.config.textColor ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ))
              .toList(),
          rows: data.map((e) => _buildDataRow(e, columns, fontSize)).toList(),
          dataRowMinHeight: rowHeight,
          dataRowMaxHeight: rowHeight,
          headingRowHeight: rowHeight,
          border: TableBorder.all(
            color: widget.config.borderColor ?? Colors.grey,
            width: 0.5,
          ),
        );

        if (hasFiniteH) {
          // Only “fill” when height is actually bounded
          return FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: table,
            ),
          );
        } else {
          // Let intrinsic sizing work in unbounded contexts and allow horizontal scroll
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        }
      },
    );
  }

  DataRow _buildDataRow(
      TimeseriesData<dynamic> entry, List<String> columns, double fontSize) {
    final cells = <DataCell>[];

    for (final column in columns) {
      if (column == 'Timestamp') {
        cells.add(DataCell(
          Text(
            _formatTimestamp(entry.time),
            style: TextStyle(
              fontSize: fontSize,
              color: widget.config.textColor ?? Colors.black,
            ),
          ),
        ));
      } else {
        final value = _extractValue(entry.value, column);
        cells.add(DataCell(
          Text(
            _formatValue(value),
            style: TextStyle(
              fontSize: fontSize,
              color: widget.config.textColor ?? Colors.black,
            ),
          ),
        ));
      }
    }

    return DataRow(cells: cells);
  }

  Widget _buildEmptyTable() {
    return Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: widget.config.borderColor ?? Theme.of(context).dividerColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          'No data available',
          style: TextStyle(
            color: widget.config.textColor ?? Colors.grey,
            fontSize: 12.0,
          ),
        ),
      ),
    );
  }

  List<String> _determineColumns(dynamic value) {
    final columns = <String>[];

    if (widget.config.showTimestamps) {
      columns.add('Timestamp');
    }

    if (value is Map) {
      // For objects, create columns for each top-level key
      for (final key in value.keys) {
        columns.add(key.toString());
      }
    } else {
      // For simple values, just create a 'Value' column
      columns.add('Value');
    }

    return columns;
  }

  dynamic _extractValue(dynamic value, String column) {
    if (column == 'Timestamp') {
      return null; // Timestamp is handled separately
    }

    if (value is Map && value.containsKey(column)) {
      return value[column];
    } else if (column == 'Value') {
      return value;
    }

    return null;
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String _formatValue(dynamic value) {
    if (value == null) return '---';

    if (value is num) {
      if (value is double) return value.toStringAsFixed(2);
      return value.toString();
    }

    if (value is bool) return value ? 'true' : 'false';
    if (value is String) return value;

    return value.toString();
  }

  Widget _buildPreview() {
    // Create sample data that mimics the structure of real TimeseriesData
    final sampleData = <TimeseriesData<dynamic>>[
      TimeseriesData(
          {'temperature': 25.5, 'humidity': 65.0, 'pressure': 1013.2},
          DateTime.now().subtract(const Duration(minutes: 5))),
      TimeseriesData(
          {'temperature': 26.1, 'humidity': 64.8, 'pressure': 1013.0},
          DateTime.now().subtract(const Duration(minutes: 4))),
      TimeseriesData(
          {'temperature': 25.8, 'humidity': 65.2, 'pressure': 1012.8},
          DateTime.now().subtract(const Duration(minutes: 3))),
      TimeseriesData(
          {'temperature': 26.3, 'humidity': 64.5, 'pressure': 1013.5},
          DateTime.now().subtract(const Duration(minutes: 2))),
      TimeseriesData(
          {'temperature': 25.9, 'humidity': 65.1, 'pressure': 1013.1},
          DateTime.now().subtract(const Duration(minutes: 1))),
    ];

    // Take only the configured number of entries
    final recentData = sampleData.take(widget.config.entryCount).toList();

    if (recentData.isEmpty) {
      return _buildEmptyTable();
    }

    // Determine columns based on the first data point
    final columns = _determineColumns(recentData.first.value);

    return Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: widget.config.borderColor ?? Theme.of(context).dividerColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.config.headerText != null) _buildHeader(),
          _buildTableContent(recentData, columns),
        ],
      ),
    );
  }
}

///
/// Config UI (consistent with other assets)
///
class _TableConfigContent extends StatefulWidget {
  final TableAssetConfig config;
  const _TableConfigContent({required this.config});

  @override
  State<_TableConfigContent> createState() => _TableConfigContentState();
}

class _TableConfigContentState extends State<_TableConfigContent> {
  late TextEditingController _entryKeyController;
  late TextEditingController _entryCountController;
  late TextEditingController _headerTextController;
  late bool _showTimestamps;
  late Color? _textColor;
  late Color? _backgroundColor;
  late Color? _borderColor;

  @override
  void initState() {
    super.initState();
    _entryKeyController = TextEditingController(text: widget.config.entryKey);
    _entryCountController =
        TextEditingController(text: widget.config.entryCount.toString());
    _headerTextController =
        TextEditingController(text: widget.config.headerText ?? '');
    _showTimestamps = widget.config.showTimestamps;
    _textColor = widget.config.textColor;
    _backgroundColor = widget.config.backgroundColor;
    _borderColor = widget.config.borderColor;
  }

  @override
  void dispose() {
    _entryKeyController.dispose();
    _entryCountController.dispose();
    _headerTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyField(
          initialValue: widget.config.entryKey,
          onChanged: (value) => setState(() => widget.config.entryKey = value),
          label: 'Entry Key (collectStream key)',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _entryCountController,
          decoration: const InputDecoration(
            labelText: 'Entry Count',
            helperText: 'Number of entries to show',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            final count = int.tryParse(value);
            if (count != null && count > 0) {
              setState(() => widget.config.entryCount = count);
            }
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _headerTextController,
          decoration: const InputDecoration(
            labelText: 'Header Text (optional)',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(
              () => widget.config.headerText = value.isEmpty ? null : value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: _showTimestamps,
              onChanged: (value) {
                setState(() {
                  _showTimestamps = value ?? true;
                  widget.config.showTimestamps = _showTimestamps;
                });
              },
            ),
            const Text('Show timestamps'),
          ],
        ),
        const SizedBox(height: 12),

        // Colors
        Text('Colors', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _colorRow(
          context,
          'Text',
          _textColor,
          (c) => setState(() {
            _textColor = c;
            widget.config.textColor = c;
          }),
        ),
        const SizedBox(height: 8),
        _colorRow(
          context,
          'Background',
          _backgroundColor,
          (c) => setState(() {
            _backgroundColor = c;
            widget.config.backgroundColor = c;
          }),
        ),
        const SizedBox(height: 8),
        _colorRow(
          context,
          'Border',
          _borderColor,
          (c) => setState(() {
            _borderColor = c;
            widget.config.borderColor = c;
          }),
        ),
        const SizedBox(height: 16),

        // Keep consistent with other assets
        SizeField(
          initialValue: widget.config.size,
          onChanged: (size) => setState(() => widget.config.size = size),
        ),
        const SizedBox(height: 12),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (c) => setState(() => widget.config.coordinates = c),
          enableAngle: true,
        ),
      ],
    );
  }

  Widget _colorRow(
    BuildContext context,
    String label,
    Color? color,
    ValueChanged<Color?> onChanged,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Container(
          width: 44,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          child: color == null
              ? const Text('None', style: TextStyle(fontSize: 10))
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          child: const Text('Pick'),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Pick $label color'),
                content: SingleChildScrollView(
                  child: ColorPicker(
                    pickerColor: color ?? Colors.black, // fallback when null
                    onColorChanged: (c) => onChanged(c),
                    pickerAreaHeightPercent: 0.8,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          icon: const Icon(Icons.clear),
          label: const Text('Clear'),
          onPressed: () => onChanged(null), // ← sets to null
        ),
      ],
    );
  }
}
