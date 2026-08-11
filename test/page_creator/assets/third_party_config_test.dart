import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/third_party.dart';
import 'package:tfc/page_creator/assets/third_party_painter.dart';

void main() {
  group('ThirdPartyEquipmentConfig defaults', () {
    test('preview is a usable, wide default', () {
      final config = ThirdPartyEquipmentConfig.preview();

      expect(config.kind, ThirdPartyEquipmentKind.multivac);
      expect(config.runKey, '');
      expect(config.invertRunPolarity, isFalse);
      expect(config.textPos, TextPos.below);
      // BaseAsset defaults to 3% x 3%, which would squash a plan view into an
      // unreadable stamp. The constructor must widen it.
      expect(config.size.width, greaterThan(0.05));
      expect(config.size.height, greaterThan(0.05));
    });

    test('displayName and category place it in its own palette group', () {
      final config = ThirdPartyEquipmentConfig.preview();
      expect(config.displayName, '3rd Party Equipment');
      expect(config.category, 'Third Party');
    });
  });

  group('JSON round-trip', () {
    test('every field survives toJson -> fromJson', () {
      final original = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.strappingLine,
        runKey: 'ST301.PK01.STRAP01.Running',
        invertRunPolarity: true,
        runningColor: Colors.lime,
        stoppedColor: Colors.orange,
        outlineColor: Colors.indigo,
        strokeWidth: 3.5,
        tag: 'STRAP-01',
        notes: 'Afak SL-15-3, three Strapex heads.',
      )
        ..coordinates = Coordinates(x: 0.25, y: 0.5, angle: 90)
        ..size = const RelativeSize(width: 0.2, height: 0.14);

      final restored =
          ThirdPartyEquipmentConfig.fromJson(original.toJson());

      expect(restored.kind, ThirdPartyEquipmentKind.strappingLine);
      expect(restored.runKey, 'ST301.PK01.STRAP01.Running');
      expect(restored.invertRunPolarity, isTrue);
      expect(restored.runningColor.toARGB32(), Colors.lime.toARGB32());
      expect(restored.stoppedColor.toARGB32(), Colors.orange.toARGB32());
      expect(restored.outlineColor.toARGB32(), Colors.indigo.toARGB32());
      expect(restored.strokeWidth, 3.5);
      expect(restored.tag, 'STRAP-01');
      expect(restored.notes, 'Afak SL-15-3, three Strapex heads.');
      expect(restored.coordinates.x, 0.25);
      expect(restored.coordinates.angle, 90);
      expect(restored.size.width, 0.2);
      expect(restored.size.height, 0.14);
    });

    test('unknown kind in persisted JSON falls back instead of throwing', () {
      final json = ThirdPartyEquipmentConfig.preview().toJson();
      json['kind'] = 'someFutureMachine';

      expect(ThirdPartyEquipmentConfig.fromJson(json).kind,
          ThirdPartyEquipmentKind.multivac);
    });

    test('text aliases tag, and a null text does not clobber a legacy tag', () {
      final config = ThirdPartyEquipmentConfig(tag: 'MV-01');
      expect(config.text, 'MV-01');

      // The generated fromJson assigns `..text =` AFTER the constructor has
      // set `tag`. Legacy pages persist `text: null` alongside a real `tag`;
      // adopting the null would silently erase the operator's label.
      config.text = null;
      expect(config.tag, 'MV-01');

      config.text = 'MV-02';
      expect(config.tag, 'MV-02');
    });

    test('runKey is discoverable through BaseAsset.allKeys', () {
      final config = ThirdPartyEquipmentConfig(runKey: 'ST301.MV01.Running');
      expect(config.allKeys, contains('ST301.MV01.Running'));
    });
  });

  group('Registry wiring', () {
    test('parse round-trips the asset out of a page JSON blob', () {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        runKey: 'ST201.SB01.Running',
      );
      final page = {
        'assets': [config.toJson()]
      };

      final parsed = AssetRegistry.parse(page);
      expect(parsed, hasLength(1));
      expect(parsed.single, isA<ThirdPartyEquipmentConfig>());
      expect((parsed.single as ThirdPartyEquipmentConfig).kind,
          ThirdPartyEquipmentKind.speedBatcher);
    });

    test('the asset palette can create one by name', () {
      final asset =
          AssetRegistry.createDefaultAssetByName('ThirdPartyEquipmentConfig');
      expect(asset, isA<ThirdPartyEquipmentConfig>());
    });
  });

  group('Run polarity', () {
    test('normal polarity passes the raw bool through', () {
      expect(
          thirdPartyIsRunning(rawBool: true, invertRunPolarity: false), isTrue);
      expect(thirdPartyIsRunning(rawBool: false, invertRunPolarity: false),
          isFalse);
    });

    test('inverted polarity flips it, for a stopped-contact machine', () {
      expect(
          thirdPartyIsRunning(rawBool: true, invertRunPolarity: true), isFalse);
      expect(
          thirdPartyIsRunning(rawBool: false, invertRunPolarity: true), isTrue);
    });
  });

  group('Painter dispatch', () {
    test('every kind maps to its own painter type', () {
      final painters = <Type>{};
      for (final kind in ThirdPartyEquipmentKind.values) {
        final painter =
            thirdPartyPainterFor(kind, color: Colors.black, strokeWidth: 2);
        painters.add(painter.runtimeType);
      }
      // One painter class per kind — no shared painter switching on `kind`
      // internally, which is what keeps painter state from leaking when the
      // operator changes the kind in the editor.
      expect(painters, hasLength(ThirdPartyEquipmentKind.values.length));
    });

    test('shouldRepaint is true across kinds and across colour changes', () {
      final multivac = thirdPartyPainterFor(ThirdPartyEquipmentKind.multivac,
          color: Colors.black, strokeWidth: 2);
      final erector = thirdPartyPainterFor(ThirdPartyEquipmentKind.boxErector,
          color: Colors.black, strokeWidth: 2);
      final recoloured = thirdPartyPainterFor(
          ThirdPartyEquipmentKind.multivac,
          color: Colors.red,
          strokeWidth: 2);
      final identical = thirdPartyPainterFor(ThirdPartyEquipmentKind.multivac,
          color: Colors.black, strokeWidth: 2);

      expect(multivac.shouldRepaint(erector), isTrue);
      expect(multivac.shouldRepaint(recoloured), isTrue);
      expect(multivac.shouldRepaint(identical), isFalse);
    });
  });

  group('Layout geometry', () {
    test('the LED header never overlaps the machine area', () {
      for (final size in const [
        Size(400, 80),
        Size(300, 260),
        Size(900, 166),
        Size(120, 90),
      ]) {
        final boundary = thirdPartyBoundaryRect(size);
        final machine = thirdPartyMachineArea(size);
        final ledBottom = boundary.top +
            thirdPartyLedInset(size) +
            thirdPartyLedDiameter(size);

        expect(machine.top, greaterThanOrEqualTo(ledBottom),
            reason: 'LED must sit in a header strip above the drawing '
                'at $size.');
      }
    });

    test('a degenerate rect falls back to the boundary instead of inverting',
        () {
      const tiny = Size(20, 14);
      final area = thirdPartyMachineArea(tiny);
      expect(area.width, greaterThan(0));
      expect(area.height, greaterThan(0));
    });

    test('painting a zero-sized canvas is a no-op, not a crash', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = thirdPartyPainterFor(ThirdPartyEquipmentKind.multivac,
          color: Colors.black, strokeWidth: 2);
      expect(() => painter.paint(canvas, Size.zero), returnsNormally);
      recorder.endRecording().dispose();
    });
  });

  group('Kind metadata', () {
    test('every kind has a label, a footprint and a sane aspect ratio', () {
      for (final kind in ThirdPartyEquipmentKind.values) {
        expect(kind.label, isNotEmpty);
        expect(kind.footprint, isNotEmpty);
        expect(kind.aspectRatio, greaterThan(0.5));
        expect(kind.aspectRatio, lessThan(10.0));
      }
    });

    test('the box erector still carries its unresolved-product-name marker',
        () {
      // Deliberate: the make/model has not been identified yet. When it is,
      // this test should be updated along with the label and the painter.
      expect(ThirdPartyEquipmentKind.boxErector.label, contains('TODO'));
    });
  });
}
