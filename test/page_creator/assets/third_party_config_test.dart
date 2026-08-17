import 'dart:collection' show LinkedHashMap;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/ratio_number.dart';
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

    test('stopped defaults to grey — red is reserved for faults', () {
      final config = ThirdPartyEquipmentConfig();
      expect(config.stoppedColor.toARGB32(), Colors.grey.toARGB32());
      expect(config.runningColor.toARGB32(), Colors.green.toARGB32());
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

    test('statusKey round-trips and is discoverable through allKeys', () {
      final original = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.speedBatcher,
        statusKey: 'SB1',
      );

      final restored = ThirdPartyEquipmentConfig.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(restored.statusKey, 'SB1');
      // Ends in "Key", so the BaseAsset introspection must pick it up — the
      // key-discovery UI would otherwise never offer the handshake struct.
      expect(restored.allKeys, contains('SB1'));
    });

    test('legacy JSON without statusKey loads with it empty', () {
      final json = jsonDecode(jsonEncode(
              ThirdPartyEquipmentConfig(kind: ThirdPartyEquipmentKind.speedBatcher)
                  .toJson()))
          as Map<String, dynamic>;
      json.remove('statusKey');

      expect(ThirdPartyEquipmentConfig.fromJson(json).statusKey, '');
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

    test('builds 2 conveyors, 2 weights and 2 accept ratios', () {
      // Exactly what the station is: each checkweigher is a conveyor, with a
      // weight and an accept rate on it.
      final children = scaffold();
      expect(children, hasLength(6));
      expect(children.where((e) => e.child is ConveyorConfig), hasLength(2));
      expect(children.where((e) => e.child is NumberConfig), hasLength(2));
      expect(children.where((e) => e.child is RatioNumberConfig), hasLength(2));
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
                e.child is! ConveyorConfig &&
                (e.offsetY - belt.offsetY).abs() < 0.02)
            .toList();
        expect(row, hasLength(2),
            reason: 'Each weigh belt gets exactly two readouts on its row.');

        final left = row.reduce((a, b) => a.offsetX < b.offsetX ? a : b);
        final right = row.reduce((a, b) => a.offsetX > b.offsetX ? a : b);

        expect(left.offsetX, lessThan(belt.offsetX));
        expect(right.offsetX, greaterThan(belt.offsetX));
        expect(left.child, isA<RatioNumberConfig>(),
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
      for (final ratio in scaffold()
          .map((e) => e.child)
          .whereType<RatioNumberConfig>()) {
        expect(ratio.key1, isEmpty);
        expect(ratio.key2, isEmpty);
      }
    });

    test('the station factory builds a ready-to-wire SpeedBatcher', () {
      // A SpeedBatcher without its belts and readouts is not a useful asset,
      // so it must not be possible to get one by accident.
      final config = ThirdPartyEquipmentConfig.speedBatcherStation();
      expect(config.kind, ThirdPartyEquipmentKind.speedBatcher);
      expect(config.children.where((e) => e.child is ConveyorConfig),
          hasLength(2));
      expect(config.children.where((e) => e.child is NumberConfig),
          hasLength(2));
      expect(config.children.where((e) => e.child is RatioNumberConfig),
          hasLength(2));
    });

    test('the whole station survives a JSON round-trip', () {
      final config = ThirdPartyEquipmentConfig.speedBatcherStation(
          acceptWindowMinutes: 20);
      final restored = ThirdPartyEquipmentConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);

      expect(restored.children, hasLength(6));
      expect(
          restored.children
              .map((e) => e.child)
              .whereType<RatioNumberConfig>()
              .first
              .sinceMinutes,
          const Duration(minutes: 20));
    });

    test('readouts are marked upright, the belts are not', () {
      for (final entry in scaffold()) {
        if (entry.child is ConveyorConfig) {
          expect(entry.keepUpright, isFalse,
              reason: 'Machinery must turn with the machine it belongs to.');
        } else {
          expect(entry.keepUpright, isTrue,
              reason: 'A weight or ratio you have to tilt your head to read '
                  'is useless.');
        }
      }
    });

    test('the accept ratio carries its averaging window natively', () {
      // RatioNumberConfig models accepted-over-total across a rolling window,
      // so the window is a real field rather than text smuggled into a units
      // string — it cannot be read as an instantaneous figure.
      RatioNumberConfig ratioFor(int minutes) =>
          buildSpeedBatcherStationChildren(acceptWindowMinutes: minutes)
              .map((e) => e.child)
              .whereType<RatioNumberConfig>()
              .first;

      expect(ratioFor(30).sinceMinutes, const Duration(minutes: 30));
      expect(ratioFor(15).sinceMinutes, const Duration(minutes: 15));
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
        strapMachines: 2,
      ).toJson();
      expect(ThirdPartyEquipmentConfig.fromJson(json).strapMachines, 2);
    });

    test('the painter draws one arch per head', () {
      for (final heads in const [1, 2, 3]) {
        expect(StrappingLinePainter.machineCentresFor(heads), hasLength(heads));
      }
    });

    test('arch centres stay inside the machine and in order', () {
      for (final heads in const [1, 2, 3]) {
        final centres = StrappingLinePainter.machineCentresFor(heads);
        expect(centres.first, greaterThan(0.05));
        expect(centres.last, lessThan(0.95));
        for (int i = 1; i < centres.length; i++) {
          expect(centres[i], greaterThan(centres[i - 1]));
        }
      }
    });

    test('label and footprint follow the strapper count', () {
      const kind = ThirdPartyEquipmentKind.strappingLine;
      expect(kind.labelFor(strapMachines: 1), contains('1 x Strapex'));
      expect(kind.labelFor(strapMachines: 3), contains('3 x Strapex'));
      // Only the 3-strapper length is published; the others must say so.
      expect(kind.footprint(strapMachines: 3), isNot(contains('estimated')));
      expect(kind.footprint(strapMachines: 2), contains('estimated'));
      expect(kind.footprint(strapMachines: 2), contains('2 strappers'));
    });

    test('fewer strappers means a shorter line', () {
      const kind = ThirdPartyEquipmentKind.strappingLine;
      expect(kind.aspectRatio(strapMachines: 1),
          lessThan(kind.aspectRatio(strapMachines: 2)));
      expect(kind.aspectRatio(strapMachines: 2),
          lessThan(kind.aspectRatio(strapMachines: 3)));
    });

    test('an out-of-range head count is clamped, not asserted on', () {
      // Persisted pages are not trusted input.
      expect(
          () => thirdPartyPainterFor(ThirdPartyEquipmentKind.strappingLine,
              color: Colors.black, strokeWidth: 2, strapMachines: 99),
          returnsNormally);
      expect(
          () => thirdPartyPainterFor(ThirdPartyEquipmentKind.strappingLine,
              color: Colors.black, strokeWidth: 2, strapMachines: 0),
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
        // Two kinds are portrait (SpeedBatcher, box erector) and the Multivac
        // is 5.4:1, so the band has to be wide — it is only guarding against
        // a degenerate or absurd value.
        expect(kind.aspectRatio(), greaterThan(0.2));
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

  group('SpeedBatcher status bits', () {
    test('the five diodes match the retired flat asset, in the same order',
        () {
      // Same members, labels and colours as speedbatcher.dart, so the pane
      // reads identically to the widget the operators already know.
      expect(speedBatcherStatusBits.map((b) => b.member), [
        'p_stat_Running',
        'p_stat_Cleaning',
        'p_stat_BatchReady',
        'p_stat_DropOk',
        'p_stat_Dropped',
      ]);
      for (final bit in speedBatcherStatusBits) {
        expect(bit.onColor.toARGB32(),
            (bit.member == 'p_stat_Cleaning' ? Colors.blue : Colors.green)
                .toARGB32());
      }
    });

    test('a present bit reads through, true and false alike', () {
      final status = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
        'p_stat_Running': true,
        'p_stat_Cleaning': false,
      }));
      expect(speedBatcherStatusBitOf(status, 'p_stat_Running'), isTrue);
      expect(speedBatcherStatusBitOf(status, 'p_stat_Cleaning'), isFalse);
    });

    test('a missing member degrades to unknown instead of throwing', () {
      // Three of the five bits have never been confirmed against the live
      // PLC, and `DynamicValue.operator[]` throws on a missing member — a
      // struct without the bit must give the grey `!`, not take the pane
      // down.
      final status = DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from({
        'p_stat_Running': true,
      }));
      expect(speedBatcherStatusBitOf(status, 'p_stat_BatchReady'), isNull);
    });

    test('no struct at all — or a non-struct value — is unknown', () {
      expect(speedBatcherStatusBitOf(null, 'p_stat_Running'), isNull);
      expect(
          speedBatcherStatusBitOf(
              DynamicValue(value: true), 'p_stat_Running'),
          isNull);
    });
  });
}
