/// `GraphAsset` re-runs every history query when its data signature changes,
/// so what the signature ignores decides what an operator sees.
///
/// The bug this locks down: the signature used to be "did the widget rebuild
/// at all", which made moving or resizing a chart — in the page editor or in
/// the floating dialog it opens into — tear the chart down and refetch it,
/// flashing "loading" for the whole gesture.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/graph.dart';
import 'package:tfc/widgets/graph.dart' show GraphType;

GraphAssetConfig config() => GraphAssetConfig(
      graphType: GraphType.timeseries,
      primarySeries: [
        GraphSeriesConfig(key: 'CN01.MOT01.CURRENT', label: 'Current'),
      ],
      timeWindowMinutes: const Duration(minutes: 10),
    );

void main() {
  group('graphDataSignature', () {
    test('ignores the asset being moved', () {
      final c = config();
      final before = graphDataSignature(c);

      c.coordinates = Coordinates(x: 0.42, y: 0.77);

      expect(graphDataSignature(c), before);
    });

    test('ignores the asset being resized', () {
      final c = config();
      final before = graphDataSignature(c);

      c.size = const RelativeSize(width: 0.6, height: 0.4);

      expect(graphDataSignature(c), before);
    });

    test('two configs built from the same values agree', () {
      // The Beckhoff pane rebuilds its GraphAssetConfig from scratch on every
      // build, so equal-by-value has to mean equal-by-signature or that chart
      // would refetch forever.
      expect(graphDataSignature(config()), graphDataSignature(config()));
    });

    test('a changed series key is a different chart', () {
      final c = config();
      final before = graphDataSignature(c);

      c.primarySeries = [
        GraphSeriesConfig(key: 'CN02.MOT01.CURRENT', label: 'Current'),
      ];

      expect(graphDataSignature(c), isNot(before));
    });

    test('an added series is a different chart', () {
      final c = config();
      final before = graphDataSignature(c);

      c.secondarySeries = [
        GraphSeriesConfig(key: 'CN01.MOT01.FREQUENCY', label: 'Frequency'),
      ];

      expect(graphDataSignature(c), isNot(before));
    });

    test('a changed time window is a different query', () {
      final c = config();
      final before = graphDataSignature(c);

      c.timeWindowMinutes = const Duration(minutes: 60);

      expect(graphDataSignature(c), isNot(before));
    });

    test('a changed aggregation is a different query', () {
      final c = config();
      final before = graphDataSignature(c);

      c.aggregation = Aggregation.minMaxLast;

      expect(graphDataSignature(c), isNot(before));
    });

    test('a substitution re-pointing the key is a different chart', () {
      // Same config, different table behind it: this is the case the old
      // unconditional re-init existed to cover, and it still has to work.
      final c = GraphAssetConfig(
        graphType: GraphType.timeseries,
        primarySeries: [
          GraphSeriesConfig(key: r'$line.MOT01.CURRENT', label: 'Current'),
        ],
      );

      final one = graphDataSignature(c,
          resolveKey: (k) => k.replaceAll(r'$line', 'CN01'));
      final two = graphDataSignature(c,
          resolveKey: (k) => k.replaceAll(r'$line', 'CN02'));

      expect(one, isNot(two));
    });
  });
}
