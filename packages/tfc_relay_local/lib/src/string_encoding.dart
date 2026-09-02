/// Per-server string encoding, and the quality code that makes a bad decode
/// visible.
///
/// ## The failure is not a crash
///
/// Every decode path in this stack today is
/// `utf8.decode(bytes, allowMalformed: true)` — the binding at
/// `extensions.dart:416`, jbtm at `m2400.dart:135`, UMAS at
/// `umas_types.dart:870-880`. Against a Latin-1 device that turns `Þ` into
/// U+FFFD and keeps going, under a **good** quality, with nothing in any log.
/// That is silent mojibake, and it is the worse of the two failures: an
/// exception gets somebody's attention, and a product name rendered
/// `<?>orskfl<?>k <?> raspi` on a packing-hall screen gets a shrug.
///
/// Design §6 rule 4 asks for per-server string encoding for exactly this, and
/// [Quality.uncertainEncoding] (260) — *"source bytes were not valid in the
/// configured string encoding; replacement characters were substituted"* — has
/// been defined and unreferenced in production since Phase 0 waiting for it.
///
/// ## Why Latin-1 and not "try harder"
///
/// `packages/tfc_mcp_server/lib/src/parser/source_encoding.dart:20-24` is the
/// one place in this repository that already reasoned this through, and the
/// reasoning is copied rather than re-derived: **every Icelandic letter — þ æ ö
/// ð and the rest — lives inside Latin-1**, so `latin1` is *exact* where
/// `allowMalformed` is lossy. Latin-1 also maps all 256 byte values, so it can
/// never itself throw: a buffer that is neither encoding degrades to mojibake
/// rather than being dropped.
///
/// ## Why the decision lives in this package
///
/// **This is the only layer that knows which server a byte came from.** The
/// binding does not; jbtm does not; both are shared with the app and neither
/// has a server alias in scope at the point of the decode. So the *policy* is
/// here and the two foreign packages get one additive optional parameter each,
/// whose default reproduces exactly what they did yesterday.
///
/// ## The OPC UA half, and why it is a completeness item
///
/// Raw bytes are **not reachable** through `ClientApi`: the binding decodes
/// before Dart sees anything (`extensions.dart:416`,
/// `types/payloads.dart:235,266`). Adding an encoding hook there is a binding
/// change, and it is recorded as a named follow-up rather than attempted here.
/// It is a completeness item and not a plant-visible gap: SVN's OPC UA servers
/// are TwinCAT, which emits UTF-8, and the plant's likely Latin-1 sources are
/// the M2400 weighers and the Saia-over-Modbus box erector — both of which this
/// module covers through the two parameters below.
library;

import 'dart:convert';

import 'package:tfc_dart/core/state_man.dart' show StateManConfig;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The two encodings a configured server may declare.
///
/// Deliberately two and not "any `Encoding`". A plant configuration file that
/// can name `shift_jis` is a configuration file that can name a typo, and the
/// answer to a third real encoding is a third enum value plus the case that
/// proves it — not an open door.
enum ServerStringEncoding {
  /// The default, and what every path in this stack does today.
  utf8,

  /// The plant's Latin-1 devices: the weighers, and the Saia-over-Modbus box
  /// erector (08-RESEARCH §H.3).
  latin1,
}

/// Which encoding each configured server speaks.
///
/// **Per alias.** One Latin-1 weigher does not make the TwinCAT PLC beside it
/// Latin-1, and a global switch is how the wrong half of a plant gets mojibake
/// instead of the right half getting fixed.
final class StringEncodingConfig {
  const StringEncodingConfig({
    Map<String, ServerStringEncoding> byAlias =
        const <String, ServerStringEncoding>{},
    this.fallback = ServerStringEncoding.utf8,
  }) : _byAlias = byAlias;

  final Map<String, ServerStringEncoding> _byAlias;

  /// What an alias with no entry gets. UTF-8, because that is what the stack
  /// does today and a silent change of default is the thing this whole module
  /// exists to prevent.
  final ServerStringEncoding fallback;

  /// The encoding configured for [alias], or [fallback].
  ///
  /// Normalised through `StateManConfig.normalizeAlias`, which is what every
  /// other alias comparison in this gateway uses. A table that matched
  /// case-sensitively would silently miss the server it was configured for and
  /// the symptom would be… mojibake, which is the symptom it was added to fix.
  ServerStringEncoding encodingFor(String alias) {
    final wanted = StateManConfig.normalizeAlias(alias);
    for (final entry in _byAlias.entries) {
      if (StateManConfig.normalizeAlias(entry.key) == wanted) return entry.value;
    }
    return fallback;
  }
}

/// One decoded string and the quality it earned.
typedef DecodedPlantString = ({String text, Quality quality});

/// A byte decoder, as the two foreign packages take it.
typedef PlantStringDecoder = String Function(List<int> bytes);

/// Decodes [bytes] under [encoding], reporting whether it had to guess.
///
/// Three outcomes, and the middle one is the point:
///
///  * **[Quality.good]** — the bytes were valid in the configured encoding
///    (and `latin1` always is, so a Latin-1 server never reaches the third
///    case).
///  * **[Quality.uncertainEncoding]** — the bytes were *not* valid UTF-8.
///    Replacement characters were substituted and the value says so. This is
///    the state that ships today wearing a good quality.
///  * There is no bad/error outcome. A string that will not decode is still a
///    reading, and blanking it would throw away the only information there is.
///
/// S7-style NUL padding is stripped first: a fixed-width `STRING` buffer is
/// padded to its declared size and the padding is not part of the product name.
/// Everything at and after the first NUL goes, which is also what
/// `umas_types.dart:876-878` already does and must keep doing.
DecodedPlantString decodePlantString(
  List<int> bytes, {
  required ServerStringEncoding encoding,
}) {
  final trimmed = _beforeFirstNul(bytes);
  switch (encoding) {
    case ServerStringEncoding.latin1:
      // Cannot throw: all 256 byte values map. Exact for every Icelandic
      // letter, which is the entire reason this branch exists.
      return (text: latin1.decode(trimmed), quality: Quality.good);
    case ServerStringEncoding.utf8:
      try {
        return (text: utf8.decode(trimmed), quality: Quality.good);
      } on FormatException {
        return (
          text: utf8.decode(trimmed, allowMalformed: true),
          quality: Quality.uncertainEncoding,
        );
      }
  }
}

/// [decodePlantString], as a value a link can publish.
///
/// The quality rides on the [DynamicValue] rather than being logged, because a
/// log is not something an operator reads and a quality badge is.
DynamicValue decodePlantStringValue(
  List<int> bytes, {
  required ServerStringEncoding encoding,
  DateTime? sourceTime,
}) {
  final decoded = decodePlantString(bytes, encoding: encoding);
  return DynamicValue(
    value: decoded.text,
    quality: decoded.quality,
    sourceTime: sourceTime ?? DateTime.now().toUtc(),
  );
}

/// The decoder to hand to `jbtm` or to `umas_types`, for a server on
/// [encoding].
///
/// The foreign packages take a plain `String Function(List<int>)` and know
/// nothing about aliases or qualities — that is the seam. What is lost across
/// it is the quality: a decoder returning a `String` cannot report that it fell
/// back, so a caller that needs the 260 uses [decodePlantString] directly and
/// this is for the paths where the framing owns the decode.
PlantStringDecoder latin1DecoderFor(ServerStringEncoding encoding) =>
    (bytes) => decodePlantString(bytes, encoding: encoding).text;

/// Everything before the first NUL, or all of it if there is none.
List<int> _beforeFirstNul(List<int> bytes) {
  final nul = bytes.indexOf(0);
  return nul < 0 ? bytes : bytes.sublist(0, nul);
}
