// ConveyorFb (FB-binding conveyor asset) tests.
//
// New contract (member-toggle UI on top of an FB DynamicValue subscription):
//  - `ConveyorFbConfig.displayedMembers` controls which FB members the
//    widget renders. Order is preserved.
//  - `fromJson` without `displayedMembers` populates the starter set
//    (REGRESSION GUARD: old saved configs keep loading).
//  - Rendering filters the FB DynamicValue map to only the selected
//    members and renders each by Dart type (bool / int / double / string).
//  - Missing members render as "?" (NOT a crash).
//  - Empty `displayedMembers` renders an empty grid + helpful hint.
//
// All view-level tests bypass Riverpod by exercising the pure
// `ConveyorFbView` widget directly.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/conveyor_fb.dart';

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
    test('default constructor populates the starter member set', () {
      final config = ConveyorFbConfig();
      expect(config.displayedMembers, isNotEmpty);
      expect(config.displayedMembers, kConveyorFbDefaultMembers);
    });

    test('fromJson without displayedMembers populates starter set '
        '(REGRESSION GUARD for old saved pages)', () {
      // Simulate an old saved Conveyor config (pre-displayedMembers).
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
      };
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.displayedMembers, kConveyorFbDefaultMembers);
      expect(restored.fbInstanceName, 'Elevator');
      expect(restored.parentWordKey, 'plc.fb01.status_word');
    });

    test('round-trip preserves displayedMembers', () {
      final config = ConveyorFbConfig(
        fbInstanceName: 'FB_Conveyor_01',
        parentWordKey: 'plc.fb01.status_word',
        displayedMembers: ['p_Stat_xRunningFwd', 'p_Stat_iThermalFaults'],
      );
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, 'FB_Conveyor_01');
      expect(restored.parentWordKey, 'plc.fb01.status_word');
      expect(
        restored.displayedMembers,
        ['p_Stat_xRunningFwd', 'p_Stat_iThermalFaults'],
      );
    });

    test('serializes and deserializes with all fields null (defaults)', () {
      final config = ConveyorFbConfig();
      final json = config.toJson();
      final restored = ConveyorFbConfig.fromJson(json);
      expect(restored.fbInstanceName, isNull);
      expect(restored.parentWordKey, isNull);
      expect(restored.displayedMembers, kConveyorFbDefaultMembers);
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
      // Preview also has displayedMembers (the starter set).
      expect(config.displayedMembers, isNotEmpty);
    });
  });

  group('ConveyorFbView — selected-member rendering', () {
    testWidgets('renders only members in displayedMembers, '
        'ignores unselected map entries', (tester) async {
      // FB exposes more than the displayed set; we should only see the
      // selected three.
      final fb = fbValue({
        'p_Stat_xRunningFwd': true,
        'p_Stat_xFault': false,
        'p_Stat_iThermalFaults': 0,
        'p_Mode_xAuto': true,
        'red': false,
        'grey': true,
        'green': false,
        // Extra members not in displayedMembers — must not appear.
        'p_Stat_diRuntime': 9876,
        'p_Stat_rVelocity': 1.5,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 400,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_01',
            fbValue: fb,
            displayedMembers: const [
              'p_Stat_xRunningFwd',
              'p_Stat_iThermalFaults',
              'grey',
            ],
          ),
        ),
      ));

      // Labels for selected members appear.
      expect(find.text('p_Stat_xRunningFwd'), findsOneWidget);
      expect(find.text('p_Stat_iThermalFaults'), findsOneWidget);
      expect(find.text('grey'), findsOneWidget);

      // Labels for unselected members do NOT appear.
      expect(find.text('p_Stat_xFault'), findsNothing);
      expect(find.text('p_Mode_xAuto'), findsNothing);
      expect(find.text('p_Stat_diRuntime'), findsNothing);
      expect(find.text('p_Stat_rVelocity'), findsNothing);
      expect(find.text('red'), findsNothing);
      expect(find.text('green'), findsNothing);
    });

    testWidgets('renders BOOL as on/off lamp keyed by state', (tester) async {
      final fb = fbValue({
        'p_Stat_xRunningFwd': true,
        'p_Stat_xFault': false,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            displayedMembers: const ['p_Stat_xRunningFwd', 'p_Stat_xFault'],
          ),
        ),
      ));

      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:p_Stat_xRunningFwd:bool:on',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:p_Stat_xFault:bool:off',
        )),
        findsOneWidget,
      );
    });

    testWidgets('renders numeric INT/DINT as digits', (tester) async {
      final fb = fbValue({
        'p_Stat_iThermalFaults': 3,
        'p_Stat_diRuntime': 12345,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            displayedMembers: const [
              'p_Stat_iThermalFaults',
              'p_Stat_diRuntime',
            ],
          ),
        ),
      ));

      expect(find.text('3'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget);
    });

    testWidgets('renders REAL with 1 decimal place', (tester) async {
      final fb = fbValue({
        'p_Stat_rVelocity': 1.5,
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            displayedMembers: const ['p_Stat_rVelocity'],
          ),
        ),
      ));

      // REAL formatted to 1 decimal.
      expect(find.text('1.5'), findsOneWidget);
    });

    testWidgets('renders STRING as text', (tester) async {
      final fb = fbValue({
        'p_Stat_sName': 'CONV-01',
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            displayedMembers: const ['p_Stat_sName'],
          ),
        ),
      ));

      expect(find.text('CONV-01'), findsOneWidget);
    });

    testWidgets('member missing from FB map renders "?" placeholder, '
        'does NOT crash', (tester) async {
      // displayedMembers includes a name not present in the FB map.
      final fb = fbValue({
        'p_Stat_xRunningFwd': true,
        // 'p_Stat_xMissing' intentionally NOT in map.
      });
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: fb,
            displayedMembers: const [
              'p_Stat_xRunningFwd',
              'p_Stat_xMissing',
            ],
          ),
        ),
      ));

      // Label still rendered.
      expect(find.text('p_Stat_xMissing'), findsOneWidget);
      // "?" placeholder shows for the missing one.
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:p_Stat_xMissing:unknown',
        )),
        findsOneWidget,
      );
    });

    testWidgets('null fbValue tolerated — every displayed member is unknown',
        (tester) async {
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB',
            fbValue: null,
            displayedMembers: const [
              'p_Stat_xRunningFwd',
              'p_Stat_xFault',
              'grey',
            ],
          ),
        ),
      ));

      // No crash; every label rendered with "?" placeholder.
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:p_Stat_xRunningFwd:unknown',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(
          'conveyor-fb-member:p_Stat_xFault:unknown',
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('conveyor-fb-member:grey:unknown')),
        findsOneWidget,
      );
    });

    testWidgets('empty displayedMembers renders a "no members selected" hint',
        (tester) async {
      final fb = fbValue({'p_Stat_xRunningFwd': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Empty',
            fbValue: fb,
            displayedMembers: const [],
          ),
        ),
      ));

      // FB header still appears.
      expect(find.text('FB_Empty'), findsOneWidget);
      // Empty-state hint is visible.
      expect(
        find.byKey(const ValueKey('conveyor-fb-empty-hint')),
        findsOneWidget,
      );
      // No member cells rendered.
      expect(
        find.byType(ConveyorFbMemberCell),
        findsNothing,
      );
    });

    testWidgets('renders FB instance name as header', (tester) async {
      final fb = fbValue({'p_Stat_xRunningFwd': true});
      await tester.pumpWidget(wrap(
        SizedBox(
          width: 400,
          height: 300,
          child: ConveyorFbView(
            fbInstanceName: 'FB_Conveyor_42',
            fbValue: fb,
            displayedMembers: const ['p_Stat_xRunningFwd'],
          ),
        ),
      ));
      expect(find.text('FB_Conveyor_42'), findsOneWidget);
    });
  });
}
