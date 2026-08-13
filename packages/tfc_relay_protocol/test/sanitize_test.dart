import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

void main() {
  group('sanitize', () {
    test('replaces NaN and infinities with null and reports it', () {
      for (final poison in [double.nan, double.infinity, double.negativeInfinity]) {
        final r = sanitize(poison);
        expect(r.value, isNull);
        expect(r.hadNonFinite, isTrue);
      }
    });

    test('passes finite edge doubles through untouched', () {
      for (final ok in [
        0.0, -0.0, double.maxFinite, -double.maxFinite,
        double.minPositive, 4.9e-324, 1.5, -1.5,
      ]) {
        final r = sanitize(ok);
        expect(r.value, ok);
        expect(r.hadNonFinite, isFalse);
      }
    });

    test('walks nested lists and maps, replacing only offenders', () {
      final r = sanitize({
        'a': [1.0, double.nan, 3.0],
        'b': {'c': double.infinity, 'd': 'text'},
        'e': 42,
      });
      expect(r.hadNonFinite, isTrue);
      expect(r.value, {
        'a': [1.0, null, 3.0],
        'b': {'c': null, 'd': 'text'},
        'e': 42,
      });
    });

    test('returns the identical object when nothing needed fixing', () {
      final clean = {'a': [1.0, 2.0], 'b': 'x'};
      final r = sanitize(clean);
      expect(identical(r.value, clean), isTrue,
          reason: 'hot path must not copy clean values');
    });

    test('non-double types are untouched', () {
      for (final v in ['NaN', true, null, 7]) {
        expect(sanitize(v).value, v);
      }
    });
  });

  group('WireValue', () {
    test('cannot be built in a state jsonEncode throws on', () {
      final wv = WireValue.of(double.nan);
      expect(wv.v, isNull);
      expect(wv.q, Quality.badNonFinite);
      expect(() => jsonEncode(wv.toJson()), returnsNormally);
    });

    test('non-finite forces badNonFinite even over a good quality claim', () {
      final wv = WireValue.of(double.infinity, quality: Quality.good);
      expect(wv.q, Quality.badNonFinite);
    });

    test('worse existing quality survives non-finite (worst-wins)', () {
      final wv =
          WireValue.of(double.nan, quality: Quality.errorConfig);
      expect(wv.q, Quality.errorConfig);
    });

    test('decode re-sanitizes: 1e999 arrives as Infinity and is defused', () {
      // 1e999 parses silently to double.infinity — a poison value that
      // would detonate on the next encode.
      final decoded = jsonDecode('{"v":1e999}') as Map<String, Object?>;
      final wv = WireValue.fromJson(decoded);
      expect(wv.v, isNull);
      expect(wv.q, Quality.badNonFinite);
      expect(() => jsonEncode(wv.toJson()), returnsNormally);
    });

    test('good quality and absent timestamp are omitted from JSON', () {
      expect(WireValue.of(1.5).toJson(), {'v': 1.5});
      expect(WireValue.of(1.5, quality: Quality.badStale, t: 123).toJson(),
          {'v': 1.5, 'q': Quality.badStale.code, 't': 123});
    });

    test('round-trips Icelandic strings intact', () {
      for (final s in ['Þorskflök í raspi', 'Ýsuhnakkar', 'ýmislegt æði']) {
        final json = jsonEncode(WireValue.of(s).toJson());
        final back = WireValue.fromJson(
            jsonDecode(json) as Map<String, Object?>);
        expect(back.v, s);
      }
    });

    test('fuzz: a frame of random doubles (including poisons) always encodes',
        () {
      final rng = Random(42); // seeded — failures reproduce
      final poisons = [double.nan, double.infinity, double.negativeInfinity];
      for (var run = 0; run < 200; run++) {
        final frame = <String, Object?>{};
        for (var i = 0; i < 50; i++) {
          final roll = rng.nextInt(10);
          final value = roll < 2
              ? poisons[rng.nextInt(3)]
              : (rng.nextDouble() - 0.5) * pow(10, rng.nextInt(60) - 30);
          frame['$i'] = WireValue.of(value).toJson();
        }
        expect(() => jsonEncode(frame), returnsNormally);
      }
    });
  });

  group('Quality', () {
    test('bands', () {
      expect(Quality.good.isGood, isTrue);
      expect(Quality.goodWritePending.isGood, isTrue);
      expect(Quality.uncertainLastKnown.isUncertain, isTrue);
      expect(Quality.uncertainEncoding.isUncertain, isTrue);
      expect(Quality.badStale.isBad, isTrue);
      expect(Quality.badCommFault.isBad, isTrue);
      expect(Quality.badNonFinite.isBad, isTrue);
      expect(Quality.errorConfig.isError, isTrue);
    });

    test('the two stale-ish states stay distinct', () {
      // uncertain-holding-last-known vs bad-past-deadline must never merge.
      expect(Quality.uncertainLastKnown.band,
          isNot(Quality.badStale.band));
    });

    test('worst-wins composition: derived values never look healthier '
        'than their worst input', () {
      expect(
        Quality.worst([Quality.good, Quality.uncertainLastKnown, Quality.good]),
        Quality.uncertainLastKnown,
      );
      expect(
        Quality.worst(
            [Quality.uncertainLastKnown, Quality.badCommFault, Quality.good]),
        Quality.badCommFault,
      );
      expect(Quality.worst([]), Quality.good);
    });
  });
}
