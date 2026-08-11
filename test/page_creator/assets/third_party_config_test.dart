import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/sensor.dart';
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

  group('Children inside the box', () {
    test('a conveyor child survives the round-trip with its position', () {
      final original = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        runKey: 'ST201.SB01.Running',
        children: [
          ThirdPartyChildEntry(
            id: 'lane-infeed',
            offsetX: 0.245,
            offsetY: 0.65,
            child: ConveyorConfig.preview(),
          ),
        ],
      );

      final restored = ThirdPartyEquipmentConfig.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(restored.children, hasLength(1));
      final entry = restored.children.single;
      expect(entry.id, 'lane-infeed');
      expect(entry.offsetX, closeTo(0.245, 1e-9));
      expect(entry.offsetY, closeTo(0.65, 1e-9));
      expect(entry.child, isA<ConveyorConfig>());
    });

    test('heterogeneous children round-trip and keep their order', () {
      final original = ThirdPartyEquipmentConfig(children: [
        ThirdPartyChildEntry(child: ConveyorConfig.preview()),
        ThirdPartyChildEntry(child: SensorConfig.preview()),
      ]);

      final restored = ThirdPartyEquipmentConfig.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(restored.children.map((e) => e.child.runtimeType),
          [ConveyorConfig, SensorConfig]);
    });

    test('an unregistered child asset_name fails loudly', () {
      // Silently dropping the child would let a saved page lose the conveyor
      // an operator depends on, with no error anywhere.
      final json = ThirdPartyEquipmentConfig(
        children: [ThirdPartyChildEntry(child: SensorConfig.preview())],
      ).toJson();
      (json['children'] as List).first['child']['asset_name'] = 'NopeConfig';

      expect(() => ThirdPartyEquipmentConfig.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('child keys surface through allKeys alongside the run key', () {
      final conveyor = ConveyorConfig.preview();
      final config = ThirdPartyEquipmentConfig(
        runKey: 'ST201.SB01.Running',
        children: [ThirdPartyChildEntry(child: conveyor)],
      );

      expect(config.allKeys, contains('ST201.SB01.Running'));
      for (final key in conveyor.allKeys) {
        expect(config.allKeys, contains(key),
            reason: 'A conveyor placed inside the box must not be invisible '
                'to key discovery.');
      }
    });

    test('entry ids are unique even when created back to back', () {
      final ids = {
        for (int i = 0; i < 50; i++)
          ThirdPartyChildEntry(child: SensorConfig.preview()).id
      };
      expect(ids, hasLength(50));
    });

    test('children default to empty, not null, on legacy JSON', () {
      final json = ThirdPartyEquipmentConfig.preview().toJson();
      json.remove('children');
      expect(ThirdPartyEquipmentConfig.fromJson(json).children, isEmpty);
    });
  });

  group('SpeedBatcher station scaffold', () {
    List<ThirdPartyChildEntry> scaffold() =>
        buildSpeedBatcherStationChildren();

    test('builds a conveyor and two readouts per checkweigher', () {
      final children = scaffold();
      expect(children.whereType<ThirdPartyChildEntry>(), hasLength(6));
      expect(children.where((e) => e.child is ConveyorConfig), hasLength(2));
      expect(children.where((e) => e.child is NumberConfig), hasLength(4));
    });

    test('the weigh-belt conveyors are bidirectional', () {
      // These belts get jogged both ways. A one-way belt would draw an arrow
      // that contradicts what the operator can see happening.
      for (final conveyor in scaffold()
          .map((e) => e.child)
          .whereType<ConveyorConfig>()) {
        expect(conveyor.bidirectional, isTrue);
        expect(conveyor.reverseDirection ?? false, isFalse,
            reason: 'Arrow direction comes from the sign of the live '
                'frequency, not a static flag.');
      }
    });

    test('weight sits right of the belt, accept rate left', () {
      final children = scaffold();
      final belts = children.where((e) => e.child is ConveyorConfig).toList();

      for (final belt in belts) {
        final row = children
            .where((e) =>
                e.child is NumberConfig && (e.offsetY - belt.offsetY).abs() < 0.02)
            .toList();
        expect(row, hasLength(2),
            reason: 'Each weigh belt gets exactly two readouts on its row.');

        final left = row.reduce((a, b) => a.offsetX < b.offsetX ? a : b);
        final right = row.reduce((a, b) => a.offsetX > b.offsetX ? a : b);

        expect(left.offsetX, lessThan(belt.offsetX));
        expect(right.offsetX, greaterThan(belt.offsetX));
        expect((left.child as NumberConfig).units, startsWith('%'),
            reason: 'Accept rate goes on the left.');
        expect((right.child as NumberConfig).units, 'g',
            reason: 'Weight goes on the right.');
      }
    });

    test('every scaffolded child lands inside the machine area', () {
      for (final entry in scaffold()) {
        expect(entry.offsetX, inInclusiveRange(0.0, 1.0));
        expect(entry.offsetY, inInclusiveRange(0.0, 1.0));
      }
    });

    test('the belts land on the painted weigh-belt beds', () {
      // The scaffold and the painter must agree on where the belt goes, or a
      // live conveyor floats off its bed.
      final belts = scaffold()
          .where((e) => e.child is ConveyorConfig)
          .map((e) => Offset(e.offsetX, e.offsetY))
          .toList();
      final decks = [
        SpeedBatcherPainter.deckOf(SpeedBatcherPainter.checkweigher1Frame),
        SpeedBatcherPainter.deckOf(SpeedBatcherPainter.checkweigher2Frame),
      ].map((r) => r.center).toList();

      for (final deck in decks) {
        expect(belts.any((b) => (b - deck).distance < 1e-9), isTrue,
            reason: 'A belt must sit at $deck.');
      }
    });

    test('readouts carry no graph, and no key to start with', () {
      for (final number in scaffold()
          .map((e) => e.child)
          .whereType<NumberConfig>()) {
        expect(number.key, isEmpty,
            reason: 'The operator points each readout at its own tag.');
        expect(number.graphConfig, isNull,
            reason: 'A tap-through to a trend from a nested child is a '
                'surprise.');
      }
    });

    test('readouts are marked upright, the belts are not', () {
      for (final entry in scaffold()) {
        if (entry.child is NumberConfig) {
          expect(entry.keepUpright, isTrue,
              reason: 'A weight you have to tilt your head to read is '
                  'useless.');
        } else {
          expect(entry.keepUpright, isFalse,
              reason: 'Machinery must turn with the machine it belongs to.');
        }
      }
    });

    test('the accept readout carries its averaging window in the units', () {
      // A bare "97.3 %" beside a running belt reads as "this pack" when it is
      // really the last half hour.
      final accept = buildSpeedBatcherStationChildren(acceptWindowMinutes: 30)
          .map((e) => e.child)
          .whereType<NumberConfig>()
          .firstWhere((n) => n.units!.contains('%'));
      expect(accept.units, '% 30m');

      final custom = buildSpeedBatcherStationChildren(acceptWindowMinutes: 15)
          .map((e) => e.child)
          .whereType<NumberConfig>()
          .firstWhere((n) => n.units!.contains('%'));
      expect(custom.units, '% 15m');
    });

    test('load cells sit clear of the belt centre', () {
      // The live Conveyor draws its run-direction arrow in the middle of the
      // belt; a painted block there sits right under it.
      final deck =
          SpeedBatcherPainter.deckOf(SpeedBatcherPainter.checkweigher1Frame);
      for (final x in [deck.left + 0.05, deck.right - 0.05]) {
        expect((x - deck.center.dx).abs(), greaterThan(0.1),
            reason: 'Load cell marks must not land under the arrow.');
      }
    });

    test('keepUpright and the text angle round-trip', () {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        childTextAngle: 15,
        acceptWindowMinutes: 45,
        children: [
          ThirdPartyChildEntry(
              keepUpright: true, child: NumberConfig(key: 'w')),
        ],
      );
      final restored = ThirdPartyEquipmentConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);

      expect(restored.childTextAngle, 15);
      expect(restored.acceptWindowMinutes, 45);
      expect(restored.children.single.keepUpright, isTrue);
    });

    test('legacy JSON without the new fields still loads', () {
      // Encode for real before mutating: a child's `toJson()` can leave
      // nested objects (Coordinates, RelativeSize) as live instances rather
      // than maps, and only jsonEncode flattens them. This mirrors the page
      // save path, which always goes through JSON.
      final json = jsonDecode(jsonEncode(ThirdPartyEquipmentConfig(
        children: [ThirdPartyChildEntry(child: NumberConfig(key: 'w'))],
      ).toJson())) as Map<String, dynamic>;

      json.remove('childTextAngle');
      json.remove('acceptWindowMinutes');
      (json['children'] as List).first.remove('keepUpright');

      final restored = ThirdPartyEquipmentConfig.fromJson(json);
      expect(restored.childTextAngle, 0);
      expect(restored.acceptWindowMinutes, 30);
      expect(restored.children.single.keepUpright, isFalse);
    });

    test('the scaffold survives a JSON round-trip intact', () {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        children: buildSpeedBatcherStationChildren(),
      );
      final restored = ThirdPartyEquipmentConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);

      expect(restored.children, hasLength(6));
      expect(restored.children.where((e) => e.child is ConveyorConfig),
          hasLength(2));
      for (final conveyor in restored.children
          .map((e) => e.child)
          .whereType<ConveyorConfig>()) {
        expect(conveyor.bidirectional, isTrue);
      }
    });
  });

  group('Strapping heads', () {
    test('head count round-trips', () {
      final json = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.strappingLine,
        strapHeads: 2,
      ).toJson();
      expect(ThirdPartyEquipmentConfig.fromJson(json).strapHeads, 2);
    });

    test('the painter draws one arch per head', () {
      for (final heads in const [1, 2, 3]) {
        expect(StrappingLinePainter.archCentresFor(heads), hasLength(heads));
      }
    });

    test('arch centres stay inside the machine and in order', () {
      for (final heads in const [1, 2, 3]) {
        final centres = StrappingLinePainter.archCentresFor(heads);
        expect(centres.first, greaterThan(0.05));
        expect(centres.last, lessThan(0.95));
        for (int i = 1; i < centres.length; i++) {
          expect(centres[i], greaterThan(centres[i - 1]));
        }
      }
    });

    test('label and footprint follow the head count into a real model number',
        () {
      const kind = ThirdPartyEquipmentKind.strappingLine;
      expect(kind.labelFor(strapHeads: 1), contains('SL-15-1'));
      expect(kind.labelFor(strapHeads: 3), contains('SL-15-3'));
      // Only the SL-15-3 length is published; the others must say so.
      expect(kind.footprint(strapHeads: 3), isNot(contains('estimated')));
      expect(kind.footprint(strapHeads: 2), contains('estimated'));
    });

    test('fewer heads means a shorter machine', () {
      const kind = ThirdPartyEquipmentKind.strappingLine;
      expect(kind.aspectRatio(strapHeads: 1),
          lessThan(kind.aspectRatio(strapHeads: 2)));
      expect(kind.aspectRatio(strapHeads: 2),
          lessThan(kind.aspectRatio(strapHeads: 3)));
    });

    test('an out-of-range head count is clamped, not asserted on', () {
      // Persisted pages are not trusted input.
      expect(
          () => thirdPartyPainterFor(ThirdPartyEquipmentKind.strappingLine,
              color: Colors.black, strokeWidth: 2, strapHeads: 99),
          returnsNormally);
      expect(
          () => thirdPartyPainterFor(ThirdPartyEquipmentKind.strappingLine,
              color: Colors.black, strokeWidth: 2, strapHeads: 0),
          returnsNormally);
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
        expect(kind.footprint(), isNotEmpty);
        expect(kind.aspectRatio(), greaterThan(0.5));
        expect(kind.aspectRatio(), lessThan(10.0));
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
