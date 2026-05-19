/// EcoStruxure `.ZEF` / `.XEF` offline parser — bit-alias map source.
///
/// SOURCE-OF-TRUTH CHAIN
/// =====================
///
///   `.ZEF`  → ZIP archive (magic `50 4B 03 04`)
///       └── inner `*.XEF` (XML)
///             └── `<dataBlockTypeDef>` → DDT type definitions
///                   └── `<structElement>` + `<extractedBit>` →
///                          bit-alias → (parent WORD member, bit offset)
///             └── `<variables>`
///                   └── `<elementaryVariable>` / `<derivedVariable>` →
///                          name → (typeName, topologicalAddress)
///
/// At runtime, the HMI's UMAS browse already knows the live `blockNo` /
/// `offset` of each top-level variable. This parser supplies the missing
/// half — the static mapping from a bit-alias name (e.g. `motor1.run`) to
/// its parent WORD member + bit offset. The two maps compose into the
/// full `bit-alias → (blockNo, byteOffset, bitOffset)` triple the
/// decoder needs.
///
/// SCHEMA NOTES
/// ============
///
/// The .XEF tag and attribute names recognised here are based on the
/// Schneider Unity Pro / Control Expert "openness" XML, as documented
/// by third-party tooling rather than an official public XSD (the XSD
/// only ships inside the paid Unity Developer's Edition SDK).
/// Sources cross-referenced:
///
///   * `corax4/ZEF_splitter` (Pascal) — naming of the inner variables file.
///   * Paul Rickard's "Unity Pro ZEF files" write-up — ZIP layout.
///   * EcoStruxure V15 release note: "When XEF file created with Unity Pro
///     V7.0 contains extracted bits in DDT, XEF file cannot be open by
///     Unity Pro version < V7.0" — confirms extracted-bit XML existed
///     since V7.0 and the schema is forward-stable.
///   * EPLAN `PlcDCXmlExchangerSchneider` — confirms `.xef/.zef/.xsy` are
///     the standard exchange surfaces.
///
/// Because real-world XEF samples are not yet validated against, the
/// parser is built tolerant-first:
///
///   * Multiple plausible tag spellings are accepted
///     (`<extractedBit>`, `<aliased_bit>`, `<extracted_bit>`, `<bit_field>`,
///     attribute-form `extractedBit="N"` on a structElement).
///   * Missing optional fields → `null`, never throws.
///   * Unknown XML → empty `ZefProject`, never throws.
///   * Only outright malformed XML raises `FormatException`.
///
/// When a real `.ZEF` from the production M580 lands, the verification
/// step is documented at `/tmp/bitalias-swarm-v2/zef-scaffold.md`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

// ---------------------------------------------------------------------------
// Public model
// ---------------------------------------------------------------------------

/// Parsed Schneider EcoStruxure project export.
class ZefProject {
  /// Variables keyed by their declared name. Order is preserved as
  /// best-effort (the underlying map is a `LinkedHashMap`).
  final Map<String, VariableEntry> variables;

  /// DDT (Derived Data Type) definitions discovered in the export.
  final List<DdtTypeEntry> ddts;

  const ZefProject({
    required this.variables,
    required this.ddts,
  });

  /// Convenience: flatten every DDT instance's bit-alias members into a
  /// resolved tuple referencing the located address of the parent.
  ///
  /// Only bit aliases whose parent member is a single-WORD inside the same
  /// DDT, and whose parent DDT instance has a `%MW`-style located address,
  /// are returned. Nested-DDT bit aliases and unlocated bit aliases are
  /// skipped (best-effort scaffold; v1.1 only needs the headline case).
  List<ResolvedBitAlias> resolveBitAliases() {
    final ddtByName = {for (final d in ddts) d.name: d};
    final out = <ResolvedBitAlias>[];
    for (final v in variables.values) {
      final typeName = v.typeName;
      if (typeName == null || typeName.isEmpty) continue;
      final ddt = ddtByName[typeName];
      if (ddt == null) continue;
      for (final m in ddt.members) {
        if (m.bitOffset == null || m.parentMemberName == null) continue;
        out.add(ResolvedBitAlias(
          aliasFullName: '${v.name}.${m.name}',
          parentVariableName: v.name,
          parentMemberName: m.parentMemberName!,
          bitOffset: m.bitOffset!,
          parentRawAddress: v.rawAddress,
          parentByteOffset: v.byteOffset,
        ));
      }
    }
    return out;
  }

  /// JSON-friendly summary; used by the CLI `--out file.json` mode.
  Map<String, Object?> toJson() => {
        'variables': {
          for (final e in variables.entries) e.key: e.value.toJson(),
        },
        'ddts': ddts.map((d) => d.toJson()).toList(),
      };
}

/// A variable declared in the project (top-level — not a struct member).
class VariableEntry {
  /// Declared variable name (e.g. `motor1`).
  final String name;

  /// Type name as declared in the XEF (e.g. `INT`, `WORD`, `MOTOR_STATUS_DDT`).
  /// Empty/missing → `null`.
  final String? typeName;

  /// Schneider topological address string (e.g. `%MW100`, `%M5`). Null when
  /// the variable is unlocated.
  final String? rawAddress;

  /// UMAS block number — *not* derivable from the XEF alone. Always null
  /// from this parser; filled in by the runtime layer that correlates
  /// names against the live `umas_client.browse()` tree.
  final int? blockNo;

  /// Byte offset within the `%MW` area, when [rawAddress] could be parsed.
  /// For bit-area addresses (`%M`) this is the byte position; the bit
  /// is in [bitOffset].
  final int? byteOffset;

  /// Bit offset 0..7 for direct bit-area addresses (`%M5` → bitOffset=5).
  /// For derived (DDT) variables, bit aliases live on the DDT members, not
  /// here — this stays null in that case.
  final int? bitOffset;

  /// For *bit-alias members* (not used on top-level variables; this field
  /// is mirrored on [DdtMember] for the in-DDT case). Kept on
  /// [VariableEntry] for forward compatibility if Schneider ever emits
  /// flat `<extractedBit>` variables alongside the DDT-internal form.
  final String? parentWordName;

  const VariableEntry({
    required this.name,
    this.typeName,
    this.rawAddress,
    this.blockNo,
    this.byteOffset,
    this.bitOffset,
    this.parentWordName,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (typeName != null) 'typeName': typeName,
        if (rawAddress != null) 'rawAddress': rawAddress,
        if (blockNo != null) 'blockNo': blockNo,
        if (byteOffset != null) 'byteOffset': byteOffset,
        if (bitOffset != null) 'bitOffset': bitOffset,
        if (parentWordName != null) 'parentWordName': parentWordName,
      };
}

/// One DDT (Derived Data Type) definition.
class DdtTypeEntry {
  final String name;
  final String? comment;
  final List<DdtMember> members;

  const DdtTypeEntry({
    required this.name,
    this.comment,
    required this.members,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (comment != null) 'comment': comment,
        'members': members.map((m) => m.toJson()).toList(),
      };
}

/// One member inside a DDT. Either a real structural field (WORD, INT, …)
/// or a bit alias (BOOL with [parentMemberName] + [bitOffset] set).
class DdtMember {
  final String name;
  final String? typeName;

  /// 0..7. Null when this member is not a bit alias.
  final int? bitOffset;

  /// Name of the sibling member whose word this bit aliases.
  /// Null when this member is not a bit alias.
  final String? parentMemberName;

  const DdtMember({
    required this.name,
    this.typeName,
    this.bitOffset,
    this.parentMemberName,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (typeName != null) 'typeName': typeName,
        if (bitOffset != null) 'bitOffset': bitOffset,
        if (parentMemberName != null) 'parentMemberName': parentMemberName,
      };
}

/// A bit alias fully resolved against its containing DDT instance's
/// located address. Produced by [ZefProject.resolveBitAliases].
class ResolvedBitAlias {
  /// Dotted full name, e.g. `motor1.run`.
  final String aliasFullName;

  /// Name of the top-level DDT instance (e.g. `motor1`).
  final String parentVariableName;

  /// Name of the parent WORD member inside the DDT (e.g. `raw`).
  /// At runtime the UMAS read is performed against
  /// `<parentVariableName>.<parentMemberName>` (a normal WORD) and the
  /// decoder masks [bitOffset].
  final String parentMemberName;

  /// 0..7.
  final int bitOffset;

  /// Located address of the DDT instance, when present.
  final String? parentRawAddress;

  /// Byte offset within the `%MW` area for [parentRawAddress], if parsable.
  final int? parentByteOffset;

  const ResolvedBitAlias({
    required this.aliasFullName,
    required this.parentVariableName,
    required this.parentMemberName,
    required this.bitOffset,
    this.parentRawAddress,
    this.parentByteOffset,
  });

  Map<String, Object?> toJson() => {
        'aliasFullName': aliasFullName,
        'parentVariableName': parentVariableName,
        'parentMemberName': parentMemberName,
        'bitOffset': bitOffset,
        if (parentRawAddress != null) 'parentRawAddress': parentRawAddress,
        if (parentByteOffset != null) 'parentByteOffset': parentByteOffset,
      };
}

/// Parsed topological address breakdown (`%MW100` → area=MW, byteOffset=200).
class TopologicalAddress {
  /// `M`, `MW`, `MD`, `S`, `SW`, `I`, `Q`, etc.
  final String area;

  /// For word/double areas: byte offset from area base.
  /// For bit areas (`%M`): byte containing the bit (= index ~/ 8).
  final int byteOffset;

  /// For bit areas only: bit 0..7. Null for word/double.
  final int? bitOffset;

  const TopologicalAddress({
    required this.area,
    required this.byteOffset,
    this.bitOffset,
  });
}

/// Best-effort parse of a `%MW100` / `%M5` / `%MD200` style address.
///
/// Returns null for anything not recognised (no throws — parser stays
/// tolerant). Currently handles:
///
///   * `%MW<n>`  word area, byte offset = n * 2
///   * `%MD<n>`  double-word area, byte offset = n * 2 (per Schneider convention,
///               %MD shares the %MW namespace; n is still a word index)
///   * `%M<n>`   bit area, byte offset = n ~/ 8, bit offset = n % 8
///   * `%SW<n>`  system word, treated like %MW
TopologicalAddress? parseTopologicalAddress(String? addr) {
  if (addr == null || addr.isEmpty) return null;
  final m = _addrRegex.firstMatch(addr);
  if (m == null) return null;
  final area = m.group(1)!;
  final n = int.tryParse(m.group(2) ?? '');
  if (n == null) return null;
  switch (area) {
    case 'MW':
    case 'SW':
    case 'MD':
    case 'KW':
      return TopologicalAddress(area: area, byteOffset: n * 2);
    case 'M':
    case 'S':
      return TopologicalAddress(
        area: area,
        byteOffset: n ~/ 8,
        bitOffset: n % 8,
      );
    default:
      return null;
  }
}

final RegExp _addrRegex = RegExp(r'^%([A-Z]+?)(\d+)$');

// ---------------------------------------------------------------------------
// Top-level parse entry points
// ---------------------------------------------------------------------------

/// Parse a `.ZEF` file (ZIP wrapping one or more XML documents). Picks the
/// first archive entry whose name ends in `.xef` (case-insensitive). If
/// none is found, throws [FormatException].
ZefProject parseZef(File file) {
  final bytes = file.readAsBytesSync();
  return parseZefBytes(bytes);
}

/// Variant for callers that already hold the bytes (e.g. tests).
ZefProject parseZefBytes(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw FormatException('not a valid ZIP / .ZEF: $e');
  }
  // Find the first .xef inside. Real EcoStruxure exports place it at the
  // archive root or under a project name folder; we don't care which.
  ArchiveFile? xef;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    if (f.name.toLowerCase().endsWith('.xef')) {
      xef = f;
      break;
    }
  }
  if (xef == null) {
    // Fallback: pick the first XML file. Some ZEF variants name the
    // variables file `var.xml` rather than `.xef`.
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = f.name.toLowerCase();
      if (n.endsWith('.xml')) {
        xef = f;
        break;
      }
    }
  }
  if (xef == null) {
    throw const FormatException(
      'no .xef or .xml entry found inside the .ZEF archive',
    );
  }
  // `archive` exposes raw bytes via `.content` (List<int>) and a typed
  // accessor; either way we want the bytes as a UTF-8 / ASCII string.
  final List<int> raw = xef.content as List<int>;
  return parseXef(String.fromCharCodes(raw));
}

/// Parse a raw `.XEF` XML document into a [ZefProject].
///
/// Throws [FormatException] only when the XML itself is unparseable.
/// Unknown schemas yield an empty [ZefProject] — never an exception.
ZefProject parseXef(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (e) {
    throw FormatException('not valid XML: $e');
  }

  final variables = <String, VariableEntry>{};
  final ddts = <DdtTypeEntry>[];

  // Tolerant walk — find any element matching known names, regardless of
  // namespace prefix or nesting depth. (XEF files in the wild have varied
  // wrapper element names by version — we deliberately don't require a
  // specific root.)
  for (final el in doc.descendants.whereType<XmlElement>()) {
    final localName = el.name.local;
    if (_isVariableElement(localName)) {
      final entry = _parseVariableElement(el);
      if (entry != null) {
        variables[entry.name] = entry;
      }
    } else if (_isDdtElement(localName)) {
      final entry = _parseDdtElement(el);
      if (entry != null) {
        ddts.add(entry);
      }
    }
  }

  return ZefProject(variables: variables, ddts: ddts);
}

// ---------------------------------------------------------------------------
// Element-shape probes
// ---------------------------------------------------------------------------

bool _isVariableElement(String localName) {
  switch (localName) {
    case 'elementaryVariable':
    case 'derivedVariable':
    case 'ioVariable':
    case 'instanceVariable':
    case 'Variable':
    case 'variable':
      return true;
    default:
      return false;
  }
}

bool _isDdtElement(String localName) {
  switch (localName) {
    case 'DDT':
    case 'ddt':
    case 'derivedDataType':
    case 'DerivedDataType':
    case 'dataType':
      return true;
    default:
      return false;
  }
}

bool _isBitAliasElement(String localName) {
  switch (localName) {
    case 'extractedBit':
    case 'extracted_bit':
    case 'aliasedBit':
    case 'aliased_bit':
    case 'bitField':
    case 'bit_field':
      return true;
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Variable + DDT element parsers
// ---------------------------------------------------------------------------

VariableEntry? _parseVariableElement(XmlElement el) {
  final name = _attr(el, 'name');
  if (name == null || name.isEmpty) return null;
  final typeNameRaw = _attr(el, 'typeName') ?? _attr(el, 'type');
  final typeName = (typeNameRaw == null || typeNameRaw.isEmpty)
      ? null
      : typeNameRaw;

  // Located address can appear as an attribute (`topologicalAddress="%MW100"`)
  // or as a child element (`<topologicalAddress>%MW100</topologicalAddress>`).
  String? rawAddress = _attr(el, 'topologicalAddress') ?? _attr(el, 'address');
  if (rawAddress == null) {
    for (final c in el.childElements) {
      final lname = c.name.local;
      if (lname == 'topologicalAddress' || lname == 'address') {
        final txt = c.innerText.trim();
        if (txt.isNotEmpty) {
          rawAddress = txt;
          break;
        }
      }
    }
  }
  if (rawAddress != null && rawAddress.isEmpty) rawAddress = null;

  final parsed = parseTopologicalAddress(rawAddress);

  return VariableEntry(
    name: name,
    typeName: typeName,
    rawAddress: rawAddress,
    byteOffset: parsed?.byteOffset,
    bitOffset: parsed?.bitOffset,
  );
}

DdtTypeEntry? _parseDdtElement(XmlElement el) {
  final name = _attr(el, 'name');
  if (name == null || name.isEmpty) return null;

  String? comment;
  for (final c in el.childElements) {
    if (c.name.local == 'comment') {
      comment = c.innerText.trim();
      break;
    }
  }

  final members = <DdtMember>[];
  for (final c in el.childElements) {
    final lname = c.name.local;
    if (lname == 'structElement' ||
        lname == 'member' ||
        lname == 'field' ||
        lname == 'StructElement') {
      final m = _parseStructElement(c);
      if (m != null) members.add(m);
    }
  }

  return DdtTypeEntry(name: name, comment: comment, members: members);
}

DdtMember? _parseStructElement(XmlElement el) {
  final name = _attr(el, 'name');
  if (name == null || name.isEmpty) return null;
  final typeName = _attr(el, 'typeName') ?? _attr(el, 'type');

  // Form 1: child <extractedBit parent="raw" bit="0"/>
  String? parentMember;
  int? bitOffset;
  for (final c in el.childElements) {
    if (!_isBitAliasElement(c.name.local)) continue;
    parentMember = _attr(c, 'parent') ??
        _attr(c, 'parentMember') ??
        _attr(c, 'word') ??
        _attr(c, 'wordName');
    final bitStr = _attr(c, 'bit') ?? _attr(c, 'bitOffset') ?? _attr(c, 'index');
    bitOffset = bitStr == null ? null : int.tryParse(bitStr);
    break;
  }

  // Form 2: attributes on the structElement itself (some Schneider XEF
  // variants flatten the bit alias into attributes — `extractedBit="0"`
  // and `parentMember="raw"`).
  if (parentMember == null) {
    parentMember = _attr(el, 'parentMember') ??
        _attr(el, 'wordName') ??
        _attr(el, 'parent');
  }
  if (bitOffset == null) {
    final bitStr = _attr(el, 'extractedBit') ??
        _attr(el, 'bit') ??
        _attr(el, 'bitOffset');
    if (bitStr != null) {
      bitOffset = int.tryParse(bitStr);
    }
  }

  return DdtMember(
    name: name,
    typeName: typeName,
    bitOffset: bitOffset,
    parentMemberName: parentMember,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Read an attribute by local name, ignoring namespace prefixes.
String? _attr(XmlElement el, String localName) {
  for (final a in el.attributes) {
    if (a.name.local == localName) return a.value;
  }
  return null;
}
