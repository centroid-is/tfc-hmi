import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/beckhoff.dart';
import 'package:tfc/page_creator/assets/ps2001.dart';
import 'package:tfc/painter/beckhoff/ps2001.dart'
    show PS2001Widget, Ps2001FaceState;
import 'package:tfc/providers/state_man.dart' show stateManProvider;
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart' show StateMan;

/// The PS2001 is the only piece of cabinet infrastructure on these pages that
/// measures anything. `ST_PS2001_2410` carries four flags and two REALs, and
/// the two REALs are the reason the asset exists: every other mimic answers
/// "is it on?", and the output volts and amps answer "how close is this to
/// falling over?".
///
/// These tests pin the decode against that struct, and pin the two places the
/// asset could quietly lie: a member that never arrived reading as 0.0 V, and
/// a headline state that swallows a flag the housing's own lamp is still
/// showing.

const _stateKey = 'ST301.ECT.ST301_T1';
const _descriptionKey = 'ST301.ECT.ST301_T1.Description';

/// Builds an `ST_PS2001_2410` with every member present unless named in
/// [absent].
DynamicValue _struct({
  Map<Ps2001Flag, bool> flags = const {},
  double voltage = 24.1,
  double current = 3.2,
  Set<String> absent = const {},
}) {
  final dv = DynamicValue();
  for (final flag in Ps2001Flag.values) {
    if (absent.contains(flag.member)) continue;
    dv[flag.member] = flags[flag] ?? false;
  }
  if (!absent.contains(ps2001VoltageMember)) {
    dv[ps2001VoltageMember] = voltage;
  }
  if (!absent.contains(ps2001CurrentMember)) {
    dv[ps2001CurrentMember] = current;
  }
  return dv;
}

void main() {
  group('Ps2001Status.read', () {
    test('reads the flags and both measurements off the struct', () {
      final status = Ps2001Status.read(_struct(
        flags: {Ps2001Flag.dcOk: true},
        voltage: 24.3,
        current: 4.5,
      ));

      expect(status[Ps2001Flag.dcOk], isTrue);
      expect(status[Ps2001Flag.error], isFalse);
      expect(status.voltage, closeTo(24.3, 0.001));
      expect(status.current, closeTo(4.5, 0.001));
    });

    test('a missing measurement stays null rather than reading as zero', () {
      // The failure this guards: a supply whose voltage member never arrived
      // showing "0.0 V" on the pane, which is indistinguishable from a rail
      // that has actually collapsed.
      final status = Ps2001Status.read(
        _struct(absent: {ps2001VoltageMember}),
      );

      expect(status.voltage, isNull);
      expect(status.current, isNotNull);
    });

    test('a null struct leaves everything unknown', () {
      final status = Ps2001Status.read(null);

      expect(status.isUnknown, isTrue);
      expect(status.voltage, isNull);
      expect(status.current, isNull);
      expect(status.state, Ps2001FaceState.unknown);
      for (final flag in Ps2001Flag.values) {
        expect(status[flag], isNull, reason: '${flag.name} should be unknown');
      }
    });
  });

  group('Ps2001Status.state', () {
    Ps2001FaceState stateOf(Map<Ps2001Flag, bool> flags) =>
        Ps2001Status.read(_struct(flags: flags)).state;

    test('DC OK and nothing flagged is healthy', () {
      expect(stateOf({Ps2001Flag.dcOk: true}), Ps2001FaceState.healthy);
    });

    test('DC OK low with nothing flagged reads as down, not faulted', () {
      // A supply somebody switched off is not a supply that failed, and
      // sending an electrician after the second when it is the first wastes
      // a walk across the plant.
      expect(stateOf(const {}), Ps2001FaceState.down);
    });

    test('error outranks undervoltage, which outranks warning', () {
      expect(
        stateOf({
          Ps2001Flag.dcOk: true,
          Ps2001Flag.error: true,
          Ps2001Flag.inputUndervoltage: true,
          Ps2001Flag.warning: true,
        }),
        Ps2001FaceState.faulted,
      );
      expect(
        stateOf({
          Ps2001Flag.dcOk: true,
          Ps2001Flag.inputUndervoltage: true,
          Ps2001Flag.warning: true,
        }),
        Ps2001FaceState.undervoltage,
      );
      expect(
        stateOf({Ps2001Flag.dcOk: true, Ps2001Flag.warning: true}),
        Ps2001FaceState.warning,
      );
    });

    test('a warning does not put out the DC OK lamp', () {
      // The headline and the lamp are separate on purpose: a supply running
      // hot is still supplying, and a mimic that darkens its DC OK lamp
      // disagrees with the lamp on the cabinet door.
      final status =
          Ps2001Status.read(_struct(flags: {
        Ps2001Flag.dcOk: true,
        Ps2001Flag.warning: true,
      }));

      expect(status.state, Ps2001FaceState.warning);
      expect(status[Ps2001Flag.dcOk], isTrue);
    });

    test('an unpublished DC OK bit does not become "down"', () {
      final status = Ps2001Status.read(
        _struct(absent: {Ps2001Flag.dcOk.member}),
      );

      expect(status.state, Ps2001FaceState.unknown);
    });
  });

  group('Ps2001Status.headroom', () {
    test('is what is left of the 10 A rating', () {
      expect(
        Ps2001Status.read(_struct(current: 2.5)).headroom,
        closeTo(0.75, 0.001),
      );
    });

    test('clamps rather than going negative on an overloaded unit', () {
      expect(Ps2001Status.read(_struct(current: 12.0)).headroom, 0.0);
    });

    test('is null when the current never arrived', () {
      expect(
        Ps2001Status.read(_struct(absent: {ps2001CurrentMember})).headroom,
        isNull,
      );
    });
  });

  group('BeckhoffPS2001Config', () {
    test('round-trips through JSON', () {
      final config = BeckhoffPS2001Config(
        nameOrId: 'ST301.T1',
        stateKey: _stateKey,
        descriptionKey: _descriptionKey,
      );

      final restored = BeckhoffPS2001Config.fromJson(config.toJson());

      expect(restored.nameOrId, 'ST301.T1');
      expect(restored.stateKey, _stateKey);
      expect(restored.descriptionKey, _descriptionKey);
    });

    test('allKeys carries the state key so resubscribe covers it', () {
      final config =
          BeckhoffPS2001Config(nameOrId: 'T1', stateKey: _stateKey);

      expect(config.allKeys, contains(_stateKey));
    });
  });

  group('the face, live', () {
    Future<PS2001Widget> pump(
      WidgetTester tester, {
      DynamicValue? struct,
      String? stateKey = _stateKey,
    }) async {
      final config = BeckhoffPS2001Config(
        nameOrId: 'ST301.T1',
        stateKey: stateKey,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          stateManProvider.overrideWith((ref) async => _Ps2001StateMan(struct)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: 400,
                child: Builder(builder: (context) => config.build(context)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      return tester.widget<PS2001Widget>(find.byType(PS2001Widget));
    }

    testWidgets('carries the tag, not the model, so seven of them can be told '
        'apart', (tester) async {
      final face = await pump(
        tester,
        struct: _struct(flags: {Ps2001Flag.dcOk: true}),
      );

      expect(face.name, 'ST301.T1');
    });

    testWidgets('lights DC OK from the bit, not from the headline',
        (tester) async {
      final face = await pump(
        tester,
        struct: _struct(flags: {
          Ps2001Flag.dcOk: true,
          Ps2001Flag.warning: true,
        }),
      );

      expect(face.state, Ps2001FaceState.warning);
      expect(face.dcOk, isTrue);
    });

    testWidgets('an unconfigured supply reports nothing rather than zero',
        (tester) async {
      final face = await pump(tester, stateKey: null);

      expect(face.state, Ps2001FaceState.unknown);
      expect(face.dcOk, isNull);
    });
  });

  group('the pane', () {
    Future<void> open(
      WidgetTester tester, {
      required DynamicValue struct,
      String? description,
    }) async {
      final config = BeckhoffPS2001Config(
        nameOrId: 'ST301.T1',
        stateKey: _stateKey,
        descriptionKey: description == null ? null : _descriptionKey,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          stateManProvider.overrideWith(
            (ref) async => _Ps2001StateMan(struct, description: description),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: 400,
                child: Builder(builder: (context) => config.build(context)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PS2001Widget));
      await tester.pumpAndSettle();
    }

    tearDown(closeSidePane);

    testWidgets('shows the two figures the struct measures', (tester) async {
      await open(
        tester,
        struct: _struct(
          flags: {Ps2001Flag.dcOk: true},
          voltage: 24.1,
          current: 3.2,
        ),
        description: 'Cabinet A1 24 V rail',
      );

      expect(find.text('24.1'), findsOneWidget);
      expect(find.text('3.2'), findsOneWidget);
      // 10 A rated, 3.2 A drawn.
      expect(find.text('68'), findsOneWidget);
      expect(find.text('Cabinet A1 24 V rail'), findsOneWidget);
    });

    testWidgets('shows a dash, never a zero, for a figure that never arrived',
        (tester) async {
      await open(
        tester,
        struct: _struct(
          flags: {Ps2001Flag.dcOk: true},
          absent: {ps2001VoltageMember},
        ),
      );

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a fault opens its explanation unprompted', (tester) async {
      await open(
        tester,
        struct: _struct(flags: {Ps2001Flag.error: true}),
      );

      expect(find.textContaining('hiccup mode'), findsOneWidget);
    });

    testWidgets('names the rail in words, never the OPC UA key',
        (tester) async {
      await open(
        tester,
        struct: _struct(flags: {Ps2001Flag.dcOk: true}),
        description: 'Cabinet A1 24 V rail',
      );

      expect(find.text('ST301.T1'), findsOneWidget);
      expect(find.textContaining('p_stat_'), findsNothing);
      expect(find.textContaining('ECT.'), findsNothing);
    });
  });
}

/// Serves one `ST_PS2001_2410`. A null struct never publishes, which is what
/// a supply with no key configured looks like.
class _Ps2001StateMan extends Fake implements StateMan {
  _Ps2001StateMan(this.struct, {this.description});

  final DynamicValue? struct;
  final String? description;

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    if (key == _stateKey && struct != null) {
      return Stream<DynamicValue>.value(struct!);
    }
    if (key == _descriptionKey && description != null) {
      return Stream<DynamicValue>.value(DynamicValue(value: description));
    }
    return const Stream<DynamicValue>.empty();
  }

  @override
  Future<DynamicValue> read(String key) async => struct ?? DynamicValue();
}
