// One recipes button, one key per line.
//
// The asset was written against the legacy `GVL_BatchLines.recipes`: a single
// node holding an ARRAY of line recipes, which is why the line pills are
// numbered by array position and why "Send values" wrote the whole array
// back. The current PLCs publish a separate ST_LineRecipe per station
// (SPB01.recipe, SPB02.recipe, SPB03.recipe), so one key cannot reach them
// all -- and writing an array would rewrite every other line.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/recipes.dart';

void main() {
  group('lineKeys', () {
    test('uses the per-line keys when they are set', () {
      final c = RecipesConfig(key: '', label: 'Line', keys: const [
        'SPB01.Recipe',
        'SPB02.Recipe',
        'SPB03.Recipe',
      ]);
      expect(c.lineKeys, ['SPB01.Recipe', 'SPB02.Recipe', 'SPB03.Recipe']);
      expect(c.perLineKeys, isTrue);
    });

    test('falls back to the legacy single key', () {
      final c = RecipesConfig(key: 'LineRecipes', label: 'Line');
      expect(c.lineKeys, ['LineRecipes']);
      expect(c.perLineKeys, isFalse);
    });

    test('per-line keys win over a leftover single key', () {
      final c = RecipesConfig(
          key: 'LineRecipes', label: 'Line', keys: const ['SPB01.Recipe']);
      expect(c.lineKeys, ['SPB01.Recipe']);
      expect(c.perLineKeys, isTrue);
    });

    test('an unconfigured asset has no lines', () {
      expect(RecipesConfig(key: '', label: 'Line').lineKeys, isEmpty);
      expect(RecipesConfig.preview().lineKeys, isEmpty);
    });
  });

  group('recipesBucket', () {
    // Saved presets are keyed by this. It must not move when an asset is
    // migrated from the single key to per-line keys, or the recipes defined
    // beforehand are orphaned.
    test('stays on the legacy key when one is present', () {
      final c = RecipesConfig(
          key: 'LineRecipes', label: 'Line', keys: const ['SPB01.Recipe']);
      expect(c.recipesBucket, 'LineRecipes');
    });

    test('uses the first line key when there is no legacy key', () {
      final c = RecipesConfig(
          key: '', label: 'Line', keys: const ['SPB01.Recipe', 'SPB02.Recipe']);
      expect(c.recipesBucket, 'SPB01.Recipe');
    });

    test('is empty when nothing is configured', () {
      expect(RecipesConfig(key: '', label: 'Line').recipesBucket, '');
    });
  });

  group('serialisation', () {
    // toJson/fromJson are exercised in each direction rather than round-trip:
    // BaseAsset.toJson leaves `coordinates` as an object, so feeding its
    // output straight back into fromJson fails for every asset type, not just
    // this one.
    Map<String, dynamic> asJson(Map<String, dynamic> extra) => <String, dynamic>{
          'asset_name': 'RecipesConfig',
          'coordinates': {'x': 0.1, 'y': 0.1},
          'size': {'width': 0.055, 'height': 0.05},
          'label': 'Line',
          ...extra,
        };

    test('writes the key list', () {
      final c = RecipesConfig(
          key: '', label: 'Line', keys: const ['SPB01.Recipe', 'SPB02.Recipe']);
      expect(c.toJson()['keys'], ['SPB01.Recipe', 'SPB02.Recipe']);
    });

    test('reads the key list', () {
      final back = RecipesConfig.fromJson(
          asJson({'key': '', 'keys': ['SPB01.Recipe', 'SPB02.Recipe']}));
      expect(back.keys, ['SPB01.Recipe', 'SPB02.Recipe']);
      expect(back.perLineKeys, isTrue);
    });

    test('a config written before keys existed still loads', () {
      final back = RecipesConfig.fromJson(asJson({'key': 'LineRecipes'}));
      expect(back.keys, isEmpty);
      expect(back.lineKeys, ['LineRecipes']);
      expect(back.perLineKeys, isFalse);
    });

    test('the decoded key list is growable, so the editor can add a line', () {
      final back =
          RecipesConfig.fromJson(asJson({'key': '', 'keys': <String>[]}));
      expect(() => back.keys = [...back.keys, 'SPB01.Recipe'], returnsNormally);
      expect(back.lineKeys, ['SPB01.Recipe']);
    });
  });

  group('allKeys', () {
    // Whatever asks which keys a page depends on -- unused-key cleanup among
    // them -- reads allKeys. A list-valued key field must not be invisible to
    // it, or its keys look free to delete.
    test('reports every per-line key', () {
      final c = RecipesConfig(key: '', label: 'Line', keys: const [
        'SPB01.Recipe',
        'SPB02.Recipe',
        'SPB03.Recipe',
      ]);
      expect(c.allKeys, containsAll(<String>[
        'SPB01.Recipe',
        'SPB02.Recipe',
        'SPB03.Recipe',
      ]));
    });

    test('still reports the legacy single key', () {
      expect(RecipesConfig(key: 'LineRecipes', label: 'Line').allKeys,
          contains('LineRecipes'));
    });

    test('an empty entry in the list is not reported', () {
      final c = RecipesConfig(
          key: '', label: 'Line', keys: const ['SPB01.Recipe', '']);
      expect(c.allKeys, ['SPB01.Recipe']);
    });
  });
}
