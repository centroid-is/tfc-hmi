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

  group('ConveyorFbConfig — config editor (multi-select picker)', () {
    testWidgets('toggling a checkbox updates displayedMembers', (tester) async {
      // Fake StateMan that returns an FB DynamicValue map for the bound
      // FB instance. The picker should discover those members and
      // surface them as checkboxes alongside the currently-selected set.
      final fake = _FakeStateMan();
      fake.pushFb('Elevator', LinkedHashMap<String, dynamic>.from({
        // Match the default starter set so they're visible AND
        // checked. We then test deselect AND a new add via discovery.
        'p_Stat_xRunningFwd': true,
        'p_Stat_xFault': false,
        'p_Mode_xAuto': true,
        'red': false,
        'grey': true,
        'green': false,
        // Extra member that's NOT in the default starter set — used
        // for the "discover & add new" path.
        'p_Stat_iThermalFaults': 0,
      }));

      final config = ConveyorFbConfig(
        fbInstanceName: 'Elevator',
        displayedMembers: List<String>.from(kConveyorFbDefaultMembers),
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
      // Let stateMan future + stream emit.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Sanity: starter member 'red' is currently selected.
      expect(config.displayedMembers, contains('red'));
      // Sanity: the unselected discovered member is NOT in the list.
      expect(config.displayedMembers, isNot(contains('p_Stat_iThermalFaults')));

      // The picker lives in a constrained ListView so individual
      // checkboxes may be outside the painted viewport. We invoke the
      // CheckboxListTile.onChanged callback directly to test the
      // wiring contract (toggle → displayedMembers mutation) without
      // depending on hit-test geometry.
      CheckboxListTile findCheckbox(String name) {
        return tester.widget<CheckboxListTile>(find.byKey(
          ValueKey('conveyor-fb-member-checkbox:$name'),
          skipOffstage: false,
        ));
      }

      // 'red' is currently checked — toggle it OFF.
      final redCheckbox = findCheckbox('red');
      expect(redCheckbox.value, isTrue,
          reason: '"red" starts in the selected set');
      redCheckbox.onChanged!(false);
      await tester.pump();

      expect(config.displayedMembers, isNot(contains('red')),
          reason: 'toggling red OFF removes it from displayedMembers');

      // 'p_Stat_iThermalFaults' is discovered but unchecked — toggle
      // it ON.
      final thermalCheckbox = findCheckbox('p_Stat_iThermalFaults');
      expect(thermalCheckbox.value, isFalse,
          reason: 'discovered-but-unselected member starts unchecked');
      thermalCheckbox.onChanged!(true);
      await tester.pump();

      expect(config.displayedMembers, contains('p_Stat_iThermalFaults'),
          reason: 'toggling a new member ON adds it to displayedMembers');
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
