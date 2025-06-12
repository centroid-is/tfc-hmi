// Write test for Graph widget

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/graph.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: child,
        ),
      ),
    );
  }

  group('Graph Widget', () {
    testWidgets('renders line chart with valid data',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 2.0],
            [2.0, 4.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles completely empty data', (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = <Map<GraphDataConfig, List<List<double>>>>[];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles empty series data', (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): <List<double>>[],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('renders bar chart without errors',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.bar,
        xAxis: GraphAxisConfig(unit: ''),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 2.0],
            [2.0, 4.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('renders scatter plot without errors',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.scatter,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 2.0],
            [2.0, 4.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles axis configuration', (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(
          unit: 'x',
          min: 0,
          max: 10,
          step: 2,
        ),
        yAxis: GraphAxisConfig(
          unit: 'y',
          min: 0,
          max: 100,
          step: 20,
        ),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 20.0],
            [5.0, 60.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles pan callback', (WidgetTester tester) async {
      bool callbackTriggered = false;

      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 2.0],
            [2.0, 4.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
            onPanCompleted: () {
              callbackTriggered = true;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the Graph widget
      final graphFinder = find.byType(Graph);
      expect(graphFinder, findsOneWidget);

      // Simulate pan gesture
      await tester.drag(graphFinder, const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(callbackTriggered, isTrue);
    });

    group('Configuration Classes', () {
      test('GraphConfig construction', () {
        final config = GraphConfig(
          type: GraphType.line,
          xAxis: GraphAxisConfig(unit: 'x'),
          yAxis: GraphAxisConfig(unit: 'y'),
          yAxis2: GraphAxisConfig(unit: 'y2'),
        );

        expect(config.type, GraphType.line);
        expect(config.xAxis.unit, 'x');
        expect(config.yAxis.unit, 'y');
        expect(config.yAxis2?.unit, 'y2');
      });

      test('GraphDataConfig construction', () {
        final dataConfig = GraphDataConfig(label: 'Test Label');
        expect(dataConfig.label, 'Test Label');
      });

      test('GraphAxisConfig construction', () {
        final axisConfig = GraphAxisConfig(
          unit: 'test',
          min: 0,
          max: 100,
          step: 10,
        );

        expect(axisConfig.unit, 'test');
        expect(axisConfig.min, 0);
        expect(axisConfig.max, 100);
        expect(axisConfig.step, 10);
      });
    });

    testWidgets('throws ArgumentError for duplicate series labels',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Same Label'): [
            [1.0, 2.0],
            [2.0, 4.0],
          ],
        },
        {
          GraphDataConfig(label: 'Same Label'): [
            [1.0, 3.0],
            [2.0, 6.0],
          ],
        },
      ];

      // Build the widget tree
      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      // Get the exception that was thrown during the build
      final dynamic exception = tester.takeException();
      expect(exception, isA<ArgumentError>());
      expect(
        exception.toString(),
        equals('Invalid argument(s): Duplicate series label: Same Label'),
      );
    });

    testWidgets('throws ArgumentError for invalid axis configuration',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(
          unit: 'x',
          min: 10, // min > max
          max: 0,
          step: 2,
        ),
        yAxis: GraphAxisConfig(
          unit: 'y',
          min: 0,
          max: 100,
          step: -20, // negative step
        ),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 20.0],
            [5.0, 60.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      final dynamic exception = tester.takeException();
      expect(exception, isA<ArgumentError>());
      expect(
        exception.toString(),
        equals('Invalid argument(s): Axis min must be less than max'),
      );
    });

    testWidgets('throws ArgumentError for negative step',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(
          unit: 'x',
          min: 0,
          max: 10,
          step: -2, // negative step
        ),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, 20.0],
            [5.0, 60.0],
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      final dynamic exception = tester.takeException();
      expect(exception, isA<ArgumentError>());
      expect(
        exception.toString(),
        equals('Invalid argument(s): Axis step must be positive'),
      );
    });
  });

  group('Graph Widget Edge Cases', () {
    testWidgets('handles null values in data points',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0, double.nan], // NaN value
            [2.0, double.infinity], // Infinity value
            [3.0, -double.infinity], // Negative infinity
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles mismatched data point lengths',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(unit: 'x'),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [1.0], // Missing y value
            [2.0, 4.0, 5.0], // Extra value
            [3.0, 6.0], // Correct length
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles data points outside axis range',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.line,
        xAxis: GraphAxisConfig(
          unit: 'x',
          min: 0,
          max: 10,
        ),
        yAxis: GraphAxisConfig(
          unit: 'y',
          min: 0,
          max: 100,
        ),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [-5.0, -20.0], // Points outside range
            [15.0, 120.0], // Points outside range
            [5.0, 50.0], // Points inside range
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('handles bar chart with non-numeric x values',
        (WidgetTester tester) async {
      final config = GraphConfig(
        type: GraphType.bar,
        xAxis: GraphAxisConfig(unit: ''),
        yAxis: GraphAxisConfig(unit: 'y'),
      );

      final data = [
        {
          GraphDataConfig(label: 'Test Series'): [
            [double.nan, 2.0], // NaN x value
            [double.infinity, 4.0], // Infinity x value
          ],
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Graph(
            config: config,
            data: data,
          ),
        ),
      );

      expect(find.byType(Graph), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
