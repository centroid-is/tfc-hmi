import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart' show constAssetName;
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/stop_timeline.dart';

/// The shape a stored asset actually has: every asset carries a position and
/// a size, and fromJson requires both.
Map<String, dynamic> storedAsset(Map<String, dynamic> extra) => {
      constAssetName: 'StopTimelineConfig',
      'coordinates': {'x': 0.5, 'y': 0.5},
      'size': {'width': 0.4, 'height': 0.3},
      ...extra,
    };

void main() {
  group('StopTimelineConfig', () {
    test('defaults to the whole alarm tree', () {
      final config = StopTimelineConfig();
      expect(config.groups, isEmpty);
      expect(config.periodHours, 12);
    });

    test('round trips through JSON', () {
      final config = StopTimelineConfig(
        groups: [
          ['Line 3', 'Multivac'],
          ['Infrastructure'],
        ],
        periodHours: 8,
        headerText: 'Packing hall',
      );
      final back = StopTimelineConfig.fromJson(
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>);

      expect(back.groups, [
        ['Line 3', 'Multivac'],
        ['Infrastructure'],
      ]);
      expect(back.periodHours, 8);
      expect(back.headerText, 'Packing hall');
    });

    test('a config stored before the fields existed still loads', () {
      final back = StopTimelineConfig.fromJson(storedAsset(const {}));
      expect(back.groups, isEmpty);
      expect(back.periodHours, 12);
      expect(back.headerText, isNull);
    });

    test('drops onto the canvas at a size a chart can be read at', () {
      // The BaseAsset default is a 3% square, which for a timeline is a
      // sliver with no room for even the header.
      final preview = StopTimelineConfig.preview();
      expect(preview.size.width, greaterThan(0.2));
      expect(preview.size.height, greaterThan(0.2));
    });

    test('binds to no OPC UA keys — it reads alarms, not tags', () {
      expect(
          StopTimelineConfig(groups: [
            ['Line 3']
          ]).allKeys,
          isEmpty);
    });

    test('is registered so a stored page can rebuild it', () {
      final parsed = AssetRegistry.parse({
        'some_asset': storedAsset({
          'groups': [
            ['Line 3']
          ],
        })
      });
      expect(parsed, hasLength(1));
      expect(parsed.single, isA<StopTimelineConfig>());
      expect((parsed.single as StopTimelineConfig).groups, [
        ['Line 3']
      ]);
    });

    test('a stored page whose asset predates the fields still parses', () {
      final parsed = AssetRegistry.parse({
        'some_asset': storedAsset(const {})
      });
      expect((parsed.single as StopTimelineConfig).groups, isEmpty);
    });

    test('has a preview so the palette can offer it', () {
      final preview = AssetRegistry.createDefaultAsset(StopTimelineConfig);
      expect(preview, isA<StopTimelineConfig>());
      expect(preview.displayName, 'Stop Analysis');
      expect(preview.category, 'Visualization');
    });

    test('is findable by the words an operator would search for', () {
      final preview = AssetRegistry.createDefaultAsset(StopTimelineConfig);
      expect(preview.searchKeywords, contains('downtime'));
      expect(preview.searchKeywords, contains('stops'));
    });
  });
}
