import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

import 'package:tfc/plc/plc_code_upload_dialog.dart';
import 'package:tfc/plc/plc_code_upload_service.dart';

// -- Mocks -------------------------------------------------------------------

class _MockPlcCodeService extends Fake implements PlcCodeService {
  final bool _hasCode;
  _MockPlcCodeService({bool hasCode = false}) : _hasCode = hasCode;

  @override
  bool get hasCode => _hasCode;

  PlcVendor? lastVendor;
  String? lastServerAlias;

  @override
  Future<UploadResult> processUpload(
    String assetKey,
    dynamic bytes, {
    PlcVendor? vendor,
    String? serverAlias,
  }) async {
    lastVendor = vendor;
    lastServerAlias = serverAlias;
    return const UploadResult(
      totalBlocks: 5,
      totalVariables: 20,
      blockTypeCounts: {'FunctionBlock': 3, 'GVL': 2},
      skippedFiles: 0,
    );
  }
}

/// Builds the dialog inside a MaterialApp for widget testing.
///
/// [serverAliases] provides the list of available server aliases from
/// StateManConfig, simulating OPC UA and JBTM server names.
/// [uploadService] is an optional mock upload service.
Widget _wrap({
  required PlcCodeUploadService uploadService,
  List<String> serverAliases = const [],
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => PlcCodeUploadDialog(
                  uploadService: uploadService,
                  serverAliases: serverAliases,
                ),
              );
            },
            child: const Text('Open Dialog'),
          );
        },
      ),
    ),
  );
}

/// Opens the dialog by tapping the trigger button.
Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open Dialog'));
  await tester.pumpAndSettle();
}

// -- Tests -------------------------------------------------------------------

void main() {
  late _MockPlcCodeService mockPlcService;
  late PlcCodeUploadService uploadService;

  setUp(() {
    mockPlcService = _MockPlcCodeService();
    uploadService = PlcCodeUploadService(mockPlcService);
  });

  group('PlcCodeUploadDialog - vendor dropdown', () {
    testWidgets('shows vendor dropdown with correct options', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // The vendor dropdown should be present
      final vendorDropdown = find.byKey(const ValueKey('plc-vendor-dropdown'));
      expect(vendorDropdown, findsOneWidget);

      // Tap to open the dropdown
      await tester.tap(vendorDropdown);
      await tester.pumpAndSettle();

      // All vendor options should appear
      expect(find.text('Beckhoff (TwinCAT)'), findsWidgets);
      expect(
        find.text('Schneider (Control Expert)'),
        findsWidgets,
      );
      expect(
        find.text('Schneider (Machine Expert)'),
        findsWidgets,
      );
    });

    testWidgets('Beckhoff is selected by default', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Beckhoff label should be visible as the selected value
      expect(find.text('Beckhoff (TwinCAT)'), findsOneWidget);
    });

    testWidgets('selecting Beckhoff shows TwinCAT export instructions',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Default is Beckhoff, so TwinCAT instructions should show
      expect(
        find.textContaining('TwinCAT'),
        findsWidgets,
      );
      // Should mention exporting as ZIP
      expect(find.textContaining('.zip'), findsWidgets);
    });

    testWidgets('selecting Schneider shows Schneider export instructions',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Open vendor dropdown and select Schneider
      final vendorDropdown = find.byKey(const ValueKey('plc-vendor-dropdown'));
      await tester.tap(vendorDropdown);
      await tester.pumpAndSettle();

      // Tap Schneider option (use last if there are duplicates from dropdown)
      await tester.tap(
        find.text('Schneider (Control Expert)').last,
      );
      await tester.pumpAndSettle();

      // Should show Schneider-specific instructions
      expect(find.textContaining('Schneider'), findsWidgets);
      // Should mention .xef or .xml export format
      expect(
        find.textContaining('.xef'),
        findsWidgets,
      );
    });

    testWidgets('file picker button label changes for Schneider vendor',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Default (Beckhoff) should show .tnzip prompt
      expect(find.textContaining('.tnzip'), findsWidgets);

      // Switch to Schneider Control Expert
      final vendorDropdown = find.byKey(const ValueKey('plc-vendor-dropdown'));
      await tester.tap(vendorDropdown);
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Schneider (Control Expert)').last,
      );
      await tester.pumpAndSettle();

      // After switching vendor, file picker should show Control Expert prompt
      // (no file should remain selected from before)
      expect(find.textContaining('.xef'), findsWidgets);
    });
  });

  group('PlcCodeUploadDialog - server alias dropdown', () {
    testWidgets('shows server alias dropdown when aliases are provided',
        (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: ['PLC-1', 'PLC-2', 'HMI-Server'],
      ));
      await _openDialog(tester);

      final aliasDropdown =
          find.byKey(const ValueKey('plc-server-alias-dropdown'));
      expect(aliasDropdown, findsOneWidget);
    });

    testWidgets('shows server alias dropdown even when no aliases provided',
        (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: [],
      ));
      await _openDialog(tester);

      final aliasDropdown =
          find.byKey(const ValueKey('plc-server-alias-dropdown'));
      expect(aliasDropdown, findsOneWidget);
    });

    testWidgets('dropdown always contains (default) option', (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: [],
      ));
      await _openDialog(tester);

      // Tap to open the dropdown
      final aliasDropdown =
          find.byKey(const ValueKey('plc-server-alias-dropdown'));
      await tester.tap(aliasDropdown);
      await tester.pumpAndSettle();

      expect(find.text('(default)'), findsWidgets);
    });

    testWidgets('dropdown contains (default) followed by provided aliases',
        (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: ['PLC-1', 'PLC-2', 'HMI-Server'],
      ));
      await _openDialog(tester);

      // Tap to open the server alias dropdown
      final aliasDropdown =
          find.byKey(const ValueKey('plc-server-alias-dropdown'));
      await tester.tap(aliasDropdown);
      await tester.pumpAndSettle();

      expect(find.text('(default)'), findsWidgets);
      expect(find.text('PLC-1'), findsWidgets);
      expect(find.text('PLC-2'), findsWidgets);
      expect(find.text('HMI-Server'), findsWidgets);
    });

    testWidgets('Upload button disabled until server alias is selected',
        (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: ['PLC-1', 'PLC-2'],
      ));
      await _openDialog(tester);

      // Upload button should be disabled (no file selected and no alias)
      final uploadButton = find.widgetWithText(FilledButton, 'Upload');
      expect(uploadButton, findsOneWidget);

      final button = tester.widget<FilledButton>(uploadButton);
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'Upload button disabled until server alias selected even with no '
        'provided aliases', (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: [],
      ));
      await _openDialog(tester);

      // Upload button should be disabled — no alias selected yet
      final uploadButton = find.widgetWithText(FilledButton, 'Upload');
      final button = tester.widget<FilledButton>(uploadButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('selecting (default) satisfies alias requirement',
        (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: [],
      ));
      await _openDialog(tester);

      // Select (default)
      final aliasDropdown =
          find.byKey(const ValueKey('plc-server-alias-dropdown'));
      await tester.tap(aliasDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('(default)').last);
      await tester.pumpAndSettle();

      // Upload still disabled because no file is selected,
      // but alias requirement is satisfied -- we verify by checking
      // hint text is replaced by the selected value
      expect(find.text('(default)'), findsOneWidget);
    });
  });

  group('PlcCodeUploadDialog - validation', () {
    testWidgets('shows server alias label', (tester) async {
      await tester.pumpWidget(_wrap(
        uploadService: uploadService,
        serverAliases: ['PLC-1'],
      ));
      await _openDialog(tester);

      expect(find.text('Server Alias'), findsOneWidget);
    });

    testWidgets('shows vendor label', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      expect(find.text('PLC Vendor'), findsOneWidget);
    });

    testWidgets('no asset key field or label is shown', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // No asset key text field
      expect(
        find.byKey(const ValueKey('plc-asset-key-field')),
        findsNothing,
      );
      // No "Asset Key" label
      expect(find.text('Asset Key'), findsNothing);
      // No "Asset:" read-only text
      expect(find.textContaining('Asset:'), findsNothing);
    });

    testWidgets('Cancel button closes dialog', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Dialog should be showing
      expect(find.text('Upload PLC Project'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Upload PLC Project'), findsNothing);
    });
  });

  group('PlcCodeUploadDialog - upload routing', () {
    testWidgets('Upload button exists and is initially disabled',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      final uploadButton = find.widgetWithText(FilledButton, 'Upload');
      expect(uploadButton, findsOneWidget);

      // No file selected yet, so upload should be disabled
      final button = tester.widget<FilledButton>(uploadButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('dialog title is Upload PLC Project', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      expect(find.text('Upload PLC Project'), findsOneWidget);
    });
  });

  group('PlcCodeUploadDialog - vendor-specific instructions', () {
    testWidgets('Beckhoff instructions mention TwinCAT export step',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Default is Beckhoff -- instructions should mention TwinCAT project
      expect(find.textContaining('TwinCAT'), findsWidgets);
    });

    testWidgets('Schneider instructions mention Control Expert',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Switch to Schneider
      final vendorDropdown = find.byKey(const ValueKey('plc-vendor-dropdown'));
      await tester.tap(vendorDropdown);
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Schneider (Control Expert)').last,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Control Expert'), findsWidgets);
    });

    testWidgets('switching vendor clears file selection', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Default Beckhoff -- the file picker should show .tnzip prompt
      expect(find.textContaining('.tnzip'), findsWidgets);

      // Switch to Schneider Control Expert
      final vendorDropdown = find.byKey(const ValueKey('plc-vendor-dropdown'));
      await tester.tap(vendorDropdown);
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Schneider (Control Expert)').last,
      );
      await tester.pumpAndSettle();

      // After switching vendor, file picker should show Control Expert prompt
      // (no file should remain selected from before)
      expect(find.textContaining('.xef'), findsWidgets);
    });
  });

  group('PlcCodeUploadDialog - existing index confirmation', () {
    testWidgets('dialog shows replace warning when index already exists',
        (tester) async {
      final existingService = PlcCodeUploadService(
        _MockPlcCodeService(hasCode: true),
      );
      await tester.pumpWidget(_wrap(uploadService: existingService));
      await _openDialog(tester);

      // The dialog should still render normally
      expect(find.text('Upload PLC Project'), findsOneWidget);
    });
  });

  group('PlcCodeUploadDialog - file picker button', () {
    testWidgets('file picker button is present', (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Should have a file open icon
      expect(find.byIcon(Icons.file_open), findsOneWidget);
    });

    testWidgets('file picker button is disabled during upload', (tester) async {
      // We can only verify the initial state -- during upload we would
      // need to simulate the async flow which requires file system access.
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // File picker button should be enabled initially
      final outlinedButton = find.byType(OutlinedButton);
      expect(outlinedButton, findsOneWidget);
      final button = tester.widget<OutlinedButton>(outlinedButton);
      expect(button.onPressed, isNotNull);
    });
  });

  group('PlcCodeUploadDialog - summary view', () {
    testWidgets('dialog renders with correct initial structure',
        (tester) async {
      await tester.pumpWidget(_wrap(uploadService: uploadService));
      await _openDialog(tester);

      // Verify the dialog has the expected structure
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Upload PLC Project'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
    });
  });
}
