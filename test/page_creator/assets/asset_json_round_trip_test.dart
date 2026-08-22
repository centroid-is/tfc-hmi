import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/led_column.dart';
import 'package:tfc/page_creator/assets/registry.dart';

/// Every asset must be able to read back its own `toJson()`.
///
/// This is not an abstract nicety. `PageEditor` applies a proposed config by
/// merging the override onto `asset.toJson()` and handing the result straight
/// to [AssetRegistry.parse] -- no `jsonEncode` in between. So `toJson()` has
/// to return plain maps, not live objects.
///
/// `LEDColumnConfig` was `@JsonSerializable()` while the `LEDConfig` it
/// contains was `@JsonSerializable(explicitToJson: true)`. Without
/// `explicitToJson` the generated `toJson()` puts the live `Coordinates`,
/// `RelativeSize` and `LEDConfig` objects in the map, and `fromJson`'s first
/// `as Map<String, dynamic>` throws on them. The editor's `catch` then
/// substituted `LEDColumnConfig.preview()` -- two grey LEDs -- so a proposed
/// three-lamp beacon column arrived wrong, with nothing logged and nothing
/// shown to the operator.
///
/// The per-type loop below is the point: this was a whole class of bug, and
/// any asset gaining a nested object field without `explicitToJson` reopens
/// it. Fixing only LED column would have left the trap set for the next one.
void main() {
  // `defaultFactories` is the palette, which is what a proposal can ask for.
  // Types registered for `fromJson` only (a `DrawingViewerConfig` when
  // `kKnowledgeEnabled` is false) are deliberately out of scope -- nothing can
  // propose one, and the registry keeps parsing them so saved pages survive.
  final types = AssetRegistry.defaultFactories.entries.toList();

  test('the palette is not empty, so the loop below means something', () {
    expect(types.length, greaterThan(20),
        reason: 'if defaultFactories were empty every test here would '
            'vacuously pass');
  });

  /// The path from a value to the first thing in it that is not JSON data,
  /// or null if there is nothing wrong.
  ///
  /// Note what this does *not* do: call `jsonEncode`. `dart:convert` falls
  /// back to calling `.toJson()` on an object it does not recognise, so
  /// encoding launders a live `Coordinates` into a map and reports success.
  /// That is exactly why this bug survived — saving a page to the database
  /// goes through `jsonEncode` and has always worked, while the editor's
  /// proposal path, which hands the raw map straight to `fromJson`, did not.
  String? firstNonJsonValue(dynamic value, String path) {
    if (value == null || value is num || value is bool || value is String) {
      return null;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final bad = firstNonJsonValue(value[i], '$path[$i]');
        if (bad != null) return bad;
      }
      return null;
    }
    if (value is Map) {
      for (final e in value.entries) {
        final bad = firstNonJsonValue(e.value, '$path.${e.key}');
        if (bad != null) return bad;
      }
      return null;
    }
    return '$path is a live ${value.runtimeType}';
  }

  group('toJson emits data, not live objects', () {
    for (final entry in types) {
      test('${entry.key}', () {
        final json = entry.value().toJson();

        expect(firstNonJsonValue(json, '<root>'), isNull,
            reason: 'toJson() left a live object in the map, so fromJson\'s '
                '`as Map<String, dynamic>` will throw on it. Add '
                'explicitToJson: true to this type\'s @JsonSerializable.');
      });
    }
  });

  group('an asset can read back its own toJson', () {
    for (final entry in types) {
      test('${entry.key}', () {
        final asset = entry.value();
        final json = asset.toJson();

        // Exactly what PageEditor does: the raw map, no encode/decode pass to
        // launder live objects into maps first.
        final reparsed =
            AssetRegistry.parse({constAssetName: asset.assetName, ...json});

        expect(reparsed, hasLength(1),
            reason: 'parse() dropped the asset instead of rebuilding it');
        expect(reparsed.first.runtimeType, asset.runtimeType,
            reason: 'parse() produced a different type than it was given');
      });
    }
  });

  group('LED column, the asset this was found on', () {
    LEDConfig led(String key) => LEDConfig.preview()..key = key;

    test('a three-LED column round-trips as three LEDs, not the preview two',
        () {
      final column = LEDColumnConfig(
        leds: [led('lamp.red'), led('lamp.amber'), led('lamp.green')],
      );

      final reparsed = AssetRegistry.parse(
          {constAssetName: column.assetName, ...column.toJson()});

      expect(reparsed, hasLength(1));
      final result = reparsed.first as LEDColumnConfig;
      expect(result.leds, hasLength(3),
          reason: 'falling back to LEDColumnConfig.preview() gives two LEDs, '
              'which is what the operator saw');
      expect(result.leds.map((l) => l.key),
          ['lamp.red', 'lamp.amber', 'lamp.green']);
    });

    test('the editor\'s merge-then-reparse keeps the proposed LEDs', () {
      // The proposal path verbatim: default asset -> toJson -> merge the
      // override -> re-parse. Before the fix this threw on the first cast and
      // the operator silently got the default.
      final base = LEDColumnConfig.preview();
      final override = <String, dynamic>{
        'leds': [
          led('beacon.fault').toJson(),
          led('beacon.warning').toJson(),
          led('beacon.ok').toJson(),
        ],
      };

      final merged = base.toJson()..addAll(override);
      merged[constAssetName] = base.assetName;

      final reparsed = AssetRegistry.parse(merged);

      expect(reparsed, hasLength(1));
      expect((reparsed.first as LEDColumnConfig).leds.map((l) => l.key),
          ['beacon.fault', 'beacon.warning', 'beacon.ok']);
    });

    test('spacing survives the round trip', () {
      final column = LEDColumnConfig(leds: [led('a'), led('b')])..spacing = 12.5;

      final reparsed = AssetRegistry.parse(
          {constAssetName: column.assetName, ...column.toJson()});

      expect((reparsed.first as LEDColumnConfig).spacing, 12.5);
    });
  });
}
