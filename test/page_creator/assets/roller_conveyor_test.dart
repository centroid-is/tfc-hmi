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

  group('ConveyorPainter with rails (top view)', () {
    const size = Size(240, 100);
    ConveyorPainter wagonAt(double? pos, {double? band}) => ConveyorPainter(
          color: Colors.grey,
          batches: const {},
          angle: 0,
          paintSize: size,
          onRails: true,
          wagonPosition: pos,
          wagonFraction: 0.4,
          straightBeltWidth: band,
        );

    test('a position-driven wagon slides along the rail, 0..1 flush to ends',
        () {
      final atStart = wagonAt(0).hitShape()!.getBounds();
      final atMid = wagonAt(0.5).hitShape()!.getBounds();
      final atEnd = wagonAt(1).hitShape()!.getBounds();
      // The hit shape is the wagon — belt plus chassis bumpers — and at the
      // extremes the bumper, not the belt, sits flush with the box edge.
      expect(atStart.left, closeTo(0, 0.01));
      expect(atMid.center.dx, closeTo(size.width / 2, 0.01));
      expect(atEnd.right, closeTo(size.width, 0.01));
      expect(atStart.width, greaterThan(size.width * 0.4));
      // The empty track beside the wagon does not take the tap.
      expect(wagonAt(0).hitTest(const Offset(200, 50)), isFalse);
      expect(wagonAt(0).hitTest(const Offset(40, 50)), isTrue);
      // The band stays vertically centred — the track runs behind it, not
      // below it.
      expect(atMid.center.dy, closeTo(size.height / 2, 0.01));
    });

    test('a wagon without a position binding parks mid-rail', () {
      final parked = wagonAt(null);
      expect(parked.hasHitShape, isTrue);
      final bounds = parked.hitShape()!.getBounds();
      expect(bounds.center.dx, closeTo(size.width / 2, 0.01));
      expect(parked.hitTest(const Offset(10, 50)), isFalse);
      expect(parked.hitTest(Offset(size.width / 2, 50)), isTrue);
    });

    test('chassis bumpers are wagon but not belt — the motor tap target', () {
      final painter = wagonAt(0.5);
      final belt = painter.beltRect(size);
      final wagon = painter.wagonRect(size);
      expect(wagon.left, lessThan(belt.left));
      expect(wagon.right, greaterThan(belt.right));
      final bumper = Offset((wagon.left + belt.left) / 2, size.height / 2);
      expect(belt.contains(bumper), isFalse);
      expect(wagon.contains(bumper), isTrue);
      expect(painter.hitTest(bumper), isTrue);
    });

    test('an explicit band stays centred in the box with rails', () {
      final railed = wagonAt(0.5, band: 40);
      final bounds = railed.hitShape()!.getBounds();
      expect(bounds.center.dy, closeTo(size.height / 2, 0.01));
      expect(bounds.height, closeTo(40, 0.01));
    });

    test('wagon keys round-trip through JSON', () {
      final config = ConveyorConfig(
          onRails: true,
          positionKey: 'AREA01.WAG01.position',
          wagonMotorKey: 'AREA01.WAG01.motor',
          wagonLength: 0.3);
      final restored = ConveyorConfig.fromJson(config.toJson());
      expect(restored.positionKey, 'AREA01.WAG01.position');
      expect(restored.wagonMotorKey, 'AREA01.WAG01.motor');
      expect(restored.wagonLength, 0.3);
      expect(restored.effectiveWagonLength, 0.3);
      expect(ConveyorConfig().effectiveWagonLength, 0.4);
    });
  });
}
