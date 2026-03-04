import 'dart:async';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // M24-01: Frame Parser (STX/ETX delimiting)
  // ---------------------------------------------------------------------------
  group('M2400FrameParser', () {
    late StreamController<Uint8List> controller;
    late List<Uint8List> frames;
    late StreamSubscription<Uint8List> subscription;

    setUp(() {
      controller = StreamController<Uint8List>();
      frames = [];
    });

    tearDown(() async {
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
    });

    test('single complete frame emits content bytes excluding STX/ETX',
        () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      // STX + "hello" + ETX
      controller.add(Uint8List.fromList(
          [0x02, 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x03]));
      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames[0], equals([0x68, 0x65, 0x6C, 0x6C, 0x6F])); // "hello"
    });

    test('frame split across two TCP chunks reassembles correctly', () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      // STX + "he" in chunk 1
      controller.add(Uint8List.fromList([0x02, 0x68, 0x65]));
      // "llo" + ETX in chunk 2
      controller.add(Uint8List.fromList([0x6C, 0x6C, 0x6F, 0x03]));

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames[0], equals([0x68, 0x65, 0x6C, 0x6C, 0x6F]));
    });

    test('multiple complete frames in one TCP chunk emit separately', () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      // Two complete frames in one chunk
      controller.add(Uint8List.fromList([
        0x02, 0x41, 0x03, // STX "A" ETX
        0x02, 0x42, 0x03, // STX "B" ETX
      ]));

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(2));
      expect(frames[0], equals([0x41])); // "A"
      expect(frames[1], equals([0x42])); // "B"
    });

    test('partial frame at end of chunk buffers until ETX arrives', () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      // Chunk 1: complete frame + start of second frame
      controller.add(Uint8List.fromList([
        0x02, 0x41, 0x03, // STX "A" ETX
        0x02, 0x42, // STX "B" (partial)
      ]));
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames[0], equals([0x41]));

      // Chunk 2: finish second frame
      controller.add(Uint8List.fromList([0x43, 0x03])); // "C" ETX

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(2));
      expect(frames[1], equals([0x42, 0x43])); // "BC"
    });

    test('inter-frame garbage bytes before STX are silently discarded',
        () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      // Garbage bytes, then a valid frame
      controller
          .add(Uint8List.fromList([0xFF, 0xFE, 0x02, 0x41, 0x03]));

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames[0], equals([0x41]));
    });

    test('oversized frame exceeding maxFrameSize is discarded', () async {
      // Use a small max for testing
      subscription = controller.stream
          .transform(M2400FrameParser(maxFrameSize: 5))
          .listen(frames.add);

      // Frame with 6 bytes of content (exceeds maxFrameSize of 5)
      controller.add(Uint8List.fromList(
          [0x02, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x03]));

      // Then a valid frame to confirm recovery
      controller.add(Uint8List.fromList([0x02, 0x42, 0x03]));

      await controller.close();
      await Future.delayed(Duration.zero);

      // Only the second (valid) frame should be emitted
      expect(frames, hasLength(1));
      expect(frames[0], equals([0x42]));
    });

    test('empty frame (STX immediately followed by ETX) emits empty Uint8List',
        () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      controller.add(Uint8List.fromList([0x02, 0x03])); // STX ETX

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames[0], isEmpty);
    });

    test('stream close with partial frame discards it', () async {
      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      // Start a frame but never close it
      controller.add(Uint8List.fromList([0x02, 0x41, 0x42]));
      await controller.close();
      await Future.delayed(Duration.zero);

      expect(frames, isEmpty);
    });

    test('error on stream resets buffer state and forwards error', () async {
      final errors = <Object>[];

      subscription = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add, onError: errors.add);

      // Start a partial frame
      controller.add(Uint8List.fromList([0x02, 0x41]));
      // Send an error
      controller.addError(Exception('connection lost'));
      await Future.delayed(Duration.zero);

      // After error, send a new valid frame (buffer should be reset)
      controller.add(Uint8List.fromList([0x02, 0x42, 0x03]));

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<Exception>());
      expect(frames, hasLength(1));
      expect(frames[0], equals([0x42])); // New frame after error
    });
  });

  // ---------------------------------------------------------------------------
  // M24-02: Record Parser (tab-separated key-value extraction)
  // ---------------------------------------------------------------------------
  group('parseM2400Frame', () {
    test('extracts tab-separated key-value pairs into Map', () {
      // "1\tvalue1\t2\tvalue2"
      final bytes = Uint8List.fromList(
          '1\tvalue1\t2\tvalue2'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields['1'], equals('value1'));
      expect(record.fields['2'], equals('value2'));
    });

    test('strips trailing CRLF before parsing', () {
      final bytes = Uint8List.fromList(
          '1\tvalue1\t2\tvalue2\r\n'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields['2'], equals('value2'));
      // Verify no trailing whitespace in last value
      expect(record.fields['2']!.contains('\r'), isFalse);
      expect(record.fields['2']!.contains('\n'), isFalse);
    });

    test('empty frame bytes returns null', () {
      final record = parseM2400Frame(Uint8List(0));
      expect(record, isNull);
    });

    test('whitespace-only frame returns null', () {
      final record = parseM2400Frame(
          Uint8List.fromList('   \r\n'.codeUnits));
      expect(record, isNull);
    });

    test('single element with no tabs returns record with empty fields and unknown type',
        () {
      final bytes = Uint8List.fromList('justonevalue'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields, isEmpty);
      expect(record.type, equals(M2400RecordType.unknown));
    });

    test('decodes with allowMalformed for non-UTF8 bytes', () {
      // Include a 0xFF byte which is invalid UTF-8
      final bytes = Uint8List.fromList([
        0x31, 0x09, // "1\t"
        0xFF, 0x09, // invalid UTF-8 + tab
        0x32, 0x09, // "2\t"
        0x76, 0x61, 0x6C, // "val"
      ]);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields.containsKey('2'), isTrue);
      expect(record.fields['2'], equals('val'));
    });
  });

  // ---------------------------------------------------------------------------
  // M24-03: Record Type Discrimination
  // ---------------------------------------------------------------------------
  group('record type discrimination', () {
    test('REC_WGT=3 maps to M2400RecordType.recWgt', () {
      expect(M2400RecordType.fromId(3), equals(M2400RecordType.recWgt));
    });

    test('REC_INTRO=5 maps to M2400RecordType.recIntro', () {
      expect(M2400RecordType.fromId(5), equals(M2400RecordType.recIntro));
    });

    test('REC_STAT=14 maps to M2400RecordType.recStat', () {
      expect(M2400RecordType.fromId(14), equals(M2400RecordType.recStat));
    });

    test('REC_LUA=87 maps to M2400RecordType.recLua', () {
      expect(M2400RecordType.fromId(87), equals(M2400RecordType.recLua));
    });

    test('unknown numeric ID maps to M2400RecordType.unknown', () {
      expect(M2400RecordType.fromId(999), equals(M2400RecordType.unknown));
    });

    test('record type extracted from key-value pairs in frame', () {
      // Build a frame with the record type field
      final bytes = Uint8List.fromList(
          '$recordTypeFieldKey\t3\t100\tsome_data'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.type, equals(M2400RecordType.recWgt));
    });

    test('missing record type field maps to unknown', () {
      // Frame with no record type field key
      final bytes = Uint8List.fromList(
          '100\tsome_data\t200\tmore_data'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.type, equals(M2400RecordType.unknown));
    });
  });

  // ---------------------------------------------------------------------------
  // M24-10: Unknown fields and graceful handling
  // ---------------------------------------------------------------------------
  group('unknown fields and edge cases', () {
    test('all fields from frame are included in record regardless of known status',
        () {
      final bytes = Uint8List.fromList(
          '$recordTypeFieldKey\t14\t999\tunknown_val\t888\tanother_val'
              .codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields['999'], equals('unknown_val'));
      expect(record.fields['888'], equals('another_val'));
      expect(record.type, equals(M2400RecordType.recStat));
    });

    test('unknown field keys do not cause exceptions', () {
      final bytes = Uint8List.fromList(
          'ZZZZZ\tval1\tXXXXX\tval2'.codeUnits);

      // Should not throw
      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields['ZZZZZ'], equals('val1'));
      expect(record.fields['XXXXX'], equals('val2'));
    });

    test('odd number of tab-separated elements does not crash', () {
      // 5 elements: "a", "b", "c", "d", "e" -- "e" is unpaired
      final bytes = Uint8List.fromList(
          'a\tb\tc\td\te'.codeUnits);

      // Should not throw
      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.fields['a'], equals('b'));
      expect(record.fields['c'], equals('d'));
      // "e" is unpaired -- should not be in fields as a key
      expect(record.fields.containsKey('e'), isFalse);
    });

    test('non-numeric record type value maps to unknown', () {
      final bytes = Uint8List.fromList(
          '$recordTypeFieldKey\tnot_a_number\t100\tdata'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.type, equals(M2400RecordType.unknown));
    });

    test('record type ID not matching known types maps to unknown', () {
      final bytes = Uint8List.fromList(
          '$recordTypeFieldKey\t999\t100\tdata'.codeUnits);

      final record = parseM2400Frame(bytes);

      expect(record, isNotNull);
      expect(record!.type, equals(M2400RecordType.unknown));
    });
  });
}
