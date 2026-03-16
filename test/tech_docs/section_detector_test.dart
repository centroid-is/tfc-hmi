import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/tech_docs/section_detector.dart';

/// Helper to create body text fragments at the standard body height (12.0).
///
/// Adds [count] body fragments to ensure the median height stays at 12.0
/// regardless of how many heading fragments exist.
List<SizedFragment> _bodyFragments(int page, {int count = 5}) {
  return List.generate(
    count,
    (i) => SizedFragment(
        text: 'Body text line ${i + 1}.', height: 12.0, pageNumber: page),
  );
}

void main() {
  const detector = SectionDetector();

  group('SectionDetector', () {
    test('empty fragment list returns empty section list', () {
      final result = detector.detectSections([]);
      expect(result, isEmpty);
    });

    test('all same-height fragments returns single section with all content',
        () {
      final fragments = [
        const SizedFragment(
            text: 'Hello world.', height: 12.0, pageNumber: 1),
        const SizedFragment(
            text: 'Second line.', height: 12.0, pageNumber: 1),
        const SizedFragment(
            text: 'Third line.', height: 12.0, pageNumber: 2),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1));
      expect(result[0].title, 'Document Content');
      expect(result[0].content, contains('Hello world.'));
      expect(result[0].content, contains('Second line.'));
      expect(result[0].content, contains('Third line.'));
      expect(result[0].pageStart, 1);
      expect(result[0].pageEnd, 2);
      expect(result[0].level, 0);
    });

    test('fragments with 2x+ median height classified as chapter (level 0)',
        () {
      final fragments = [
        // Chapter heading at 26.0 (>2x median of 12.0)
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        // Enough body text to keep median at 12.0
        ..._bodyFragments(1),
        ..._bodyFragments(2),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1));
      expect(result[0].title, 'Chapter One');
      expect(result[0].level, 0);
      expect(result[0].content, contains('Body text line 1.'));
    });

    test('fragments with 1.4x median height classified as section (level 1)',
        () {
      final fragments = [
        // Chapter heading at 26.0 (>2x median of 12.0)
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1),
        // Section heading at 18.0 (~1.5x median of 12.0)
        const SizedFragment(
            text: 'Section Alpha', height: 18.0, pageNumber: 2),
        ..._bodyFragments(2),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1)); // one chapter
      expect(result[0].children, hasLength(1)); // one section child
      expect(result[0].children[0].title, 'Section Alpha');
      expect(result[0].children[0].level, 1);
    });

    test(
        'fragments with 1.15x median height classified as subsection (level 2)',
        () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1),
        const SizedFragment(
            text: 'Section Alpha', height: 18.0, pageNumber: 2),
        ..._bodyFragments(2),
        // Subsection heading at 14.5 (~1.2x median of 12.0)
        const SizedFragment(
            text: 'Subsection Beta', height: 14.5, pageNumber: 3),
        ..._bodyFragments(3),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1)); // one chapter
      expect(result[0].children, hasLength(1)); // one section
      expect(result[0].children[0].children, hasLength(1)); // one subsection
      expect(result[0].children[0].children[0].title, 'Subsection Beta');
      expect(result[0].children[0].children[0].level, 2);
    });

    test('body text accumulated into nearest preceding heading', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        const SizedFragment(
            text: 'First body line.', height: 12.0, pageNumber: 1),
        const SizedFragment(
            text: 'Second body line.', height: 12.0, pageNumber: 1),
        ..._bodyFragments(1, count: 3),
        const SizedFragment(
            text: 'Chapter Two', height: 26.0, pageNumber: 2),
        const SizedFragment(
            text: 'Chapter two body.', height: 12.0, pageNumber: 2),
        ..._bodyFragments(2, count: 3),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(2));
      expect(result[0].title, 'Chapter One');
      expect(result[0].content, contains('First body line.'));
      expect(result[0].content, contains('Second body line.'));
      expect(result[0].content, isNot(contains('Chapter two body.')));
      expect(result[1].title, 'Chapter Two');
      expect(result[1].content, contains('Chapter two body.'));
    });

    test('hierarchical tree built correctly', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1),
        const SizedFragment(
            text: 'Section A', height: 18.0, pageNumber: 2),
        ..._bodyFragments(2),
        const SizedFragment(
            text: 'Subsection A1', height: 14.5, pageNumber: 3),
        ..._bodyFragments(3),
        const SizedFragment(
            text: 'Section B', height: 18.0, pageNumber: 4),
        ..._bodyFragments(4),
        const SizedFragment(
            text: 'Chapter Two', height: 26.0, pageNumber: 5),
        ..._bodyFragments(5),
      ];

      final result = detector.detectSections(fragments);

      // Two chapters
      expect(result, hasLength(2));
      expect(result[0].title, 'Chapter One');
      expect(result[1].title, 'Chapter Two');

      // Chapter One has 2 sections
      expect(result[0].children, hasLength(2));
      expect(result[0].children[0].title, 'Section A');
      expect(result[0].children[1].title, 'Section B');

      // Section A has 1 subsection
      expect(result[0].children[0].children, hasLength(1));
      expect(result[0].children[0].children[0].title, 'Subsection A1');

      // Section B has no subsections
      expect(result[0].children[1].children, isEmpty);

      // Chapter Two has no sections
      expect(result[1].children, isEmpty);
    });

    test('page ranges span from heading page to next heading page - 1', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(2),
        ..._bodyFragments(3),
        const SizedFragment(
            text: 'Chapter Two', height: 26.0, pageNumber: 4),
        ..._bodyFragments(5),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(2));
      expect(result[0].pageStart, 1);
      expect(result[0].pageEnd, 3);
      expect(result[1].pageStart, 4);
      expect(result[1].pageEnd, 5);
    });

    test('last section pageEnd equals last page number', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(5),
        ..._bodyFragments(10),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1));
      expect(result[0].pageEnd, 10);
    });

    test('sortOrder assigned sequentially within each parent', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1),
        const SizedFragment(
            text: 'Chapter Two', height: 26.0, pageNumber: 2),
        ..._bodyFragments(2),
        const SizedFragment(
            text: 'Chapter Three', height: 26.0, pageNumber: 3),
        ..._bodyFragments(3),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(3));
      expect(result[0].sortOrder, 0);
      expect(result[1].sortOrder, 1);
      expect(result[2].sortOrder, 2);
    });

    test('sortOrder sequential within children', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1, count: 3),
        const SizedFragment(
            text: 'Section A', height: 18.0, pageNumber: 1),
        ..._bodyFragments(1),
        const SizedFragment(
            text: 'Section B', height: 18.0, pageNumber: 2),
        ..._bodyFragments(2),
        const SizedFragment(
            text: 'Section C', height: 18.0, pageNumber: 3),
        ..._bodyFragments(3),
      ];

      final result = detector.detectSections(fragments);
      expect(result[0].children, hasLength(3));
      expect(result[0].children[0].sortOrder, 0);
      expect(result[0].children[1].sortOrder, 1);
      expect(result[0].children[2].sortOrder, 2);
    });

    test('short text lines at heading height classified as headings', () {
      // 2 words, at chapter height -- should be a heading
      final fragments = [
        const SizedFragment(
            text: 'My Chapter', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1),
        ..._bodyFragments(2),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1));
      expect(result[0].title, 'My Chapter');
      expect(result[0].level, 0);
    });

    test('long text at heading height NOT classified as heading', () {
      // >12 words at chapter height -- should be body text (bold body)
      final fragments = [
        const SizedFragment(
            text: 'Real Heading', height: 26.0, pageNumber: 1),
        const SizedFragment(
            text:
                'This is a very long line of bold text that has many more than twelve words and should not be treated as a heading',
            height: 26.0,
            pageNumber: 1),
        ..._bodyFragments(1),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1));
      expect(result[0].title, 'Real Heading');
      // The long bold text should be in the content, not a separate heading
      expect(result[0].content, contains('very long line of bold text'));
    });

    test('body text before any heading is captured in first section', () {
      // Some PDFs have body text before the first heading
      final fragments = [
        const SizedFragment(
            text: 'Preamble text.', height: 12.0, pageNumber: 1),
        ..._bodyFragments(1, count: 4),
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 2),
        ..._bodyFragments(2),
      ];

      final result = detector.detectSections(fragments);
      // Should have a preamble section + the actual chapter
      // The preamble text should not be lost
      expect(result.length, greaterThanOrEqualTo(1));

      // Find if the preamble text is captured somewhere
      final allContent =
          result.map((s) => '${s.title} ${s.content}').join(' ');
      expect(allContent, contains('Preamble text.'));
    });

    test('empty text fragments are filtered out', () {
      final fragments = [
        const SizedFragment(text: '', height: 12.0, pageNumber: 1),
        const SizedFragment(text: '   ', height: 12.0, pageNumber: 1),
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1),
      ];

      final result = detector.detectSections(fragments);
      expect(result, hasLength(1));
      expect(result[0].title, 'Chapter One');
    });

    test('subsection page ranges computed correctly within sections', () {
      final fragments = [
        const SizedFragment(
            text: 'Chapter One', height: 26.0, pageNumber: 1),
        ..._bodyFragments(1, count: 3),
        const SizedFragment(
            text: 'Section A', height: 18.0, pageNumber: 1),
        ..._bodyFragments(1, count: 3),
        const SizedFragment(text: 'Sub A1', height: 14.5, pageNumber: 2),
        ..._bodyFragments(3),
        const SizedFragment(text: 'Sub A2', height: 14.5, pageNumber: 4),
        ..._bodyFragments(5),
      ];

      final result = detector.detectSections(fragments);
      final sectionA = result[0].children[0];
      expect(sectionA.children, hasLength(2));
      expect(sectionA.children[0].title, 'Sub A1');
      expect(sectionA.children[0].pageStart, 2);
      expect(sectionA.children[0].pageEnd, 3);
      expect(sectionA.children[1].title, 'Sub A2');
      expect(sectionA.children[1].pageStart, 4);
      expect(sectionA.children[1].pageEnd, 5);
    });
  });
}
