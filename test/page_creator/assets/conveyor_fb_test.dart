// ConveyorFb (FB-binding conveyor asset) tests.
//
// New contract (schema picker on top of an FB DynamicValue subscription):
//  - `ConveyorFbConfig.schema` (a `ConveyorSchema?`) selects which vendor
//    convention the bound FB conforms to. Two values are supported:
//      * `ConveyorSchema.beckhoff`  — TwinCAT-style Hungarian-prefix members
//      * `ConveyorSchema.schneider` — Schneider HMI sub-FB style
//    Default is `null` → asset renders a config hint instead of a value grid.
//  - The schema is the *only* thing that decides which FB member names the
//    asset reads from the live DynamicValue map. There is no longer a
//    free-form `displayedMembers` toggle.
//  - The legacy `displayedMembers` field is GONE. Old saved JSON loses that
//    data silently (intentional — schema picker replaces the toggle UI).
//  - Members missing from the FB map (e.g. `HMI.Color.red` before the
//    named-bit-decoder agent has landed) render as "?" — never a crash.
//
// All view-level tests bypass Riverpod by exercising the pure
// `ConveyorFbView` widget directly.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc/page_creator/assets/conveyor_fb.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );

  DynamicValue fbValue(Map<String, dynamic> members) {
    return DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from(members));
  }

  group('ConveyorFbConfig — defaults & JSON round-trip', () {
    test('default constructor leaves schema null', () {
      final config = ConveyorFbConfig();
      expect(config.schema, isNull);
    });

    test('fromJson without schema field defaults to null '
        '(REGRESSION GUARD for old saved pages)', () {
      // Simulate an old saved Conveyor config (pre-schema, also pre-removal
      // of `displayedMembers`).
      final json = <String, dynamic>{
        'asset_name': 'ConveyorFbConfig',
        'coordinates': {'x': 0.1, 'y': 0.2, 'angle': 0.0},
        'size': {'width': 0.05, 'height': 0.05},
        'text': null,
        'textPos': null,
        'techDocId': null,
        'plcAssetKey': null,
        'fbInstanceName': 'Elevator',
        'parentWordKey': 'plc.fb01.status_word',
        // Legacy `displayedMembers` payload — ignored by the new model.
        'displayedMembers': ['p_Stat_xRunningFwd', 'p_Stat_xFault'],
      };
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.schema, isNull,
          reason: 'no schema field → null (config hint)');
      expect(restored.fbInstanceName, 'Elevator');
      expect(restored.parentWordKey, 'plc.fb01.status_word');
    });

    test('round-trip preserves schema=schneider', () {
      final config = ConveyorFbConfig(
        fbInstanceName: 'FB_Conveyor_01',
        parentWordKey: 'plc.fb01.status_word',
        schema: ConveyorSchema.schneider,
      );
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, 'FB_Conveyor_01');
      expect(restored.parentWordKey, 'plc.fb01.status_word');
      expect(restored.schema, ConveyorSchema.schneider);
    });

    test('round-trip preserves schema=beckhoff', () {
      final config = ConveyorFbConfig(
        fbInstanceName: 'FB_Conveyor_02',
        schema: ConveyorSchema.beckhoff,
      );
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, 'FB_Conveyor_02');
      expect(restored.schema, ConveyorSchema.beckhoff);
    });

    test('serializes and deserializes with all fields null (defaults)', () {
      final config = ConveyorFbConfig();
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, isNull);
      expect(restored.parentWordKey, isNull);
      expect(restored.schema, isNull);
    });

    test('asset_name discriminator is "ConveyorFbConfig"', () {
      final config = ConveyorFbConfig();
      final json = config.toJson();
      expect(json['asset_name'], 'ConveyorFbConfig');
    });

    test('preview constructor produces a renderable instance', () {
      final config = ConveyorFbConfig.preview();
      expect(config, isNotNull);
      expect(config.assetName, 'ConveyorFbConfig');
      // Preview ships with a sensible schema so the asset is visible in
      // the page-editor catalogue rather than just a config hint.
      expect(config.schema, isNotNull);
    });
  });

  group('ConveyorFbView — schema=schneider (WORD-bit decode)', () {
    // The Schneider FB_ATV320 layout packs status / command / mode / color
    // BOOLs into parent WORDs declared in the FB's inner `HMI` sub-FB.
    // The asset reads those WORDs from the FB DynamicValue map and masks
    // the canonical bit positions client-side. This mirrors the Aveva HMI
    // approach (local schema + WORD-only wire reads) and matches the
    // declaration order observed on the live M580 (see commit message).
    //
    // Bit positions (Schneider FB_ATV320 public block):
    //   HMI.Status : bit 2  → p_Stat_xFault         (concept: fault)
    //                bit 4  → p_Stat_xRunningFwd    (concept: running)
    //   HMI.Mode   : bit 1  → p_Mode_xMan           (concept: mode)
    //   HMI.Color  : bit 0  → red, 1 → grey, 2 → green
    //
    // Scalar members (`p_Stat_diRuntime`, `p_Stat_rVelocity`,
    // `p_Stat_iThermalFaults`) remain real leaf entries in the FB map and
    // are read directly with no bit-masking.

    testWidgets(
        'decodes Schneider HMI.Status / HMI.Mode / HMI.Color bits '
        'from parent WORDs', (tester) async {
      // HMI.Status = 0x0014 sets bits 2 (fault) AND 4 (running).
      // HMI.Mode   = 0x0002 sets bit 1 (manual mode active).
      // HMI.Color  = 0x0002 sets bit 1 (grey lamp; red+green off).
      final fb = fbValue({
        'HMI.Status': 0x0014,
        'HMI.Mode': 0x0002,
        'HMI.Color': 0x0002,
        'HMI.p_Stat_iThermalFaults': 0,
        'HMI.p_Stat_diRuntime': 12345,
        'HMI.p_Stat_rVelocity': 1.5,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            schema: ConveyorSchema.schneider,
          ),
        ),
      ));

      // BOOLs render via the bool-dot lamp keyed by their canonical
      // concept name (NOT the raw vendor member path / not the WORD key).
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:running:bool:on',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:fault:bool:on',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:mode:bool:on',
        )),
        findsOneWidget,
      );

      // Color indicators (grey active, red+green off).
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:colorGrey:bool:on',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:colorRed:bool:off',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:colorGreen:bool:off',
        )),
        findsOneWidget,
      );

      // Scalar numerics (INT/DINT plain digits; REAL 1-decimal) still
      // read directly from member keys, NOT from a WORD mask.
      expect(find.text('12345'), findsOneWidget); // runtime DINT
      expect(find.text('1.5'), findsOneWidget); // velocity REAL
    });

    testWidgets(
        'all bits clear on WORD=0 → every Schneider concept renders off',
        (tester) async {
      // Mirrors the live-M580 quiescent state: every HMI WORD is 0 → every
      // derived bit should be `false` (and the bool-dot keyed `:off`),
      // never an unknown placeholder.
      final fb = fbValue({
        'HMI.Status': 0,
        'HMI.Mode': 0,
        'HMI.Color': 0,
        'HMI.p_Stat_iThermalFaults': 0,
        'HMI.p_Stat_diRuntime': 0,
        'HMI.p_Stat_rVelocity': 0.0,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            schema: ConveyorSchema.schneider,
          ),
        ),
      ));

      for (final concept in const [
        'running',
        'fault',
        'mode',
        'colorRed',
        'colorGrey',
        'colorGreen',
      ]) {
        expect(
          find.byKey(ValueKey('conveyor-fb-member:$concept:bool:off')),
          findsOneWidget,
          reason: '$concept must be off when its parent WORD is 0',
        );
      }
    });

    testWidgets(
        'missing parent WORDs render bit concepts as "?" '
        '(graceful when the FB is not bound / stream has not arrived)',
        (tester) async {
      // No HMI.Status / HMI.Mode / HMI.Color in the map (e.g. before the
      // first stream value arrives, or if the FB browse did not include
      // them). The asset must NOT crash — every bit concept renders as
      // unknown.
      final fb = fbValue({
        'HMI.p_Stat_diRuntime': 999,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            schema: ConveyorSchema.schneider,
          ),
        ),
      ));

      for (final concept in const [
        'running',
        'fault',
        'mode',
        'colorRed',
        'colorGrey',
        'colorGreen',
      ]) {
        expect(
          find.byKey(ValueKey('conveyor-fb-member:$concept:unknown')),
          findsOneWidget,
          reason: '$concept must be "?" when its parent WORD is missing',
        );
      }

      // Scalar that IS present still renders.
      expect(find.text('999'), findsOneWidget);
    });

    testWidgets(
        'each Color bit position decodes independently '
        '(red=bit0, grey=bit1, green=bit2)', (tester) async {
      // Set only Color.green (bit 2) → 0x0004.
      final fb = fbValue({
        'HMI.Status': 0,
        'HMI.Mode': 0,
        'HMI.Color': 0x0004,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            schema: ConveyorSchema.schneider,
          ),
        ),
      ));
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:colorGreen:bool:on')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:colorRed:bool:off')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:colorGrey:bool:off')),
        findsOneWidget,
      );
    });

    testWidgets(
        'WORD value can be supplied as a Dart int (matches real wire shape)',
        (tester) async {
      // Smoke test against the live wire shape — the WORD comes back as
      // an int from DynamicValue, not as a bool or string.
      final fb = fbValue({
        'HMI.Status': 0x0001, // bit 0 = p_Stat_xAuto (not currently surfaced
        // as a canonical concept, so we just check that the present bits
        // decode without crashing the renderer).
        'HMI.Mode': 0x0001, // bit 0 = p_Mode_xAuto → "mode" concept reads
        // p_Mode_xMan (bit 1) so this must render off.
        'HMI.Color': 0x0001, // bit 0 = red.
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            schema: ConveyorSchema.schneider,
          ),
        ),
      ));
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:mode:bool:off')),
        findsOneWidget,
        reason: 'mode = HMI.Mode bit 1; only bit 0 set → off',
      );
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:colorRed:bool:on')),
        findsOneWidget,
        reason: 'colorRed = HMI.Color bit 0; bit 0 set → on',
      );
    });
  });

  group('ConveyorFbView — schema=beckhoff', () {
    testWidgets('reads Beckhoff/TwinCAT Hungarian-prefix member names',
        (tester) async {
      final fb = fbValue({
        'bRunning': true,
        'bFault': false,
        'bMan': true,
        'rActSpeed': 2.5,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Motor_01',
            fbValue: fb,
            schema: ConveyorSchema.beckhoff,
          ),
        ),
      ));

      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:running:bool:on',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:fault:bool:off',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:mode:bool:on',
        )),
        findsOneWidget,
      );
      // REAL formatted to 1 decimal.
      expect(find.text('2.5'), findsOneWidget);
    });
  });

  group('ConveyorFbView — schema=null', () {
    testWidgets('null schema renders config hint, no value grid',
        (tester) async {
      final fb = fbValue({'bRunning': true, 'p_Stat_xRunningFwd': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Unconfigured',
            fbValue: fb,
            schema: null,
          ),
        ),
      ));

      // FB header still appears.
      expect(find.text('FB_Unconfigured'), findsOneWidget);
      // Config hint visible.
      expect(
        find.byKey(const ValueKey('conveyor-fb-schema-hint')),
        findsOneWidget,
      );
      // No member cells rendered.
      expect(find.byType(ConveyorFbMemberCell), findsNothing);
    });
  });

  group('ConveyorFbView — null fbValue handling', () {
    testWidgets('null fbValue with a schema renders all concepts as "?"',
        (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: null,
            schema: ConveyorSchema.schneider,
          ),
        ),
      ));

      // No crash; canonical concepts present as unknown.
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:running:unknown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:fault:unknown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:colorRed:unknown')),
        findsOneWidget,
      );
    });
  });

  group('ConveyorFbConfig — config editor (schema dropdown)', () {
    testWidgets('changing the schema dropdown updates the saved config',
        (tester) async {
      // Fake StateMan present so the FutureBuilder inside the editor does
      // not need a real PLC.
      final fake = _FakeStateMan();
      final config = ConveyorFbConfig(
        fbInstanceName: 'Elevator',
        schema: ConveyorSchema.schneider,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateManProvider.overrideWith((_) async => fake),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => config.configure(ctx),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The schema dropdown is keyed for stable test discovery.
      final dropdownFinder = find.byKey(
        const ValueKey('conveyor-fb-schema-dropdown'),
      );
      expect(dropdownFinder, findsOneWidget);

      // Resolve current value via the widget — sanity.
      expect(config.schema, ConveyorSchema.schneider);

      // Simulate the user picking Beckhoff. We invoke the onChanged
      // callback directly to side-step layout issues with hit-testing
      // a popup menu inside a constrained-size SingleChildScrollView.
      final dropdown = tester.widget<DropdownButton<ConveyorSchema?>>(
        dropdownFinder,
      );
      dropdown.onChanged!(ConveyorSchema.beckhoff);
      await tester.pump();

      expect(config.schema, ConveyorSchema.beckhoff,
          reason: 'selecting Beckhoff updates the saved config');
    });
  });
}

/// Fake StateMan that returns FB DynamicValue maps for keys pushed via
/// [pushFb] (or bool scalars via [push] for back-compat with other
/// tests). Backs the `stateManProvider` override.
class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};

  // KeyField widget pulls `.keys` to populate its autocomplete list;
  // return the set of streams we've pushed so it doesn't throw.
  @override
  List<String> get keys => _streams.keys.toList();

  /// Push a flat `{member: value}` map as the latest value for [key].
  void pushFb(String key, LinkedHashMap<String, dynamic> members) {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    s.add(DynamicValue.fromMap(members));
  }

  void push(String key, bool value) {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    s.add(DynamicValue(value: value, typeId: NodeId.boolean));
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    final s = _streams.putIfAbsent(
      key,
      () => BehaviorSubject<DynamicValue>(),
    );
    return s.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
    );
  }
}
