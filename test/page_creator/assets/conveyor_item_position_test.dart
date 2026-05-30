// Conveyor "single tracked item" math test.
//
// Spec: ConveyorConfig grows three fields — itemPositionKey (UMAS-by-name key
// emitting the rear-edge position in mm), conveyorLengthMm, and itemLengthMm.
// When all three are set and the PLC emits a position, the conveyor must
// render ONE Batch (keyed 'item' in the painter's batches map) whose
// normalized [start, end] is just `position / length` and
// `(position + itemLength) / length`.
//
// Per the spec ("Option A — pure math test (preferred)"), we test the math
// directly via a small public helper `itemBatchFor(...)` rather than spinning
// up the widget + a StateMan fake. The widget listener is then a one-liner
// that calls this helper and writes the result into `_batches['item']`.
//
// No clamping: the existing painter already tolerates start<0 / end>1 (see
// `Batch` doc comment in conveyor.dart at line ~1274). Operators see the item
// slide on and off the visual — desired behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

void main() {
  group('itemBatchFor — rear-edge position in mm → normalized Batch', () {
    test('position 0 places item flush with the start of the conveyor', () {
      final batch = itemBatchFor(
        positionMm: 0,
        lengthMm: 1000,
        itemLengthMm: 200,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(0.0, 1e-9));
      expect(batch.end, closeTo(0.2, 1e-9));
    });

    test('position at the centre places item across the middle', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: 1000,
        itemLengthMm: 200,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(0.5, 1e-9));
      expect(batch.end, closeTo(0.7, 1e-9));
    });

    test('position lengthMm - itemLengthMm places item flush with the end', () {
      final batch = itemBatchFor(
        positionMm: 800,
        lengthMm: 1000,
        itemLengthMm: 200,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(0.8, 1e-9));
      expect(batch.end, closeTo(1.0, 1e-9));
    });

    test(
        'position at lengthMm exits the right edge (end > 1, allowed by painter)',
        () {
      final batch = itemBatchFor(
        positionMm: 1000,
        lengthMm: 1000,
        itemLengthMm: 200,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(1.0, 1e-9));
      expect(batch.end, closeTo(1.2, 1e-9));
    });

    test('negative position enters from the left (start < 0, allowed)', () {
      final batch = itemBatchFor(
        positionMm: -100,
        lengthMm: 1000,
        itemLengthMm: 200,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(-0.1, 1e-9));
      expect(batch.end, closeTo(0.1, 1e-9));
    });

    test('null lengthMm returns null (feature disabled)', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: null,
        itemLengthMm: 200,
      );
      expect(batch, isNull);
    });

    test('null itemLengthMm returns null (feature disabled)', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: 1000,
        itemLengthMm: null,
      );
      expect(batch, isNull);
    });

    test('zero lengthMm returns null (avoid divide-by-zero)', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: 0,
        itemLengthMm: 200,
      );
      expect(batch, isNull);
    });

    test('negative lengthMm returns null (nonsensical config)', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: -10,
        itemLengthMm: 200,
      );
      expect(batch, isNull);
    });
  });

  group('itemBatchFor — front edge interpretation', () {
    test('front edge: position 500 / length 10000 / item 500 → '
        'item rear at 0%, front at 5%', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: 10000,
        itemLengthMm: 500,
        edge: ItemPositionEdge.front,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(0.0, 1e-9));
      expect(batch.end, closeTo(0.05, 1e-9));
    });

    test('front edge: position 10000 / length 10000 / item 500 → '
        'item fully on, about to exit', () {
      final batch = itemBatchFor(
        positionMm: 10000,
        lengthMm: 10000,
        itemLengthMm: 500,
        edge: ItemPositionEdge.front,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(0.95, 1e-9));
      expect(batch.end, closeTo(1.0, 1e-9));
    });

    test('front edge: position 0 / length 10000 / item 500 → '
        'item entirely off the back (start < 0)', () {
      final batch = itemBatchFor(
        positionMm: 0,
        lengthMm: 10000,
        itemLengthMm: 500,
        edge: ItemPositionEdge.front,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(-0.05, 1e-9));
      expect(batch.end, closeTo(0.0, 1e-9));
    });

    test('explicit edge=rear matches default behaviour (no regression)', () {
      final batch = itemBatchFor(
        positionMm: 500,
        lengthMm: 1000,
        itemLengthMm: 200,
        edge: ItemPositionEdge.rear,
      );
      expect(batch, isNotNull);
      expect(batch!.start, closeTo(0.5, 1e-9));
      expect(batch.end, closeTo(0.7, 1e-9));
    });

    test('front edge respects null/non-positive length guards', () {
      expect(
        itemBatchFor(
          positionMm: 500,
          lengthMm: null,
          itemLengthMm: 200,
          edge: ItemPositionEdge.front,
        ),
        isNull,
      );
      expect(
        itemBatchFor(
          positionMm: 500,
          lengthMm: 1000,
          itemLengthMm: null,
          edge: ItemPositionEdge.front,
        ),
        isNull,
      );
      expect(
        itemBatchFor(
          positionMm: 500,
          lengthMm: 0,
          itemLengthMm: 200,
          edge: ItemPositionEdge.front,
        ),
        isNull,
      );
    });
  });

  group('ConveyorConfig — item position edge toggle', () {
    test('itemPositionEdge defaults to null (backwards-compatible)', () {
      final config = ConveyorConfig();
      expect(config.itemPositionEdge, isNull);
    });

    test('constructor accepts itemPositionEdge', () {
      final config = ConveyorConfig(
        itemPositionEdge: ItemPositionEdge.front,
      );
      expect(config.itemPositionEdge, ItemPositionEdge.front);
    });

    test('JSON round-trip preserves itemPositionEdge = front', () {
      final original = ConveyorConfig(
        itemPositionKey: 'plant.line1.itemPos',
        conveyorLengthMm: 10000.0,
        itemLengthMm: 500.0,
        itemPositionEdge: ItemPositionEdge.front,
      );
      final json = original.toJson();
      expect(json['itemPositionEdge'], 'front');

      final restored = ConveyorConfig.fromJson(json);
      expect(restored.itemPositionEdge, ItemPositionEdge.front);
    });

    test('JSON round-trip preserves itemPositionEdge = rear', () {
      final original = ConveyorConfig(
        itemPositionEdge: ItemPositionEdge.rear,
      );
      final json = original.toJson();
      expect(json['itemPositionEdge'], 'rear');

      final restored = ConveyorConfig.fromJson(json);
      expect(restored.itemPositionEdge, ItemPositionEdge.rear);
    });

    test('fromJson without itemPositionEdge defaults to null '
        '(REGRESSION GUARD for old saved pages)', () {
      final json = <String, dynamic>{
        'asset_name': 'ConveyorConfig',
        'coordinates': {'x': 0.1, 'y': 0.2, 'angle': 0.0},
        'size': {'width': 0.05, 'height': 0.05},
        'text': null,
        'textPos': null,
        'techDocId': null,
        'plcAssetKey': null,
        'key': null,
        'batchesKey': null,
        'frequencyKey': null,
        'tripKey': null,
        'simulateBatches': null,
        'bidirectional': null,
        'reverseDirection': null,
        'showFrequency': null,
        'showAuger': null,
        'augerRpmKey': null,
        'augerOpenEnd': null,
        'itemPositionKey': null,
        'conveyorLengthMm': null,
        'itemLengthMm': null,
        'gates': <dynamic>[],
      };
      final config = ConveyorConfig.fromJson(json);
      expect(config.itemPositionEdge, isNull);
    });
  });

  group('ConveyorConfig — new item-tracking fields', () {
    test('defaults to null for all three new fields', () {
      final config = ConveyorConfig();
      expect(config.itemPositionKey, isNull);
      expect(config.conveyorLengthMm, isNull);
      expect(config.itemLengthMm, isNull);
    });

    test('constructor accepts the three new fields', () {
      final config = ConveyorConfig(
        itemPositionKey: 'plant.line1.itemPos',
        conveyorLengthMm: 3500.0,
        itemLengthMm: 250.0,
      );
      expect(config.itemPositionKey, 'plant.line1.itemPos');
      expect(config.conveyorLengthMm, 3500.0);
      expect(config.itemLengthMm, 250.0);
    });

    test('JSON round-trip preserves the three new fields', () {
      final original = ConveyorConfig(
        itemPositionKey: 'plant.line1.itemPos',
        conveyorLengthMm: 3500.0,
        itemLengthMm: 250.0,
      );
      final json = original.toJson();
      expect(json['itemPositionKey'], 'plant.line1.itemPos');
      expect(json['conveyorLengthMm'], 3500.0);
      expect(json['itemLengthMm'], 250.0);

      final restored = ConveyorConfig.fromJson(json);
      expect(restored.itemPositionKey, 'plant.line1.itemPos');
      expect(restored.conveyorLengthMm, 3500.0);
      expect(restored.itemLengthMm, 250.0);
    });

    test('fromJson without the new fields defaults to null '
        '(REGRESSION GUARD for old saved pages)', () {
      final json = <String, dynamic>{
        'asset_name': 'ConveyorConfig',
        'coordinates': {'x': 0.1, 'y': 0.2, 'angle': 0.0},
        'size': {'width': 0.05, 'height': 0.05},
        'text': null,
        'textPos': null,
        'techDocId': null,
        'plcAssetKey': null,
        'key': null,
        'batchesKey': null,
        'frequencyKey': null,
        'tripKey': null,
        'simulateBatches': null,
        'bidirectional': null,
        'reverseDirection': null,
        'showFrequency': null,
        'showAuger': null,
        'augerRpmKey': null,
        'augerOpenEnd': null,
        'gates': <dynamic>[],
      };
      final config = ConveyorConfig.fromJson(json);
      expect(config.itemPositionKey, isNull);
      expect(config.conveyorLengthMm, isNull);
      expect(config.itemLengthMm, isNull);
    });
  });
}
