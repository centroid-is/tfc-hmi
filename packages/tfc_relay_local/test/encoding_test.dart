/// Per-server string encoding: Þorskflök í raspi, and the quality code that
/// makes a failed decode visible.
///
/// The failure this file exists to stop is **not** a crash. It is
/// `utf8.decode(bytes, allowMalformed: true)`, which is what every decode path
/// in this stack does today — `extensions.dart:416`, `m2400.dart:135`,
/// `umas_types.dart:870-880` — and which turns a Latin-1 `þ` into U+FFFD and
/// keeps going, under a good quality, with nothing in any log. Silent mojibake
/// on a product name is worse than an exception, because an exception gets
/// somebody's attention.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart' show parseM2400Frame;
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:test/test.dart';

/// The string that has to survive. A real SVN product name, and every letter in
/// it that is not ASCII — Þ, ö, í — lives inside Latin-1.
const String icelandic = 'Þorskflök í raspi';

/// The same string as the bytes a Latin-1 device puts on the wire.
final Uint8List latin1Bytes = Uint8List.fromList(latin1.encode(icelandic));

/// The plant's two aliases in this file: a weigher configured Latin-1, and a
/// TwinCAT PLC left on the default.
const String weigher = 'weigher1v';
const String twincat = 'ST101';

void main() {
  group('the configuration is per server alias', () {
    test('an unconfigured alias is utf8, which is what the stack does today',
        () {
      const config = StringEncodingConfig();

      expect(config.encodingFor(twincat), ServerStringEncoding.utf8);
    });

    test('a configured alias is what it was configured as', () {
      const config = StringEncodingConfig(byAlias: {
        weigher: ServerStringEncoding.latin1,
      });

      expect(config.encodingFor(weigher), ServerStringEncoding.latin1);
      expect(config.encodingFor(twincat), ServerStringEncoding.utf8,
          reason: 'per SERVER. One Latin-1 weigher does not make the TwinCAT '
              'PLC beside it Latin-1, and a global switch is how the wrong '
              'half of a plant gets mojibake instead of the right half getting '
              'fixed');
    });

    test('the alias match is EXACTLY as strict as every other one', () {
      // Measured, not assumed: `StateManConfig.normalizeAlias`
      // (state_man.dart:454-455) maps empty to null and nothing else — it does
      // not fold case and does not trim. This case pins that the encoding table
      // is as strict as the rest of the gateway rather than more lenient. A
      // table that quietly matched `Weigher1V` against `weigher1v` would be a
      // second opinion about what an alias is, and the two opinions would
      // disagree on the day somebody renamed a server.
      const config = StringEncodingConfig(byAlias: {
        'Weigher1V': ServerStringEncoding.latin1,
      });

      expect(config.encodingFor('Weigher1V'), ServerStringEncoding.latin1);
      expect(config.encodingFor('weigher1v'), ServerStringEncoding.utf8,
          reason: 'a near-miss falls back to the default, which is the safe '
              'direction: the operator sees mojibake AND a 260, rather than a '
              'Latin-1 read of a UTF-8 server that looks plausible');
    });

    test('the unnamed server is addressable, because normalizeAlias makes '
        'empty and unnamed the same thing', () {
      const config = StringEncodingConfig(byAlias: {
        '': ServerStringEncoding.latin1,
      });

      expect(config.encodingFor(''), ServerStringEncoding.latin1);
    });
  });

  group('Þorskflök í raspi', () {
    test('survives a Latin-1 device, character for character', () {
      final decoded = decodePlantString(latin1Bytes,
          encoding: ServerStringEncoding.latin1);

      expect(decoded.text, icelandic,
          reason: 'every Icelandic letter lives inside Latin-1, so latin1 is '
              'EXACT here where allowMalformed is lossy — '
              'tfc_mcp_server/lib/src/parser/source_encoding.dart:20-24 is the '
              'one place in this repository that already got this right');
      expect(decoded.quality, Quality.good);
    });

    test('under the utf8 default it mojibakes AND says so', () {
      final decoded =
          decodePlantString(latin1Bytes, encoding: ServerStringEncoding.utf8);

      expect(decoded.text, isNot(icelandic));
      expect(decoded.text, contains('\u{FFFD}'),
          reason: 'this is exactly what ships today — the replacement '
              'characters are not the news');
      expect(decoded.quality, Quality.uncertainEncoding,
          reason: 'THE quality code is the news. 260 has been defined and '
              'unreferenced in production since Phase 0 waiting for this: the '
              'failure becomes visible instead of silent, which is the whole '
              'point. Today it is mojibake under a GOOD quality');
      expect(decoded.quality.code, 260);
    });

    test('a valid UTF-8 string under the default is untouched and good', () {
      // The anti-vacuity arm. Without it, a `decodePlantString` that returned
      // `uncertainEncoding` unconditionally would pass every case above.
      final decoded = decodePlantString(utf8.encode(icelandic),
          encoding: ServerStringEncoding.utf8);

      expect(decoded.text, icelandic);
      expect(decoded.quality, Quality.good);
    });

    test('plain ASCII is good under both encodings', () {
      for (final encoding in ServerStringEncoding.values) {
        expect(decodePlantString(utf8.encode('CN01 running'), encoding: encoding),
            (text: 'CN01 running', quality: Quality.good));
      }
    });

    test('latin1 can never itself fail', () {
      // All 256 byte values map, so the fallback cannot throw. A file that is
      // neither encoding degrades to mojibake rather than being dropped —
      // the same bargain source_encoding.dart strikes.
      // 1..255: byte 0 is the S7 terminator and is stripped before the
      // decoder ever runs, which the padding group below is about.
      final decoded = decodePlantString(
          Uint8List.fromList(List<int>.generate(255, (i) => i + 1)),
          encoding: ServerStringEncoding.latin1);

      expect(decoded.text.runes.length, 255);
      expect(decoded.quality, Quality.good);
    });
  });

  group('S7 NUL padding', () {
    test('is stripped, and the text before it is kept whole', () {
      final padded = Uint8List.fromList(
          [...latin1.encode(icelandic), 0, 0, 0, 0, 0, 0]);

      final decoded =
          decodePlantString(padded, encoding: ServerStringEncoding.latin1);

      expect(decoded.text, icelandic,
          reason: 'an S7 STRING is a fixed-width buffer; the padding is not '
              'part of the product name and would render as boxes');
    });

    test('a buffer that is all padding is the empty string, not a fault', () {
      final decoded = decodePlantString(Uint8List.fromList([0, 0, 0, 0]),
          encoding: ServerStringEncoding.latin1);

      expect(decoded.text, isEmpty);
      expect(decoded.quality, Quality.good,
          reason: 'an empty tag is an empty tag, not a decode failure');
    });

    test('bytes AFTER the first NUL are not smuggled through', () {
      final decoded = decodePlantString(
          Uint8List.fromList([...latin1.encode('ok'), 0, 0x41, 0x42]),
          encoding: ServerStringEncoding.latin1);

      expect(decoded.text, 'ok');
    });
  });

  group('the value, not just the string', () {
    test('carries the quality onto the DynamicValue', () {
      final at = DateTime.utc(2026, 9, 1, 12);

      final value = decodePlantStringValue(latin1Bytes,
          encoding: ServerStringEncoding.utf8, sourceTime: at);

      expect(value.quality, Quality.uncertainEncoding);
      expect(value.sourceTime, at);
      expect(value.value, isNotNull,
          reason: 'unlike a comms fault, a decode fallback still has a '
              'reading — a mangled one, openly labelled. Blanking it would '
              'throw away the only information there is');
    });

    test('a Latin-1 string round-trips through sanitize and jsonEncode', () {
      final value = decodePlantStringValue(latin1Bytes,
          encoding: ServerStringEncoding.latin1,
          sourceTime: DateTime.utc(2026, 9, 1));

      final sanitized = sanitize(value.value);
      expect(sanitized.value, icelandic);

      // A test that stops before the encoder has not proven the operator sees
      // it. Icelandic characters are not the wire hazard NaN is, but the claim
      // is that the string reaches a panel, and the panel is on the other side
      // of jsonEncode.
      final encoded = jsonEncode({'v': sanitized.value});
      expect(jsonDecode(encoded), {'v': icelandic});
    });
  });

  group('the two foreign packages took an additive parameter', () {
    test('jbtm decodes with utf8 + allowMalformed by DEFAULT, unchanged', () {
      final frame = Uint8List.fromList(
          [...latin1.encode('(14\tFLD\t$icelandic')]);

      final record = parseM2400Frame(frame)!;

      expect(record.fields['FLD'], isNot(icelandic),
          reason: 'the default must reproduce today\'s behaviour BYTE FOR '
              'BYTE. jbtm ships to the plant through the app long before it '
              'reaches it through this gateway (T-08-38)');
      expect(record.fields['FLD'], contains('\u{FFFD}'));
    });

    test('jbtm decodes Latin-1 exactly when handed this package\'s decoder',
        () {
      final frame = Uint8List.fromList(
          [...latin1.encode('(14\tFLD\t$icelandic')]);

      final record = parseM2400Frame(frame,
          decodeBytes: latin1DecoderFor(ServerStringEncoding.latin1))!;

      expect(record.fields['FLD'], icelandic);
    });

    test('umas_types decodes with utf8 + allowMalformed by DEFAULT, unchanged',
        () {
      final bytes = Uint8List.fromList([...latin1.encode('ök'), 0, 0]);
      final type = UmasDataTypeRef(id: 1, name: 'STRING', byteSize: bytes.length);

      final parsed = parseVariableValue(bytes, 0, type);

      expect(parsed.value, isNot('ök'));
      expect((parsed.value as String), contains('\u{FFFD}'));
    });

    test('umas_types decodes Latin-1 when handed the decoder, NUL trim kept',
        () {
      final bytes = Uint8List.fromList([...latin1.encode('ök'), 0, 0x41]);
      final type = UmasDataTypeRef(id: 1, name: 'STRING', byteSize: bytes.length);

      final parsed = parseVariableValue(bytes, 0, type,
          decodeString: latin1DecoderFor(ServerStringEncoding.latin1));

      expect(parsed.value, 'ök',
          reason: 'the NUL-position trimming that was already there is '
              'untouched — the byte after the terminator is not smuggled in');
    });
  });
}
