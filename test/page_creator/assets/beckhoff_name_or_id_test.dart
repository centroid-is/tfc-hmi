import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/beckhoff.dart';
import 'package:tfc/page_creator/assets/common.dart' show Asset, BaseAsset;
import 'package:tfc/painter/beckhoff/cx5010.dart' show CXxxxx;
import 'package:tfc/painter/beckhoff/ek1100.dart' show EK1100;
import 'package:tfc/painter/beckhoff/ek1110.dart' show EK1110Widget;
import 'package:tfc/painter/beckhoff/io8.dart' show IO8Widget;
import 'package:tfc/providers/state_man.dart' show stateManProvider;
import 'package:tfc_dart/core/state_man.dart' show StateMan;

/// The passive Beckhoff drawings carry a `nameOrId` the operator can set, and
/// what these pin is the part that is easy to get wrong: the *fallback*.
///
/// A cabinet page holds three EK1100s and several EL6070s, and the only way
/// to tell them apart on the mimic is the name printed on the face. But the
/// field is new: every page already saved stores no `nameOrId` at all, and an
/// operator who selects the box and deletes the text leaves it empty. Neither
/// may produce a nameless block — both fall back to the model name, so an
/// untouched page renders exactly as it did before the field existed.

class _FakeStateMan extends Fake implements StateMan {}

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

/// The name the device's own drawing was handed — whichever way it draws.
String paintedName(WidgetTester tester) {
  final cx = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CXxxxx);
  if (cx.evaluate().isNotEmpty) {
    return (tester.widget<CustomPaint>(cx.first).painter! as CXxxxx).name;
  }

  final ek = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is EK1100);
  if (ek.evaluate().isNotEmpty) {
    return (tester.widget<CustomPaint>(ek.first).painter! as EK1100).name;
  }

  final ek1110 = find.byType(EK1110Widget);
  if (ek1110.evaluate().isNotEmpty) {
    return tester.widget<EK1110Widget>(ek1110.first).name;
  }

  final io8 = find.byType(IO8Widget);
  if (io8.evaluate().isNotEmpty) {
    return tester.widget<IO8Widget>(io8.first).name;
  }

  fail('no Beckhoff drawing found to read a name off');
}

/// One device under test: how to make one, what it is called by default, and
/// how to read and write its name.
class _Device {
  final String model;
  final BaseAsset Function() make;
  final BaseAsset Function(Map<String, dynamic>) fromJson;
  final String Function(BaseAsset) label;
  final String Function(BaseAsset) nameOrId;
  final void Function(BaseAsset, String) setNameOrId;

  const _Device({
    required this.model,
    required this.make,
    required this.fromJson,
    required this.label,
    required this.nameOrId,
    required this.setNameOrId,
  });
}

final _devices = <_Device>[
  _Device(
    model: 'CX5010',
    make: BeckhoffCX5010Config.new,
    fromJson: BeckhoffCX5010Config.fromJson,
    label: (a) => (a as BeckhoffCX5010Config).label,
    nameOrId: (a) => (a as BeckhoffCX5010Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffCX5010Config).nameOrId = v,
  ),
  _Device(
    model: 'CX5340',
    make: BeckhoffCX5340Config.new,
    fromJson: BeckhoffCX5340Config.fromJson,
    label: (a) => (a as BeckhoffCX5340Config).label,
    nameOrId: (a) => (a as BeckhoffCX5340Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffCX5340Config).nameOrId = v,
  ),
  _Device(
    model: 'EK1100',
    make: BeckhoffEK1100Config.new,
    fromJson: BeckhoffEK1100Config.fromJson,
    label: (a) => (a as BeckhoffEK1100Config).label,
    nameOrId: (a) => (a as BeckhoffEK1100Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEK1100Config).nameOrId = v,
  ),
  _Device(
    model: 'EK1110',
    make: BeckhoffEK1110Config.new,
    fromJson: BeckhoffEK1110Config.fromJson,
    label: (a) => (a as BeckhoffEK1110Config).label,
    nameOrId: (a) => (a as BeckhoffEK1110Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEK1110Config).nameOrId = v,
  ),
  _Device(
    model: 'EL6070',
    make: BeckhoffEL6070Config.new,
    fromJson: BeckhoffEL6070Config.fromJson,
    label: (a) => (a as BeckhoffEL6070Config).label,
    nameOrId: (a) => (a as BeckhoffEL6070Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEL6070Config).nameOrId = v,
  ),
  _Device(
    model: 'EL9187',
    make: BeckhoffEL9187Config.new,
    fromJson: BeckhoffEL9187Config.fromJson,
    label: (a) => (a as BeckhoffEL9187Config).label,
    nameOrId: (a) => (a as BeckhoffEL9187Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEL9187Config).nameOrId = v,
  ),
];

void main() {
  for (final device in _devices) {
    group('${device.model} — name or ID', () {
      test('a fresh one is unnamed and labels itself with the model', () {
        final asset = device.make();
        expect(device.nameOrId(asset), '');
        expect(device.label(asset), device.model);
      });

      test('a page saved before the field existed still loads', () {
        // The whole point of the default: `nameOrId` is simply absent from
        // every asset already on a saved page.
        final json = device.make().toJson()..remove('nameOrId');
        expect(json.containsKey('nameOrId'), isFalse);

        final back = device.fromJson(json);
        expect(device.nameOrId(back), '');
        expect(device.label(back), device.model);
      });

      test('a name round-trips through JSON', () {
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');

        final back = device.fromJson(asset.toJson());
        expect(device.nameOrId(back), 'ST301 A1');
        expect(device.label(back), 'ST301 A1');
      });

      test('clearing the box gives the model name back, not a blank', () {
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');
        device.setNameOrId(asset, '');
        expect(device.label(asset), device.model);
      });

      testWidgets('the drawing is labelled with the name', (tester) async {
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');
        await pumpAsset(tester, asset);
        expect(paintedName(tester), 'ST301 A1');
      });

      testWidgets('an unnamed drawing is labelled with the model',
          (tester) async {
        await pumpAsset(tester, device.make());
        expect(paintedName(tester), device.model);
      });
    });
  }

  group('the configure form', () {
    for (final device in _devices) {
      testWidgets('${device.model} offers a Name or ID box that writes back',
          (tester) async {
        final asset = device.make();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              stateManProvider.overrideWith((ref) async => _FakeStateMan()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(builder: (context) => asset.configure(context)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final box = find.widgetWithText(TextFormField, 'Name or ID');
        expect(box, findsOneWidget);

        await tester.enterText(box, 'ST301 A1');
        expect(device.nameOrId(asset), 'ST301 A1');
      });
    }
  });
}
