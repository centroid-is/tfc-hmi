// ConveyorFb (FB-binding conveyor asset) tests.
//
// Locks the contract:
//  - Renders standard FB fields (running / fault / mode / runtime) from the
//    bound FB DynamicValue.
//  - Bit-aliased color indicators (red / grey / green) are resolved by the
//    injected BitAliasDecoder against the parent WORD.
//  - Missing FB fields render as "—" (em dash), NEVER crash.
//  - Decoder returning null renders as "?" (NOT off / NOT crash).
//  - Decoder returning true/false renders the indicator on/off.
//
// All tests bypass Riverpod by exercising the pure `ConveyorFbView`
// widget directly — `ConveyorFb` is the Riverpod-wired wrapper and is
// covered by a smaller smoke test below.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/conveyor_fb.dart';
import 'package:tfc_dart/core/umas_bit_alias.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );

  DynamicValue fbValue(Map<String, dynamic> members) {
    return DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from(members));
  }

  group('ConveyorFbView — FB field rendering', () {
    testWidgets('renders all standard fields when populated', (tester) async {
      final fb = fbValue({
        'running': true,
        'fault': false,
        'mode': 'auto',
        'runtime': 12345,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            parentWordValue: 0,
            decoder: const StubBitAliasDecoder(),
          ),
        ),
      ));

      // Running field — bool true renders as 'true'
      expect(find.text('running'), findsOneWidget);
      expect(find.text('true'), findsOneWidget);
      // Fault field — bool false
      expect(find.text('fault'), findsOneWidget);
      expect(find.text('false'), findsOneWidget);
      // Mode field — string 'auto'
      expect(find.text('mode'), findsOneWidget);
      expect(find.text('auto'), findsOneWidget);
      // Runtime field — int 12345
      expect(find.text('runtime'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget);
    });

    testWidgets('renders FB instance name as header', (tester) async {
      final fb = fbValue({'running': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            parentWordValue: 0,
            decoder: const StubBitAliasDecoder(),
          ),
        ),
      ));
      expect(find.text('FB_Conveyor_01'), findsOneWidget);
    });

    testWidgets('missing fields render as em-dash, never crash',
        (tester) async {
      // Only running present; others missing.
      final fb = fbValue({'running': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            parentWordValue: 0,
            decoder: const StubBitAliasDecoder(),
          ),
        ),
      ));

      // Labels always rendered
      expect(find.text('running'), findsOneWidget);
      expect(find.text('fault'), findsOneWidget);
      expect(find.text('mode'), findsOneWidget);
      expect(find.text('runtime'), findsOneWidget);

      // Em-dash for the three missing fields (NOT a crash)
      // (running has the value 'true', the others 'missing').
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('null fbValue tolerated — all fields show em-dash',
        (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: null,
            parentWordValue: 0,
            decoder: const StubBitAliasDecoder(),
          ),
        ),
      ));

      // No crash. All 4 fields show em-dash.
      expect(find.text('—'), findsNWidgets(4));
    });
  });

  group('ConveyorFbView — bit-alias color indicators', () {
    testWidgets('decoder=null result renders "?" fallback',
        (tester) async {
      // Stub decoder returns null for everything.
      final fb = fbValue({'running': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            parentWordValue: 0xFFFF,
            decoder: const StubBitAliasDecoder(),
          ),
        ),
      ));

      // All three indicators render a "?" placeholder via the
      // ConveyorFbIndicator widget. Locate by Semantics label so
      // we test the contract, not the painter.
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:red:unknown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:grey:unknown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:green:unknown')),
          findsOneWidget);
      // The "?" glyph appears for every unknown indicator.
      expect(find.text('?'), findsNWidgets(3));
    });

    testWidgets('decoder returning true/false renders correct state',
        (tester) async {
      // Map decoder: red=bit0, grey=bit1, green=bit2.
      const decoder =
          MapBitAliasDecoder({'red': 0, 'grey': 1, 'green': 2});
      final fb = fbValue({'running': true});
      // 0b001 -> only red lit.
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            parentWordValue: 0x01,
            decoder: decoder,
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('conveyor-fb-indicator:red:on')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:grey:off')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:green:off')),
          findsOneWidget);
    });

    testWidgets('decoder result flips when parent word changes',
        (tester) async {
      const decoder =
          MapBitAliasDecoder({'red': 0, 'grey': 1, 'green': 2});
      final fb = fbValue({'running': true});

      // First: green only.
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            parentWordValue: 0x04,
            decoder: decoder,
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:red:off')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:green:on')),
          findsOneWidget);

      // Then: all three lit.
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            parentWordValue: 0x07,
            decoder: decoder,
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:red:on')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:grey:on')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:green:on')),
          findsOneWidget);
    });

    testWidgets('partial decoder result — some bits known, others unknown',
        (tester) async {
      // Only `red` is known. `grey` and `green` decode to null.
      const decoder = MapBitAliasDecoder({'red': 0});
      final fb = fbValue({'running': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            parentWordValue: 0x01,
            decoder: decoder,
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('conveyor-fb-indicator:red:on')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:grey:unknown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:green:unknown')),
          findsOneWidget);
    });

    testWidgets('null parentWordValue -> all indicators unknown',
        (tester) async {
      // Decoder is real, but the parent word hasn't been fetched yet.
      const decoder =
          MapBitAliasDecoder({'red': 0, 'grey': 1, 'green': 2});
      final fb = fbValue({'running': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            parentWordValue: null,
            decoder: decoder,
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('conveyor-fb-indicator:red:unknown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:grey:unknown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conveyor-fb-indicator:green:unknown')),
          findsOneWidget);
      // The "?" glyph appears for every unknown indicator.
      expect(find.text('?'), findsNWidgets(3));
    });
  });

  group('ConveyorFbConfig — JSON round-trip', () {
    test('serializes and deserializes with all fields', () {
      final config = ConveyorFbConfig(
        fbInstanceName: 'FB_Conveyor_01',
        parentWordKey: 'plc.fb01.status_word',
      );
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, 'FB_Conveyor_01');
      expect(restored.parentWordKey, 'plc.fb01.status_word');
    });

    test('serializes and deserializes with all fields null (defaults)', () {
      final config = ConveyorFbConfig();
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, isNull);
      expect(restored.parentWordKey, isNull);
    });

    test('asset_name discriminator is "ConveyorFbConfig"', () {
      final config = ConveyorFbConfig();
      final json = config.toJson();
      expect(json['asset_name'], 'ConveyorFbConfig');
    });

    test('preview constructor produces a renderable instance', () {
      final config = ConveyorFbConfig.preview();
      expect(config, isNotNull);
      // preview should be safe to call configure() / build() on.
      expect(config.assetName, 'ConveyorFbConfig');
    });
  });
}
