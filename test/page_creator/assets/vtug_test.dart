import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/festo.dart';
import 'package:tfc/page_creator/assets/vtug.dart';
import 'package:tfc/painter/festo/vtug.dart'
    show
        CteuLedState,
        cteuFaceMm,
        vtugEndPlateWidthMm,
        vtugFaceMm,
        vtugSliceCount,
        vtugSliceWidthMm;
import 'package:tfc/theme.dart';

/// Contract under test — the Festo VTUG-14 valve terminal.
///
/// Three things carry the weight here and none of them are visual:
///
///  * **The bit map.** Sixteen coils behind two bytes, and every lamp,
///    button and force word in this asset reads its index from
///    `vtugBitIndex`. If that function is wrong, the terminal is wrong in a
///    way that looks entirely plausible on screen — valve 3 lighting when
///    valve 2 moves.
///
///  * **The force words.** `p_cmd_Force` says which coils the HMI has taken
///    and `p_cmd_Value` says what to do with them, and the two only mean
///    anything together. A test that checked only the value word would pass
///    on a terminal that drove coils it had never been given.
///
///  * **Release.** A push that does not release is a valve held on by a
///    screen nobody is looking at any more. The release paths — button up,
///    pointer cancel, widget disposed mid-press — are the ones worth
///    hammering.
void main() {
  /// A 380 px column that scrolls, which is what `SidePane` gives its body.
  /// A full manifold's status list and force rows are taller than a screen
  /// and are meant to be — pinning them to a fixed box here would fail on
  /// overflow rather than on anything the pane does wrong.
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(
          extensions: const [HmiStateColors.solarizedLight],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );

  List<VtugValveKind> allDouble() =>
      List.filled(vtugPositionCount, VtugValveKind.doubleSolenoid);

  DynamicValue struct({
    int coils = 0,
    int forceMask = 0,
    int forceValue = 0,
  }) {
    final dv = DynamicValue();
    dv['p_stat_Coils'] = coils;
    dv['p_stat_Forced'] = 0;
    dv['p_cmd_Force'] = forceMask;
    dv['p_cmd_Value'] = forceValue;
    return dv;
  }

  group('bit map', () {
    test('each position owns two consecutive bits, 14 low and 12 high', () {
      for (var position = 1; position <= vtugPositionCount; position++) {
        expect(vtugBitIndex(position, VtugCoil.p14), (position - 1) * 2);
        expect(vtugBitIndex(position, VtugCoil.p12), (position - 1) * 2 + 1);
      }
    });

    test('positions 1..4 land in the low byte and 5..8 in the high one', () {
      // The PLC publishes two bytes — `C1 Output` and `C2 Output` — and the
      // struct packs them low-then-high. A map that spilled position 4 into
      // the high byte would light valves on the wrong half of the manifold.
      for (var position = 1; position <= 4; position++) {
        expect(vtugBitIndex(position, VtugCoil.p12), lessThan(8));
      }
      for (var position = 5; position <= 8; position++) {
        expect(vtugBitIndex(position, VtugCoil.p14),
            greaterThanOrEqualTo(8));
      }
    });

    test('no two coils share a bit', () {
      final seen = <int>{};
      for (var position = 1; position <= vtugPositionCount; position++) {
        for (final coil in VtugCoil.values) {
          expect(seen.add(vtugBitIndex(position, coil)), isTrue,
              reason: 'position $position coil ${coil.label} collided');
        }
      }
      expect(seen.length, vtugCoilCount);
    });
  });

  group('decode', () {
    test('a null struct leaves every fitted position unknown', () {
      final terminal = VtugTerminal.read(null, kinds: allDouble());
      expect(terminal.isUnknown, isTrue);
      expect(terminal.valves, hasLength(vtugPositionCount));
      for (final valve in terminal.valves) {
        expect(valve.coil14, isNull);
        expect(valve.coil12, isNull);
        expect(valve.force, VtugForce.auto);
      }
    });

    test('an energised coil reads back on the position that owns it', () {
      // Position 3's coil 12 is bit 5.
      final terminal =
          VtugTerminal.read(struct(coils: 1 << 5), kinds: allDouble());
      expect(terminal.valves[2].coil12, isTrue);
      expect(terminal.valves[2].coil14, isFalse);
      expect(terminal.energisedCount, 1);
      // And nothing else moved.
      for (var i = 0; i < vtugPositionCount; i++) {
        if (i == 2) continue;
        expect(terminal.valves[i].energised, isFalse);
      }
    });

    test('a blanked position reports no coils at all', () {
      final kinds = allDouble()..[4] = VtugValveKind.blank;
      // Every bit set — a blank must still show nothing, because the bits
      // behind it drive no coil.
      final terminal = VtugTerminal.read(struct(coils: 0xFFFF), kinds: kinds);
      expect(terminal.valves[4].coil14, isNull);
      expect(terminal.valves[4].coil12, isNull);
      expect(terminal.valves[4].energised, isFalse);
      expect(terminal.fittedCount, vtugPositionCount - 1);
    });

    test('a single-solenoid position reports coil 14 only', () {
      final kinds = allDouble()..[0] = VtugValveKind.singleSolenoid;
      final terminal = VtugTerminal.read(
        // Bits 0 and 1 — coil 14 and the bit where coil 12 would be.
        struct(coils: 0x3),
        kinds: kinds,
      );
      expect(terminal.valves[0].coil14, isTrue);
      expect(terminal.valves[0].coil12, isNull,
          reason: 'there is no second coil, so the bit behind it is not a '
              'reading of anything');
      expect(terminal.valves[0].hasCoil(VtugCoil.p12), isFalse);
    });

    test('descriptions land on the positions they were given for', () {
      final terminal = VtugTerminal.read(
        struct(),
        kinds: allDouble(),
        descriptions: const ['Gate lift', '', '  ', 'Pusher'],
      );
      expect(terminal.valves[0].description, 'Gate lift');
      expect(terminal.valves[1].description, isNull);
      expect(terminal.valves[2].description, isNull,
          reason: 'whitespace is not a name');
      expect(terminal.valves[3].description, 'Pusher');
      expect(terminal.valves[7].description, isNull);
    });
  });

  group('force words', () {
    test('open takes both coils and drives 14 on a double', () {
      final next = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.doubleSolenoid,
        position: 1,
        force: VtugForce.open,
      );
      // Both coils taken: on a bistable valve, holding 14 on while leaving
      // 12 to the PLC is a valve two masters are driving at once.
      expect(next.mask, 0x3);
      expect(next.value, 0x1);
    });

    test('close takes both coils and drives 12 on a double', () {
      final next = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.doubleSolenoid,
        position: 1,
        force: VtugForce.closed,
      );
      expect(next.mask, 0x3);
      expect(next.value, 0x2);
    });

    test('close on a single holds the one coil OFF rather than driving a '
        'second', () {
      final next = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.singleSolenoid,
        position: 2,
        force: VtugForce.closed,
      );
      // Bit 2 taken, bit 2 low, and bit 3 — the coil that is not fitted —
      // untouched in both words.
      expect(next.mask, 0x4);
      expect(next.value, 0);
    });

    test('auto gives both coils back and clears their values', () {
      final held = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.doubleSolenoid,
        position: 4,
        force: VtugForce.open,
      );
      final released = vtugApplyForce(
        forceMask: held.mask,
        forceValue: held.value,
        kind: VtugValveKind.doubleSolenoid,
        position: 4,
        force: VtugForce.auto,
      );
      expect(released.mask, 0);
      expect(released.value, 0,
          reason: 'a coil handed back with its value bit still set comes up '
              'energised the moment anything sets the mask bit again');
    });

    test('forcing one position leaves every other position alone', () {
      final first = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.doubleSolenoid,
        position: 7,
        force: VtugForce.open,
      );
      final second = vtugApplyForce(
        forceMask: first.mask,
        forceValue: first.value,
        kind: VtugValveKind.doubleSolenoid,
        position: 2,
        force: VtugForce.closed,
      );
      // Position 7 is bits 12/13, position 2 is bits 2/3.
      expect(second.mask, (0x3 << 12) | (0x3 << 2));
      expect(second.value, (0x1 << 12) | (0x2 << 2));
    });

    test('a blank position cannot be forced', () {
      final next = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.blank,
        position: 5,
        force: VtugForce.open,
      );
      expect(next.mask, 0);
      expect(next.value, 0);
    });

    test('the words round-trip back through the decode', () {
      for (final force in VtugForce.values) {
        for (final kind in [
          VtugValveKind.singleSolenoid,
          VtugValveKind.doubleSolenoid,
        ]) {
          final next = vtugApplyForce(
            forceMask: 0,
            forceValue: 0,
            kind: kind,
            position: 6,
            force: force,
          );
          expect(
            vtugForceOf(
              kind: kind,
              position: 6,
              forceMask: next.mask,
              forceValue: next.value,
            ),
            force,
            reason: '$kind at $force did not read back as itself',
          );
        }
      }
    });
  });

  group('push words', () {
    test('a press takes exactly the coil under the finger', () {
      final next = vtugApplyPush(
        forceMask: 0,
        forceValue: 0,
        position: 3,
        coil: VtugCoil.p14,
        pressed: true,
      );
      expect(next.mask, 1 << 4);
      expect(next.value, 1 << 4);
    });

    test('a release gives it back and clears its value', () {
      final down = vtugApplyPush(
        forceMask: 0,
        forceValue: 0,
        position: 3,
        coil: VtugCoil.p14,
        pressed: true,
      );
      final up = vtugApplyPush(
        forceMask: down.mask,
        forceValue: down.value,
        position: 3,
        coil: VtugCoil.p14,
        pressed: false,
      );
      expect(up.mask, 0);
      expect(up.value, 0);
    });

    test('a push does not disturb a hold on another position', () {
      final held = vtugApplyForce(
        forceMask: 0,
        forceValue: 0,
        kind: VtugValveKind.doubleSolenoid,
        position: 1,
        force: VtugForce.open,
      );
      final pushed = vtugApplyPush(
        forceMask: held.mask,
        forceValue: held.value,
        position: 8,
        coil: VtugCoil.p12,
        pressed: true,
      );
      expect(pushed.mask & 0x3, 0x3);
      expect(pushed.value & 0x3, 0x1);
      expect(
        vtugForceOf(
          kind: VtugValveKind.doubleSolenoid,
          position: 1,
          forceMask: pushed.mask,
          forceValue: pushed.value,
        ),
        VtugForce.open,
      );
    });

    test('release-all clears both words', () {
      final next = vtugReleaseAll();
      expect(next.mask, 0);
      expect(next.value, 0);
    });
  });

  group('pane status', () {
    test('a held valve outranks a busy one', () {
      final terminal = VtugTerminal.read(
        struct(coils: 0xFF, forceMask: 0x3, forceValue: 0x1),
        kinds: allDouble(),
      );
      expect(terminal.forcedCount, 1);
      expect(vtugPaneStatus(terminal).label, '1 held');
    });

    test('nothing received reads as no data, not as all quiet', () {
      expect(
        vtugPaneStatus(VtugTerminal.read(null, kinds: allDouble())).label,
        'No data',
      );
    });

    test('an all-blank manifold says so rather than claiming to be quiet', () {
      final terminal = VtugTerminal.read(
        struct(),
        kinds: List.filled(vtugPositionCount, VtugValveKind.blank),
      );
      expect(vtugPaneStatus(terminal).label, 'No valves');
    });

    test('quiet and busy are counted against the fitted positions', () {
      final kinds = allDouble()
        ..[6] = VtugValveKind.blank
        ..[7] = VtugValveKind.blank;
      expect(
        vtugPaneStatus(VtugTerminal.read(struct(), kinds: kinds)).label,
        'All quiet',
      );
      expect(
        vtugPaneStatus(
          VtugTerminal.read(struct(coils: 0x5), kinds: kinds),
        ).label,
        '2 of 6 on',
      );
    });
  });

  group('bus node', () {
    test('a live link lights only the lamps the data actually vouches for',
        () {
      final leds = {for (final led in CteuLink.live.leds) led.label: led.state};
      expect(leds['PS'], CteuLedState.green);
      expect(leds['X1'], CteuLedState.green);
      expect(leds['RUN'], CteuLedState.green);
      expect(leds['L/A1'], CteuLedState.green);
      // Silence is not an all-clear: nothing published these, so nothing
      // claims them.
      expect(leds['ERR'], CteuLedState.unknown);
      expect(leds['X2'], CteuLedState.unknown);
      expect(leds['L/A2'], CteuLedState.unknown);
    });

    test('a dark link guesses at nothing', () {
      for (final led in CteuLink.dark.leds) {
        expect(led.state, CteuLedState.unknown,
            reason: '${led.label} claimed a state nobody reported');
      }
    });
  });

  group('pane body', () {
    testWidgets('lists every position, blanks included', (tester) async {
      final kinds = allDouble()..[3] = VtugValveKind.blank;
      await tester.pumpWidget(wrap(
        VtugPaneBody(terminal: VtugTerminal.read(struct(), kinds: kinds)),
      ));

      for (var position = 1; position <= vtugPositionCount; position++) {
        expect(find.text('V$position'), findsWidgets,
            reason: 'position $position vanished from the pane');
      }
      expect(find.text('Blanking plate'), findsOneWidget);
    });

    testWidgets('with no command callbacks the force section says so',
        (tester) async {
      await tester.pumpWidget(wrap(
        VtugPaneBody(terminal: VtugTerminal.read(struct(), kinds: allDouble())),
      ));
      expect(find.textContaining('No command keys are configured'),
          findsOneWidget);
      expect(find.byType(SegmentedButton<VtugForce>), findsNothing);
    });

    testWidgets('a blank position gets no force row', (tester) async {
      final kinds = List.filled(vtugPositionCount, VtugValveKind.blank)
        ..[0] = VtugValveKind.doubleSolenoid;
      await tester.pumpWidget(wrap(
        VtugPaneBody(
          terminal: VtugTerminal.read(struct(), kinds: kinds),
          onForce: (_, __) {},
          onPush: (_, __, ___) {},
        ),
      ));
      expect(find.byType(SegmentedButton<VtugForce>), findsOneWidget);
    });

    testWidgets('a single-solenoid position offers one push button, a double '
        'offers two', (tester) async {
      final kinds = List.filled(vtugPositionCount, VtugValveKind.blank)
        ..[0] = VtugValveKind.singleSolenoid
        ..[1] = VtugValveKind.doubleSolenoid;
      await tester.pumpWidget(wrap(
        VtugPaneBody(
          terminal: VtugTerminal.read(struct(), kinds: kinds),
          onForce: (_, __) {},
          onPush: (_, __, ___) {},
        ),
      ));
      expect(find.byType(VtugPushButton), findsNWidgets(3));
      expect(find.text('14'), findsNWidgets(2));
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('carries the bus node section, and it follows the link',
        (tester) async {
      // The node's account belongs in this pane rather than one of its own:
      // it has no state to open, and a pane whose whole content is "we
      // cannot see this" teaches an operator to stop opening panes.
      await tester.pumpWidget(wrap(
        VtugPaneBody(
          terminal: VtugTerminal.read(struct(), kinds: allDouble()),
          link: CteuLink.live,
        ),
      ));
      expect(find.text('BUS NODE'), findsOneWidget);
      expect(find.text('Arriving'), findsOneWidget);

      await tester.pumpWidget(wrap(
        VtugPaneBody(
          terminal: VtugTerminal.read(null, kinds: allDouble()),
          link: CteuLink.dark,
        ),
      ));
      expect(find.text('Not arriving'), findsOneWidget);
    });

    testWidgets('choosing Open reports the position and the force',
        (tester) async {
      final calls = <(int, VtugForce)>[];
      await tester.pumpWidget(wrap(
        VtugPaneBody(
          terminal: VtugTerminal.read(struct(), kinds: allDouble()),
          onForce: (valve, force) => calls.add((valve.position, force)),
        ),
      ));

      await tester.tap(find.text('Open').first);
      await tester.pump();
      expect(calls, [(1, VtugForce.open)]);
    });
  });

  group('push button', () {
    testWidgets('reports true on the way down and false on the way up',
        (tester) async {
      final events = <bool>[];
      await tester.pumpWidget(wrap(
        VtugPushButton(label: '14', onPressedChanged: events.add),
      ));

      final gesture =
          await tester.press(find.byType(VtugPushButton));
      await tester.pump();
      expect(events, [true]);

      await gesture.up();
      await tester.pump();
      expect(events, [true, false]);
    });

    testWidgets('a cancelled gesture still releases the coil', (tester) async {
      // A finger that slides off the button is a gesture the framework
      // cancels rather than completes. Without the cancel handler the coil
      // would stay energised with nothing on screen holding it.
      final events = <bool>[];
      await tester.pumpWidget(wrap(
        VtugPushButton(label: '14', onPressedChanged: events.add),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VtugPushButton)),
      );
      await tester.pump();
      expect(events, [true]);

      await gesture.moveBy(const Offset(0, 400));
      await gesture.up();
      await tester.pump();
      expect(events.last, isFalse);
    });

    testWidgets('being disposed mid-press releases the coil', (tester) async {
      // Closing the pane under a held finger is the same failure with a
      // different cause, and the one nobody would think to try by hand.
      final events = <bool>[];
      await tester.pumpWidget(wrap(
        VtugPushButton(label: '14', onPressedChanged: events.add),
      ));

      await tester.startGesture(
        tester.getCenter(find.byType(VtugPushButton)),
      );
      await tester.pump();
      expect(events, [true]);

      await tester.pumpWidget(wrap(const SizedBox.shrink()));
      expect(events, [true, false]);
    });

    testWidgets('a null callback makes the button inert', (tester) async {
      await tester.pumpWidget(wrap(
        const VtugPushButton(label: '14', onPressedChanged: null),
      ));
      // Nothing to assert but the absence of a crash and the absence of a
      // write — pressing a button with no key behind it must do neither.
      await tester.tap(find.byType(VtugPushButton));
      await tester.pump();
    });
  });

  group('config', () {
    test('a fresh terminal is eight double-solenoid positions', () {
      final config = FestoVTUGConfig();
      expect(config.slices, hasLength(vtugPositionCount));
      expect(config.kinds,
          everyElement(equals(VtugValveKind.doubleSolenoid)));
    });

    test('a short saved slice list is padded out with blanks', () {
      // Pages saved by hand, or by a future that trims empty positions, must
      // still deserialise to a whole manifold — every consumer indexes 1..8.
      final json = FestoVTUGConfig().toJson();
      json['slices'] = (json['slices']! as List).sublist(0, 3);
      final config = FestoVTUGConfig.fromJson(json);
      expect(config.slices, hasLength(vtugPositionCount));
      expect(config.slices[7].kind, VtugValveKind.blank);
    });

    test('an over-long saved slice list is trimmed', () {
      final json = FestoVTUGConfig().toJson();
      final slices = (json['slices']! as List).toList();
      json['slices'] = [...slices, ...slices];
      expect(FestoVTUGConfig.fromJson(json).slices,
          hasLength(vtugPositionCount));
    });

    test('the state key is picked up by allKeys', () {
      final config = FestoVTUGConfig(stateKey: 'ST301.ECT.ST303_A1');
      expect(config.allKeys, contains('ST301.ECT.ST303_A1'));
    });

    test('slice kind and name survive a JSON round trip', () {
      final config = FestoVTUGConfig(nameOrId: 'ST303.A1');
      config.slices[2].kind = VtugValveKind.singleSolenoid;
      config.slices[2].name = 'Gate 1 lift';
      config.slices[5].kind = VtugValveKind.blank;

      final back = FestoVTUGConfig.fromJson(config.toJson());
      expect(back.nameOrId, 'ST303.A1');
      expect(back.slices[2].kind, VtugValveKind.singleSolenoid);
      expect(back.slices[2].name, 'Gate 1 lift');
      expect(back.slices[5].kind, VtugValveKind.blank);
    });
  });

  group('face geometry', () {
    test('the face is the parts it is made of', () {
      // `vtugFaceMm` is spelled out as a literal because a `const Size`
      // cannot read a field off another one. This is the guard that keeps
      // the literal honest when an end plate or a slice pitch changes.
      expect(
        vtugFaceMm.width,
        cteuFaceMm.width +
            vtugEndPlateWidthMm * 2 +
            vtugSliceWidthMm * vtugSliceCount,
      );
      expect(vtugFaceMm.height, cteuFaceMm.height);
    });

    test('the painter and the decode agree on how many positions there are',
        () {
      expect(vtugSliceCount, vtugPositionCount);
    });
  });
}
