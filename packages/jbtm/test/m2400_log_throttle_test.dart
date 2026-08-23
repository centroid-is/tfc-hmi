import 'dart:convert';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

/// Collects every line any logger actually emits.
class _Capture {
  final List<String> lines = [];
  void Function(OutputEvent)? _cb;

  void start() {
    lines.clear();
    final cb = _cb = (event) => lines.addAll(event.lines);
    Logger.addOutputListener(cb);
  }

  void stop() {
    final cb = _cb;
    if (cb != null) Logger.removeOutputListener(cb);
    _cb = null;
  }

  int countContaining(String needle) =>
      lines.where((l) => l.contains(needle)).length;
}

void main() {
  setUp(resetM2400LogCounts);
  tearDown(resetM2400LogCounts);

  group('shouldReportM2400', () {
    test('reports the first occurrence', () {
      expect(shouldReportM2400('a'), isTrue);
    });

    test('suppresses occurrences 2..1000 and reports the 1001st', () {
      expect(shouldReportM2400('a'), isTrue);
      for (var i = 2; i <= m2400LogReportInterval; i++) {
        expect(shouldReportM2400('a'), isFalse, reason: 'occurrence $i');
      }
      expect(shouldReportM2400('a'), isTrue,
          reason: 'occurrence ${m2400LogReportInterval + 1}');
    });

    test('counts every occurrence, reported or not', () {
      for (var i = 0; i < 7; i++) {
        shouldReportM2400('a');
      }
      expect(m2400LogCount('a'), equals(7));
    });

    test('distinct reasons throttle independently', () {
      for (var i = 0; i < 5; i++) {
        shouldReportM2400('a');
      }
      // A second, different problem is still reported immediately -- the
      // throttle must not hide a new fault behind an old one.
      expect(shouldReportM2400('b'), isTrue);
      expect(m2400LogCount('b'), equals(1));
    });

    test('resetM2400LogCounts clears the counters', () {
      shouldReportM2400('a');
      resetM2400LogCounts();
      expect(m2400LogCount('a'), equals(0));
      expect(shouldReportM2400('a'), isTrue);
    });
  });

  group('parseTypedRecord log volume', () {
    final capture = _Capture();
    setUp(capture.start);
    tearDown(capture.stop);

    test('an unknown field id is logged once, not once per record', () {
      // 8 scales streaming weighments: an id this parser has not been taught
      // repeats on every single record, forever.
      final raw = M2400Record(
        type: M2400RecordType.recWgt,
        fields: {'9991': 'x', '9992': 'y'},
      );

      for (var i = 0; i < 2 * m2400LogReportInterval; i++) {
        parseTypedRecord(raw);
      }

      expect(capture.countContaining('Unknown field ID: 9991'), equals(2),
          reason: 'first occurrence plus the ${m2400LogReportInterval}th');
      expect(capture.countContaining('Unknown field ID: 9992'), equals(2));
      // The count still reaches support, so the second line says how bad it is.
      expect(capture.lines.any((l) => l.contains('occurrence 1001')), isTrue);
      expect(m2400LogCount('unknownFieldId:9991'),
          equals(2 * m2400LogReportInterval));
    });

    test('a malformed value is logged once, not once per record', () {
      // Field 1 is Weight, a decimal; feed it something unparseable.
      final raw = M2400Record(
        type: M2400RecordType.recWgt,
        fields: {'1': 'not-a-number'},
      );

      for (var i = 0; i < 500; i++) {
        parseTypedRecord(raw);
      }

      expect(capture.countContaining('Failed to parse'), equals(1));
    });

    test('the first bad record still reports, immediately', () {
      final raw = M2400Record(
        type: M2400RecordType.recWgt,
        fields: {'9991': 'x'},
      );
      parseTypedRecord(raw);
      expect(capture.countContaining('Unknown field ID: 9991'), equals(1),
          reason: 'throttling must not swallow the first sighting');
    });
  });

  group('parseM2400Frame log volume', () {
    final capture = _Capture();
    setUp(capture.start);
    tearDown(capture.stop);

    test('an unknown record type warns once, not once per record', () {
      // Warning level: this survives CENTROID_LOG_LEVEL=warning, so the level
      // default alone would never have contained it.
      for (var i = 0; i < 500; i++) {
        parseM2400Frame(Uint8List.fromList(utf8.encode('(77\t1\ta')));
      }
      expect(capture.countContaining('Unknown record type ID: 77'), equals(1));
      expect(m2400LogCount('unknownRecordType:77'), equals(500));
    });

    test('an unpaired trailing field warns once, not once per record', () {
      for (var i = 0; i < 500; i++) {
        parseM2400Frame(Uint8List.fromList(utf8.encode('(14\ta\tb\tc')));
      }
      expect(capture.countContaining('unpaired'), equals(1));
    });
  });
}
