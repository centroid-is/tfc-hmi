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

    test('a position-driven wagon slides along the rail, 0..1 flush to ends',
        () {
      const size = Size(240, 100);
      ConveyorPainter wagonAt(double pos) => ConveyorPainter(
            color: Colors.grey,
            batches: const {},
            angle: 0,
            paintSize: size,
            onRails: true,
            wagonPosition: pos,
            wagonFraction: 0.4,
          );
      final atStart = wagonAt(0).hitShape()!.getBounds();
      final atMid = wagonAt(0.5).hitShape()!.getBounds();
      final atEnd = wagonAt(1).hitShape()!.getBounds();
      expect(atStart.width, closeTo(size.width * 0.4, 0.01));
      expect(atStart.left, closeTo(0, 0.01));
      expect(atMid.center.dx, closeTo(size.width / 2, 0.01));
      expect(atEnd.right, closeTo(size.width, 0.01));
      // The empty rail beside the wagon does not take the tap.
      expect(wagonAt(0).hitTest(const Offset(200, 30)), isFalse);
      expect(wagonAt(0).hitTest(const Offset(40, 30)), isTrue);
    });

    test('a wagon without a position binding still spans the whole box', () {
      const size = Size(240, 100);
      final parked = ConveyorPainter(
        color: Colors.grey,
        batches: const {},
        angle: 0,
        paintSize: size,
        onRails: true,
      );
      // No explicit band and no position: the belt fills the belt area, so
      // there is no separate hit shape and the box stays the tap target.
      expect(parked.hasHitShape, isFalse);
      expect(parked.hitTest(const Offset(200, 30)), isTrue);
    });

    test('position key round-trips and only reads while rails are active',
        () {
      final config = ConveyorConfig(
          onRails: true, positionKey: 'AREA01.WAG01.position',
          wagonLength: 0.3);
      final json = config.toJson();
      final restored = ConveyorConfig.fromJson(json);
      expect(restored.positionKey, 'AREA01.WAG01.position');
      expect(restored.wagonLength, 0.3);
      expect(restored.effectiveWagonLength, 0.3);
      expect(ConveyorConfig().effectiveWagonLength, 0.4);
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
