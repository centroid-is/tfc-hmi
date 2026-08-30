import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/registry.dart';

void main() {
  group('RollerConveyorConfig', () {
    test('round-trips through the registry as its own asset type', () {
      final config = RollerConveyorConfig(key: 'AREA01.CNV01', onRails: true)
        ..coordinates = Coordinates(x: 0.1, y: 0.2)
        ..size = const RelativeSize(width: 0.2, height: 0.05);
      final json = config.toJson();
      expect(json['asset_name'], 'RollerConveyorConfig');

      final parsed = AssetRegistry.parse({'assets': [json]});
      expect(parsed, hasLength(1));
      final restored = parsed.single;
      expect(restored, isA<RollerConveyorConfig>());
      final roller = restored as RollerConveyorConfig;
      expect(roller.key, 'AREA01.CNV01');
      expect(roller.onRails, true);
      expect(roller.style, ConveyorStyle.roller);
    });

    test('shares the conveyor logic but paints as rollers', () {
      final roller = RollerConveyorConfig();
      final box = ConveyorConfig();
      expect(roller.style, ConveyorStyle.roller);
      expect(box.style, ConveyorStyle.box);
      expect(roller.displayName, 'Roller Conveyor');
      // The palette can create one.
      expect(AssetRegistry.createDefaultAssetByName('RollerConveyorConfig'),
          isA<RollerConveyorConfig>());
    });

    test('style stays out of the page JSON — asset_name already decides it',
        () {
      expect(RollerConveyorConfig().toJson().containsKey('style'), isFalse);
      expect(ConveyorConfig().toJson().containsKey('style'), isFalse);
    });
  });

  group('railsActive', () {
    test('follows onRails on a straight belt', () {
      expect(ConveyorConfig(onRails: true).railsActive, isTrue);
      expect(ConveyorConfig().railsActive, isFalse);
      expect(ConveyorConfig(onRails: false).railsActive, isFalse);
    });

    test('stands down for turned belts and the auger renderer', () {
      expect(
          ConveyorConfig(onRails: true, turns: [ConveyorTurnEntry()])
              .railsActive,
          isFalse);
      expect(ConveyorConfig(onRails: true, showAuger: true).railsActive,
          isFalse);
    });
  });

  group('ConveyorPainter with rails', () {
    test('centres an explicit band in the belt area, not the whole box', () {
      const size = Size(240, 100);
      final flat = ConveyorPainter(
        color: Colors.grey,
        batches: const {},
        angle: 0,
        straightBeltWidth: 20,
        paintSize: size,
      );
      final railed = ConveyorPainter(
        color: Colors.grey,
        batches: const {},
        angle: 0,
        straightBeltWidth: 20,
        paintSize: size,
        onRails: true,
      );
      final flatCenter = flat.hitShape()!.getBounds().center.dy;
      final railedCenter = railed.hitShape()!.getBounds().center.dy;
      expect(flatCenter, closeTo(size.height / 2, 0.01));
      final beltArea =
          size.height * (1 - ConveyorPainter.railZoneFraction);
      expect(railedCenter, closeTo(beltArea / 2, 0.01));
    });

    test('band above the rails still takes the tap, the rail zone does not',
        () {
      const size = Size(240, 100);
      final railed = ConveyorPainter(
        color: Colors.grey,
        batches: const {},
        angle: 0,
        straightBeltWidth: 40,
        paintSize: size,
        onRails: true,
      );
      final beltArea =
          size.height * (1 - ConveyorPainter.railZoneFraction);
      expect(railed.hitTest(Offset(120, beltArea / 2)), isTrue);
      expect(railed.hitTest(const Offset(120, 95)), isFalse);
    });
  });
}
