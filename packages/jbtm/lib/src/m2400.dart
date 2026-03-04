import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logger/logger.dart';

final _logger = Logger();

/// Record type field key in the M2400 protocol.
///
/// This is the key in the tab-separated key-value stream that identifies
/// the record type. The value paired with this key is a numeric record type ID.
///
/// NOTE: This key must match the actual M2400 protocol. If records show as
/// "unknown" type, check this constant against protocol documentation or
/// device captures.
const String recordTypeFieldKey = 'REC';

/// Known M2400 record types with their numeric protocol IDs.
enum M2400RecordType {
  recWgt(3),
  recIntro(5),
  recStat(14),
  recLua(87),
  unknown(-1);

  final int id;
  const M2400RecordType(this.id);

  /// Look up record type by numeric ID. Returns [unknown] for unrecognized IDs.
  static M2400RecordType fromId(int id) {
    for (final type in values) {
      if (type.id == id && type != unknown) return type;
    }
    return unknown;
  }
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
/// Takes the raw bytes from inside a frame (excluding STX/ETX delimiters),
/// decodes as UTF-8, splits by tab into consecutive key-value pairs, and
/// extracts the record type from the [recordTypeFieldKey] field.
///
/// Returns null if [frameBytes] is empty or contains only whitespace.
M2400Record? parseM2400Frame(Uint8List frameBytes) {
  if (frameBytes.isEmpty) return null;

  final content = utf8.decode(frameBytes, allowMalformed: true).trimRight();
  if (content.isEmpty) return null;

  final parts = content.split('\t');
  final fields = <String, String>{};

  // Pair consecutive elements as key-value
  for (var i = 0; i + 1 < parts.length; i += 2) {
    fields[parts[i]] = parts[i + 1];
  }

  // Log warning for odd number of elements (unpaired trailing element)
  if (parts.length > 1 && parts.length.isOdd) {
    _logger.w(
        'Odd number of tab-separated elements; trailing "${parts.last}" unpaired');
  }

  // Determine record type
  final recordTypeValue = fields[recordTypeFieldKey];
  M2400RecordType type;
  if (recordTypeValue != null) {
    final id = int.tryParse(recordTypeValue);
    if (id != null) {
      type = M2400RecordType.fromId(id);
      if (type == M2400RecordType.unknown) {
        _logger.w('Unknown record type ID: $id');
      }
    } else {
      type = M2400RecordType.unknown;
      _logger.w('Non-numeric record type value: $recordTypeValue');
    }
  } else {
    type = M2400RecordType.unknown;
    if (parts.length > 1) {
      _logger.w('No record type field found in frame');
    }
  }

  return M2400Record(type: type, fields: fields);
}
