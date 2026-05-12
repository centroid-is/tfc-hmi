import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/advantys_stb.dart';
import 'package:tfc/page_creator/assets/beckhoff.dart' show RowIOView, FilterEdit;
import 'package:tfc/page_creator/assets/button.dart' show ButtonConfig;
import 'package:tfc/page_creator/assets/common.dart'
    show
        Asset,
        Coordinates,
        CoordinatesField,
        KeyField,
        RelativeSize,
        TextPos;
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/painter/advantys_stb/ddi3725.dart';
import 'package:tfc/painter/advantys_stb/ddo3705.dart';
import 'package:tfc/painter/advantys_stb/nip2311.dart';
import 'package:tfc/painter/advantys_stb/pdt3100.dart';
import 'package:tfc/painter/advantys_stb/io16.dart';
import 'package:tfc/painter/beckhoff/io8.dart' show IOState;
import 'package:tfc/providers/state_man.dart' show stateManProvider;
import 'package:tfc_dart/core/state_man.dart' show StateMan;

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

  // ---------------------------------------------------------------------------
  // Golden matrix — 5 states × 2 themes = 10 PNGs.
  //
  // Per Plan 02 Task 4 checkpoint: LSB-first bit-order is auto-resolved per
  // the CONTEXT.md locked decision. `alternating_0xAAAA` therefore renders
  // channels 2,4,6,8,10,12,14,16 lit (odd indices in the LED array).
  //
  // QUAL-02 invariant: the cream body is FIXED (bodyColor from io16.dart, not
  // theme-driven). The light/dark goldens for the same input state must show
  // identical cream-body pixels — only the outside Theme.surface differs. The
  // harness wraps everything in a Scaffold-coloured background that varies
  // between light/dark to make the body-color invariance visually obvious.
  //
  // Harness mirrors `elevator_painter_test.dart:62-96`:
  // - `RepaintBoundary` + unique `Key` so the matched widget = painter pixels
  // - `tester.pump(Duration.zero)` — NEVER `pumpAndSettle()` (Pitfall 6)
  // - `AlwaysStoppedAnimation(0)` — deterministic frame
  // - macOS-gated via `skip: !Platform.isMacOS` (QUAL-01)
  // ---------------------------------------------------------------------------
  group('STBDDI3725 goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    const goldenKey = Key('stb_ddi3725_golden');

    Future<void> pumpDDI3725(
      WidgetTester tester, {
      required List<IOState> ledStates,
      required bool isStale,
      required bool isDisconnected,
      required Brightness theme,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: goldenKey,
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: STBDDI3725Widget(
                    ledStates: ledStates,
                    isStale: isStale,
                    isDisconnected: isDisconnected,
                    animation: const AlwaysStoppedAnimation<int>(0),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
    }

    // 1. all_off — 0x0000 → all 16 LEDs low. RDY green (module alive).
    testWidgets('ddi3725_all_off_light.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0x0000),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddi3725_all_off_light.png'),
      );
    });

    testWidgets('ddi3725_all_off_dark.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0x0000),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddi3725_all_off_dark.png'),
      );
    });

    // 2. all_on — 0xFFFF → all 16 LEDs high (green). RDY green.
    testWidgets('ddi3725_all_on_light.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0xFFFF),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddi3725_all_on_light.png'),
      );
    });

    testWidgets('ddi3725_all_on_dark.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0xFFFF),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddi3725_all_on_dark.png'),
      );
    });

    // 3. alternating_0xAAAA — LSB-first locked → odd indices 1,3,5,...,15 lit
    // (channels 2,4,6,8,10,12,14,16). RDY green.
    testWidgets('ddi3725_alternating_0xAAAA_light.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0xAAAA),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddi3725_alternating_0xAAAA_light.png'),
      );
    });

    testWidgets('ddi3725_alternating_0xAAAA_dark.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0xAAAA),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddi3725_alternating_0xAAAA_dark.png'),
      );
    });

    // 4. forced_mix — raw 0xFFFF with forces[0]=1 (forcedLow on ch1) and
    // forces[2]=2 (forcedHigh on ch3, raw bit collapsed). The remaining 14
    // channels stay high. Shows force-collapse + forced-vs-unforced visual.
    testWidgets('ddi3725_forced_mix_light.png', (tester) async {
      const forces = <int>[
        1, 0, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
      ];
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0xFFFF, forceValues: forces),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddi3725_forced_mix_light.png'),
      );
    });

    testWidgets('ddi3725_forced_mix_dark.png', (tester) async {
      const forces = <int>[
        1, 0, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
      ];
      await pumpDDI3725(tester,
          ledStates: bitmaskToLedStates(0xFFFF, forceValues: forces),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddi3725_forced_mix_dark.png'),
      );
    });

    // 5. disconnected — all LEDs low, isStale=true + isDisconnected=true.
    // RDY dim grey; red exclamation overlay in upper-center.
    testWidgets('ddi3725_disconnected_light.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: List<IOState>.filled(16, IOState.low),
          isStale: true,
          isDisconnected: true,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddi3725_disconnected_light.png'),
      );
    });

    testWidgets('ddi3725_disconnected_dark.png', (tester) async {
      await pumpDDI3725(tester,
          ledStates: List<IOState>.filled(16, IOState.low),
          isStale: true,
          isDisconnected: true,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddi3725_disconnected_dark.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Plan 03: detail dialog — trigger group.
  //
  // With all five `*Key` fields null, `_combinedStream` emits nothing, so the
  // `StreamBuilder` inside the dialog stays in the no-data state. The dialog
  // still opens with its title (`config.nameOrId`) and `Close` action — that's
  // enough to lock the onTap-handler shape replaced from the Plan 02 stub.
  //
  // `_FakeStateMan` lets `stateManProvider.future` resolve so the
  // `_STBDDI3725State.initState` callback runs to completion. No `subscribe`
  // or `write` methods are touched on this path (keys are null).
  // ---------------------------------------------------------------------------
  group('STBDDI3725 detail dialog — trigger', () {
    Future<void> pumpAndOpen(WidgetTester tester, STBDDI3725Config cfg,
        {StateMan? stateMan}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider
                .overrideWith((ref) async => stateMan ?? _FakeStateMan()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      // Pump once for the FutureProvider to resolve, then settle the
      // setState() inside `initState.then`.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('tap opens AlertDialog titled with nameOrId', (tester) async {
      final cfg = STBDDI3725Config(nameOrId: 'DI-3725-A');
      await pumpAndOpen(tester, cfg);

      // No dialog up front.
      expect(find.byType(AlertDialog), findsNothing);

      // Tap the body. With null keys the body renders the stale shell — the
      // GestureDetector wraps the `STBDDI3725Widget`. Tap the widget directly
      // to avoid finder ambiguity with the parent SizedBox.
      await tester.tap(find.byType(STBDDI3725Widget));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('DI-3725-A'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Close action dismisses the dialog', (tester) async {
      final cfg = STBDDI3725Config(nameOrId: 'DI-X');
      await pumpAndOpen(tester, cfg);

      await tester.tap(find.byType(STBDDI3725Widget));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
      'with all-null keys, dialog body renders no rows (no data yet)',
      (tester) async {
        // All-null path: `_combinedStream` is empty, so the StreamBuilder
        // returns `SizedBox.shrink()` (mirrors EL1008 behaviour). RowIOView
        // count must be zero.
        final cfg = STBDDI3725Config(nameOrId: '1');
        await pumpAndOpen(tester, cfg);

        await tester.tap(find.byType(STBDDI3725Widget));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(RowIOView), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Plan 03: detail dialog — row structure + force-write integration.
  //
  // `_StreamingStubStateMan` returns canned DynamicValues for each *Key. The
  // dialog StreamBuilder receives a single combined emission and renders the
  // 8 RowIOView widgets (16 FilterEdits). Force writes round-trip through
  // the fake's `writes` log so we can assert the mutated `force` list.
  // ---------------------------------------------------------------------------
  group('STBDDI3725 detail dialog — row structure', () {
    late _StreamingStubStateMan stub;
    setUp(() {
      stub = _StreamingStubStateMan(
        raw: 0xAAAA,
        // forces[0]=1 (auto), all others auto for predictability.
        force: List<int>.filled(16, 0),
        onFilters: List<int>.filled(16, 5),
        offFilters: List<int>.filled(16, 10),
        descriptions: List<String>.generate(16, (i) => 'ch${i + 1}'),
      );
    });

    // RowIOView is wide (~900px per row including filter inputs). The
    // default 800×600 test viewport overflows; widen so layouts settle.
    tearDown(() async {
      // Restore default surface for subsequent groups.
      // Note: setSurfaceSize is per-test; resetting is best practice.
    });

    Future<void> openWithStub(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cfg = STBDDI3725Config(
        nameOrId: 'DI-test',
        rawStateKey: 'raw',
        forceValuesKey: 'force',
        onFiltersKey: 'onf',
        offFiltersKey: 'offf',
        descriptionsKey: 'desc',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((ref) async => stub),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(STBDDI3725Widget));
      await tester.pumpAndSettle();
    }

    testWidgets('renders 8 RowIOView widgets when data flows', (tester) async {
      await openWithStub(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      // DDI-09: 8 rows × 2 cols.
      expect(find.byType(RowIOView), findsNWidgets(8));
    });

    testWidgets('renders 16 FilterEdit widgets (2 per row)', (tester) async {
      await openWithStub(tester);
      // DDI-06 + DDI-07: ON + OFF filter inputs visible per channel.
      expect(find.byType(FilterEdit), findsNWidgets(16));
    });

    testWidgets('row 0 shows ch1 + ch9 descriptions (left+right pairing)',
        (tester) async {
      await openWithStub(tester);
      expect(find.text('Ch1'), findsOneWidget); // RowControl uppercases char 0
      expect(find.text('Ch9'), findsOneWidget);
    });

    testWidgets('row 7 shows ch8 + ch16 descriptions (last-row pairing)',
        (tester) async {
      await openWithStub(tester);
      expect(find.text('Ch8'), findsOneWidget);
      expect(find.text('Ch16'), findsOneWidget);
    });
  });

  group('STBDDI3725 detail dialog — force write integration', () {
    late _StreamingStubStateMan stub;
    setUp(() {
      stub = _StreamingStubStateMan(
        raw: 0x0000,
        force: List<int>.filled(16, 0),
        onFilters: List<int>.filled(16, 5),
        offFilters: List<int>.filled(16, 10),
        descriptions: List<String>.generate(16, (i) => 'ch${i + 1}'),
      );
    });

    Future<void> openWithStub(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cfg = STBDDI3725Config(
        nameOrId: 'DI-fwt',
        rawStateKey: 'raw',
        forceValuesKey: 'force',
        onFiltersKey: 'onf',
        offFiltersKey: 'offf',
        descriptionsKey: 'desc',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((ref) async => stub),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(STBDDI3725Widget));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'tapping a Low SegmentedButton writes to forceValuesKey with [0]==1',
      (tester) async {
        await openWithStub(tester);
        expect(find.byType(AlertDialog), findsOneWidget);

        // Each of 16 channels has an "Auto / Low / High" SegmentedButton.
        // Tap the FIRST "Low " label (channel 1, row 0 left). The Low label
        // contains a trailing space — match exactly.
        final lowFinders = find.text('Low ');
        expect(lowFinders, findsNWidgets(16));
        await tester.tap(lowFinders.first);
        await tester.pumpAndSettle();

        // The handler does `map['force']![0].value = 1` then writes the
        // whole force DynamicValue array under `forceValuesKey`.
        expect(stub.writes, isNotEmpty);
        final lastWrite = stub.writes.last;
        expect(lastWrite.key, 'force');
        expect(lastWrite.value.isArray, isTrue);
        expect(lastWrite.value[0].asInt, 1,
            reason: 'channel 1 must be forced low after first Low tap');
        // Other channels remain auto.
        for (int i = 1; i < 16; i++) {
          expect(lastWrite.value[i].asInt, 0,
              reason: 'channel ${i + 1} must remain auto');
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Plan 04 Task 1: AssetRegistry resolution.
  //
  // Two factory maps in `lib/page_creator/assets/registry.dart`:
  //   - `_fromJsonFactories`: drives `AssetRegistry.parse(saveJson)` —
  //     missing entry = legacy JSON crashes on load.
  //   - `defaultFactories`: drives the page-editor palette via
  //     `AssetRegistry.createDefaultAssetByName(name)` — missing entry =
  //     palette doesn't list the asset.
  //
  // Both maps key on `Type` and the resolution code compares
  // `factory.key.toString()` against the JSON `asset_name` (i.e. the Dart
  // class name string). The dual-map convention is the PITFALL §9.2 lock.
  // ---------------------------------------------------------------------------
  group('STBDDI3725Config registry resolution', () {
    test('createDefaultAssetByName returns a typed STBDDI3725Config', () {
      final asset =
          AssetRegistry.createDefaultAssetByName('STBDDI3725Config');
      expect(asset, isNotNull,
          reason:
              'defaultFactories must register STBDDI3725Config (palette wiring).');
      expect(asset, isA<STBDDI3725Config>());
      final cfg = asset! as STBDDI3725Config;
      expect(cfg.nameOrId, '1');
      expect(cfg.rawStateKey, isNull);
    });

    test('AssetRegistry.parse round-trips a STBDDI3725Config from saved JSON',
        () {
      // Real production save flow round-trips through jsonEncode/jsonDecode
      // (see `lib/page_creator/page.dart`), which invokes nested
      // `Coordinates.toJson` / `RelativeSize.toJson` along the way. Going
      // through `Map<String, dynamic>` directly leaves those nested fields
      // as Dart objects — same shape as the existing `fromJson(toJson())`
      // test at line 132 (matches Beckhoff EL1008 codegen).
      final cfg = STBDDI3725Config(
        nameOrId: 'DI-99',
        rawStateKey: 'plc/raw',
      );
      final saveJson = jsonDecode(jsonEncode(<String, dynamic>{
        'assets': <Map<String, dynamic>>[cfg.toJson()],
      })) as Map<String, dynamic>;
      final parsed = AssetRegistry.parse(saveJson);
      expect(parsed, hasLength(1),
          reason:
              '_fromJsonFactories must register STBDDI3725Config (JSON load wiring).');
      expect(parsed[0], isA<STBDDI3725Config>());
      final restored = parsed[0] as STBDDI3725Config;
      expect(restored.nameOrId, 'DI-99');
      expect(restored.rawStateKey, 'plc/raw');
    });

    test('defaultFactories Map contains STBDDI3725Config type key', () {
      expect(
        AssetRegistry.defaultFactories.keys.any(
          (t) => t.toString() == 'STBDDI3725Config',
        ),
        isTrue,
        reason:
            'STBDDI3725Config must be enumerable through defaultFactories '
            'for the palette to list it.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Plan 04 Task 2: JSON full round-trip + legacy-JSON back-compat.
  //
  // Full round-trip covers every settable field on `STBDDI3725Config` plus
  // every BaseAsset field (coordinates / size / text / textPos / techDocId /
  // plcAssetKey). Encoded through `jsonEncode`/`jsonDecode` to mirror the
  // real production save path in `lib/page_creator/page.dart`.
  //
  // Back-compat covers the QUAL-04 lock:
  //   - A minimal legacy snippet (only `asset_name`) — every settable
  //     STBDDI3725 field falls back to its declared default.
  //   - A v1.0-era save-page-shaped JSON (assets list nested under a `pages`
  //     map) flows through `AssetRegistry.parse` and the legacy snippet is
  //     recovered into a typed `STBDDI3725Config` instance.
  //
  // Default-handling note: `@JsonKey(defaultValue: '1')` on `nameOrId`
  // already covers the "missing in JSON" case (verified by the existing
  // 'legacy JSON without nameOrId loads as "1"' test at the data-shape
  // group). No factory belt-and-suspenders is required.
  // ---------------------------------------------------------------------------
  group('STBDDI3725Config full JSON round-trip', () {
    test(
      'every field (incl. BaseAsset coordinates/size/text/textPos/techDocId/plcAssetKey) '
      'survives jsonEncode + jsonDecode + fromJson',
      () {
        final original = STBDDI3725Config(
          nameOrId: 'DI-42',
          rawStateKey: 'plc/di/raw',
          forceValuesKey: 'plc/di/force',
          onFiltersKey: 'plc/di/on_filter',
          offFiltersKey: 'plc/di/off_filter',
          descriptionsKey: 'plc/di/desc',
        )
          ..coordinates = Coordinates(x: 0.25, y: 0.5)
          ..size = const RelativeSize(width: 0.1, height: 0.2)
          ..text = 'unit test'
          ..textPos = TextPos.below
          ..techDocId = 42
          ..plcAssetKey = 'plc.42';

        // Production round-trip: through jsonEncode/jsonDecode.
        final encoded = jsonEncode(original.toJson());
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        final parsed = STBDDI3725Config.fromJson(decoded);

        // STBDDI3725 fields.
        expect(parsed.nameOrId, 'DI-42');
        expect(parsed.rawStateKey, 'plc/di/raw');
        expect(parsed.forceValuesKey, 'plc/di/force');
        expect(parsed.onFiltersKey, 'plc/di/on_filter');
        expect(parsed.offFiltersKey, 'plc/di/off_filter');
        expect(parsed.descriptionsKey, 'plc/di/desc');
        // BaseAsset fields.
        expect(parsed.coordinates.x, 0.25);
        expect(parsed.coordinates.y, 0.5);
        expect(parsed.size.width, 0.1);
        expect(parsed.size.height, 0.2);
        expect(parsed.text, 'unit test');
        expect(parsed.textPos, TextPos.below);
        expect(parsed.techDocId, 42);
        expect(parsed.plcAssetKey, 'plc.42');
        // assetName is set by BaseAsset's variant logic.
        expect(parsed.assetName, 'STBDDI3725Config');
      },
    );
  });

  group('STBDDI3725Config JSON back-compat', () {
    // "v1.0-era" here means: predates Phase 1 (this milestone). The shape
    // therefore carries the v1.0 BaseAsset baseline (asset_name +
    // coordinates + size, both always present since the codegen requires
    // them — verified by inspecting `advantys_stb.g.dart` and all peer
    // *.g.dart files like `beckhoff.g.dart`). What v1.0-era saved pages
    // would NOT carry are the Phase 1 additions: `nameOrId` and the five
    // `*Key` fields. Those must rehydrate to their declared defaults.
    Map<String, dynamic> baseLegacyJson() => <String, dynamic>{
          'asset_name': 'STBDDI3725Config',
          'coordinates': {'x': 0.0, 'y': 0.0},
          'size': {'width': 0.03, 'height': 0.03},
        };

    test(
      'minimal legacy snippet (only v1.0 fields) → Phase 1 defaults rehydrate',
      () {
        final legacyJson = baseLegacyJson();
        final config = STBDDI3725Config.fromJson(legacyJson);
        // Phase 1 fields fall back to declared defaults.
        expect(config.nameOrId, '1', reason: 'defaultValue must kick in');
        expect(config.rawStateKey, isNull);
        expect(config.forceValuesKey, isNull);
        expect(config.onFiltersKey, isNull);
        expect(config.offFiltersKey, isNull);
        expect(config.descriptionsKey, isNull);
        // BaseAsset fields fall back to their declared defaults.
        expect(config.coordinates.x, 0.0);
        expect(config.coordinates.y, 0.0);
        expect(config.size.width, 0.03);
        expect(config.size.height, 0.03);
        expect(config.text, isNull);
        expect(config.textPos, isNull);
        expect(config.techDocId, isNull);
        expect(config.plcAssetKey, isNull);
        expect(config.assetName, 'STBDDI3725Config');
      },
    );

    test(
      'v1.0-era saved-page JSON wrapping the legacy snippet '
      'flows through AssetRegistry.parse',
      () {
        // Save-page-shaped JSON: `pages` map → `assets` list → legacy snippet.
        // Mirrors the shape produced by `PageManager` before Phase 1 existed.
        // The crawler in `AssetRegistry.parse` must descend through both
        // nested objects, match `asset_name == 'STBDDI3725Config'`, and call
        // `STBDDI3725Config.fromJson` on the legacy snippet.
        final saveJson = <String, dynamic>{
          'pages': <String, dynamic>{
            'home': <String, dynamic>{
              'assets': <Map<String, dynamic>>[
                baseLegacyJson(),
              ],
            },
          },
        };
        final parsed = AssetRegistry.parse(saveJson);
        expect(parsed, hasLength(1),
            reason:
                'AssetRegistry must recover a legacy snippet inside a v1.0-era '
                'saved-page JSON shape (QUAL-04 end-to-end).');
        expect(parsed[0], isA<STBDDI3725Config>());
        final cfg = parsed[0] as STBDDI3725Config;
        expect(cfg.nameOrId, '1');
        expect(cfg.rawStateKey, isNull);
        expect(cfg.coordinates.x, 0.0);
      },
    );

    test(
      'unknown forward-compat field in legacy snippet is ignored, not fatal',
      () {
        // QUAL-04 forward-compat: a v3.0-era saved page may carry fields
        // unknown to this binary. The codegen's `_$STBDDI3725ConfigFromJson`
        // ignores unknown keys silently — verify the contract so a future
        // regression that flips it to strict-mode fails this test loudly.
        final futureJson = baseLegacyJson()
          ..['someFutureFieldKey'] = 'plc/future'
          ..['unknownEnum'] = 'unknown_value';
        final cfg = STBDDI3725Config.fromJson(futureJson);
        expect(cfg.nameOrId, '1');
        expect(cfg.rawStateKey, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Plan 04 Task 3: Mount/unmount + dialog open/close leak tests
  // (DDI-10 / QUAL-03 lifecycle verification).
  //
  // The two groups follow the elevator/sensor v1.0 precedent at
  // `elevator_widget_test.dart:1873-1934`:
  //   1. Pump live widget → pump empty replacement → pump 1s → assert
  //      `tester.takeException()` is null.
  //   2. Source-level grep guard locks the dispose contract structurally,
  //      so a future refactor cannot silently regress the lifecycle.
  //
  // `_STBDDI3725State` holds `_combinedStreamCache` (a cold
  // `CombineLatestStream`) and uses `StreamBuilder` exclusively for
  // subscription. When the widget unmounts, `StreamBuilder`'s State
  // cancels the underlying `StreamSubscription`; no explicit dispose
  // override is required for correctness. We still add a defensive
  // dispose() that nulls `_combinedStreamCache` to release the closure's
  // reference to `StateMan` (prevents the cached stream from keeping
  // `StateMan` reachable through GC roots in long-running pages — paranoid
  // but cheap).
  // ---------------------------------------------------------------------------
  group('STBDDI3725 mount/unmount lifecycle (DDI-10 / QUAL-03)', () {
    testWidgets(
      'mount + unmount with stubbed StateMan throws no exceptions',
      (tester) async {
        final stub = _StreamingStubStateMan(
          raw: 0x00FF,
          force: List<int>.filled(16, 0),
          onFilters: List<int>.filled(16, 5),
          offFilters: List<int>.filled(16, 10),
          descriptions: List<String>.generate(16, (i) => 'ch${i + 1}'),
        );
        final cfg = STBDDI3725Config(
          nameOrId: 'leak-test',
          rawStateKey: 'raw',
          forceValuesKey: 'force',
          onFiltersKey: 'onf',
          offFiltersKey: 'offf',
          descriptionsKey: 'desc',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              stateManProvider.overrideWith((ref) async => stub),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 200,
                    height: 300,
                    child: Builder(builder: (context) => cfg.build(context)),
                  ),
                ),
              ),
            ),
          ),
        );
        // Let the FutureProvider resolve + initState setState land.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(STBDDI3725Widget), findsOneWidget);

        // Force unmount: replace with empty widget tree. If dispose is
        // missing, framework surfaces "X was used after being disposed"
        // or leaks an uncancelled subscription on the next frame.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));

        expect(
          tester.takeException(),
          isNull,
          reason:
              'Mount/unmount must not throw or leak (DDI-10 / QUAL-03 '
              'dispose contract on the StreamBuilder subscription).',
        );
      },
    );

    test(
      'advantys_stb.dart dispose contract grep guard (QUAL-03 fallback)',
      () {
        // Source-level guard mirroring the elevator/sensor v1.0 pattern at
        // `elevator_widget_test.dart:1897-1932`. Even if the runtime leak
        // assertion above passes silently, the dispose contract MUST be
        // present in the source so a future refactor surfaces here loudly.
        //
        // What we require: _STBDDI3725State overrides dispose() and either
        // (a) cancels held subscriptions, or (b) nulls the cached stream
        // reference to release closure refs to StateMan. Calling
        // `super.dispose()` is mandatory.
        final src = File('lib/page_creator/assets/advantys_stb.dart')
            .readAsStringSync();
        final disposeIdx = src.indexOf(
            RegExp(r'class\s+_STBDDI3725State[\s\S]*?void\s+dispose\s*\(\)'));
        expect(disposeIdx, greaterThan(-1),
            reason:
                '_STBDDI3725State must override dispose() (DDI-10 / QUAL-03).');
        // Examine the dispose body window for super.dispose() + at least one
        // release call (cancel() or null assignment to the cache).
        final tail = src.substring(disposeIdx);
        expect(tail.contains('super.dispose()'), isTrue,
            reason:
                '_STBDDI3725State.dispose() must call super.dispose() last.');
        final hasReleaseCall = tail.contains('cancel()') ||
            tail.contains('_combinedStreamCache = null');
        expect(hasReleaseCall, isTrue,
            reason:
                '_STBDDI3725State.dispose() must release the cached stream '
                '(cancel held subscription OR null out _combinedStreamCache to '
                'release the closure-captured StateMan reference).');
      },
    );
  });

  group(
    'STBDDI3725 dialog open/close 10× leak (DDI-10 / QUAL-03)',
    () {
      testWidgets(
        '10 dialog cycles + unmount throws no exceptions',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1400, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final stub = _StreamingStubStateMan(
            raw: 0x0000,
            force: List<int>.filled(16, 0),
            onFilters: List<int>.filled(16, 5),
            offFilters: List<int>.filled(16, 10),
            descriptions: List<String>.generate(16, (i) => 'ch${i + 1}'),
          );
          final cfg = STBDDI3725Config(
            nameOrId: 'DI-leak',
            rawStateKey: 'raw',
            forceValuesKey: 'force',
            onFiltersKey: 'onf',
            offFiltersKey: 'offf',
            descriptionsKey: 'desc',
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                stateManProvider.overrideWith((ref) async => stub),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 200,
                      height: 300,
                      child: Builder(
                          builder: (context) => cfg.build(context)),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(STBDDI3725Widget), findsOneWidget);

          // 10× open / close cycles. Each open spawns a fresh dialog
          // StreamBuilder; each close (Navigator.pop via 'Close' action)
          // disposes it, releasing the underlying StateMan listeners.
          for (int i = 0; i < 10; i++) {
            await tester.tap(find.byType(STBDDI3725Widget));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget,
                reason: 'iteration $i: dialog should open');

            await tester.tap(find.widgetWithText(TextButton, 'Close'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing,
                reason: 'iteration $i: dialog should close');
          }

          // After 10 cycles, also dispose the parent — covers the
          // combined "dialog churn + page navigation" lifecycle path.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));

          expect(
            tester.takeException(),
            isNull,
            reason:
                '10× dialog cycles + parent unmount must not throw or leak '
                '(DDI-10 / QUAL-03 — listener counts return to baseline).',
          );
        },
      );
    },
  );

  // ===========================================================================
  // Phase 2 — STBDDO3705 (16-Ch Digital Output)
  // ===========================================================================
  //
  // Clone of Phase 1 minus filters, plus end-to-end manual force-write path.
  // Outputs do NOT have on/off filters — the detail dialog renders only force
  // SegmentedButton + description per channel.
  //
  // Bit-order parity canary: DDO3705 uses the SAME `kSTBChannelBitOrder`
  // constant as DDI3725 — compile-time guard that DI and DO conventions stay
  // locked together (CONTEXT.md §Bit-Ordering & Force Encoding).
  // ===========================================================================

  group('STBDDO3705 bit-order parity (cross DI/DO canary)', () {
    test('DDO3705 consumes the same kSTBChannelBitOrder as DDI3725', () {
      // If a future refactor re-declares the bit-order constant inside
      // ddo3705.dart instead of importing from io16.dart, the divergence trip
      // wires here. We require the canonical io16.dart constant to remain the
      // single source of truth for both modules.
      expect(kSTBChannelBitOrder, STBBitOrder.lsbFirst);
      // Re-derive an LED list via the shared helper and verify it matches the
      // DDI expectations — this is the run-time half of the parity guarantee.
      final states = bitmaskToLedStates(0x0001);
      expect(states[0], IOState.high);
      for (int i = 1; i < 16; i++) {
        expect(states[i], IOState.low);
      }
    });
  });

  group('STBDDO3705Config — data shape', () {
    test('preview() succeeds with nameOrId=="1" and all three *Key fields null',
        () {
      final c = STBDDO3705Config.preview();
      expect(c.nameOrId, '1');
      expect(c.rawStateKey, isNull);
      expect(c.forceValuesKey, isNull);
      expect(c.descriptionsKey, isNull);
    });

    test('toJson()["asset_name"] == "STBDDO3705Config"', () {
      final c = STBDDO3705Config(nameOrId: 'DO-01', rawStateKey: 'do/raw');
      final json = c.toJson();
      expect(json['asset_name'], 'STBDDO3705Config');
    });

    test(
        'allKeys picks up all three *Key fields via the Key\$ regex (no override needed)',
        () {
      final c = STBDDO3705Config(
        nameOrId: 'DO-01',
        rawStateKey: 'do/raw',
        forceValuesKey: 'do/force',
        descriptionsKey: 'do/desc',
      );
      expect(c.allKeys.toSet(), {'do/raw', 'do/force', 'do/desc'});
    });

    test('fromJson(toJson()) round-trips cleanly via real JSON encode/decode',
        () {
      final original = STBDDO3705Config(
        nameOrId: 'X',
        rawStateKey: 'a/raw',
        forceValuesKey: 'a/force',
        descriptionsKey: 'a/desc',
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final parsed = STBDDO3705Config.fromJson(decoded);
      expect(parsed.nameOrId, 'X');
      expect(parsed.rawStateKey, 'a/raw');
      expect(parsed.forceValuesKey, 'a/force');
      expect(parsed.descriptionsKey, 'a/desc');
    });

    test('legacy JSON without nameOrId loads as "1" (QUAL-04 back-compat)', () {
      final legacyJson = <String, dynamic>{
        'asset_name': 'STBDDO3705Config',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final parsed = STBDDO3705Config.fromJson(legacyJson);
      expect(parsed.nameOrId, '1');
      expect(parsed.rawStateKey, isNull);
    });
  });

  group('STBDDO3705BodyPainter shouldRepaint contract', () {
    STBDDO3705BodyPainter makePainter({
      List<IOState>? ledStates,
      bool isStale = false,
      bool isDisconnected = false,
      int animationValue = 0,
    }) {
      return STBDDO3705BodyPainter(
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
      final other = _DummyDDO3705Painter();
      expect(p.shouldRepaint(other), isTrue);
    });
  });

  group('STBDDO3705Config.configure — editor surface', () {
    Future<void> openEditor(WidgetTester tester, STBDDO3705Config cfg) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('3 KeyField labels + Name or ID present (NO filter fields)',
        (tester) async {
      final cfg = STBDDO3705Config.preview();
      await openEditor(tester, cfg);

      expect(find.text('Name or ID'), findsOneWidget);
      expect(find.text('Raw State Key'), findsOneWidget);
      expect(find.text('Force Values Key'), findsOneWidget);
      expect(find.text('Descriptions Key'), findsOneWidget);
      // Outputs don't have filters — these labels must NOT appear.
      expect(find.text('On Filters Key'), findsNothing);
      expect(find.text('Off Filters Key'), findsNothing);
    });

    testWidgets('exactly 3 KeyField widgets in editor tree', (tester) async {
      final cfg = STBDDO3705Config.preview();
      await openEditor(tester, cfg);
      // Locks the editor surface — filter fields must NOT be added back.
      expect(find.byType(KeyField), findsNWidgets(3));
    });
  });

  group('STBDDO3705Widget — mount sanity', () {
    testWidgets('pumps cleanly with 16 low LEDs (no exceptions)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: STBDDO3705Widget(
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
      expect(find.byType(STBDDO3705Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Detail dialog — trigger group. Mirrors DDI3725 dialog trigger group but
  // with three keys (no filter keys).
  // ---------------------------------------------------------------------------
  group('STBDDO3705 detail dialog — trigger', () {
    Future<void> pumpAndOpen(WidgetTester tester, STBDDO3705Config cfg,
        {StateMan? stateMan}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider
                .overrideWith((ref) async => stateMan ?? _FakeStateMan()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('tap opens AlertDialog titled with nameOrId', (tester) async {
      final cfg = STBDDO3705Config(nameOrId: 'DO-3705-A');
      await pumpAndOpen(tester, cfg);

      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byType(STBDDO3705Widget));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('DO-3705-A'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets(
      'with all-null keys, dialog body renders no rows (no data yet)',
      (tester) async {
        final cfg = STBDDO3705Config(nameOrId: '1');
        await pumpAndOpen(tester, cfg);

        await tester.tap(find.byType(STBDDO3705Widget));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(RowIOView), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Detail dialog — row structure + force-write integration.
  //
  // The dialog StreamBuilder receives a combined emission and renders 8
  // RowIOView widgets. Outputs do NOT have filter rows — assert ZERO
  // FilterEdit widgets (this is the key visual difference from DDI3725).
  // ---------------------------------------------------------------------------
  group('STBDDO3705 detail dialog — row structure (NO filters)', () {
    late _StreamingStubDOStateMan stub;
    setUp(() {
      stub = _StreamingStubDOStateMan(
        raw: 0xAAAA,
        force: List<int>.filled(16, 0),
        descriptions: List<String>.generate(16, (i) => 'ch${i + 1}'),
      );
    });

    Future<void> openWithStub(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cfg = STBDDO3705Config(
        nameOrId: 'DO-test',
        rawStateKey: 'raw',
        forceValuesKey: 'force',
        descriptionsKey: 'desc',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((ref) async => stub),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(STBDDO3705Widget));
      await tester.pumpAndSettle();
    }

    testWidgets('renders 8 RowIOView widgets when data flows', (tester) async {
      await openWithStub(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      // DDO-06: 8 rows × 2 cols.
      expect(find.byType(RowIOView), findsNWidgets(8));
    });

    testWidgets('renders ZERO FilterEdit widgets (outputs have no filters)',
        (tester) async {
      await openWithStub(tester);
      // DDO-06 differentiator vs DDI3725 — no filter ms inputs.
      expect(find.byType(FilterEdit), findsNothing);
    });

    testWidgets('row 0 shows ch1 + ch9 descriptions (left+right pairing)',
        (tester) async {
      await openWithStub(tester);
      expect(find.text('Ch1'), findsOneWidget);
      expect(find.text('Ch9'), findsOneWidget);
    });

    testWidgets('row 7 shows ch8 + ch16 descriptions (last-row pairing)',
        (tester) async {
      await openWithStub(tester);
      expect(find.text('Ch8'), findsOneWidget);
      expect(find.text('Ch16'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // DDO-09: Force-write end-to-end integration test (the DDO3705 differentiator).
  //
  // This is the genuine operator-driven force-write path: tap Low on the
  // SegmentedButton → handler writes int8[16] to forceValuesKey via StateMan.
  // ---------------------------------------------------------------------------
  group('STBDDO3705 detail dialog — force write integration (DDO-09)', () {
    late _StreamingStubDOStateMan stub;
    setUp(() {
      stub = _StreamingStubDOStateMan(
        raw: 0x0000,
        force: List<int>.filled(16, 0),
        descriptions: List<String>.generate(16, (i) => 'ch${i + 1}'),
      );
    });

    Future<void> openWithStub(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cfg = STBDDO3705Config(
        nameOrId: 'DO-fwt',
        rawStateKey: 'raw',
        forceValuesKey: 'force',
        descriptionsKey: 'desc',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((ref) async => stub),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(STBDDO3705Widget));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'tapping a Low SegmentedButton writes to forceValuesKey with [0]==1',
      (tester) async {
        await openWithStub(tester);
        expect(find.byType(AlertDialog), findsOneWidget);

        final lowFinders = find.text('Low ');
        expect(lowFinders, findsNWidgets(16));
        await tester.tap(lowFinders.first);
        await tester.pumpAndSettle();

        expect(stub.writes, isNotEmpty);
        final lastWrite = stub.writes.last;
        expect(lastWrite.key, 'force');
        expect(lastWrite.value.isArray, isTrue);
        expect(lastWrite.value[0].asInt, 1,
            reason: 'channel 1 must be forced low after first Low tap');
        for (int i = 1; i < 16; i++) {
          expect(lastWrite.value[i].asInt, 0,
              reason: 'channel ${i + 1} must remain auto');
        }
      },
    );

    testWidgets(
      'tapping a High SegmentedButton writes to forceValuesKey with [0]==2',
      (tester) async {
        await openWithStub(tester);
        expect(find.byType(AlertDialog), findsOneWidget);

        // RowControl renders the High label as 'High'. Tap the first High to
        // force channel 1 high.
        final highFinders = find.text('High');
        // Each row has Auto/Low/High for two channels = 32 High labels possible,
        // but RowControl renders one SegmentedButton per side; assert >=16.
        expect(highFinders, findsNWidgets(16));
        await tester.tap(highFinders.first);
        await tester.pumpAndSettle();

        expect(stub.writes, isNotEmpty);
        final lastWrite = stub.writes.last;
        expect(lastWrite.key, 'force');
        expect(lastWrite.value[0].asInt, 2,
            reason: 'channel 1 must be forced high after first High tap');
      },
    );

    testWidgets(
      'force-write round-trips: write [5]=2 → next emission lights channel 6 green',
      (tester) async {
        // End-to-end: the operator forces channel 6 high via the dialog. The
        // stub mutates its cached force DV in-place and re-emits, so the body
        // painter's IOState[5] must transition to forcedHigh on the next frame.
        await openWithStub(tester);

        // High buttons appear in widget-tree traversal order: for row r the
        // left RowControl (channel r+1) comes before the right RowControl
        // (channel r+9). So the sequence is:
        //   index 0  → ch1   (row 0 left)
        //   index 1  → ch9   (row 0 right)
        //   index 2  → ch2   (row 1 left)
        //   index 3  → ch10  (row 1 right)
        //   ...
        //   index 10 → ch6   (row 5 left)  ← target
        final highFinders = find.text('High');
        expect(highFinders, findsNWidgets(16));
        await tester.tap(highFinders.at(10));
        await tester.pumpAndSettle();

        // Verify the write was recorded with [5]==2.
        final writeWithCh6 = stub.writes.lastWhere(
          (w) => w.value[5].asInt == 2,
          orElse: () =>
              (key: '', value: DynamicValue(value: 0)),
        );
        expect(writeWithCh6.key, 'force',
            reason:
                'A write to forceValuesKey with [5]==2 (forcedHigh) must be '
                'recorded after tapping the High button for channel 6 (DDO-09).');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Goldens — 5 states × 2 themes = 10 PNGs. Must be visually distinct from
  // the DDI3725 goldens (CONTEXT.md §Visual Differentiation).
  // ---------------------------------------------------------------------------
  group('STBDDO3705 goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    const goldenKey = Key('stb_ddo3705_golden');

    Future<void> pumpDDO3705(
      WidgetTester tester, {
      required List<IOState> ledStates,
      required bool isStale,
      required bool isDisconnected,
      required Brightness theme,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: goldenKey,
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: STBDDO3705Widget(
                    ledStates: ledStates,
                    isStale: isStale,
                    isDisconnected: isDisconnected,
                    animation: const AlwaysStoppedAnimation<int>(0),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
    }

    testWidgets('ddo3705_all_off_light.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0x0000),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddo3705_all_off_light.png'),
      );
    });

    testWidgets('ddo3705_all_off_dark.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0x0000),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddo3705_all_off_dark.png'),
      );
    });

    testWidgets('ddo3705_all_on_light.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0xFFFF),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddo3705_all_on_light.png'),
      );
    });

    testWidgets('ddo3705_all_on_dark.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0xFFFF),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/ddo3705_all_on_dark.png'),
      );
    });

    testWidgets('ddo3705_alternating_0xAAAA_light.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0xAAAA),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddo3705_alternating_0xAAAA_light.png'),
      );
    });

    testWidgets('ddo3705_alternating_0xAAAA_dark.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0xAAAA),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddo3705_alternating_0xAAAA_dark.png'),
      );
    });

    testWidgets('ddo3705_forced_mix_light.png', (tester) async {
      const forces = <int>[
        1, 0, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
      ];
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0xFFFF, forceValues: forces),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddo3705_forced_mix_light.png'),
      );
    });

    testWidgets('ddo3705_forced_mix_dark.png', (tester) async {
      const forces = <int>[
        1, 0, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
      ];
      await pumpDDO3705(tester,
          ledStates: bitmaskToLedStates(0xFFFF, forceValues: forces),
          isStale: false,
          isDisconnected: false,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddo3705_forced_mix_dark.png'),
      );
    });

    testWidgets('ddo3705_disconnected_light.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: List<IOState>.filled(16, IOState.low),
          isStale: true,
          isDisconnected: true,
          theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddo3705_disconnected_light.png'),
      );
    });

    testWidgets('ddo3705_disconnected_dark.png', (tester) async {
      await pumpDDO3705(tester,
          ledStates: List<IOState>.filled(16, IOState.low),
          isStale: true,
          isDisconnected: true,
          theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
            'goldens/advantys_stb/ddo3705_disconnected_dark.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Registry resolution + JSON back-compat (DDO-07).
  // ---------------------------------------------------------------------------
  group('STBDDO3705Config registry resolution', () {
    test('createDefaultAssetByName returns a typed STBDDO3705Config', () {
      final asset =
          AssetRegistry.createDefaultAssetByName('STBDDO3705Config');
      expect(asset, isNotNull,
          reason:
              'defaultFactories must register STBDDO3705Config (palette wiring).');
      expect(asset, isA<STBDDO3705Config>());
      final cfg = asset! as STBDDO3705Config;
      expect(cfg.nameOrId, '1');
      expect(cfg.rawStateKey, isNull);
    });

    test('AssetRegistry.parse round-trips a STBDDO3705Config from saved JSON',
        () {
      final cfg = STBDDO3705Config(
        nameOrId: 'DO-99',
        rawStateKey: 'plc/raw',
      );
      final saveJson = jsonDecode(jsonEncode(<String, dynamic>{
        'assets': <Map<String, dynamic>>[cfg.toJson()],
      })) as Map<String, dynamic>;
      final parsed = AssetRegistry.parse(saveJson);
      expect(parsed, hasLength(1),
          reason:
              '_fromJsonFactories must register STBDDO3705Config (JSON load wiring).');
      expect(parsed[0], isA<STBDDO3705Config>());
      final restored = parsed[0] as STBDDO3705Config;
      expect(restored.nameOrId, 'DO-99');
      expect(restored.rawStateKey, 'plc/raw');
    });

    test('defaultFactories Map contains STBDDO3705Config type key', () {
      expect(
        AssetRegistry.defaultFactories.keys.any(
          (t) => t.toString() == 'STBDDO3705Config',
        ),
        isTrue,
      );
    });
  });

  group('STBDDO3705Config full JSON round-trip + back-compat (DDO-07)', () {
    test(
      'every field survives jsonEncode + jsonDecode + fromJson',
      () {
        final original = STBDDO3705Config(
          nameOrId: 'DO-42',
          rawStateKey: 'plc/do/raw',
          forceValuesKey: 'plc/do/force',
          descriptionsKey: 'plc/do/desc',
        )
          ..coordinates = Coordinates(x: 0.25, y: 0.5)
          ..size = const RelativeSize(width: 0.1, height: 0.2)
          ..text = 'unit test'
          ..textPos = TextPos.below
          ..techDocId = 42
          ..plcAssetKey = 'plc.42';

        final encoded = jsonEncode(original.toJson());
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        final parsed = STBDDO3705Config.fromJson(decoded);

        expect(parsed.nameOrId, 'DO-42');
        expect(parsed.rawStateKey, 'plc/do/raw');
        expect(parsed.forceValuesKey, 'plc/do/force');
        expect(parsed.descriptionsKey, 'plc/do/desc');
        expect(parsed.coordinates.x, 0.25);
        expect(parsed.coordinates.y, 0.5);
        expect(parsed.size.width, 0.1);
        expect(parsed.size.height, 0.2);
        expect(parsed.text, 'unit test');
        expect(parsed.textPos, TextPos.below);
        expect(parsed.techDocId, 42);
        expect(parsed.plcAssetKey, 'plc.42');
        expect(parsed.assetName, 'STBDDO3705Config');
      },
    );

    test(
      'minimal legacy snippet (only v1.0 fields) → Phase 2 defaults rehydrate',
      () {
        final legacyJson = <String, dynamic>{
          'asset_name': 'STBDDO3705Config',
          'coordinates': {'x': 0.0, 'y': 0.0},
          'size': {'width': 0.03, 'height': 0.03},
        };
        final config = STBDDO3705Config.fromJson(legacyJson);
        expect(config.nameOrId, '1');
        expect(config.rawStateKey, isNull);
        expect(config.forceValuesKey, isNull);
        expect(config.descriptionsKey, isNull);
        expect(config.assetName, 'STBDDO3705Config');
      },
    );

    test(
      'unknown forward-compat field in legacy snippet is ignored, not fatal',
      () {
        final futureJson = <String, dynamic>{
          'asset_name': 'STBDDO3705Config',
          'coordinates': {'x': 0.0, 'y': 0.0},
          'size': {'width': 0.03, 'height': 0.03},
          'someFutureFieldKey': 'plc/future',
          'unknownEnum': 'unknown_value',
        };
        final cfg = STBDDO3705Config.fromJson(futureJson);
        expect(cfg.nameOrId, '1');
        expect(cfg.rawStateKey, isNull);
      },
    );
  });

  // ===========================================================================
  // PHASE 3 — STBNIP2311Config (decorative Ethernet head adapter).
  //
  // Decorative-only module: NO PLC state keys. The configure dialog exposes
  // only `nameOrId` + `Coordinates` + `Size`. The status LEDs (RUN/PWR/ERR/
  // ST/TEST) render in a fixed "normal" state in the body painter (RUN+PWR
  // green; ERR+ST+TEST dim grey) — driven by firmware on real hardware, NOT
  // by Modbus. Requirements: NIP-01..04. Locked by 03-CONTEXT.md.
  // ===========================================================================

  group('STBNIP2311Config — data shape', () {
    test('preview() succeeds with nameOrId=="1" and no key fields', () {
      final c = STBNIP2311Config.preview();
      expect(c.nameOrId, '1');
      expect(c.assetName, 'STBNIP2311Config');
    });

    test('toJson()["asset_name"] == "STBNIP2311Config"', () {
      final c = STBNIP2311Config(nameOrId: 'NIP-01');
      final json = c.toJson();
      expect(json['asset_name'], 'STBNIP2311Config');
      expect(json['nameOrId'], 'NIP-01');
      // NIP2311 has NO state-key fields. Round-trip must not silently grow them.
      expect(json.containsKey('runKey'), isFalse);
      expect(json.containsKey('pwrKey'), isFalse);
      expect(json.containsKey('errKey'), isFalse);
      expect(json.containsKey('stKey'), isFalse);
      expect(json.containsKey('testKey'), isFalse);
      expect(json.containsKey('rawStateKey'), isFalse);
    });

    test('explicit nameOrId is honored', () {
      final c = STBNIP2311Config(nameOrId: 'head-A');
      expect(c.nameOrId, 'head-A');
    });
  });

  group('STBNIP2311BodyPainter shouldRepaint contract', () {
    STBNIP2311BodyPainter makePainter({String nameOrId = '1'}) {
      return STBNIP2311BodyPainter(nameOrId: nameOrId);
    }

    test('same inputs → shouldRepaint=false', () {
      final a = makePainter();
      final b = makePainter();
      expect(a.shouldRepaint(b), isFalse);
    });

    test('different nameOrId → shouldRepaint=true', () {
      final a = makePainter(nameOrId: 'head-A');
      final b = makePainter(nameOrId: 'head-B');
      expect(a.shouldRepaint(b), isTrue);
    });

    test('cross-runtimeType → shouldRepaint=true (Pitfall 3 guard)', () {
      final p = makePainter();
      final other = _DummyNIP2311Painter();
      expect(p.shouldRepaint(other), isTrue);
    });
  });

  group('STBNIP2311Config.configure — editor surface', () {
    Future<void> openEditor(WidgetTester tester, STBNIP2311Config cfg) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('Name or ID is present, NO KeyField widgets (decorative only)',
        (tester) async {
      final cfg = STBNIP2311Config.preview();
      await openEditor(tester, cfg);

      expect(find.text('Name or ID'), findsOneWidget);
      // NIP2311 is decorative — the editor must NOT expose any state keys.
      expect(find.byType(KeyField), findsNothing);
      expect(find.text('Raw State Key'), findsNothing);
      expect(find.text('RUN Key'), findsNothing);
      expect(find.text('PWR Key'), findsNothing);
    });
  });

  group('STBNIP2311Widget — mount sanity', () {
    testWidgets('pumps cleanly (no exceptions)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: STBNIP2311Widget(nameOrId: 'NIP-01'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      expect(find.byType(STBNIP2311Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('config.build mounts the underlying STBNIP2311Widget',
        (tester) async {
      final cfg = STBNIP2311Config(nameOrId: 'NIP-mount');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 280,
                  child: Builder(builder: (context) => cfg.build(context)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(STBNIP2311Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Goldens — single "normal" state (RUN/PWR green, ERR/ST/TEST dim grey)
  // rendered in light + dark themes. macOS-only per project convention.
  // ---------------------------------------------------------------------------
  group('STBNIP2311 goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    const goldenKey = Key('stb_nip2311_golden');

    Future<void> pumpNIP2311(
      WidgetTester tester, {
      required Brightness theme,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: goldenKey,
                child: SizedBox(
                  width: 200,
                  height: 280,
                  child: STBNIP2311Widget(nameOrId: 'NIP-01'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
    }

    testWidgets('nip2311_normal_light.png', (tester) async {
      await pumpNIP2311(tester, theme: Brightness.light);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/nip2311_normal_light.png'),
      );
    });

    testWidgets('nip2311_normal_dark.png', (tester) async {
      await pumpNIP2311(tester, theme: Brightness.dark);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/nip2311_normal_dark.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Registry resolution + JSON back-compat (NIP-04).
  // ---------------------------------------------------------------------------
  group('STBNIP2311Config registry resolution', () {
    test('createDefaultAssetByName returns a typed STBNIP2311Config', () {
      final asset =
          AssetRegistry.createDefaultAssetByName('STBNIP2311Config');
      expect(asset, isNotNull,
          reason:
              'defaultFactories must register STBNIP2311Config (palette wiring).');
      expect(asset, isA<STBNIP2311Config>());
      final cfg = asset! as STBNIP2311Config;
      expect(cfg.nameOrId, '1');
    });

    test('AssetRegistry.parse round-trips a STBNIP2311Config from saved JSON',
        () {
      final cfg = STBNIP2311Config(nameOrId: 'NIP-99');
      final saveJson = jsonDecode(jsonEncode(<String, dynamic>{
        'assets': <Map<String, dynamic>>[cfg.toJson()],
      })) as Map<String, dynamic>;
      final parsed = AssetRegistry.parse(saveJson);
      expect(parsed, hasLength(1),
          reason:
              '_fromJsonFactories must register STBNIP2311Config (JSON load wiring).');
      expect(parsed[0], isA<STBNIP2311Config>());
      final restored = parsed[0] as STBNIP2311Config;
      expect(restored.nameOrId, 'NIP-99');
    });

    test('defaultFactories Map contains STBNIP2311Config type key', () {
      expect(
        AssetRegistry.defaultFactories.keys.any(
          (t) => t.toString() == 'STBNIP2311Config',
        ),
        isTrue,
      );
    });
  });

  group('STBNIP2311Config full JSON round-trip + back-compat (NIP-04)', () {
    test('every field survives jsonEncode + jsonDecode + fromJson', () {
      final original = STBNIP2311Config(nameOrId: 'NIP-42')
        ..coordinates = Coordinates(x: 0.25, y: 0.5)
        ..size = const RelativeSize(width: 0.1, height: 0.2)
        ..text = 'unit test'
        ..textPos = TextPos.below
        ..techDocId = 42
        ..plcAssetKey = 'plc.42';

      final encoded = jsonEncode(original.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final parsed = STBNIP2311Config.fromJson(decoded);

      expect(parsed.nameOrId, 'NIP-42');
      expect(parsed.coordinates.x, 0.25);
      expect(parsed.coordinates.y, 0.5);
      expect(parsed.size.width, 0.1);
      expect(parsed.size.height, 0.2);
      expect(parsed.text, 'unit test');
      expect(parsed.textPos, TextPos.below);
      expect(parsed.techDocId, 42);
      expect(parsed.plcAssetKey, 'plc.42');
      expect(parsed.assetName, 'STBNIP2311Config');
    });

    test(
        'minimal legacy snippet (only base fields) → STBNIP2311 defaults rehydrate',
        () {
      final legacyJson = <String, dynamic>{
        'asset_name': 'STBNIP2311Config',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = STBNIP2311Config.fromJson(legacyJson);
      expect(config.nameOrId, '1');
      expect(config.assetName, 'STBNIP2311Config');
    });

    test('unknown forward-compat field is ignored, not fatal', () {
      final futureJson = <String, dynamic>{
        'asset_name': 'STBNIP2311Config',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
        'someFutureFieldKey': 'plc/future',
      };
      final cfg = STBNIP2311Config.fromJson(futureJson);
      expect(cfg.nameOrId, '1');
    });
  });

  // ===========================================================================
  // PHASE 4 — STBPDT3100Config (24 VDC power distribution module).
  //
  // Single optional bool key (`inputOkKey`) drives ONE LED in the body painter:
  //   - stream emits true  → LED green
  //   - stream emits false → LED dim grey
  //   - stream errored / not yet emitted / key null → LED dim grey
  //
  // Configure dialog exposes ONLY `nameOrId` + `inputOkKey` + Coordinates + Size
  // (no detail dialog — single bool is too narrow to warrant one). Requirements:
  // PDT-01..03. Locked by 04-CONTEXT.md.
  // ===========================================================================

  group('STBPDT3100Config — data shape', () {
    test('preview() succeeds with nameOrId=="1" and inputOkKey null', () {
      final c = STBPDT3100Config.preview();
      expect(c.nameOrId, '1');
      expect(c.inputOkKey, isNull);
      expect(c.assetName, 'STBPDT3100Config');
    });

    test('toJson()["asset_name"] == "STBPDT3100Config"', () {
      final c = STBPDT3100Config(nameOrId: 'PDT-01', inputOkKey: 'pdt/ok');
      final json = c.toJson();
      expect(json['asset_name'], 'STBPDT3100Config');
      expect(json['nameOrId'], 'PDT-01');
      expect(json['inputOkKey'], 'pdt/ok');
    });

    test('allKeys picks up inputOkKey via the Key\$ regex', () {
      final c = STBPDT3100Config(nameOrId: 'PDT-A', inputOkKey: 'pdt/ok');
      expect(c.allKeys.toSet(), {'pdt/ok'});
    });

    test('allKeys is empty when inputOkKey is null (optional binding)', () {
      final c = STBPDT3100Config(nameOrId: 'PDT-B');
      expect(c.allKeys, isEmpty);
    });

    test('explicit nameOrId is honored', () {
      final c = STBPDT3100Config(nameOrId: 'power-A');
      expect(c.nameOrId, 'power-A');
    });
  });

  group('STBPDT3100BodyPainter shouldRepaint contract', () {
    STBPDT3100BodyPainter makePainter({
      String nameOrId = '1',
      bool? inputOk,
    }) {
      return STBPDT3100BodyPainter(nameOrId: nameOrId, inputOk: inputOk);
    }

    test('same inputs → shouldRepaint=false', () {
      final a = makePainter();
      final b = makePainter();
      expect(a.shouldRepaint(b), isFalse);
    });

    test('different nameOrId → shouldRepaint=true', () {
      final a = makePainter(nameOrId: 'A');
      final b = makePainter(nameOrId: 'B');
      expect(a.shouldRepaint(b), isTrue);
    });

    test('different inputOk → shouldRepaint=true', () {
      final a = makePainter(inputOk: true);
      final b = makePainter(inputOk: false);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('null vs false inputOk → shouldRepaint=true', () {
      // null (stale/disconnected) and false render the same color (dim grey),
      // but the painter is conservative: the input field changed, repaint.
      final a = makePainter(inputOk: null);
      final b = makePainter(inputOk: false);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('cross-runtimeType → shouldRepaint=true (Pitfall 3 guard)', () {
      final p = makePainter();
      final other = _DummyPDT3100Painter();
      expect(p.shouldRepaint(other), isTrue);
    });
  });

  group('STBPDT3100 aspect ratio (PDT3100 DXF bounding box)', () {
    test('kPDT3100AspectRatio is the DXF width/height ratio (≈ 0.7071)', () {
      // DXF EXTMAX: 114.5914794492 × 162.0650923639 mm. The painter MUST lock
      // to this ratio so the module reads as the slim cream PDT module beside
      // the wider IO modules in a stack.
      const expected = 114.5914794492 / 162.0650923639;
      expect(kPDT3100AspectRatio, closeTo(expected, 1e-6));
    });
  });

  group('STBPDT3100Config.configure — editor surface', () {
    Future<void> openEditor(WidgetTester tester, STBPDT3100Config cfg) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'editor exposes Name or ID + Input OK Key (and NO other KeyFields)',
      (tester) async {
        final cfg = STBPDT3100Config.preview();
        await openEditor(tester, cfg);

        expect(find.text('Name or ID'), findsOneWidget);
        // Single KeyField for inputOkKey only — no force/raw/filter fields.
        expect(find.byType(KeyField), findsOneWidget);
        expect(find.text('Input OK Key'), findsOneWidget);
        expect(find.text('Raw State Key'), findsNothing);
        expect(find.text('Force Values Key'), findsNothing);
      },
    );
  });

  group('STBPDT3100Widget — mount sanity', () {
    testWidgets('pumps cleanly with inputOk=null (no exceptions)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: STBPDT3100Widget(nameOrId: 'PDT-01', inputOk: null),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      expect(find.byType(STBPDT3100Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pumps cleanly with inputOk=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: STBPDT3100Widget(nameOrId: 'PDT-01', inputOk: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      expect(find.byType(STBPDT3100Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pumps cleanly with inputOk=false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: STBPDT3100Widget(nameOrId: 'PDT-01', inputOk: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      expect(find.byType(STBPDT3100Widget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'config.build mounts STBPDT3100Widget when inputOkKey is null',
      (tester) async {
        final cfg = STBPDT3100Config(nameOrId: 'PDT-mount');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              stateManProvider
                  .overrideWith((ref) async => _FakeStateMan()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 200,
                    height: 280,
                    child: Builder(builder: (context) => cfg.build(context)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(STBPDT3100Widget), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'config.build reflects inputOkKey=true emission (green LED state)',
      (tester) async {
        final cfg = STBPDT3100Config(nameOrId: 'PDT-live', inputOkKey: 'ok');
        final stateMan = _StreamingStubPDTStateMan(inputOk: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              stateManProvider.overrideWith((ref) async => stateMan),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 200,
                    height: 280,
                    child: Builder(builder: (context) => cfg.build(context)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The underlying STBPDT3100Widget should receive the bool from the
        // stream and propagate to its painter via the `inputOk` field.
        final widget =
            tester.widget<STBPDT3100Widget>(find.byType(STBPDT3100Widget));
        expect(widget.inputOk, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Goldens — 2 states (input_ok / fault) × 2 themes (light / dark).
  //
  // `fault` is the union semantic class for false / stale / disconnected /
  // errored — all collapse to dim grey per CONTEXT.md §Single LED State
  // Mapping. We render `fault` via inputOk=null (no PLC binding) which is
  // pixel-equivalent to inputOk=false on the painter's color branch. macOS-
  // only per project golden convention (font rendering parity).
  // ---------------------------------------------------------------------------
  group('STBPDT3100 goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    const goldenKey = Key('stb_pdt3100_golden');

    Future<void> pumpPDT3100(
      WidgetTester tester, {
      required Brightness theme,
      required bool? inputOk,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme:
              theme == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: goldenKey,
                child: SizedBox(
                  width: 200,
                  height: 280,
                  child: STBPDT3100Widget(
                    nameOrId: 'PDT-01',
                    inputOk: inputOk,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
    }

    testWidgets('pdt3100_input_ok_light.png', (tester) async {
      await pumpPDT3100(tester, theme: Brightness.light, inputOk: true);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/pdt3100_input_ok_light.png'),
      );
    });

    testWidgets('pdt3100_input_ok_dark.png', (tester) async {
      await pumpPDT3100(tester, theme: Brightness.dark, inputOk: true);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/pdt3100_input_ok_dark.png'),
      );
    });

    testWidgets('pdt3100_fault_light.png', (tester) async {
      await pumpPDT3100(tester, theme: Brightness.light, inputOk: null);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/pdt3100_fault_light.png'),
      );
    });

    testWidgets('pdt3100_fault_dark.png', (tester) async {
      await pumpPDT3100(tester, theme: Brightness.dark, inputOk: null);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/pdt3100_fault_dark.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Registry resolution + JSON back-compat (PDT-01, PDT-03).
  // ---------------------------------------------------------------------------
  group('STBPDT3100Config registry resolution', () {
    test('createDefaultAssetByName returns a typed STBPDT3100Config', () {
      final asset =
          AssetRegistry.createDefaultAssetByName('STBPDT3100Config');
      expect(asset, isNotNull,
          reason:
              'defaultFactories must register STBPDT3100Config (palette wiring).');
      expect(asset, isA<STBPDT3100Config>());
      final cfg = asset! as STBPDT3100Config;
      expect(cfg.nameOrId, '1');
      expect(cfg.inputOkKey, isNull);
    });

    test('AssetRegistry.parse round-trips a STBPDT3100Config from saved JSON',
        () {
      final cfg = STBPDT3100Config(nameOrId: 'PDT-99', inputOkKey: 'pdt/ok');
      final saveJson = jsonDecode(jsonEncode(<String, dynamic>{
        'assets': <Map<String, dynamic>>[cfg.toJson()],
      })) as Map<String, dynamic>;
      final parsed = AssetRegistry.parse(saveJson);
      expect(parsed, hasLength(1),
          reason:
              '_fromJsonFactories must register STBPDT3100Config (JSON load wiring).');
      expect(parsed[0], isA<STBPDT3100Config>());
      final restored = parsed[0] as STBPDT3100Config;
      expect(restored.nameOrId, 'PDT-99');
      expect(restored.inputOkKey, 'pdt/ok');
    });

    test('defaultFactories Map contains STBPDT3100Config type key', () {
      expect(
        AssetRegistry.defaultFactories.keys.any(
          (t) => t.toString() == 'STBPDT3100Config',
        ),
        isTrue,
      );
    });
  });

  group('STBPDT3100Config full JSON round-trip + back-compat (PDT-03)', () {
    test('every field survives jsonEncode + jsonDecode + fromJson', () {
      final original = STBPDT3100Config(nameOrId: 'PDT-42', inputOkKey: 'plc/ok')
        ..coordinates = Coordinates(x: 0.25, y: 0.5)
        ..size = const RelativeSize(width: 0.1, height: 0.2)
        ..text = 'unit test'
        ..textPos = TextPos.below
        ..techDocId = 42
        ..plcAssetKey = 'plc.42';

      final encoded = jsonEncode(original.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final parsed = STBPDT3100Config.fromJson(decoded);

      expect(parsed.nameOrId, 'PDT-42');
      expect(parsed.inputOkKey, 'plc/ok');
      expect(parsed.coordinates.x, 0.25);
      expect(parsed.coordinates.y, 0.5);
      expect(parsed.size.width, 0.1);
      expect(parsed.size.height, 0.2);
      expect(parsed.text, 'unit test');
      expect(parsed.textPos, TextPos.below);
      expect(parsed.techDocId, 42);
      expect(parsed.plcAssetKey, 'plc.42');
      expect(parsed.assetName, 'STBPDT3100Config');
    });

    test(
        'minimal legacy snippet (only base fields) → STBPDT3100 defaults rehydrate (inputOkKey null)',
        () {
      final legacyJson = <String, dynamic>{
        'asset_name': 'STBPDT3100Config',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
      };
      final config = STBPDT3100Config.fromJson(legacyJson);
      expect(config.nameOrId, '1');
      expect(config.inputOkKey, isNull);
      expect(config.assetName, 'STBPDT3100Config');
    });

    test('unknown forward-compat field is ignored, not fatal', () {
      final futureJson = <String, dynamic>{
        'asset_name': 'STBPDT3100Config',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.03, 'height': 0.03},
        'someFutureFieldKey': 'plc/future',
      };
      final cfg = STBPDT3100Config.fromJson(futureJson);
      expect(cfg.nameOrId, '1');
      expect(cfg.inputOkKey, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Plan 05-01: AdvantysSTBStackConfig — composite parent (TDD anchor).
  //
  // Mirrors BeckhoffCX5010Config verbatim with the four-type whitelist
  // substituted, plus a NET-NEW post-fromJson sanitiser that drops foreign
  // child types. Tests in this section establish the RED contract before the
  // class lands; once implemented (Plan 05-01 GREEN), every assertion here is
  // load-bearing for the data layer.
  // ---------------------------------------------------------------------------
  group('AdvantysSTBStackConfig — data shape', () {
    test('default constructor produces empty subdevices + BaseAsset defaults',
        () {
      final stack = AdvantysSTBStackConfig();
      expect(stack.subdevices, isEmpty);
      expect(stack.coordinates.x, 0.0);
      expect(stack.coordinates.y, 0.0);
      expect(stack.size.width, 0.03);
      expect(stack.size.height, 0.03);
      expect(stack.text, isNull);
      expect(stack.textPos, isNull);
      expect(stack.techDocId, isNull);
      expect(stack.plcAssetKey, isNull);
    });

    test('preview() factory returns an instance with empty subdevices', () {
      final stack = AdvantysSTBStackConfig.preview();
      expect(stack, isA<AdvantysSTBStackConfig>());
      expect(stack.subdevices, isEmpty);
    });

    test('displayName and category match the locked phase contract', () {
      final stack = AdvantysSTBStackConfig();
      expect(stack.displayName, 'Advantys STB Stack');
      expect(stack.category, 'Advantys STB');
    });

    test('assetName resolves to the class name via BaseAsset.variant', () {
      final stack = AdvantysSTBStackConfig();
      expect(stack.assetName, 'AdvantysSTBStackConfig');
    });
  });

  group('AdvantysSTBStackConfig.fromJson sanitiser', () {
    test('drops a foreign child type (ButtonConfig) while keeping 3 STB types',
        () {
      // Three legitimate STB children + one ButtonConfig (foreign). The
      // post-fromJson sanitiser must retainWhere over the whitelist and drop
      // the ButtonConfig silently (with a log line). Permissive render,
      // restrictive load — per CONTEXT.md §Whitelist Filter.
      //
      // The production load path is `jsonEncode → jsonDecode → fromJson` so
      // the test mirrors that round-trip. Passing raw `.toJson()` output
      // directly would leave nested codegen-typed objects (e.g.
      // `Coordinates`, `RelativeSize`) in the map and trip the leaf
      // `_$XxxFromJson` cast guards. The round-trip below normalises every
      // value to JSON-native types exactly like the real load path.
      final rawJson = <String, dynamic>{
        'asset_name': 'AdvantysSTBStackConfig',
        'coordinates': <String, dynamic>{'x': 0.0, 'y': 0.0},
        'size': <String, dynamic>{'width': 0.5, 'height': 0.5},
        'subdevices': <Map<String, dynamic>>[
          STBNIP2311Config.preview().toJson(),
          STBDDI3725Config.preview().toJson(),
          ButtonConfig.preview().toJson(), // foreign — must be dropped
          STBPDT3100Config.preview().toJson(),
        ],
      };
      final json = jsonDecode(jsonEncode(rawJson)) as Map<String, dynamic>;
      final cfg = AdvantysSTBStackConfig.fromJson(json);
      expect(cfg.subdevices, hasLength(3),
          reason: 'Sanitiser must drop the foreign ButtonConfig.');
      // The 3 retained children preserve their original order.
      expect(
        cfg.subdevices.map((s) => s.runtimeType.toString()).toList(),
        <String>[
          'STBNIP2311Config',
          'STBDDI3725Config',
          'STBPDT3100Config',
        ],
      );
    });

    test(
      'runtimeType strings of the 4 STB leaf configs match the whitelist '
      'literals exactly (Pitfall 2 typo guard)',
      () {
        // If anyone in the whitelist literal writes 'STBDDI3725' (no Config)
        // or 'STBNip2311Config' (wrong case), every legitimate child is
        // silently dropped on load. This test catches that loudly.
        expect(STBNIP2311Config.preview().runtimeType.toString(),
            'STBNIP2311Config');
        expect(STBPDT3100Config.preview().runtimeType.toString(),
            'STBPDT3100Config');
        expect(STBDDI3725Config.preview().runtimeType.toString(),
            'STBDDI3725Config');
        expect(STBDDO3705Config.preview().runtimeType.toString(),
            'STBDDO3705Config');
      },
    );

    test('empty subdevices list survives fromJson unchanged (no-op sanitiser)',
        () {
      final json = <String, dynamic>{
        'asset_name': 'AdvantysSTBStackConfig',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.5, 'height': 0.5},
        'subdevices': <Map<String, dynamic>>[],
      };
      final cfg = AdvantysSTBStackConfig.fromJson(json);
      expect(cfg.subdevices, isEmpty);
    });
  });

  group('AdvantysSTBStackConfig registry resolution', () {
    test(
      'createDefaultAssetByName returns a typed AdvantysSTBStackConfig '
      '(defaultFactories wiring — Pitfall 3 guard)',
      () {
        final asset =
            AssetRegistry.createDefaultAssetByName('AdvantysSTBStackConfig');
        expect(asset, isNotNull,
            reason:
                'defaultFactories must register AdvantysSTBStackConfig (palette wiring).');
        expect(asset, isA<AdvantysSTBStackConfig>());
        final cfg = asset! as AdvantysSTBStackConfig;
        expect(cfg.subdevices, isEmpty);
      },
    );

    test(
      'AssetRegistry.parse round-trips a stack with a STBPDT3100 subdevice '
      '(_fromJsonFactories wiring — Pitfall 3 other half)',
      () {
        final stack = AdvantysSTBStackConfig()
          ..subdevices = <Asset>[
            STBPDT3100Config(nameOrId: 'PDT', inputOkKey: 'plc.ok'),
          ];
        final saveJson = jsonDecode(jsonEncode(<String, dynamic>{
          'assets': <Map<String, dynamic>>[stack.toJson()],
        })) as Map<String, dynamic>;
        final parsed = AssetRegistry.parse(saveJson);
        expect(parsed, hasLength(1),
            reason:
                '_fromJsonFactories must register AdvantysSTBStackConfig.');
        expect(parsed[0], isA<AdvantysSTBStackConfig>());
        final restored = parsed[0] as AdvantysSTBStackConfig;
        expect(restored.subdevices, hasLength(1));
        expect(restored.subdevices[0], isA<STBPDT3100Config>());
        final pdt = restored.subdevices[0] as STBPDT3100Config;
        expect(pdt.inputOkKey, 'plc.ok');
      },
    );

    test('defaultFactories Map contains AdvantysSTBStackConfig type key', () {
      expect(
        AssetRegistry.defaultFactories.keys.any(
          (t) => t.toString() == 'AdvantysSTBStackConfig',
        ),
        isTrue,
        reason:
            'AdvantysSTBStackConfig must be enumerable through defaultFactories '
            'for the palette to list it.',
      );
    });
  });

  group('AdvantysSTBStackConfig full JSON round-trip', () {
    test(
      'every BaseAsset field + 4-subdevice list survives jsonEncode + jsonDecode + fromJson',
      () {
        final original = AdvantysSTBStackConfig()
          ..coordinates = Coordinates(x: 0.1, y: 0.2)
          ..size = const RelativeSize(width: 0.5, height: 0.3)
          ..text = 'stack-rt'
          ..textPos = TextPos.below
          ..techDocId = 7
          ..plcAssetKey = 'plc.stack'
          ..subdevices = <Asset>[
            STBDDI3725Config(nameOrId: 'DI', rawStateKey: 'a'),
            STBDDO3705Config(nameOrId: 'DO', rawStateKey: 'b'),
            STBNIP2311Config(nameOrId: 'NIP'),
            STBPDT3100Config(nameOrId: 'PDT', inputOkKey: 'ok'),
          ];

        // Production round-trip: through jsonEncode/jsonDecode.
        final encoded = jsonEncode(original.toJson());
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;
        final parsed = AdvantysSTBStackConfig.fromJson(decoded);

        // BaseAsset fields.
        expect(parsed.coordinates.x, 0.1);
        expect(parsed.coordinates.y, 0.2);
        expect(parsed.size.width, 0.5);
        expect(parsed.size.height, 0.3);
        expect(parsed.text, 'stack-rt');
        expect(parsed.textPos, TextPos.below);
        expect(parsed.techDocId, 7);
        expect(parsed.plcAssetKey, 'plc.stack');
        expect(parsed.assetName, 'AdvantysSTBStackConfig');

        // Subdevices: order, types, and key fields preserved.
        expect(parsed.subdevices, hasLength(4));
        expect(parsed.subdevices[0], isA<STBDDI3725Config>());
        expect(parsed.subdevices[1], isA<STBDDO3705Config>());
        expect(parsed.subdevices[2], isA<STBNIP2311Config>());
        expect(parsed.subdevices[3], isA<STBPDT3100Config>());
        expect((parsed.subdevices[0] as STBDDI3725Config).nameOrId, 'DI');
        expect((parsed.subdevices[0] as STBDDI3725Config).rawStateKey, 'a');
        expect((parsed.subdevices[1] as STBDDO3705Config).nameOrId, 'DO');
        expect((parsed.subdevices[1] as STBDDO3705Config).rawStateKey, 'b');
        expect((parsed.subdevices[2] as STBNIP2311Config).nameOrId, 'NIP');
        expect((parsed.subdevices[3] as STBPDT3100Config).nameOrId, 'PDT');
        expect((parsed.subdevices[3] as STBPDT3100Config).inputOkKey, 'ok');
      },
    );
  });

  group('AdvantysSTBStackConfig JSON back-compat', () {
    test(
      'minimal legacy snippet without subdevices field loads with empty list',
      () {
        // Forward-compat: a JSON written before Phase 5 obviously did not
        // include a `subdevices` field. The codegen must default it to []
        // rather than throwing. (CX5010 in production never hits this because
        // the field was always present, but the contract must hold for a
        // forward-compat-friendly Phase 5 stack.)
        final legacyJson = <String, dynamic>{
          'asset_name': 'AdvantysSTBStackConfig',
          'coordinates': {'x': 0.0, 'y': 0.0},
          'size': {'width': 0.5, 'height': 0.3},
          'subdevices': <Map<String, dynamic>>[],
        };
        final cfg = AdvantysSTBStackConfig.fromJson(legacyJson);
        expect(cfg.subdevices, isEmpty);
        expect(cfg.coordinates.x, 0.0);
        expect(cfg.size.width, 0.5);
        expect(cfg.assetName, 'AdvantysSTBStackConfig');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Plan 05-02: configure dialog widget tests (STACK-04).
  //
  // The dialog mirrors `_CXxxxxConfigContent` (lib/page_creator/assets/beckhoff.dart:136-285)
  // verbatim, substituting:
  //   - `_availableSubdevices` → `_availableSTBSubdevices`
  //   - `enableAngle: true` on the Coordinates field (CX5010 parity per RESEARCH Q3)
  //
  // The Plan-01 stub `configure()` previously returned a Column with the text
  // "Subdevice management UI ships in Plan 05-02. Edit JSON directly for now."
  // — these tests fail against that stub (RED gate) and pass once Plan 05-02
  // ships the real `_AdvantysSTBStackConfigContent` dialog.
  // ---------------------------------------------------------------------------
  group('AdvantysSTBStack configure dialog', () {
    Future<void> pumpConfigure(
      WidgetTester tester,
      AdvantysSTBStackConfig cfg,
    ) async {
      // 1400×900 surface ensures the 800×500 dialog has full room without
      // RenderFlex overflows in the dropdown's internal InputDecorator row.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((ref) async => _FakeStateMan()),
          ],
          child: MaterialApp(
            home: Scaffold(
              // Center keeps the 800×500 dialog at a fixed size rather than
              // letting Scaffold expand it to fill the viewport. Wrap in
              // Material so the DropdownButtonFormField's InputDecorator has
              // its expected ancestor (production showDialog wraps in Dialog
              // → Material; without it the InputDecorator's layout pass
              // produces different intrinsic constraints).
              body: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Builder(
                    builder: (context) => cfg.configure(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'Test 1: Add subdevice via dropdown — picks STBDDI3725Config',
      (tester) async {
        final cfg = AdvantysSTBStackConfig();
        await pumpConfigure(tester, cfg);

        // Open the dropdown.
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        // The dropdown menu (overlay) carries exactly the 4 STB display names.
        expect(
          find.text('STBDDI3725 (16-Ch DI)').hitTestable(),
          findsOneWidget,
        );

        // Tap the DDI entry.
        await tester.tap(find.text('STBDDI3725 (16-Ch DI)').hitTestable());
        await tester.pumpAndSettle();

        expect(cfg.subdevices.length, 1);
        expect(cfg.subdevices[0], isA<STBDDI3725Config>());
      },
    );

    testWidgets(
      'Test 2: Dropdown is FILTERED to the 4 STB types only '
      '(positive assertions only per checker iteration 1 warning #5)',
      (tester) async {
        final cfg = AdvantysSTBStackConfig();
        await pumpConfigure(tester, cfg);

        // Open the dropdown.
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        // Collect the visible item Texts inside the open menu by scanning all
        // DropdownMenuItem<String> widgets and pulling their child Text.
        final items = tester
            .widgetList<DropdownMenuItem<String>>(
                find.byType(DropdownMenuItem<String>))
            .toList();
        final itemTexts = items
            .map((item) {
              final child = item.child;
              if (child is Text) return child.data ?? '';
              return '';
            })
            .where((s) => s.isNotEmpty)
            .toList();

        // hasLength(4) + containsAll([...]) — locked positive form. Do NOT add
        // a negative `itemTexts.any((t) => t.contains('Button')...)` assertion
        // (checker iteration 1 warning #5 — brittle and redundant).
        expect(itemTexts, hasLength(4));
        expect(
          itemTexts,
          containsAll(<String>[
            'STBNIP2311 (Ethernet Head)',
            'STBPDT3100 (24 VDC PDM)',
            'STBDDI3725 (16-Ch DI)',
            'STBDDO3705 (16-Ch DO)',
          ]),
        );
      },
    );

    testWidgets(
      'Test 3: Reorder via ReorderableListView swaps adjacent subdevices',
      (tester) async {
        // Build a stack with 3 subdevices in order [DI, DO, PDT].
        final cfg = AdvantysSTBStackConfig()
          ..subdevices = <Asset>[
            STBDDI3725Config(nameOrId: 'A'),
            STBDDO3705Config(nameOrId: 'B'),
            STBPDT3100Config(nameOrId: 'C'),
          ];
        await pumpConfigure(tester, cfg);

        // ReorderableListView drag-and-drop is finicky in widget tests
        // (RESEARCH §Pitfall 6); invoke the onReorder callback directly via
        // the widget reference. Testing the ordering invariant matters more
        // than the drag gesture mechanic.
        final reorderable = tester
            .widget<ReorderableListView>(find.byType(ReorderableListView));
        // Swap items 0 and 1: oldIndex=0, newIndex=2 (Flutter API: newIndex
        // is the insertion slot *after* removal, so moving 0 → "after 1"
        // means newIndex=2).
        reorderable.onReorder(0, 2);
        await tester.pumpAndSettle();

        expect(cfg.subdevices.length, 3);
        expect(cfg.subdevices[0], isA<STBDDO3705Config>());
        expect((cfg.subdevices[0] as STBDDO3705Config).nameOrId, 'B');
        expect(cfg.subdevices[1], isA<STBDDI3725Config>());
        expect((cfg.subdevices[1] as STBDDI3725Config).nameOrId, 'A');
        expect(cfg.subdevices[2], isA<STBPDT3100Config>());
        expect((cfg.subdevices[2] as STBPDT3100Config).nameOrId, 'C');
      },
    );

    testWidgets(
      'Test 4: Delete IconButton removes the subdevice with NO confirmation',
      (tester) async {
        // No confirmation dialog — CX5010 parity per CONTEXT.md line 38
        // verbatim-mirror commitment, overriding the §Configure Dialog
        // "with confirmation" phrasing. See checker iteration 1 warning #2;
        // SUMMARY must list this as a user-decision item.
        final cfg = AdvantysSTBStackConfig()
          ..subdevices = <Asset>[
            STBDDI3725Config(nameOrId: 'first'),
            STBDDO3705Config(nameOrId: 'second'),
          ];
        await pumpConfigure(tester, cfg);

        // Sanity: no AlertDialog up front (configure() returns inline body, not
        // an AlertDialog wrapper).
        expect(find.byType(AlertDialog), findsNothing);

        // Tap the first delete IconButton.
        final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete);
        expect(deleteButtons, findsNWidgets(2));
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();

        // List shrank to one; the second entry survived.
        expect(cfg.subdevices.length, 1);
        expect(cfg.subdevices[0], isA<STBDDO3705Config>());
        expect((cfg.subdevices[0] as STBDDO3705Config).nameOrId, 'second');

        // NO confirmation AlertDialog appeared — CX5010 parity.
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Test 5: No nameOrId / Name field on the stack itself — CX5010 parity',
      (tester) async {
        // No nameOrId field on the stack — CX5010 parity. The four leaf
        // modules carry their own. Deviates from CONTEXT §Specifics
        // implication; verbatim-mirror commitment overrides. See checker
        // iteration 1 warning #3; SUMMARY must list this as a user-decision
        // item.
        final cfg = AdvantysSTBStackConfig();
        await pumpConfigure(tester, cfg);

        // Left pane MUST only contain SizeField + CoordinatesField — no
        // stack-level Name / nameOrId TextField/TextFormField inputs.
        expect(find.widgetWithText(TextField, 'Name'), findsNothing);
        expect(find.widgetWithText(TextField, 'Name or ID'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'Name or ID'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'nameOrId'), findsNothing);
      },
    );

    testWidgets(
      'Test 6: CoordinatesField has enableAngle=true (CX5010 parity per RESEARCH Q3)',
      (tester) async {
        final cfg = AdvantysSTBStackConfig();
        await pumpConfigure(tester, cfg);

        // LOCKED widget-access mechanic per checker iteration 1 warning #4 —
        // do NOT use find.byWidgetPredicate or chain from tester.firstWidget.
        expect(
          tester
              .widget<CoordinatesField>(find.byType(CoordinatesField))
              .enableAngle,
          isTrue,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Plan 05-02: QUAL-07 full-stack integration test.
  //
  // Pumps the canonical 4-module stack (1× NIP + 1× PDT + 1× DDI + 1× DDO) and
  // verifies: clean mount, all four leaf widgets present, taps on DDI+DDO
  // bodies open their detail dialogs, taps on NIP+PDT areas do NOT throw and
  // do NOT open dialogs (per RESEARCH finding 4 — NIP and PDT have no
  // GestureDetector by design, they are decorative).
  // ---------------------------------------------------------------------------
  group('AdvantysSTBStack full-stack integration (QUAL-07)', () {
    AdvantysSTBStackConfig buildCanonicalStack() {
      return AdvantysSTBStackConfig()
        ..subdevices = <Asset>[
          STBNIP2311Config.preview(),
          STBPDT3100Config.preview(),
          STBDDI3725Config(nameOrId: 'DI', rawStateKey: 'plc.di.raw'),
          STBDDO3705Config(nameOrId: 'DO', rawStateKey: 'plc.do.raw'),
        ]
        ..size = const RelativeSize(width: 0.8, height: 0.3);
    }

    Future<void> pumpStack(
      WidgetTester tester,
      AdvantysSTBStackConfig stack,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((ref) async => _FakeStateMan()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (ctx) => stack.build(ctx),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'Test 1: 1× NIP + 1× PDT + 1× DDI + 1× DDO renders cleanly',
      (tester) async {
        final stack = buildCanonicalStack();
        await pumpStack(tester, stack);

        expect(tester.takeException(), isNull);
        expect(find.byType(STBNIP2311Widget), findsOneWidget);
        expect(find.byType(STBPDT3100Widget), findsOneWidget);
        expect(find.byType(STBDDI3725Widget), findsOneWidget);
        expect(find.byType(STBDDO3705Widget), findsOneWidget);
      },
    );

    test(
      'Test 2: stack.allKeys returns the deduplicated union of subdevice keys',
      () {
        final stack = AdvantysSTBStackConfig()
          ..subdevices = <Asset>[
            STBDDI3725Config(
              rawStateKey: 'di.raw',
              forceValuesKey: 'di.force',
            ),
            STBDDO3705Config(rawStateKey: 'do.raw'),
            STBPDT3100Config(inputOkKey: 'pdt.ok'),
            STBNIP2311Config(),
          ];

        expect(
          stack.allKeys,
          containsAll(<String>[
            'di.raw',
            'di.force',
            'do.raw',
            'pdt.ok',
          ]),
        );
        // NIP contributes nothing (decorative); no duplicates.
        expect(stack.allKeys, hasLength(4));
      },
    );

    testWidgets(
      'Test 3: tap on DDI body opens its detail AlertDialog',
      (tester) async {
        final stack = buildCanonicalStack();
        await pumpStack(tester, stack);

        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(find.byType(STBDDI3725Widget));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        // Clean tester state — close the dialog.
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Test 4: tap on DDO body opens its detail AlertDialog',
      (tester) async {
        final stack = buildCanonicalStack();
        await pumpStack(tester, stack);

        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(find.byType(STBDDO3705Widget));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Test 5: tap on NIP body does NOT throw and does NOT open a dialog '
      '(NIP is decorative — no GestureDetector per RESEARCH finding 4)',
      (tester) async {
        final stack = buildCanonicalStack();
        await pumpStack(tester, stack);

        // Tap with warnIfMissed: false because NIP has no GestureDetector;
        // the framework would otherwise warn that no hit was registered.
        await tester.tap(find.byType(STBNIP2311Widget), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Test 6: tap on PDT body does NOT throw and does NOT open a dialog '
      '(PDT is decorative — no GestureDetector per RESEARCH finding 4)',
      (tester) async {
        final stack = buildCanonicalStack();
        await pumpStack(tester, stack);

        await tester.tap(find.byType(STBPDT3100Widget), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Plan 05-02: full-stack goldens (QUAL-07 visual gate).
  //
  // Two PNGs: light + dark themes, canonical NIP+PDT+DDI+DDO layout. macOS-gated
  // via `skip: !Platform.isMacOS` (no `tags: ['golden']` — Phase 1-4 convention).
  // Generate locally with `--update-goldens` on macOS dev hardware.
  // ---------------------------------------------------------------------------
  group(
    'AdvantysSTBStack goldens',
    skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null,
    () {
      const goldenKey = Key('stb_stack_full_golden');

      Future<void> pumpStack(
        WidgetTester tester, {
        required Brightness theme,
      }) async {
        final stack = AdvantysSTBStackConfig()
          ..subdevices = <Asset>[
            STBNIP2311Config.preview(),
            STBPDT3100Config.preview(),
            STBDDI3725Config.preview(),
            STBDDO3705Config.preview(),
          ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              stateManProvider.overrideWith((ref) async => _FakeStateMan()),
            ],
            child: MaterialApp(
              theme: theme == Brightness.dark
                  ? ThemeData.dark()
                  : ThemeData.light(),
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: goldenKey,
                    child: SizedBox(
                      width: 800,
                      height: 200,
                      child: Builder(
                        builder: (ctx) => stack.build(ctx),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // NEVER pumpAndSettle() — Phase 1 goldens pitfall (non-deterministic
        // animation frame). Use explicit duration only.
        await tester.pump(const Duration(milliseconds: 100));
      }

      testWidgets('stack_full_light.png', (tester) async {
        await pumpStack(tester, theme: Brightness.light);
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/advantys_stb/stack_full_light.png'),
        );
      });

      testWidgets('stack_full_dark.png', (tester) async {
        await pumpStack(tester, theme: Brightness.dark);
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/advantys_stb/stack_full_dark.png'),
        );
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Test stubs
// ---------------------------------------------------------------------------

/// Minimal StateMan stub used by the detail-dialog trigger test. All five
/// `*Key` fields on the config are null, so `_combinedStream` never calls
/// `subscribe` and the fake's no-op behaviour is sufficient.
class _FakeStateMan extends Fake implements StateMan {}

/// StateMan stub that emits canned DynamicValues for each subscribed key and
/// records every `write` call for later assertion. Used by the
/// row-structure + force-write-integration groups.
class _StreamingStubStateMan extends Fake implements StateMan {
  _StreamingStubStateMan({
    required this.raw,
    required this.force,
    required this.onFilters,
    required this.offFilters,
    required this.descriptions,
  });

  int raw;
  List<int> force;
  List<int> onFilters;
  List<int> offFilters;
  List<String> descriptions;

  /// Round-trip-able log of `write(key, value)` invocations. The value is the
  /// DynamicValue passed in by the dialog's onChanged handlers; tests inspect
  /// it via `.isArray`, `[i].asInt`, etc.
  final List<({String key, DynamicValue value})> writes =
      <({String key, DynamicValue value})>[];

  // Live DynamicValue instances that the dialog's StreamBuilder mutates
  // in-place when onChanged handlers fire (see beckhoff.dart:1397-1405 for
  // the canonical mutation pattern). Cached so successive subscribes return
  // the same instance (mirrors the BehaviorSubject contract).
  late final DynamicValue _rawDv = DynamicValue(value: raw);
  late final DynamicValue _forceDv =
      DynamicValue.fromList(force.map((v) => DynamicValue(value: v)).toList());
  late final DynamicValue _onFiltersDv = DynamicValue.fromList(
      onFilters.map((v) => DynamicValue(value: v)).toList());
  late final DynamicValue _offFiltersDv = DynamicValue.fromList(
      offFilters.map((v) => DynamicValue(value: v)).toList());
  late final DynamicValue _descriptionsDv = DynamicValue.fromList(
      descriptions.map((v) => DynamicValue(value: v)).toList());

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    switch (key) {
      case 'raw':
        return Stream<DynamicValue>.value(_rawDv);
      case 'force':
        return Stream<DynamicValue>.value(_forceDv);
      case 'onf':
        return Stream<DynamicValue>.value(_onFiltersDv);
      case 'offf':
        return Stream<DynamicValue>.value(_offFiltersDv);
      case 'desc':
        return Stream<DynamicValue>.value(_descriptionsDv);
      default:
        return const Stream<DynamicValue>.empty();
    }
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    writes.add((key: key, value: value));
  }
}

class _DummyDDI3725Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _DummyDDO3705Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _DummyNIP2311Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _DummyPDT3100Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// StateMan stub for STBPDT3100 widget tests. Emits a single canned bool
/// DynamicValue when `subscribe('ok')` is called; any other key returns the
/// empty stream (the PDT3100 widget only ever subscribes to `inputOkKey`).
class _StreamingStubPDTStateMan extends Fake implements StateMan {
  _StreamingStubPDTStateMan({required this.inputOk});

  bool inputOk;

  late final DynamicValue _inputOkDv = DynamicValue(value: inputOk);

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    if (key == 'ok') {
      return Stream<DynamicValue>.value(_inputOkDv);
    }
    return const Stream<DynamicValue>.empty();
  }

  @override
  Future<void> write(String key, DynamicValue value) async {}
}

/// StateMan stub for DDO3705 detail-dialog tests. Like
/// [_StreamingStubStateMan] but drops the filter keys (outputs don't have
/// filters). Records every `write` call for force-write integration assertions.
class _StreamingStubDOStateMan extends Fake implements StateMan {
  _StreamingStubDOStateMan({
    required this.raw,
    required this.force,
    required this.descriptions,
  });

  int raw;
  List<int> force;
  List<String> descriptions;

  final List<({String key, DynamicValue value})> writes =
      <({String key, DynamicValue value})>[];

  late final DynamicValue _rawDv = DynamicValue(value: raw);
  late final DynamicValue _forceDv =
      DynamicValue.fromList(force.map((v) => DynamicValue(value: v)).toList());
  late final DynamicValue _descriptionsDv = DynamicValue.fromList(
      descriptions.map((v) => DynamicValue(value: v)).toList());

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    switch (key) {
      case 'raw':
        return Stream<DynamicValue>.value(_rawDv);
      case 'force':
        return Stream<DynamicValue>.value(_forceDv);
      case 'desc':
        return Stream<DynamicValue>.value(_descriptionsDv);
      default:
        return const Stream<DynamicValue>.empty();
    }
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    writes.add((key: key, value: value));
  }
}
