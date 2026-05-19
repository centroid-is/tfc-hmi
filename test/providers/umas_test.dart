// Unit tests for `lib/providers/umas.dart`.
//
// Scope: the parts of the provider graph that don't need a live PLC.
//
//  * `bitAliasDecoderProvider(null)` and `bitAliasDecoderProvider('')`
//    must fall back to `StubBitAliasDecoder` synchronously (no
//    StateMan / PLC dependency in that path).
//  * `bitAliasDecoderProvider(someAlias)` reads the underlying map
//    provider — overriding the map provider with a fixed value swaps
//    in the real `UmasBitAliasDecoder` deterministically.
//
// The "happy path" against a real adapter / PLC requires
// `ensureBitAliasMap` to succeed against a paired UMAS session, which
// is exercised by `packages/tfc_dart/test/umas_*` integration tests
// and by the live M580 verification step in the SUMMARY.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/umas.dart';
import 'package:tfc_dart/core/umas_bit_alias.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';

void main() {
  group('bitAliasDecoderProvider', () {
    test('null alias -> StubBitAliasDecoder, never touches StateMan',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final decoder = container.read(bitAliasDecoderProvider(null));
      expect(decoder, isA<StubBitAliasDecoder>());
      // Stub decoder returns null for every alias -> UI shows "?".
      expect(decoder.decodeBit(0xFFFF, 'anything'), isNull);
    });

    test('empty alias -> StubBitAliasDecoder', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final decoder = container.read(bitAliasDecoderProvider(''));
      expect(decoder, isA<StubBitAliasDecoder>());
    });

    test(
        'when underlying map provider is overridden to null, '
        'decoder is StubBitAliasDecoder', () async {
      final container = ProviderContainer(overrides: [
        umasBitAliasMapProvider('PLC_A').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      // Wait for the map provider to settle (we override with an
      // already-completed null Future; settling is still an async tick).
      await container.read(umasBitAliasMapProvider('PLC_A').future);
      final decoder = container.read(bitAliasDecoderProvider('PLC_A'));
      expect(decoder, isA<StubBitAliasDecoder>());
    });

    test(
        'when underlying map provider yields a real map, '
        'decoder is UmasBitAliasDecoder backed by it', () async {
      // Hand-crafted minimal map with one entry: alias `red` -> bit 0 of
      // a parent word in block 0x10 at offset 0x20.
      final map = UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: 'red',
          parentBlock: 0x10,
          parentByteOffset: 0x20,
          bitOffset: 0,
        ),
      ]);

      final container = ProviderContainer(overrides: [
        umasBitAliasMapProvider('PLC_A').overrideWith((ref) async => map),
      ]);
      addTearDown(container.dispose);

      await container.read(umasBitAliasMapProvider('PLC_A').future);
      final decoder = container.read(bitAliasDecoderProvider('PLC_A'));
      expect(decoder, isA<UmasBitAliasDecoder>());

      // Known alias decodes against the supplied parent WORD.
      expect(decoder.decodeBit(0x0001, 'red'), isTrue);
      expect(decoder.decodeBit(0x0000, 'red'), isFalse);
      // Unknown alias still returns null (NOT a crash).
      expect(decoder.decodeBit(0xFFFF, 'green'), isNull);
    });

    test(
        'decoder is keyed per serverAlias — different aliases get '
        'different decoders even from the same container', () async {
      final mapA = UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: 'red',
          parentBlock: 0,
          parentByteOffset: 0,
          bitOffset: 0,
        ),
      ]);
      final mapB = UmasBitAliasMap(const [
        BitAliasEntry(
          aliasName: 'green',
          parentBlock: 0,
          parentByteOffset: 0,
          bitOffset: 2,
        ),
      ]);

      final container = ProviderContainer(overrides: [
        umasBitAliasMapProvider('PLC_A').overrideWith((ref) async => mapA),
        umasBitAliasMapProvider('PLC_B').overrideWith((ref) async => mapB),
      ]);
      addTearDown(container.dispose);

      await container.read(umasBitAliasMapProvider('PLC_A').future);
      await container.read(umasBitAliasMapProvider('PLC_B').future);

      final decoderA = container.read(bitAliasDecoderProvider('PLC_A'));
      final decoderB = container.read(bitAliasDecoderProvider('PLC_B'));

      // PLC_A knows `red` but not `green`.
      expect(decoderA.decodeBit(0x01, 'red'), isTrue);
      expect(decoderA.decodeBit(0x04, 'green'), isNull);

      // PLC_B knows `green` but not `red`.
      expect(decoderB.decodeBit(0x01, 'red'), isNull);
      expect(decoderB.decodeBit(0x04, 'green'), isTrue);
    });
  });
}
