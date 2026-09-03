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
/// it lands where the EL terminals have always put theirs: a marker tag over
/// the terminal-marker band, with the model name left where it is printed.
///
/// Two things are easy to get wrong and are what these pin. The tag must not
/// eat the model name — a rack of `ST301 A1`s with no EK1100 or EL6070
/// anywhere on it tells an operator less than the drawing did before. And an
/// empty name must draw no tag at all, because every page already saved
/// stores no `nameOrId`, so an untouched page has to render exactly as it did
/// before the field existed.

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

/// The model name printed on the device, and the marker tag over its band —
/// whichever of the four drawings it is.
({String name, String marker}) painted(WidgetTester tester) {
  final cx =
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CXxxxx);
  if (cx.evaluate().isNotEmpty) {
    final p = tester.widget<CustomPaint>(cx.first).painter! as CXxxxx;
    return (name: p.name, marker: p.markerLabel);
  }

  final ek =
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is EK1100);
  if (ek.evaluate().isNotEmpty) {
    final p = tester.widget<CustomPaint>(ek.first).painter! as EK1100;
    return (name: p.name, marker: p.markerLabel);
  }

  final ek1110 = find.byType(EK1110Widget);
  if (ek1110.evaluate().isNotEmpty) {
    final w = tester.widget<EK1110Widget>(ek1110.first);
    return (name: w.name, marker: w.markerLabel);
  }

  final io8 = find.byType(IO8Widget);
  if (io8.evaluate().isNotEmpty) {
    final w = tester.widget<IO8Widget>(io8.first);
    return (name: w.name, marker: w.markerLabel);
  }

  fail('no Beckhoff drawing found to read a name off');
}

/// One device under test: how to make one, what it is called by default, and
/// how to read and write its name.
class _Device {
  final String model;
  final BaseAsset Function() make;
  final BaseAsset Function(Map<String, dynamic>) fromJson;
  final String Function(BaseAsset) nameOrId;
  final void Function(BaseAsset, String) setNameOrId;

  const _Device({
    required this.model,
    required this.make,
    required this.fromJson,
    required this.nameOrId,
    required this.setNameOrId,
  });
}

final _devices = <_Device>[
  _Device(
    model: 'CX5010',
    make: BeckhoffCX5010Config.new,
    fromJson: BeckhoffCX5010Config.fromJson,
    nameOrId: (a) => (a as BeckhoffCX5010Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffCX5010Config).nameOrId = v,
  ),
  _Device(
    model: 'CX5340',
    make: BeckhoffCX5340Config.new,
    fromJson: BeckhoffCX5340Config.fromJson,
    nameOrId: (a) => (a as BeckhoffCX5340Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffCX5340Config).nameOrId = v,
  ),
  _Device(
    model: 'EK1100',
    make: BeckhoffEK1100Config.new,
    fromJson: BeckhoffEK1100Config.fromJson,
    nameOrId: (a) => (a as BeckhoffEK1100Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEK1100Config).nameOrId = v,
  ),
  _Device(
    model: 'EK1110',
    make: BeckhoffEK1110Config.new,
    fromJson: BeckhoffEK1110Config.fromJson,
    nameOrId: (a) => (a as BeckhoffEK1110Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEK1110Config).nameOrId = v,
  ),
  _Device(
    model: 'EL6070',
    make: BeckhoffEL6070Config.new,
    fromJson: BeckhoffEL6070Config.fromJson,
    nameOrId: (a) => (a as BeckhoffEL6070Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEL6070Config).nameOrId = v,
  ),
  _Device(
    model: 'EL9187',
    make: BeckhoffEL9187Config.new,
    fromJson: BeckhoffEL9187Config.fromJson,
    nameOrId: (a) => (a as BeckhoffEL9187Config).nameOrId,
    setNameOrId: (a, v) => (a as BeckhoffEL9187Config).nameOrId = v,
  ),
];

void main() {
  for (final device in _devices) {
    group('${device.model} — name or ID', () {
      test('a fresh one carries no name', () {
        expect(device.nameOrId(device.make()), '');
      });

      test('a page saved before the field existed still loads', () {
        // The whole point of the default: `nameOrId` is simply absent from
        // every asset already on a saved page.
        final json = device.make().toJson()..remove('nameOrId');
        expect(json.containsKey('nameOrId'), isFalse);

        expect(device.nameOrId(device.fromJson(json)), '');
      });

      test('a name round-trips through JSON', () {
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');

        expect(device.nameOrId(device.fromJson(asset.toJson())), 'ST301 A1');
      });

      testWidgets('the name goes on the marker tag', (tester) async {
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');
        await pumpAsset(tester, asset);
        expect(painted(tester).marker, 'ST301 A1');
      });

      testWidgets('the model name survives being named', (tester) async {
        // The regression this exists for: naming a terminal must not take
        // the printed type off it. A rack of tags with no model anywhere is
        // less use to an operator than the drawing was unnamed.
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');
        await pumpAsset(tester, asset);
        expect(painted(tester).name, device.model);
      });

      testWidgets('an unnamed drawing wears no tag', (tester) async {
        await pumpAsset(tester, device.make());
        final p = painted(tester);
        expect(p.marker, '');
        expect(p.name, device.model);
      });

      testWidgets('clearing the box takes the tag away again', (tester) async {
        final asset = device.make();
        device.setNameOrId(asset, 'ST301 A1');
        device.setNameOrId(asset, '');
        await pumpAsset(tester, asset);
        expect(painted(tester).marker, '');
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
