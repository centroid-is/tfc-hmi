import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/beckhoff.dart';
import 'package:tfc/page_creator/assets/common.dart' show Asset, RelativeSize;
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/painter/beckhoff/cx5010.dart' show CXxxxx;
import 'package:tfc/providers/state_man.dart' show stateManProvider;
import 'package:tfc_dart/core/state_man.dart' show StateMan;

/// The CX variants are one asset with one string changed — the `CXxxxx`
/// painter has always taken the model name as a parameter. What these pin is
/// that the string is the *only* thing that changed:
///
///  * a CX5340 paints `CX5340` and a CX5010 still paints `CX5010`;
///  * both are addressable as their own asset type, because the page editor
///    picks by class and a saved page stores the class in `asset_name`;
///  * a CX5010 already on a saved page round-trips exactly as before — the
///    shared base class must not have moved its JSON.

/// The model name the CX painter under [finder] was handed.
String paintedModel(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(FittedBox),
      matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CXxxxx),
    ),
  );
  return (paint.painter! as CXxxxx).name;
}

/// Subdevices are `ConsumerWidget`s that reach for `stateManProvider`, so
/// even a CX rendered purely for its label needs the scope present.
Future<void> pumpAsset(WidgetTester tester, Asset config) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stateManProvider.overrideWith((ref) async => _FakeStateMan()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: Builder(builder: (context) => config.build(context)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeStateMan extends Fake implements StateMan {}

void main() {
  group('BeckhoffCX5340Config — identity', () {
    test('names itself CX5340 and sits with the other Beckhoff devices', () {
      final cx = BeckhoffCX5340Config();
      expect(cx.model, 'CX5340');
      expect(cx.displayName, 'Beckhoff CX5340');
      expect(cx.category, 'Beckhoff Devices');
    });

    test('is its own asset type, not a relabelled CX5010', () {
      // The page editor picks assets by class and a saved page stores the
      // class name, so the two must not collapse into one.
      expect(BeckhoffCX5340Config().assetName, 'BeckhoffCX5340Config');
      expect(BeckhoffCX5010Config().assetName, 'BeckhoffCX5010Config');
    });

    test('preview() constructs', () {
      expect(BeckhoffCX5340Config.preview().model, 'CX5340');
    });
  });

  group('BeckhoffCX5340Config — serialization', () {
    test('round-trips through JSON, subdevices included', () {
      final cx = BeckhoffCX5340Config()
        ..size = const RelativeSize(width: 0.5, height: 0.5)
        ..subdevices = [
          BeckhoffEL1008Config(nameOrId: '1', rawStateKey: 'el1.raw'),
        ];

      final json = cx.toJson();
      expect(json['asset_name'], 'BeckhoffCX5340Config');

      final back = BeckhoffCX5340Config.fromJson(json);
      expect(back.model, 'CX5340');
      expect(back.subdevices, hasLength(1));
      expect((back.subdevices.single as BeckhoffEL1008Config).rawStateKey,
          'el1.raw');
    });

    test('a CX5010 on a saved page is untouched by the shared base', () {
      // The refactor moved `subdevices` onto BeckhoffCXConfig. If that had
      // changed the generated JSON, every page already storing a CX5010
      // would have broken.
      final cx = BeckhoffCX5010Config()
        ..subdevices = [BeckhoffEL2008Config(nameOrId: '1')];
      final json = cx.toJson();

      expect(json['asset_name'], 'BeckhoffCX5010Config');
      expect(json.keys, contains('subdevices'));
      expect(BeckhoffCX5010Config.fromJson(json).subdevices, hasLength(1));
    });

    test('the registry parses a saved page carrying one', () {
      final parsed = AssetRegistry.parse({
        'assets': [
          BeckhoffCX5340Config()
            ..subdevices = [BeckhoffEL2008Config(nameOrId: '1')],
        ].map((a) => a.toJson()).toList(),
      });

      expect(parsed, hasLength(1));
      expect(parsed.single, isA<BeckhoffCX5340Config>());
      expect((parsed.single as BeckhoffCX5340Config).model, 'CX5340');
    });

    test('the palette can create one by name', () {
      // How the page editor offers a new asset.
      final made = AssetRegistry.createDefaultAssetByName(
          'BeckhoffCX5340Config');
      expect(made, isA<BeckhoffCX5340Config>());
    });
  });

  group('BeckhoffCXConfig — shared behaviour', () {
    test('CX5340 gathers keys from its subdevices, same as CX5010', () {
      final cx = BeckhoffCX5340Config()
        ..subdevices = [
          BeckhoffEL1008Config(
            nameOrId: '1',
            descriptionsKey: 'el1.desc',
            rawStateKey: 'el1.raw',
          ),
        ];
      expect(cx.allKeys, containsAll(['el1.desc', 'el1.raw']));
    });

    test('empty subdevices means no keys', () {
      expect(BeckhoffCX5340Config().allKeys, isEmpty);
    });
  });

  group('BeckhoffCXConfig — what gets painted', () {
    testWidgets('a CX5340 paints CX5340 down the stripe', (tester) async {
      await pumpAsset(tester, BeckhoffCX5340Config());
      expect(paintedModel(tester), 'CX5340');
    });

    testWidgets('a CX5010 still paints CX5010', (tester) async {
      await pumpAsset(tester, BeckhoffCX5010Config());
      expect(paintedModel(tester), 'CX5010');
    });

    testWidgets('subdevices render beside a CX5340 too', (tester) async {
      final cx = BeckhoffCX5340Config()
        ..subdevices = [BeckhoffEL2008Config(nameOrId: '1')];
      await pumpAsset(tester, cx);

      expect(paintedModel(tester), 'CX5340');
      // The rack is the reason this asset is a composite at all.
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
