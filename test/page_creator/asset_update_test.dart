import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/asset_update.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/registry.dart';

Asset makeAsset(String type, {String? key, String? text}) {
  final asset = AssetRegistry.createDefaultAssetByName(type)!;
  if (key != null) (asset as dynamic).key = key;
  if (text != null) asset.text = text;
  return asset;
}

Map<String, dynamic> proposal({
  required String assetType,
  String? title,
  String? key,
  String? childId,
  required Map<String, dynamic> patch,
}) =>
    {
      '_proposal_type': 'asset_update',
      'page_key': '/',
      'target': {
        'asset_type': assetType,
        if (title != null) 'title': title,
        if (key != null) 'key': key,
        if (childId != null) 'child_id': childId,
      },
      'patch': patch,
    };

void main() {
  test('unique type match patches the asset and preserves position', () {
    final assets = [
      makeAsset('ButtonConfig'),
      makeAsset('LEDConfig', key: 'old.key', text: 'Pump'),
    ];

    final result = applyAssetUpdate(
      assets,
      proposal(assetType: 'LEDConfig', patch: {'key': 'pump3.running'}),
    );

    expect(result.error, isNull);
    expect(result.index, 1);
    expect((result.updated! as dynamic).key, 'pump3.running');
    expect(result.updated!.text, 'Pump', reason: 'unpatched fields survive');
    // The input list itself is not mutated.
    expect((assets[1] as dynamic).key, 'old.key');
  });

  test('two candidates fail; title narrows to one', () {
    final assets = [
      makeAsset('LEDConfig', key: 'a', text: 'Infeed'),
      makeAsset('LEDConfig', key: 'b', text: 'Outfeed'),
    ];

    final ambiguous = applyAssetUpdate(
      assets,
      proposal(assetType: 'LEDConfig', patch: {'key': 'x'}),
    );
    expect(ambiguous.updated, isNull);
    expect(ambiguous.error, contains('2 assets match'));

    final narrowed = applyAssetUpdate(
      assets,
      proposal(assetType: 'LEDConfig', title: 'Outfeed', patch: {'key': 'x'}),
    );
    expect(narrowed.error, isNull);
    expect(narrowed.index, 1);
    expect((narrowed.updated! as dynamic).key, 'x');
  });

  test('key narrows the match', () {
    final assets = [
      makeAsset('LEDConfig', key: 'a'),
      makeAsset('LEDConfig', key: 'b'),
    ];

    final result = applyAssetUpdate(
      assets,
      proposal(assetType: 'LEDConfig', key: 'b', patch: {'key': 'c'}),
    );
    expect(result.error, isNull);
    expect(result.index, 1);
    expect((result.updated! as dynamic).key, 'c');
  });

  test('no match reports the selector', () {
    final assets = [makeAsset('ButtonConfig')];

    final result = applyAssetUpdate(
      assets,
      proposal(
          assetType: 'LEDConfig', title: 'Pump', patch: {'key': 'x'}),
    );
    expect(result.updated, isNull);
    expect(result.error, contains('no asset matches'));
    expect(result.error, contains('LEDConfig'));
    expect(result.error, contains('Pump'));
  });

  test('patch cannot switch the asset type', () {
    final assets = [makeAsset('LEDConfig', key: 'a')];

    final result = applyAssetUpdate(
      assets,
      proposal(assetType: 'LEDConfig', patch: {
        constAssetName: 'ButtonConfig',
        'key': 'b',
      }),
    );
    expect(result.error, isNull);
    expect(result.updated!.runtimeType.toString(), 'LEDConfig');
    expect((result.updated! as dynamic).key, 'b');
  });

  group('child_id targeting', () {
    Asset thirdPartyWithChild(String childId) {
      final tp =
          AssetRegistry.createDefaultAssetByName('ThirdPartyEquipmentConfig')!;
      final sensor = AssetRegistry.createDefaultAssetByName('SensorConfig')!;
      final json = tp.toJson();
      json['children'] = [
        {
          'id': childId,
          'offsetX': 0.5,
          'offsetY': 0.5,
          'child': sensor.toJson(),
        }
      ];
      return AssetRegistry.parse({'a': json}).single;
    }

    test('patch lands on the embedded child asset', () {
      final assets = [thirdPartyWithChild('c1')];

      final result = applyAssetUpdate(
        assets,
        proposal(
          assetType: 'ThirdPartyEquipmentConfig',
          childId: 'c1',
          patch: {'detectionKey': 'SB1.Infeed.PE'},
        ),
      );

      expect(result.error, isNull);
      final children = result.updated!.toJson()['children'] as List;
      final child = (children.single as Map)['child'] as Map;
      expect(child['detectionKey'], 'SB1.Infeed.PE');
    });

    test('unknown child_id fails without touching the asset', () {
      final assets = [thirdPartyWithChild('c1')];

      final result = applyAssetUpdate(
        assets,
        proposal(
          assetType: 'ThirdPartyEquipmentConfig',
          childId: 'nope',
          patch: {'detectionKey': 'x'},
        ),
      );

      expect(result.updated, isNull);
      expect(result.error, contains('no child with id "nope"'));
    });

    test('child_id on an asset without children fails', () {
      final assets = [makeAsset('LEDConfig', key: 'a')];

      final result = applyAssetUpdate(
        assets,
        proposal(
          assetType: 'LEDConfig',
          childId: 'c1',
          patch: {'key': 'x'},
        ),
      );

      expect(result.updated, isNull);
      expect(result.error, contains('no children'));
    });
  });

  test('malformed proposals fail cleanly', () {
    final assets = [makeAsset('LEDConfig')];

    expect(applyAssetUpdate(assets, {'patch': {'key': 'x'}}).error,
        contains('no target'));
    expect(
        applyAssetUpdate(assets, {
          'target': {'asset_type': 'LEDConfig'},
        }).error,
        contains('no patch'));
    expect(
        applyAssetUpdate(assets, {
          'target': <String, dynamic>{},
          'patch': {'key': 'x'},
        }).error,
        contains('no asset_type'));
  });
}
