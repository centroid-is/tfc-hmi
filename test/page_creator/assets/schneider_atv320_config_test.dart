import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/schneider.dart';
import 'package:tfc/painter/schneider/atv320.dart';

void main() {
  group('SchneiderATV320Config.resolvedLabelFontSize', () {
    test('an unset size falls back to the drive default', () {
      expect(
        SchneiderATV320Config().resolvedLabelFontSize,
        ATV320.defaultLabelFontSize,
      );
    });

    test('a size inside the range is used as given', () {
      expect(
        SchneiderATV320Config(labelFontSize: 26).resolvedLabelFontSize,
        26,
      );
    });

    test('a size outside the range is held at the nearest bound', () {
      // A page hand-edited or written by an older tool must not be able to
      // paint a label of 0 or one that runs down over the LCD screen.
      expect(
        SchneiderATV320Config(labelFontSize: 0).resolvedLabelFontSize,
        ATV320.minLabelFontSize,
      );
      expect(
        SchneiderATV320Config(labelFontSize: 500).resolvedLabelFontSize,
        ATV320.maxLabelFontSize,
      );
      expect(
        SchneiderATV320Config(labelFontSize: -12).resolvedLabelFontSize,
        ATV320.minLabelFontSize,
      );
    });
  });

  group('SchneiderATV320Config serialisation', () {
    test('the label size survives a round trip', () {
      final json = SchneiderATV320Config(
        label: 'CN01\nFD01',
        labelFontSize: 28,
        hmisKey: 'a',
        freqKey: 'b',
        configKey: 'c',
      ).toJson();

      final restored = SchneiderATV320Config.fromJson(json);
      expect(restored.labelFontSize, 28);
      expect(restored.label, 'CN01\nFD01');
    });

    test('a page saved before the field existed loads at the default', () {
      // Pages already on the stations have no labelFontSize key at all; they
      // must keep drawing exactly as they do today.
      final legacy = SchneiderATV320Config(label: 'CN01', hmisKey: 'a').toJson()
        ..remove('labelFontSize');
      expect(legacy.containsKey('labelFontSize'), isFalse);

      final restored = SchneiderATV320Config.fromJson(legacy);
      expect(restored.labelFontSize, isNull);
      expect(restored.resolvedLabelFontSize, ATV320.defaultLabelFontSize);
    });
  });
}
