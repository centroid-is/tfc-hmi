import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/drawings/drawing_overlay.dart';
import 'package:tfc/page_creator/assets/drawing_viewer.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/providers/tech_doc.dart';
import 'package:tfc/tech_docs/tech_doc_picker.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart';

void main() {
  group('DrawingViewerConfig serialization', () {
    test('serializes to JSON with all fields', () {
      final config = DrawingViewerConfig(
        drawingName: 'Panel A',
        filePath: '/drawings/panel_a.pdf',
        startPage: 3,
      );
      final json = config.toJson();
      expect(json['drawingName'], 'Panel A');
      expect(json['filePath'], '/drawings/panel_a.pdf');
      expect(json['startPage'], 3);
    });

    test('deserializes from JSON correctly (round-trip)', () {
      final original = DrawingViewerConfig(
        drawingName: 'Panel B',
        filePath: '/drawings/panel_b.pdf',
        startPage: 5,
      );
      // Full JSON round-trip through encode/decode to get pure Maps
      final jsonStr = jsonEncode(original.toJson());
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = DrawingViewerConfig.fromJson(decoded);
      expect(restored.drawingName, original.drawingName);
      expect(restored.filePath, original.filePath);
      expect(restored.startPage, original.startPage);
    });

    test('preserves techDocId through serialization round-trip', () {
      final config = DrawingViewerConfig(
        drawingName: 'Panel C',
        filePath: '',
        startPage: 2,
      )..techDocId = 42;

      final jsonStr = jsonEncode(config.toJson());
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = DrawingViewerConfig.fromJson(decoded);
      expect(restored.techDocId, 42);
      expect(restored.drawingName, 'Panel C');
      expect(restored.startPage, 2);
    });

    test('preview() creates instance with empty defaults', () {
      final config = DrawingViewerConfig.preview();
      expect(config.drawingName, '');
      expect(config.filePath, '');
      expect(config.startPage, 1);
    });

    test('displayName returns Drawing Viewer', () {
      final config = DrawingViewerConfig.preview();
      expect(config.displayName, 'Drawing Viewer');
    });

    test('category returns Application', () {
      final config = DrawingViewerConfig.preview();
      expect(config.category, 'Application');
    });
  });

  group('AssetRegistry integration', () {
    test('defaultFactories contains DrawingViewerConfig', () {
      final asset = AssetRegistry.createDefaultAsset(DrawingViewerConfig);
      expect(asset, isA<DrawingViewerConfig>());
    });

    test('fromJsonFactories can parse DrawingViewerConfig', () {
      final config = DrawingViewerConfig(
        drawingName: 'Test',
        filePath: '/test.pdf',
        startPage: 1,
      );
      // Full JSON round-trip to get pure Maps (Coordinates/RelativeSize)
      final jsonStr = jsonEncode(config.toJson());
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final assets = AssetRegistry.parse(json);
      expect(assets, hasLength(1));
      expect(assets.first, isA<DrawingViewerConfig>());
      final parsed = assets.first as DrawingViewerConfig;
      expect(parsed.drawingName, 'Test');
      expect(parsed.filePath, '/test.pdf');
    });
  });

  group('DrawingViewerButton', () {
    testWidgets('renders without error', (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Panel A',
        filePath: '/drawings/panel_a.pdf',
        startPage: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(DrawingViewerButton), findsOneWidget);
    });

    testWidgets('shows PDF icon', (tester) async {
      final config = DrawingViewerConfig.preview();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });

    testWidgets('shows drawingName text', (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Panel A',
        filePath: '/drawings/panel_a.pdf',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Panel A'), findsOneWidget);
    });

    testWidgets('shows Drawing fallback when name empty', (tester) async {
      final config = DrawingViewerConfig.preview();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Drawing'), findsOneWidget);
    });

    testWidgets('tap with techDocId loads PDF bytes from tech doc provider',
        (tester) async {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
      final config = DrawingViewerConfig(
        drawingName: 'ATV320 Manual',
        filePath: '',
        startPage: 5,
      )..techDocId = 42;

      final container = ProviderContainer(
        overrides: [
          techDocPdfBytesProvider(42).overrideWith((_) async => pdfBytes),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DrawingViewerButton));
      await tester.pumpAndSettle();

      expect(container.read(activeDrawingBytesProvider), pdfBytes);
      expect(container.read(activeDrawingPathProvider), isNull);
      expect(container.read(activeDrawingPageProvider), 5);
      expect(container.read(activeDrawingTitleProvider), 'ATV320 Manual');
      expect(container.read(drawingVisibleProvider), true);
      expect(container.read(activeDrawingHighlightProvider), isNull);
    });

    testWidgets('tap with null techDocId does not open overlay',
        (tester) async {
      final config = DrawingViewerConfig(
        drawingName: '',
        filePath: '',
        startPage: 1,
      ); // techDocId is null by default
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DrawingViewerButton));
      await tester.pump();

      expect(container.read(drawingVisibleProvider), false);
    });

    testWidgets('tap with techDocId but null bytes does not open overlay',
        (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Missing Doc',
        filePath: '',
        startPage: 1,
      )..techDocId = 99;

      final container = ProviderContainer(
        overrides: [
          techDocPdfBytesProvider(99).overrideWith((_) async => null),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DrawingViewerButton));
      await tester.pumpAndSettle();

      expect(container.read(drawingVisibleProvider), false);
    });

    testWidgets('tap uses Document fallback title when drawingName is empty',
        (tester) async {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      final config = DrawingViewerConfig(
        drawingName: '',
        filePath: '',
        startPage: 1,
      )..techDocId = 10;

      final container = ProviderContainer(
        overrides: [
          techDocPdfBytesProvider(10).overrideWith((_) async => pdfBytes),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DrawingViewerButton));
      await tester.pumpAndSettle();

      expect(container.read(activeDrawingTitleProvider), 'Document');
      expect(container.read(drawingVisibleProvider), true);
    });

    // Legacy backward compatibility: filePath still works for existing configs
    testWidgets('tap with filePath (legacy) sets drawing path providers',
        (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Panel A',
        filePath: '/drawings/panel_a.pdf',
        startPage: 3,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 100,
                height: 100,
                child: DrawingViewerButton(config: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DrawingViewerButton));
      await tester.pump();

      expect(
          container.read(activeDrawingPathProvider), '/drawings/panel_a.pdf');
      expect(container.read(activeDrawingPageProvider), 3);
      expect(container.read(drawingVisibleProvider), true);
      expect(container.read(activeDrawingHighlightProvider), isNull);
    });
  });

  group('DrawingViewerConfigEditor', () {
    final sampleDocs = [
      TechDocSummary(
        id: 1,
        name: 'ATV320 User Manual',
        pageCount: 120,
        sectionCount: 15,
        uploadedAt: DateTime(2026, 1, 1),
      ),
      TechDocSummary(
        id: 2,
        name: 'PT100 Sensor Datasheet',
        pageCount: 4,
        sectionCount: 3,
        uploadedAt: DateTime(2026, 1, 2),
      ),
    ];

    testWidgets('config editor shows TechDocPicker', (tester) async {
      final config = DrawingViewerConfig.preview();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbTechDocsProvider.overrideWith((_) async => sampleDocs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: config.configure(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TechDocPicker), findsOneWidget);
    });

    testWidgets('config editor shows Button Text field', (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Panel A',
        filePath: '',
        startPage: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbTechDocsProvider.overrideWith((_) async => sampleDocs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: config.configure(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Button Text'), findsOneWidget);
      // The TextField should be pre-populated with the config's drawingName
      expect(find.text('Panel A'), findsOneWidget);
    });

    testWidgets('editing Button Text updates config.drawingName',
        (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Old Label',
        filePath: '',
        startPage: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbTechDocsProvider.overrideWith((_) async => sampleDocs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: config.configure(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Button Text TextField (first TextField in the editor)
      final textFields = find.byType(TextField);
      // Button Text is the first, Start Page is the second
      expect(textFields, findsAtLeast(2));

      // Clear and enter new text
      await tester.enterText(textFields.first, 'New Label');
      await tester.pump();

      expect(config.drawingName, 'New Label');
    });

    testWidgets('Button Text field appears above Start Page field',
        (tester) async {
      final config = DrawingViewerConfig.preview();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbTechDocsProvider.overrideWith((_) async => sampleDocs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: config.configure(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both labels should be present
      final buttonTextLabel = find.text('Button Text');
      final startPageLabel = find.text('Start Page');
      expect(buttonTextLabel, findsOneWidget);
      expect(startPageLabel, findsOneWidget);

      // Button Text should appear above Start Page (smaller Y coordinate)
      final buttonTextY = tester.getTopLeft(buttonTextLabel).dy;
      final startPageY = tester.getTopLeft(startPageLabel).dy;
      expect(buttonTextY, lessThan(startPageY));
    });

    testWidgets('config editor shows Start Page field', (tester) async {
      final config = DrawingViewerConfig(
        drawingName: 'Test',
        filePath: '',
        startPage: 7,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbTechDocsProvider.overrideWith((_) async => sampleDocs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: config.configure(context),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start Page'), findsOneWidget);
    });
  });
}
