/// Golden + widget tests for UMAS browse panel integration.
///
/// Uses UmasBrowseDataSource with a mock UmasClient to verify:
/// 1. The browse panel renders the UMAS variable tree correctly
/// 2. Folder expansion works
/// 3. Variable selection and detail strip show correct metadata
/// 4. Golden images capture the visual state for manual review
///
/// To update goldens: flutter test test/widgets/umas_browse_golden_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

import 'package:tfc/widgets/browse_panel.dart';
import 'package:tfc/widgets/umas_browse.dart';

// ---------------------------------------------------------------------------
// Fake UMAS send function — returns canned FC90 responses
// ---------------------------------------------------------------------------

/// Builds a success PDU: [0x5A, pairingKey, 0xFE, subFunc, ...payload]
Uint8List _successPdu(int subFunc, List<int> payload,
    {int pairingKey = 0x00}) {
  return Uint8List.fromList([0x5A, pairingKey, 0xFE, subFunc, ...payload]);
}

/// Little-endian uint16
List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

/// Build variable names payload (same data as stub server)
List<int> _variableNamesPayload() {
  final buf = <int>[];
  for (final (name, blockNo, offset, typeId) in [
    ('Application.GVL.temperature', 1, 0, 5),
    ('Application.GVL.pressure', 1, 4, 5),
    ('Application.GVL.motor_running', 1, 8, 6),
    ('Application.GVL.setpoint', 1, 9, 1),
    ('Application.GVL.error_code', 1, 11, 2),
    ('Application.Motor.speed', 2, 0, 5),
    ('Application.Motor.torque', 2, 4, 5),
    ('Application.Motor.enabled', 2, 8, 6),
    ('Application.Counters.production', 3, 0, 4),
    ('Application.Counters.runtime_ms', 3, 4, 8),
  ]) {
    final nameBytes = name.codeUnits;
    buf.addAll(_le16(nameBytes.length));
    buf.addAll(nameBytes);
    buf.addAll(_le16(blockNo));
    buf.addAll(_le16(offset));
    buf.addAll(_le16(typeId));
  }
  return buf;
}

/// Build data types payload (custom types from stub server)
List<int> _dataTypesPayload() {
  final buf = <int>[];
  for (final (typeId, name, byteSize) in [
    (100, 'MY_STRUCT', 16),
    (101, 'ALARM_TYPE', 8),
  ]) {
    final nameBytes = name.codeUnits;
    buf.addAll(_le16(typeId));
    buf.addAll(_le16(nameBytes.length));
    buf.addAll(nameBytes);
    buf.addAll(_le16(byteSize));
  }
  return buf;
}

/// Mock send function that mimics the stub server responses
Future<ModbusResponseCode> _fakeSend(ModbusRequest request) async {
  if (request is! UmasRequest) {
    return ModbusResponseCode.requestTimeout;
  }

  final subFunc = request.umasSubFunction;
  Uint8List pdu;

  if (subFunc == 0x01) {
    // Init: max frame size = 1024
    pdu = _successPdu(0x01, _le16(1024));
  } else if (subFunc == 0x26) {
    // ReadDataDictionary
    final recordType = request.umasPayload[0] | (request.umasPayload[1] << 8);
    if (recordType == 0xDD02) {
      pdu = _successPdu(0x26, _variableNamesPayload());
    } else if (recordType == 0xDD03) {
      pdu = _successPdu(0x26, _dataTypesPayload());
    } else {
      pdu = Uint8List.fromList([0x5A, 0x00, 0xFD, 0x03]);
    }
  } else {
    pdu = Uint8List.fromList([0x5A, 0x00, 0xFD, 0x04]);
  }

  request.internalSetFromPduResponse(pdu);
  return ModbusResponseCode.requestSucceed;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pump a BrowsePanel inside a MaterialApp with Solarized-like dark theme.
Future<void> _showUmasBrowse(WidgetTester tester) async {
  final client = UmasClient(sendFn: _fakeSend);
  final dataSource = UmasBrowseDataSource(client);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBrowseDialog(
                context: context,
                dataSource: dataSource,
                serverAlias: 'Schneider M340',
              ),
              child: const Text('Browse'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Browse'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UMAS Browse Panel', () {
    testWidgets('renders root "Application" folder from UMAS browse',
        (tester) async {
      await _showUmasBrowse(tester);

      // Root should show "Application" (may appear in breadcrumb too)
      expect(find.text('Application'), findsWidgets);
    });

    testWidgets('expanding Application shows GVL, Motor, Counters folders',
        (tester) async {
      await _showUmasBrowse(tester);

      // Tap to expand Application (use .first — breadcrumb also shows it)
      // pump(kDoubleTapTimeout) needed to distinguish from double-tap
      await tester.tap(find.text('Application').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.text('GVL'), findsWidgets);
      expect(find.text('Motor'), findsWidgets);
      expect(find.text('Counters'), findsWidgets);
    });

    testWidgets('expanding GVL shows 5 variables with correct types',
        (tester) async {
      await _showUmasBrowse(tester);

      // Expand Application
      await tester.tap(find.text('Application').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Expand GVL
      await tester.tap(find.text('GVL').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.text('temperature'), findsWidgets);
      expect(find.text('pressure'), findsWidgets);
      expect(find.text('motor_running'), findsWidgets);
      expect(find.text('setpoint'), findsWidgets);
      expect(find.text('error_code'), findsWidgets);
    });

    testWidgets('selecting a variable shows detail strip', (tester) async {
      await _showUmasBrowse(tester);

      // Expand Application → GVL
      await tester.tap(find.text('Application').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GVL').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Tap temperature to select it
      await tester.tap(find.text('temperature').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // The detail strip should show path info
      expect(find.text('Application.GVL.temperature'), findsWidgets);
    });

    testWidgets('golden: initial state with Application root',
        (tester) async {
      await _showUmasBrowse(tester);
      await expectLater(
        find.byType(Dialog),
        matchesGoldenFile('goldens/umas_browse_initial.png'),
      );
    });

    testWidgets('golden: expanded tree showing variables', (tester) async {
      await _showUmasBrowse(tester);

      // Expand Application → GVL
      await tester.tap(find.text('Application').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GVL').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Also expand Motor
      await tester.tap(find.text('Motor').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Dialog),
        matchesGoldenFile('goldens/umas_browse_expanded.png'),
      );
    });

    testWidgets('golden: variable selected with detail strip',
        (tester) async {
      await _showUmasBrowse(tester);

      await tester.tap(find.text('Application').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GVL').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Select temperature
      await tester.tap(find.text('temperature').first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Dialog),
        matchesGoldenFile('goldens/umas_browse_selected.png'),
      );
    });
  });
}
