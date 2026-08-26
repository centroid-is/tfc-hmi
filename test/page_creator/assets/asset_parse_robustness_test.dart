import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/converter/color_converter.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/third_party.dart';

/// 2026-08-26, plant HMI 10.104.60.83: a ThirdPartyEquipment asset was saved
/// with `{"role": "green"}` colors — the AssetColor role format — in fields
/// declared with the plain [ColorConverter]. `fromJson` threw on the missing
/// `red` key, the registry rethrew, and `PageManager.load()`'s catch reset
/// every page to defaults: the entire HMI went blank over one color field.
///
/// These tests pin the two lines of defense against that class of outage.
void main() {
  group('ColorConverter never throws on malformed stored colors', () {
    test('role-format map resolves to a fallback literal', () {
      final c = const ColorConverter().fromJson({'role': 'green'});
      expect(c, isA<Color>());
    });

    test('unknown role resolves to the grey fallback', () {
      final c = const ColorConverter().fromJson({'role': 'chartreuse'});
      expect(c, const Color(0xFF9E9E9E));
    });

    test('empty map resolves to a color instead of throwing', () {
      expect(const ColorConverter().fromJson({}), isA<Color>());
    });

    test('literal maps still round-trip exactly', () {
      const original = Color.fromRGBO(76, 175, 80, 1.0);
      final json = const ColorConverter().toJson(original);
      final back = const ColorConverter().fromJson(json);
      expect(back.r, closeTo(original.r, 1 / 255));
      expect(back.g, closeTo(original.g, 1 / 255));
      expect(back.b, closeTo(original.b, 1 / 255));
    });
  });

  group('AssetRegistry.parse survives one bad asset', () {
    Map<String, dynamic> goodThirdParty() =>
        (ThirdPartyEquipmentConfig.preview()).toJson();

    test('a bad asset is skipped, the rest of the page parses', () {
      final bad = goodThirdParty();
      // A field shape fromJson genuinely cannot use: kind must decode, so
      // break something structural instead of a color (colors are now
      // fault-tolerant by the group above).
      bad['coordinates'] = 'not-a-map';

      final page = {
        'assets': [bad, goodThirdParty(), goodThirdParty()],
      };

      final parsed = AssetRegistry.parse(page);
      expect(parsed.length, 2,
          reason: 'the two good assets must survive the bad one');
    });

    test('the 2026-08-26 incident shape parses fully after the color fix', () {
      final incident = goodThirdParty();
      incident['runningColor'] = {'role': 'green'};
      incident['stoppedColor'] = {'role': 'red'};

      final parsed = AssetRegistry.parse({
        'assets': [incident, goodThirdParty()],
      });
      expect(parsed.length, 2,
          reason: 'role-format colors must not cost even that one asset');
    });
  });
}
