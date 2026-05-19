/// EcoStruxure .ZEF / .XEF offline parser — scaffold tests.
///
/// Source-of-truth chain:
///   .ZEF (ZIP) → inner .XEF (XML) → variables + DDT defs → bit-alias map.
///
/// Schema notes:
///   * .XEF tag/attribute names are based on the Schneider "openness"
///     XML emitted by Control Expert. Verified attribute names against
///     ZEF_splitter (Pascal, https://github.com/corax4/ZEF_splitter) and
///     the V15 release-note language about "extracted bits in DDT" being
///     XEF-first-class since V7.0.
///   * Real-world XEF files have not been validated against in this
///     scaffold — see `/tmp/bitalias-swarm-v2/zef-scaffold.md` for the
///     verification checklist when a real .ZEF lands.
///
/// Fixtures under test/fixtures/ are clearly flagged as SYNTHETIC.
@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:tfc_dart/core/ecostruxure_zef.dart';
import 'package:test/test.dart';

void main() {
  group('parseXef — synthetic minimal fixture', () {
    late ZefProject project;

    setUpAll(() {
      final xml = File('test/fixtures/minimal.xef').readAsStringSync();
      project = parseXef(xml);
    });

    test('parses every declared variable', () {
      // 4 elementaryVariables + 1 derivedVariable = 5 entries.
      // (no_type_attr is still listed; we only skip nameless variables.)
      expect(project.variables.keys, containsAll(<String>[
        'speed_setpoint',
        'run_command',
        'motor1',
        'unlocated_temp',
        'no_type_attr',
      ]));
      expect(project.variables.length, 5);
    });

    test('elementary located variable: address parsed, no bit offset', () {
      final v = project.variables['speed_setpoint']!;
      expect(v.name, 'speed_setpoint');
      expect(v.typeName, 'INT');
      expect(v.bitOffset, isNull);
      expect(v.parentWordName, isNull);
      expect(v.rawAddress, '%MW100');
      // %MW100 → word index 100 → byte offset 200 from %MW0.
      expect(v.byteOffset, 200);
      // blockNo is not derivable from XEF alone (UMAS runtime artifact).
      expect(v.blockNo, isNull);
    });

    test('derived DDT instance has typeName + parsed address', () {
      final v = project.variables['motor1']!;
      expect(v.typeName, 'MOTOR_STATUS_DDT');
      expect(v.rawAddress, '%MW200');
      expect(v.byteOffset, 400);
      expect(v.bitOffset, isNull);
    });

    test('unlocated variable: address fields null, type preserved', () {
      final v = project.variables['unlocated_temp']!;
      expect(v.typeName, 'REAL');
      expect(v.rawAddress, isNull);
      expect(v.byteOffset, isNull);
      expect(v.blockNo, isNull);
      expect(v.bitOffset, isNull);
    });

    test('variable with no typeName attribute does not crash', () {
      final v = project.variables['no_type_attr']!;
      expect(v.name, 'no_type_attr');
      // typeName should be empty or null, not throw.
      expect(v.typeName, anyOf(isNull, equals('')));
    });

    test('discovers the MOTOR_STATUS_DDT type with three bit aliases', () {
      final ddt = project.ddts.firstWhere((d) => d.name == 'MOTOR_STATUS_DDT');
      expect(ddt.members.length, 4);

      // raw is the parent word (no bit alias).
      final raw = ddt.members.firstWhere((m) => m.name == 'raw');
      expect(raw.typeName, 'WORD');
      expect(raw.bitOffset, isNull);
      expect(raw.parentMemberName, isNull);

      // run, fault, ready are bit aliases of `raw`.
      final run = ddt.members.firstWhere((m) => m.name == 'run');
      expect(run.typeName, 'BOOL');
      expect(run.parentMemberName, 'raw');
      expect(run.bitOffset, 0);

      final fault = ddt.members.firstWhere((m) => m.name == 'fault');
      expect(fault.parentMemberName, 'raw');
      expect(fault.bitOffset, 1);

      final ready = ddt.members.firstWhere((m) => m.name == 'ready');
      expect(ready.parentMemberName, 'raw');
      expect(ready.bitOffset, 7);
    });

    test('empty DDT is preserved as zero-member entry', () {
      final ddt = project.ddts.firstWhere((d) => d.name == 'EMPTY_DDT');
      expect(ddt.members, isEmpty);
    });
  });

  group('bit-alias resolution — flatten DDT instance', () {
    test('motor1.run resolves to parent=%MW200, bitOffset=0', () {
      final xml = File('test/fixtures/minimal.xef').readAsStringSync();
      final project = parseXef(xml);

      final aliases = project.resolveBitAliases();
      // We expect at least these three flattened bit aliases for motor1.
      final names = aliases.map((a) => a.aliasFullName).toSet();
      expect(names, containsAll(<String>[
        'motor1.run',
        'motor1.fault',
        'motor1.ready',
      ]));

      final run = aliases.firstWhere((a) => a.aliasFullName == 'motor1.run');
      expect(run.parentVariableName, 'motor1');
      expect(run.parentMemberName, 'raw');
      expect(run.bitOffset, 0);
      // parent word address is the DDT instance's %MW200 (bit aliases inherit
      // the located address; this is the v1.1 simplification — single-WORD DDT).
      expect(run.parentRawAddress, '%MW200');
      expect(run.parentByteOffset, 400);

      final ready = aliases.firstWhere((a) => a.aliasFullName == 'motor1.ready');
      expect(ready.bitOffset, 7);
    });
  });

  group('parseZef — minimal ZIP roundtrip', () {
    test('extracts inner .xef from a synthetic ZIP', () async {
      final xml = File('test/fixtures/minimal.xef').readAsStringSync();
      final archive = Archive();
      archive.addFile(ArchiveFile.string('inner.xef', xml));
      final zipBytes = ZipEncoder().encode(archive);
      final tmp = File('${Directory.systemTemp.path}/synthetic_${DateTime.now().microsecondsSinceEpoch}.zef');
      try {
        await tmp.writeAsBytes(zipBytes);
        final project = parseZef(tmp);
        expect(project.variables.keys, contains('motor1'));
        expect(project.ddts.map((d) => d.name), contains('MOTOR_STATUS_DDT'));
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    });

    test('throws clear error if ZIP has no .xef entry', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile.string('readme.txt', 'no xef here'));
      final zipBytes = ZipEncoder().encode(archive);
      final tmp = File('${Directory.systemTemp.path}/empty_${DateTime.now().microsecondsSinceEpoch}.zef');
      try {
        await tmp.writeAsBytes(zipBytes);
        expect(() => parseZef(tmp), throwsA(isA<FormatException>()));
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    });
  });

  group('tolerance — malformed / missing fields', () {
    test('XEF with no <variables> block parses to empty project', () {
      const xml = '''<?xml version="1.0"?>
<FileExchangeFile>
  <FileHeader><Version>1.0</Version></FileHeader>
  <contents><dataBlock></dataBlock></contents>
</FileExchangeFile>''';
      final project = parseXef(xml);
      expect(project.variables, isEmpty);
      expect(project.ddts, isEmpty);
    });

    test('completely unrecognised XML parses without throwing', () {
      const xml = '<?xml version="1.0"?><random><x/></random>';
      final project = parseXef(xml);
      expect(project.variables, isEmpty);
      expect(project.ddts, isEmpty);
    });

    test('invalid XML throws FormatException', () {
      const xml = 'not even xml <<<>>>';
      expect(() => parseXef(xml), throwsA(isA<FormatException>()));
    });

    test('extracted bit with non-integer bit attribute is ignored', () {
      const xml = '''<?xml version="1.0"?>
<FileExchangeFile><contents><dataBlock><dataBlockTypeDef>
  <DDT name="BAD_DDT">
    <structElement name="raw" typeName="WORD"/>
    <structElement name="weird" typeName="BOOL">
      <extractedBit parent="raw" bit="not-a-number"/>
    </structElement>
  </DDT>
</dataBlockTypeDef></dataBlock></contents></FileExchangeFile>''';
      final project = parseXef(xml);
      final ddt = project.ddts.firstWhere((d) => d.name == 'BAD_DDT');
      final weird = ddt.members.firstWhere((m) => m.name == 'weird');
      // bit attribute couldn't be parsed → bitOffset null,
      // parentMemberName still preserved so caller can inspect.
      expect(weird.bitOffset, isNull);
      expect(weird.parentMemberName, 'raw');
    });
  });

  group('address parser', () {
    test('parses %MW word-area addresses', () {
      expect(parseTopologicalAddress('%MW0')!.byteOffset, 0);
      expect(parseTopologicalAddress('%MW100')!.byteOffset, 200);
      expect(parseTopologicalAddress('%MW0')!.area, 'MW');
    });

    test('parses %M bit-area addresses', () {
      final addr = parseTopologicalAddress('%M5')!;
      expect(addr.area, 'M');
      // %M is bit-addressed; byteOffset reflects 5/8 = 0 (with remainder bit).
      expect(addr.byteOffset, 0);
      expect(addr.bitOffset, 5);
    });

    test('rejects garbage addresses', () {
      expect(parseTopologicalAddress('garbage'), isNull);
      expect(parseTopologicalAddress(''), isNull);
      expect(parseTopologicalAddress('%QQ123'), isNull);
    });
  });
}
