import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tfc/widgets/graph.dart';

class GraphDemo extends StatefulWidget {
  const GraphDemo({super.key});

  @override
  State<GraphDemo> createState() => _GraphDemoState();
}

class _GraphDemoState extends State<GraphDemo> {
  // Current graph configuration
  late GraphConfig _config;
  late List<Map<GraphDataConfig, List<List<double>>>> _data;

  // Controls
  GraphType _selectedType = GraphType.line;
  double _minX = 0;
  double _maxX = 10;
  double _stepX = 1;
  double _minY = 0;
  double _maxY = 100;
  double _stepY = 10;
  // Second Y-axis controls
  double _minY2 = 0;
  double _maxY2 = 1000;
  double _stepY2 = 100;
  bool _showY2 = true;

  @override
  void initState() {
    super.initState();
    _updateGraph();
  }

  void _updateGraph() {
    // Create graph configuration
    _config = GraphConfig(
      type: _selectedType,
      xAxis: GraphAxisConfig(
        unit: 's',
        min: _minX,
        max: _maxX,
        step: _stepX,
      ),
      yAxis: GraphAxisConfig(
        unit: 'mA',
        min: _minY,
        max: _maxY,
        step: _stepY,
      ),
      yAxis2: _showY2
          ? GraphAxisConfig(
              unit: '°C',
              min: _minY2,
              max: _maxY2,
              step: _stepY2,
            )
          : null,
    );

    // Generate sample data
    _data = [
      {
        GraphDataConfig(label: 'Series 1'): List.generate(
          10,
          (i) => [i.toDouble(), (i * i).toDouble()],
        ),
      },
      {
        GraphDataConfig(label: 'Series 2'): List.generate(
          10,
          (i) => [i.toDouble(), (50 + i * 5).toDouble()],
        ),
      },
      // Third series using second Y-axis (showing exponential growth)
      if (_showY2)
        {
          GraphDataConfig(
            label: 'Exponential Series',
            mainAxis: false,
          ): List.generate(
            10,
            (i) => [i.toDouble(), (10 * pow(2, i)).toDouble()],
          ),
        },
    ];

    setState(() {});
  }

  Widget _buildAxisControls(
    String title, {
    required double min,
    required double max,
    required double step,
    required Function(double) onMinChanged,
    required Function(double) onMaxChanged,
    required Function(double) onStepChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'Min'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: min.toString()),
                onSubmitted: (value) {
                  final newValue = double.tryParse(value);
                  if (newValue != null) onMinChanged(newValue);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'Max'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: max.toString()),
                onSubmitted: (value) {
                  final newValue = double.tryParse(value);
                  if (newValue != null) onMaxChanged(newValue);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'Step'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: step.toString()),
                onSubmitted: (value) {
                  final newValue = double.tryParse(value);
                  if (newValue != null) onStepChanged(newValue);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Graph type selector
            Row(
              children: [
                Expanded(
                  child: DropdownButton<GraphType>(
                    value: _selectedType,
                    items: GraphType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedType = value;
                          _updateGraph();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Second Y-axis toggle
                Row(
                  children: [
                    const Text('Show Second Y-Axis'),
                    Switch(
                      value: _showY2,
                      onChanged: (value) {
                        setState(() {
                          _showY2 = value;
                          _updateGraph();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // X-axis controls
            _buildAxisControls(
              'X-Axis Configuration',
              min: _minX,
              max: _maxX,
              step: _stepX,
              onMinChanged: (value) => setState(() {
                _minX = value;
                _updateGraph();
              }),
              onMaxChanged: (value) => setState(() {
                _maxX = value;
                _updateGraph();
              }),
              onStepChanged: (value) => setState(() {
                _stepX = value;
                _updateGraph();
              }),
            ),
            const SizedBox(height: 16),

            // Primary Y-axis controls
            _buildAxisControls(
              'Primary Y-Axis Configuration',
              min: _minY,
              max: _maxY,
              step: _stepY,
              onMinChanged: (value) => setState(() {
                _minY = value;
                _updateGraph();
              }),
              onMaxChanged: (value) => setState(() {
                _maxY = value;
                _updateGraph();
              }),
              onStepChanged: (value) => setState(() {
                _stepY = value;
                _updateGraph();
              }),
            ),
            const SizedBox(height: 16),

            // Secondary Y-axis controls (only shown when enabled)
            if (_showY2) ...[
              _buildAxisControls(
                'Secondary Y-Axis Configuration',
                min: _minY2,
                max: _maxY2,
                step: _stepY2,
                onMinChanged: (value) => setState(() {
                  _minY2 = value;
                  _updateGraph();
                }),
                onMaxChanged: (value) => setState(() {
                  _maxY2 = value;
                  _updateGraph();
                }),
                onStepChanged: (value) => setState(() {
                  _stepY2 = value;
                  _updateGraph();
                }),
              ),
              const SizedBox(height: 16),
            ],

            // The graph
            SizedBox(
              height: 400,
              child: Graph(
                config: _config,
                data: _data,
                onPanCompleted: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pan completed!')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      body: GraphDemo(),
    ),
  ));
}
