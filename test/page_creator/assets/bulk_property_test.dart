/// The selection logic behind the page editor's multi-select property
/// editor: which settings a group of assets has in common, whether they
/// agree on a value, and what writing one does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/converter/color_converter.dart' show AssetColor;
import 'package:tfc/page_creator/assets/analog_box.dart';
import 'package:tfc/page_creator/assets/bulk_property.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/schneider.dart';

/// [asset]'s bulk property with this id, or null.
BulkProperty? _property(Asset asset, String id) =>
    asset.bulkProperties.where((p) => p.id == id).firstOrNull;

/// The one slot for [id] across [selection].
BulkPropertySlot _slot(List<Asset> selection, String id) {
  final slots = commonBulkProperties(
    [for (final asset in selection) asset.bulkProperties],
  );
  return slots.firstWhere(
    (slot) => slot.id == id,
    orElse: () => throw StateError(
      'No shared property "$id"; got ${slots.map((s) => s.id).toList()}',
    ),
  );
}

SchneiderATV320Config _drive({double? fontSize, String? label}) =>
    SchneiderATV320Config(label: label, labelFontSize: fontSize);

void main() {
  group('commonBulkProperties', () {
    test('a selection of one kind keeps that kind\'s own settings', () {
      final slots = commonBulkProperties([
        for (final asset in [_drive(), _drive()]) asset.bulkProperties,
      ]);
      final ids = slots.map((slot) => slot.id).toList();

      expect(ids, contains('width'));
      expect(ids, contains('label.text'));
      expect(ids, contains('SchneiderATV320Config.labelFontSize'));
    });

    test('a mixed selection keeps only what every asset has', () {
      final selection = <Asset>[_drive(), LEDConfig(key: 'a')];
      final ids = commonBulkProperties(
        [for (final asset in selection) asset.bulkProperties],
      ).map((slot) => slot.id).toList();

      // Geometry and the label are on BaseAsset, so they survive anything.
      expect(ids, containsAll(['x', 'y', 'width', 'height', 'angle']));
      expect(ids, containsAll(['label.text', 'label.position']));
      // The device-specific rows go, in both directions.
      expect(ids, isNot(contains('SchneiderATV320Config.labelFontSize')));
      expect(ids, isNot(contains('LEDConfig.onColor')));
    });

    test('rows follow the first asset\'s order, not an alphabetical one', () {
      final drive = _drive();
      final slots = commonBulkProperties([drive.bulkProperties]);

      expect(
        slots.map((slot) => slot.id).take(5).toList(),
        ['x', 'y', 'width', 'height', 'angle'],
      );
    });

    test('an empty selection has nothing in common', () {
      expect(commonBulkProperties([]), isEmpty);
    });

    test('fields that merely share a name do not merge across asset types',
        () {
      // Both hold a nullable `units` string, but under ids of their own, so a
      // selection of one of each does not offer a row that would write a
      // gauge's unit onto a readout.
      final selection = <Asset>[
        NumberConfig(key: 'n', units: 'bar'),
        AnalogBoxConfig(analogKey: 'a', units: 'kg'),
      ];
      final ids = commonBulkProperties(
        [for (final asset in selection) asset.bulkProperties],
      ).map((slot) => slot.id).toList();

      expect(ids, isNot(contains('NumberConfig.units')));
      expect(ids, isNot(contains('AnalogBoxConfig.units')));
    });
  });

  group('agreement', () {
    test('a selection holding one value is not mixed', () {
      final slot = _slot([_drive(fontSize: 12), _drive(fontSize: 12)],
          'SchneiderATV320Config.labelFontSize');

      expect(slot.isMixed, isFalse);
      expect(slot.value, 12);
      expect(slot.count, 2);
    });

    test('a selection holding different values is mixed', () {
      final slot = _slot([_drive(fontSize: 12), _drive(fontSize: 18)],
          'SchneiderATV320Config.labelFontSize');

      expect(slot.isMixed, isTrue);
      // Deliberately null rather than one of the two — the pane shows
      // "Multiple values", it does not pick a winner.
      expect(slot.value, isNull);
    });

    test('a value every asset leaves unset is a value, not a disagreement',
        () {
      final slot = _slot([_drive(), _drive()],
          'SchneiderATV320Config.labelFontSize');

      expect(slot.isMixed, isFalse);
      expect(slot.value, isNull);
    });

    test('one unset asset among set ones is a disagreement', () {
      final slot = _slot([_drive(fontSize: 12), _drive()],
          'SchneiderATV320Config.labelFontSize');

      expect(slot.isMixed, isTrue);
    });
  });

  group('writing', () {
    test('a write makes a non-common setting common — the EPLAN move', () {
      final wide = _drive(fontSize: 18);
      final narrow = _drive(fontSize: 9);
      final slot = _slot(
          [wide, narrow], 'SchneiderATV320Config.labelFontSize');
      expect(slot.isMixed, isTrue);

      slot.write(14.0);

      expect(wide.labelFontSize, 14);
      expect(narrow.labelFontSize, 14);
      expect(slot.isMixed, isFalse);
    });

    test('geometry is written as a percentage of the canvas', () {
      final assets = [_drive(), _drive()];
      _slot(assets, 'width').write(8.0);

      // 8% of the canvas, stored as the 0..1 fraction the page uses.
      expect(assets[0].size.width, closeTo(0.08, 1e-9));
      expect(assets[1].size.width, closeTo(0.08, 1e-9));
      expect(_slot(assets, 'width').value, closeTo(8.0, 1e-9));
    });

    test('a width write leaves height alone', () {
      final drive = _drive()..size = const RelativeSize(width: .1, height: .4);
      _slot([drive], 'width').write(20.0);

      expect(drive.size.width, closeTo(0.2, 1e-9));
      expect(drive.size.height, closeTo(0.4, 1e-9));
    });

    test('an x write leaves the angle alone', () {
      final drive = _drive()
        ..coordinates = Coordinates(x: .1, y: .2, angle: 90);
      _slot([drive], 'x').write(50.0);

      expect(drive.coordinates.x, closeTo(0.5, 1e-9));
      expect(drive.coordinates.y, closeTo(0.2, 1e-9));
      expect(drive.coordinates.angle, 90);
    });

    test('out-of-range numbers clamp rather than being rejected', () {
      final drive = _drive();
      _slot([drive], 'width').write(500.0);
      expect(drive.size.width, 1.0);

      // The floor matters most: an asset scaled to nothing cannot be found
      // on the canvas again to fix it.
      _slot([drive], 'width').write(0.0);
      expect(drive.size.width, closeTo(0.01, 1e-9));
    });

    test('an int property rounds what it is given', () {
      final number = NumberConfig(key: 'n');
      _slot([number], 'NumberConfig.decimalPlaces').write(2.6);

      expect(number.decimalPlaces, 3);
    });

    test('clearing a nullable property writes null', () {
      final drive = _drive(fontSize: 12);
      _slot([drive], 'SchneiderATV320Config.labelFontSize').write(null);

      expect(drive.labelFontSize, isNull);
    });

    test('clearing a non-nullable number leaves the assets alone', () {
      final drive = _drive()..size = const RelativeSize(width: .3, height: .3);
      _slot([drive], 'width').write(null);

      expect(drive.size.width, closeTo(0.3, 1e-9));
    });

    test('a value of the wrong type is ignored, not half-applied', () {
      final drive = _drive(fontSize: 12);
      final slot =
          _slot([drive], 'SchneiderATV320Config.labelFontSize');

      slot.write('not a number');

      expect(drive.labelFontSize, 12);
    });

    test('enum rows write to every selected asset', () {
      final leds = [LEDConfig(key: 'a'), LEDConfig(key: 'b')];
      _slot(leds, 'LEDConfig.ledType').write(LEDType.square);

      expect(leds.every((led) => led.ledType == LEDType.square), isTrue);
    });

    test('an AssetColor keeps its theme role through a bulk write', () {
      final leds = [
        LEDConfig(key: 'a', onColor: AssetColor.literal(Colors.red)),
        LEDConfig(key: 'b'),
      ];
      _slot(leds, 'LEDConfig.onColor').write(AssetColor.green);

      expect(leds.every((led) => led.onColor.isRole), isTrue);
      expect(leds.every((led) => led.onColor == AssetColor.green), isTrue);
    });
  });

  group('label position', () {
    test('an asset that has never had one reads as its painted default', () {
      // Null means "wherever this asset draws it"; the dropdown has no entry
      // for that, so the row reports the position actually rendered.
      final drive = _drive();
      expect(drive.textPos, isNull);
      expect(_slot([drive], 'label.position').value, TextPos.below);
    });

    test('assets differing only in an unset position are not mixed', () {
      final unset = _drive();
      final explicit = _drive()..textPos = TextPos.below;

      expect(_slot([unset, explicit], 'label.position').isMixed, isFalse);
    });
  });

  group('grouping', () {
    test('sections come out in the order the rows first mention them', () {
      final groups = groupBulkProperties(
        commonBulkProperties([_drive().bulkProperties]),
      );

      expect(groups.map((g) => g.name).toList(),
          ['Geometry', 'Label', 'Schneider ATV320']);
    });

    test('a mixed selection loses the device section entirely', () {
      final selection = <Asset>[_drive(), LEDConfig(key: 'a')];
      final groups = groupBulkProperties(
        commonBulkProperties(
          [for (final asset in selection) asset.bulkProperties],
        ),
      );

      expect(groups.map((g) => g.name).toList(), ['Geometry', 'Label']);
    });

    test('every group holds at least one row', () {
      final groups = groupBulkProperties(
        commonBulkProperties([AnalogBoxConfig(analogKey: 'a').bulkProperties]),
      );

      expect(groups, isNotEmpty);
      expect(groups.every((g) => g.slots.isNotEmpty), isTrue);
    });
  });

  group('what is deliberately absent', () {
    // Bulk-setting a tag name points every selected asset at one signal: a
    // mimic that looks right and is wrong. These stay in the per-asset form,
    // where the key picker vets them one at a time.
    test('no OPC UA key is bulk-editable', () {
      final assets = <Asset>[
        _drive(),
        LEDConfig(key: 'a'),
        NumberConfig(key: 'n'),
        AnalogBoxConfig(analogKey: 'a'),
      ];

      for (final asset in assets) {
        final ids = asset.bulkProperties.map((p) => p.id.toLowerCase());
        expect(
          ids.where((id) => id.endsWith('key')),
          isEmpty,
          reason: '${asset.displayName} exposes a key field',
        );
      }
    });

    test('every asset offers the geometry rows', () {
      // The guarantee a mixed selection rests on. Sampled across the kinds
      // that carry their own overrides.
      for (final asset in <Asset>[
        _drive(),
        LEDConfig(key: 'a'),
        NumberConfig(key: 'n'),
        AnalogBoxConfig(analogKey: 'a'),
      ]) {
        for (final id in ['x', 'y', 'width', 'height', 'angle']) {
          expect(_property(asset, id), isNotNull,
              reason: '${asset.displayName} is missing "$id"');
        }
      }
    });
  });
}
