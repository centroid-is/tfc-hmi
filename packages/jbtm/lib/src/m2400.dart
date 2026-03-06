import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logger/logger.dart';

final _logger = Logger();

/// Known M2400 record types with their numeric protocol IDs.
enum M2400RecordType {
  recWgt(3),
  recIntro(5),
  recStat(14),
  recLua(87),
  recBatch(103),
  unknown(-1);

  final int id;
  const M2400RecordType(this.id);

  /// Pre-built lookup table for O(1) record type resolution.
  static final Map<int, M2400RecordType> _byId = {
    for (final type in values)
      if (type != unknown) type.id: type,
  };

  /// Look up record type by numeric ID. Returns [unknown] for unrecognized IDs.
  static M2400RecordType fromId(int id) => _byId[id] ?? unknown;
}

/// An immutable M2400 record parsed from a framed byte stream.
class M2400Record {
  final M2400RecordType type;
  final Map<String, String> fields;

  const M2400Record({required this.type, required this.fields});

  @override
  String toString() => 'M2400Record(type: $type, fields: $fields)';
}

/// Extracts complete frames delimited by STX (0x02) and ETX (0x03) from a
/// byte stream, handling TCP chunking, inter-frame garbage, and oversized frames.
///
/// Usage:
/// ```dart
/// msocket.dataStream
///     .transform(M2400FrameParser())
///     .map(parseM2400Frame)
///     .where((r) => r != null)
///     .listen((record) => print(record));
/// ```
class M2400FrameParser implements StreamTransformer<Uint8List, Uint8List> {
  static const int _stx = 0x02;
  static const int _etx = 0x03;

  /// Maximum frame content size in bytes. Frames exceeding this limit are
  /// discarded and the buffer is reset. Default: 64KB.
  final int maxFrameSize;

  M2400FrameParser({this.maxFrameSize = 65536});

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) {
    final buffer = BytesBuilder(copy: false);
    var inFrame = false;

    return stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (Uint8List data, EventSink<Uint8List> sink) {
          for (var i = 0; i < data.length; i++) {
            final byte = data[i];
            if (!inFrame) {
              if (byte == _stx) {
                inFrame = true;
                buffer.clear();
              }
              // Inter-frame bytes silently discarded
            } else {
              if (byte == _etx) {
                sink.add(buffer.takeBytes());
                inFrame = false;
              } else {
                buffer.addByte(byte);
                if (buffer.length > maxFrameSize) {
                  _logger.w(
                      'Frame exceeded max size ($maxFrameSize bytes), discarding');
                  buffer.clear();
                  inFrame = false;
                }
              }
            }
          }
        },
        handleError:
            (Object error, StackTrace stackTrace, EventSink<Uint8List> sink) {
          buffer.clear();
          inFrame = false;
          sink.addError(error, stackTrace);
        },
        handleDone: (EventSink<Uint8List> sink) {
          if (inFrame && buffer.length > 0) {
            _logger.w(
                'Stream closed with ${buffer.length} bytes of partial frame');
          }
          buffer.clear();
          inFrame = false;
          sink.close();
        },
      ),
    );
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<Uint8List, Uint8List, RS, RT>(this);
}

/// Parse frame content (bytes between STX and ETX) into a structured record.
///
/// Real M2400 frame content format:
/// ```
/// (REC_TYPE\tFLD_ID\tVALUE\tFLD_ID\tVALUE...\r\n
/// ```
///
/// The first token is `(REC_TYPE` — a `(` prefix followed immediately by a
/// numeric record type ID. Field ID / value pairs follow as tab-separated
/// elements starting at index 1.
///
/// Returns null if [frameBytes] is empty or contains only whitespace.
M2400Record? parseM2400Frame(Uint8List frameBytes) {
  if (frameBytes.isEmpty) return null;

  final content = utf8.decode(frameBytes, allowMalformed: true).trimRight();
  if (content.isEmpty) return null;

  final parts = content.split('\t');
  final fields = <String, String>{};

  // First token is (REC_TYPE — strip the ( prefix and parse the record type
  String firstToken = parts[0];
  if (firstToken.startsWith('(')) {
    firstToken = firstToken.substring(1);
  }

  // Determine record type from the first token
  M2400RecordType type;
  final recTypeId = int.tryParse(firstToken);
  if (recTypeId != null) {
    type = M2400RecordType.fromId(recTypeId);
    if (type == M2400RecordType.unknown) {
      _logger.w('Unknown record type ID: $recTypeId');
    }
  } else {
    type = M2400RecordType.unknown;
    if (firstToken.isNotEmpty) {
      _logger.w('Non-numeric record type value: $firstToken');
    }
  }

  // Key-value pairs start at index 1 (after the record type token)
  for (var i = 1; i + 1 < parts.length; i += 2) {
    fields[parts[i]] = parts[i + 1];
  }

  // Log warning for even total count (odd number of field tokens = unpaired trailing element)
  if (parts.length > 1 && parts.length.isEven) {
    _logger.w(
        'Odd number of field elements; trailing "${parts.last}" unpaired');
  }

  return M2400Record(type: type, fields: fields);
}
