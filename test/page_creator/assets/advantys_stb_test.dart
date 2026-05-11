import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/advantys_stb.dart';
import 'package:tfc/page_creator/assets/common.dart' show KeyField;
import 'package:tfc/painter/advantys_stb/ddi3725.dart';
import 'package:tfc/painter/advantys_stb/io16.dart';
import 'package:tfc/painter/beckhoff/io8.dart' show IOState;

void main() {
  group('kSTBChannelBitOrder + bitmaskToLedStates', () {
    // TODO(stb-bit-order): Bit-order is LSB-first per CONTEXT.md §Bit-Ordering.
    // Backend team must confirm Schneider Advantys STB convention before goldens
    // lock (Plan 02). If MSB-first: flip `kSTBChannelBitOrder` constant default +
    // flip the 0x0001/0x8000/0xAAAA index expectations in this group; painter math
    // is unchanged.

    test('bit-order constant default is LSB-first (locked canary)', () {
      expect(kSTBChannelBitOrder, STBBitOrder.lsbFirst);
    });

    test('output length contract is always 16', () {
      expect(bitmaskToLedStates(0).length, 16);
    });

    test('0x0000 → all 16 entries IOState.low', () {
      final states = bitmaskToLedStates(0x0000);
      expect(states, List.filled(16, IOState.low));
    });

    test('0x0001 → only channel 1 (index 0) lit', () {
      final states = bitmaskToLedStates(0x0001);
      expect(states[0], IOState.high);
      for (int i = 1; i < 16; i++) {
        expect(states[i], IOState.low, reason: 'index $i should be low');
      }
    });

    test('0x8000 → only channel 16 (index 15) lit', () {
      final states = bitmaskToLedStates(0x8000);
      expect(states[15], IOState.high);
      for (int i = 0; i < 15; i++) {
        expect(states[i], IOState.low, reason: 'index $i should be low');
      }
    });

    test('0xAAAA → odd indices (channels 2,4,6,8,10,12,14,16) lit', () {
      final states = bitmaskToLedStates(0xAAAA);
      for (int i = 0; i < 16; i++) {
        if (i.isOdd) {
          expect(states[i], IOState.high,
              reason: 'index $i (channel ${i + 1}) should be high');
        } else {
          expect(states[i], IOState.low,
              reason: 'index $i (channel ${i + 1}) should be low');
        }
      }
    });

    test('0xFFFF → all 16 entries IOState.high', () {
      final states = bitmaskToLedStates(0xFFFF);
      expect(states, List.filled(16, IOState.high));
    });

    test('forceValues[0] == 1 collapses raw high → forcedLow', () {
      // raw 0xFFFF would normally render all 16 channels high; the force value
      // on channel 1 must collapse that channel to forcedLow (no corner pip).
      final states = bitmaskToLedStates(
        0xFFFF,
        forceValues: const <int>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(states[0], IOState.forcedLow);
      for (int i = 1; i < 16; i++) {
        expect(states[i], IOState.high,
            reason: 'index $i should remain high');
      }
    });

    test('forceValues[1] == 2 collapses raw low → forcedHigh', () {
      // raw 0x0000 would normally render all 16 channels low; the force value
      // on channel 2 must collapse that channel to forcedHigh (no corner pip).
      final states = bitmaskToLedStates(
        0x0000,
        forceValues: const <int>[0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(states[1], IOState.forcedHigh);
      expect(states[0], IOState.low);
      for (int i = 2; i < 16; i++) {
        expect(states[i], IOState.low, reason: 'index $i should remain low');
      }
    });
  });

  group('STBDDI3725Config — data shape', () {
    test('preview() succeeds with nameOrId=="1" and all five *Key fields null',
        () {
      final c = STBDDI3725Config.preview();
      expect(c.nameOrId, '1');
      expect(c.rawStateKey, isNull);
      expect(c.forceValuesKey, isNull);
      expect(c.onFiltersKey, isNull);
      expect(c.offFiltersKey, isNull);
      expect(c.descriptionsKey, isNull);
    });

    test('toJson()["asset_name"] == "STBDDI3725Config" (BaseAsset variant auto-set)',
        () {
      final c = STBDDI3725Config(nameOrId: 'DI-01', rawStateKey: 'di/raw');
      final json = c.toJson();
      expect(json['asset_name'], 'STBDDI3725Config');
    });

    test('allKeys picks up all five *Key fields via the Key\$ regex (no override needed)',
        () {
      final c = STBDDI3725Config(
        nameOrId: 'DI-01',
        rawStateKey: 'di/raw',
        forceValuesKey: 'di/force',
        descriptionsKey: 'di/desc',
      );
      expect(c.allKeys.toSet(), {'di/raw', 'di/force', 'di/desc'});
    });

    test('fromJson(toJson()) round-trips cleanly via real JSON encode/decode',
        () {
      // Real production round-trip goes through `jsonEncode`/`jsonDecode` (see
      // `lib/page_creator/page.dart`), which invokes nested `Coordinates.toJson`
      // / `RelativeSize.toJson` via their own `toJson` methods. Going through
      // `Map<String, dynamic>` directly leaves them as Dart objects (matches
      // Beckhoff EL1008 — same generated code shape).
      final original = STBDDI3725Config(
        nameOrId: 'X',
        rawStateKey: 'a/raw',
        forceValuesKey: 'a/force',
        onFiltersKey: 'a/onf',
        offFiltersKey: 'a/offf',
        descriptionsKey: 'a/desc',
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final parsed = STBDDI3725Config.fromJson(decoded);
      expect(parsed.nameOrId, 'X');
      expect(parsed.rawStateKey, 'a/raw');
      expect(parsed.forceValuesKey, 'a/force');
      expect(parsed.onFiltersKey, 'a/onf');
      expect(parsed.offFiltersKey, 'a/offf');
      expect(parsed.descriptionsKey, 'a/desc');
    });

    test('legacy JSON without nameOrId loads as "1" (QUAL-04 back-compat)', () {
      // Construct a minimal legacy JSON blob lacking nameOrId — the
      // @JsonKey(defaultValue: '1') annotation must rehydrate it.
      final legacyJson = <String, dynamic>{
        'asset_name': 'STBDDI3725Config',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final parsed = STBDDI3725Config.fromJson(legacyJson);
      expect(parsed.nameOrId, '1');
      expect(parsed.rawStateKey, isNull);
    });
  });

  group('STBDDI3725BodyPainter shouldRepaint contract', () {
    STBDDI3725BodyPainter makePainter({
      List<IOState>? ledStates,
      bool isStale = false,
      bool isDisconnected = false,
      int animationValue = 0,
    }) {
      return STBDDI3725BodyPainter(
        ledStates: ledStates ?? List<IOState>.filled(16, IOState.low),
        isStale: isStale,
        isDisconnected: isDisconnected,
        animation: AlwaysStoppedAnimation<int>(animationValue),
      );
    }

    test('same inputs → shouldRepaint=false', () {
      final a = makePainter();
      final b = makePainter();
      expect(a.shouldRepaint(b), isFalse);
    });

    test('different ledStates → shouldRepaint=true', () {
      final a = makePainter();
      final b = makePainter(
          ledStates: List<IOState>.filled(16, IOState.high));
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different isStale → shouldRepaint=true', () {
      final a = makePainter(isStale: false);
      final b = makePainter(isStale: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different isDisconnected → shouldRepaint=true', () {
      final a = makePainter(isDisconnected: false);
      final b = makePainter(isDisconnected: true);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different animation.value → shouldRepaint=true', () {
      final a = makePainter(animationValue: 0);
      final b = makePainter(animationValue: 128);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('cross-runtimeType → shouldRepaint=true (Pitfall 3 guard)', () {
      final p = makePainter();
      final other = _DummyDDI3725Painter();
      expect(p.shouldRepaint(other), isTrue);
    });
  });

  group('STBDDI3725Config.configure — editor surface', () {
    // Mirrors elevator_widget_test's `openConfigEditor` pattern: stage the
    // dialog behind an ElevatedButton + showDialog so the editor body resolves
    // its Material/Theme ancestors. KeyField is a ConsumerStatefulWidget that
    // futures-on stateManProvider — under ProviderScope without overrides the
    // future never completes, but the widget tree is still pumped and findable
    // (KeyField renders a placeholder while waiting). That's enough to verify
    // the editor surface locks the 5-KeyField shape.
    Future<void> openEditor(WidgetTester tester, STBDDI3725Config cfg) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(child: cfg.configure(context)),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(); // open dialog frame
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('all 5 KeyField labels + Name or ID present', (tester) async {
      final cfg = STBDDI3725Config.preview();
      await openEditor(tester, cfg);

      expect(find.text('Name or ID'), findsOneWidget);
      expect(find.text('Raw State Key'), findsOneWidget);
      expect(find.text('Force Values Key'), findsOneWidget);
      expect(find.text('On Filters Key'), findsOneWidget);
      expect(find.text('Off Filters Key'), findsOneWidget);
      expect(find.text('Descriptions Key'), findsOneWidget);
    });

    testWidgets('exactly 5 KeyField widgets in editor tree', (tester) async {
      final cfg = STBDDI3725Config.preview();
      await openEditor(tester, cfg);
      // Locks the editor surface — Phase 3 will not silently drop a field.
      expect(find.byType(KeyField), findsNWidgets(5));
    });
  });

  group('STBDDI3725Widget — mount sanity', () {
    testWidgets('pumps cleanly with 16 low LEDs (no exceptions)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: STBDDI3725Widget(
                  ledStates: List<IOState>.filled(16, IOState.low),
                  isStale: false,
                  isDisconnected: false,
                  animation: const AlwaysStoppedAnimation<int>(0),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      expect(find.byType(STBDDI3725Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _DummyDDI3725Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
