import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/providers/collector.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

/// The conveyor pane used to print the drive's two status words raw, which
/// on a live station reads as `rdY(2)` / `OCF(9)` — or, when the server does
/// not publish enum names, as a bare `2` / `9`. Neither tells an operator
/// standing at a stopped belt what is wrong or what to do.
///
/// These tests pin the decode (`p_stat_State` = `hmis_e`, `p_stat_LastFault`
/// = `lft_e`) and the behaviour around it.

/// Serves one drive struct on the conveyor's `key`.
class _DriveStateMan extends Fake implements StateMan {
  _DriveStateMan({required this.driveKey, required this.state, this.fault = 0});

  final String driveKey;
  final int state;
  final int fault;

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    if (key != driveKey) return const Stream<DynamicValue>.empty();
    final dv = DynamicValue();
    dv['p_stat_State'] = state;
    dv['p_stat_LastFault'] = fault;
    dv['p_stat_Frequency'] = 0.0;
    dv['p_stat_Current'] = 0.0;
    dv['p_stat_RunMinutes'] = 0;
    dv['p_stat_JogFwd'] = false;
    dv['p_stat_JogBwd'] = false;
    dv['p_stat_ManualStopOnRelease'] = true;
    // The pane's setpoint fields read these directly; a struct without them
    // throws before anything renders.
    dv['p_cfg_ManualFreq'] = 20.0;
    dv['p_cfg_AutoFreq'] = 20.0;
    dv['p_cfg_CleaningFreq'] = 20.0;
    return Stream<DynamicValue>.value(dv);
  }

  @override
  Future<void> write(String key, DynamicValue value) async {}
}

Future<void> _openPane(
  WidgetTester tester, {
  required int state,
  int fault = 0,
}) async {
  const key = 'Line1.Belt2.Drive';
  final config = ConveyorConfig(key: key)
    ..size = const RelativeSize(width: 1.0, height: 1.0);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      // The pane's trend tile resolves the collector, which builds a real
      // Database with periodic timers and leaves them pending past the test.
      // Nothing here is about the trend, so cut it off at the provider.
      collectorProvider.overrideWith((ref) async => null),
      stateManProvider.overrideWith(
        (ref) async =>
            _DriveStateMan(driveKey: key, state: state, fault: fault),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: 80, child: Conveyor(config)),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Conveyor));
  // Not pumpAndSettle: the pane's trend tile spins on a collector that never
  // resolves under a fake StateMan, so the frame never goes quiet. Two pumps
  // past the pane's slide-in is enough for everything under test.
  await _settlePane(tester);
}

/// Text inside a status row, as opposed to the same word in the header chip.
Finder _inRow(String text) => find.descendant(
      of: find.byType(PaneExplainRow),
      matching: find.text(text),
    );

/// Advances past the pane animation without waiting for the trend spinner.
Future<void> _settlePane(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // A real station is a 1080p panel, and the default 800x600 test surface is
  // short enough that the pane's pinned action bar sits on top of the status
  // rows — taps aimed at a row land on 'Fault reset' instead.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(1200, 900);
  });

  tearDown(() {
    closeSidePane();
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
        .resetPhysicalSize();
  });

  testWidgets('a healthy drive reads in words, not codes', (tester) async {
    await _openPane(tester, state: 2); // hmis_e.rdy

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('No fault'), findsOneWidget);
    // The raw form the pane used to print.
    expect(find.textContaining('rdY('), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('the running state is named', (tester) async {
    await _openPane(tester, state: 4); // hmis_e.run
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets(
    'a trip names the fault and opens its explanation unprompted',
    (tester) async {
      // hmis_e.fault + lft_e.ocf — the belt tripped on overcurrent.
      await _openPane(tester, state: 23, fault: 9);

      // 'Faulted' also lands in the header chip, which is the point of the
      // header change — scope to the row.
      expect(_inRow('Faulted'), findsOneWidget);
      expect(find.text('Overcurrent'), findsOneWidget);

      // Auto-expanded: the operator should not have to discover the tap.
      expect(find.text('OCF'), findsOneWidget);
      expect(find.textContaining('more current than the drive allows'),
          findsOneWidget);
      // And the first thing it says is to check the belt, not to reset.
      expect(find.textContaining('Check the belt for a jam'), findsOneWidget);
    },
  );

  testWidgets(
    'a fault needing a power cycle says the reset button will not do it',
    (tester) async {
      await _openPane(tester, state: 23, fault: 24); // lft_e.sof — overspeed

      expect(find.text('Overspeed'), findsOneWidget);
      expect(
        find.textContaining('Fault reset will not clear this'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a resettable fault says so', (tester) async {
    await _openPane(tester, state: 23, fault: 17); // lft_e.olf

    expect(find.text('Motor overload'), findsOneWidget);
    expect(find.textContaining('Fault reset clears it'), findsOneWidget);
  });

  testWidgets(
    'the drive-state explanation is closed until it is asked for',
    (tester) async {
      await _openPane(tester, state: 3); // hmis_e.nst — freewheel

      expect(find.text('Freewheel stop'), findsOneWidget);
      expect(find.text('NST'), findsNothing);

      await tester.tap(find.text('Freewheel stop'));
      await _settlePane(tester);

      expect(find.text('NST'), findsOneWidget);
      expect(find.textContaining('coasting'), findsOneWidget);
    },
  );

  testWidgets('a lost EtherCAT link is not blamed on the drive',
      (tester) async {
    // What FB_ATV320 publishes when it cannot reach the slave: the made-up
    // state 99 paired with a CNF last fault.
    await _openPane(tester, state: 99, fault: 7);

    expect(_inRow('No link to drive'), findsOneWidget);

    // The fault row auto-opens on CNF, and what it says matters: an
    // electrician must not go looking for a fieldbus fault inside a drive
    // the PLC simply cannot see.
    expect(find.textContaining('not a fault inside the drive'), findsOneWidget);

    await tester.tap(_inRow('No link to drive'));
    await _settlePane(tester);
    expect(find.textContaining('cannot reach this drive over EtherCAT'),
        findsOneWidget);
  });

  testWidgets('a faulted drive does not present itself as merely stopped',
      (tester) async {
    await _openPane(tester, state: 23, fault: 9);

    final chip = tester.widget<PaneStatusChip>(find.byType(PaneStatusChip));
    expect(chip.status.label, 'Faulted');
  });

  testWidgets('STO shows in the header as a safety hold, not a trip',
      (tester) async {
    await _openPane(tester, state: 30);

    final chip = tester.widget<PaneStatusChip>(find.byType(PaneStatusChip));
    expect(chip.status.label, 'Safe Torque Off');
    expect(chip.status.icon, Icons.warning_amber);
  });

  testWidgets('a healthy stopped belt still reads as stopped', (tester) async {
    await _openPane(tester, state: 2);

    final chip = tester.widget<PaneStatusChip>(find.byType(PaneStatusChip));
    expect(chip.status.label, 'Stopped');
  });
}
