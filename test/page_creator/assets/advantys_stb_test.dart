import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/advantys_stb.dart';
import 'package:tfc/page_creator/assets/beckhoff.dart' show RowIOView, FilterEdit;
import 'package:tfc/page_creator/assets/common.dart'
    show Coordinates, KeyField, RelativeSize, TextPos;
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/painter/advantys_stb/ddi3725.dart';
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
