import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/interfaces/tech_doc_index.dart';
import 'package:tfc_mcp_server/src/services/drift_tech_doc_index.dart';

void main() {
  late ServerDatabase db;
  late DriftTechDocIndex index;

  /// Sample PDF bytes for testing.
  final samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d]); // %PDF-

  /// Sample hierarchical sections: chapter > section > subsection.
  final sampleSections = [
    ParsedSection(
      title: 'Chapter 1: Installation',
      content: 'This chapter covers the installation procedure for the ATV320 drive.',
      pageStart: 1,
      pageEnd: 10,
      level: 1,
      sortOrder: 0,
      children: [
        ParsedSection(
          title: '1.1 Mounting',
          content: 'Mount the drive on a flat surface using M5 bolts.',
          pageStart: 2,
          pageEnd: 5,
          level: 2,
          sortOrder: 1,
          children: [
            ParsedSection(
              title: '1.1.1 Wall Mounting',
              content: 'For wall mounting, use the included bracket kit.',
              pageStart: 3,
              pageEnd: 4,
              level: 3,
              sortOrder: 2,
            ),
          ],
        ),
        ParsedSection(
          title: '1.2 Wiring',
          content: 'Connect power cables to terminals L1, L2, L3.',
          pageStart: 6,
          pageEnd: 10,
          level: 2,
          sortOrder: 3,
        ),
      ],
    ),
    ParsedSection(
      title: 'Chapter 2: Configuration',
      content: 'This chapter covers the configuration parameters.',
      pageStart: 11,
      pageEnd: 20,
      level: 1,
      sortOrder: 4,
    ),
  ];

  setUp(() {
    db = ServerDatabase.inMemory();
    index = DriftTechDocIndex(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('isEmpty returns true initially', () async {
    expect(await index.isEmpty, isTrue);
  });

  test('isEmpty returns false after storeDocument', () async {
    await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    expect(await index.isEmpty, isFalse);
  });

  test('storeDocument creates doc row and section rows, returns valid ID',
      () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    expect(docId, greaterThan(0));

    // Verify doc appears in summary.
    final summaries = await index.getSummary();
    expect(summaries, hasLength(1));
    expect(summaries[0].name, 'ATV320 Manual');
    expect(summaries[0].id, docId);
  });

  test('getSummary returns doc metadata without blob bytes', () async {
    await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    final summaries = await index.getSummary();
    expect(summaries, hasLength(1));
    expect(summaries[0].name, 'ATV320 Manual');
    expect(summaries[0].pageCount, 20); // max pageEnd
    expect(summaries[0].sectionCount, 5); // 2 chapters + 2 sections + 1 subsection
    expect(summaries[0].uploadedAt, isA<DateTime>());
  });

  test('search finds sections by fuzzy title match', () async {
    await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    final results = await index.search('mounting');
    expect(results, isNotEmpty);
    expect(
      results.any((r) => r.sectionTitle.toLowerCase().contains('mounting')),
      isTrue,
    );
    expect(results[0].docName, 'ATV320 Manual');
  });

  test('search finds sections by content keyword match', () async {
    await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    final results = await index.search('bracket');
    expect(results, isNotEmpty);
    // The bracket text is in '1.1.1 Wall Mounting' content.
    expect(
      results.any((r) => r.sectionTitle == '1.1.1 Wall Mounting'),
      isTrue,
    );
  });

  test('getSection returns full section with content', () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    // Search for a section to get its ID.
    final results = await index.search('wiring');
    expect(results, isNotEmpty);

    final section = await index.getSection(results[0].sectionId);
    expect(section, isNotNull);
    expect(section!.title, contains('Wiring'));
    expect(section.content, contains('terminals'));
    expect(section.docId, docId);
  });

  test('deleteDocument removes doc and all sections', () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    await index.deleteDocument(docId);

    expect(await index.isEmpty, isTrue);
    expect(await index.getSummary(), isEmpty);
    expect(await index.search('installation'), isEmpty);
  });

  test('renameDocument updates the name', () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    await index.renameDocument(docId, 'ATV320 Installation Guide v2');

    final summaries = await index.getSummary();
    expect(summaries[0].name, 'ATV320 Installation Guide v2');
  });

  test('updateSections replaces all sections for a doc', () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    // Replace with simpler sections.
    final newSections = [
      ParsedSection(
        title: 'New Chapter 1',
        content: 'Completely new content.',
        pageStart: 1,
        pageEnd: 5,
        level: 1,
        sortOrder: 0,
      ),
    ];

    await index.updateSections(docId, newSections);

    // Old sections should be gone.
    final results = await index.search('installation');
    expect(results, isEmpty);

    // New section should be findable.
    final newResults = await index.search('new content');
    expect(newResults, isNotEmpty);
    expect(newResults[0].sectionTitle, 'New Chapter 1');

    // Summary should reflect new section count.
    final summaries = await index.getSummary();
    expect(summaries[0].sectionCount, 1);
  });

  test('getPdfBytes returns the blob', () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    final bytes = await index.getPdfBytes(docId);
    expect(bytes, isNotNull);
    expect(bytes!, samplePdf);
  });

  test('getPdfBytes returns null for non-existent doc', () async {
    final bytes = await index.getPdfBytes(999);
    expect(bytes, isNull);
  });

  test('storeDocument with hierarchical sections preserves parent-child relationships',
      () async {
    await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    // Search for the subsection.
    final results = await index.search('wall mounting');
    expect(results, isNotEmpty);

    final subsection = await index.getSection(results[0].sectionId);
    expect(subsection, isNotNull);
    expect(subsection!.level, 3);
    expect(subsection.parentId, isNotNull);

    // The parent should be '1.1 Mounting'.
    final parent = await index.getSection(subsection.parentId!);
    expect(parent, isNotNull);
    expect(parent!.title, '1.1 Mounting');
    expect(parent.level, 2);
    expect(parent.parentId, isNotNull);

    // The grandparent should be 'Chapter 1: Installation'.
    final grandparent = await index.getSection(parent.parentId!);
    expect(grandparent, isNotNull);
    expect(grandparent!.title, 'Chapter 1: Installation');
    expect(grandparent.level, 1);
    expect(grandparent.parentId, isNull);
  });

  test('search respects limit parameter', () async {
    // Store a document with many sections that match.
    final manySections = List.generate(
      30,
      (i) => ParsedSection(
        title: 'Section $i about installation',
        content: 'Installation procedure step $i.',
        pageStart: i + 1,
        pageEnd: i + 2,
        level: 1,
        sortOrder: i,
      ),
    );

    await index.storeDocument(
      name: 'Big Manual',
      pdfBytes: samplePdf,
      sections: manySections,
    );

    final limited = await index.search('installation', limit: 5);
    expect(limited, hasLength(5));

    final unlimited = await index.search('installation', limit: 50);
    expect(unlimited, hasLength(30));
  });

  test('getLinkedAssets returns empty list (v1)', () async {
    final docId = await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: sampleSections,
    );

    final links = await index.getLinkedAssets(docId);
    expect(links, isEmpty);
  });

  test('schema v7 migration creates tech_doc and tech_doc_section tables',
      () async {
    // The in-memory database uses onCreate which creates all tables.
    // Verify we can insert and query from both tables.
    final docId = await index.storeDocument(
      name: 'Test Doc',
      pdfBytes: samplePdf,
      sections: [
        ParsedSection(
          title: 'Test Section',
          content: 'Test content.',
          pageStart: 1,
          pageEnd: 1,
          level: 1,
          sortOrder: 0,
        ),
      ],
    );

    expect(docId, greaterThan(0));
    final summaries = await index.getSummary();
    expect(summaries, hasLength(1));

    final results = await index.search('test');
    expect(results, hasLength(1));
  });

  test('DrawingTable pdfBytes column is nullable', () async {
    // Insert a drawing without pdfBytes (legacy mode).
    await db.into(db.drawingTable).insert(
          DrawingTableCompanion.insert(
            assetKey: 'panel-a',
            drawingName: 'Test Drawing',
            filePath: '/drawings/test.pdf',
            pageCount: 5,
            uploadedAt: DateTime.now(),
          ),
        );

    // Verify the drawing was stored with null pdfBytes.
    final drawings = await db.select(db.drawingTable).get();
    expect(drawings, hasLength(1));
    expect(drawings[0].pdfBytes, isNull);
    expect(drawings[0].drawingName, 'Test Drawing');
  });

  test('search by document name returns sections even when title/content do not match',
      () async {
    // Store a document whose name contains "ATV320" but sections have
    // completely unrelated titles and content.
    await index.storeDocument(
      name: 'ATV320 Installation Manual',
      pdfBytes: samplePdf,
      sections: [
        ParsedSection(
          title: 'Safety Precautions',
          content: 'Always disconnect power before servicing.',
          pageStart: 1,
          pageEnd: 3,
          level: 1,
          sortOrder: 0,
        ),
        ParsedSection(
          title: 'Warranty Information',
          content: 'This product is covered for 24 months.',
          pageStart: 4,
          pageEnd: 5,
          level: 1,
          sortOrder: 1,
        ),
      ],
    );

    // Search for "ATV320" — neither section title nor content contains it,
    // but the document name does.
    final results = await index.search('ATV320');
    expect(results, isNotEmpty,
        reason: 'Should find sections via document name match');
    expect(results, hasLength(2),
        reason: 'Both sections of the matching document should be returned');
    expect(results[0].docName, 'ATV320 Installation Manual');
    expect(results[1].docName, 'ATV320 Installation Manual');

    // Snippets for doc-name-only matches should include doc name context.
    expect(results[0].matchSnippet, contains('ATV320'));
  });

  test('exact substring search works alongside fuzzy match', () async {
    await index.storeDocument(
      name: 'XYZ-9000 Datasheet',
      pdfBytes: samplePdf,
      sections: [
        ParsedSection(
          title: 'Overview',
          content: 'The XYZ-9000 is a high-performance controller.',
          pageStart: 1,
          pageEnd: 2,
          level: 1,
          sortOrder: 0,
        ),
      ],
    );

    // Exact substring in content.
    final results = await index.search('XYZ-9000');
    expect(results, isNotEmpty);
    expect(results[0].docName, 'XYZ-9000 Datasheet');

    // Exact substring in document name only (section has no match).
    await index.storeDocument(
      name: 'ABC-1234 Quick Start',
      pdfBytes: samplePdf,
      sections: [
        ParsedSection(
          title: 'Getting Started',
          content: 'Plug in the device and press the power button.',
          pageStart: 1,
          pageEnd: 1,
          level: 1,
          sortOrder: 0,
        ),
      ],
    );

    final docNameResults = await index.search('ABC-1234');
    expect(docNameResults, isNotEmpty);
    expect(docNameResults[0].docName, 'ABC-1234 Quick Start');
  });

  test('multiple documents can be stored and searched independently', () async {
    await index.storeDocument(
      name: 'ATV320 Manual',
      pdfBytes: samplePdf,
      sections: [
        ParsedSection(
          title: 'ATV320 Installation',
          content: 'Install the ATV320 drive.',
          pageStart: 1,
          pageEnd: 5,
          level: 1,
          sortOrder: 0,
        ),
      ],
    );

    await index.storeDocument(
      name: 'Sensor Datasheet',
      pdfBytes: Uint8List.fromList([1, 2, 3]),
      sections: [
        ParsedSection(
          title: 'Temperature Sensor Specs',
          content: 'Operating range: -40 to 85 degrees.',
          pageStart: 1,
          pageEnd: 2,
          level: 1,
          sortOrder: 0,
        ),
      ],
    );

    final atv = await index.search('ATV320');
    expect(atv, hasLength(1));
    expect(atv[0].docName, 'ATV320 Manual');

    final sensor = await index.search('temperature');
    expect(sensor, hasLength(1));
    expect(sensor[0].docName, 'Sensor Datasheet');

    final summaries = await index.getSummary();
    expect(summaries, hasLength(2));
  });
}
