import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/third_party.dart';
import 'package:tfc/theme.dart'
    show AppColorScheme, HmiColorRole, themesForScheme;

void main() {
  // ProviderScope + MaterialApp so the editor's Navigator/theme are present,
  // and a real HmiStateColors-carrying theme so the preview's role colours
  // resolve. No provider overrides — the editor pane reads no live keys.
  Widget wrap(ThirdPartyEquipmentConfig config) {
    final (lightMuted, _) = themesForScheme(AppColorScheme.muted);
    return ProviderScope(
      child: MaterialApp(
        theme: lightMuted,
        home: Scaffold(
          body: Builder(builder: (context) => config.configure(context)),
        ),
      ),
    );
  }

  // The editor is a long SingleChildScrollView, so the extra-diodes section
  // sits below the fold — a widget must be scrolled into view before it can
  // be tapped or typed into.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterVisible(
      WidgetTester tester, Finder finder, String text) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  group('Extra status diodes editor', () {
    testWidgets('a multivac editor starts with no extra diodes and an add '
        'button', (tester) async {
      final config =
          ThirdPartyEquipmentConfig(kind: ThirdPartyEquipmentKind.multivac);

      await tester.pumpWidget(wrap(config));
      await tester.pumpAndSettle();

      expect(config.extraBits, isEmpty);
      expect(find.text('No extra diodes'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add diode'), findsOneWidget);
    });

    testWidgets('tapping add appends one empty blue diode row', (tester) async {
      final config =
          ThirdPartyEquipmentConfig(kind: ThirdPartyEquipmentKind.multivac);

      await tester.pumpWidget(wrap(config));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Add diode'));

      expect(config.extraBits, hasLength(1));
      final bit = config.extraBits.single;
      expect(bit.key, isEmpty);
      expect(bit.label, isEmpty);
      expect(bit.onRole, HmiColorRole.blue);
      // The placeholder row text is gone once a real row exists.
      expect(find.text('No extra diodes'), findsNothing);
    });

    testWidgets('entering a key and label writes them back into the bit',
        (tester) async {
      final config =
          ThirdPartyEquipmentConfig(kind: ThirdPartyEquipmentKind.multivac);

      await tester.pumpWidget(wrap(config));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Add diode'));

      await enterVisible(tester, find.widgetWithText(TextFormField, 'Key'),
          'MVC02.PermitOutfeed');
      await enterVisible(tester, find.widgetWithText(TextFormField, 'Label'),
          'Way out of Multivac is clear');

      final bit = config.extraBits.single;
      expect(bit.key, 'MVC02.PermitOutfeed');
      expect(bit.label, 'Way out of Multivac is clear');
      // The other field is preserved across each in-place rebuild.
      expect(bit.onRole, HmiColorRole.blue);
    });

    testWidgets('selecting a colour role updates the bit, keeping key/label',
        (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.multivac,
        extraBits: const [
          ExtraStatusBit(
              key: 'MVC01.PermitOutfeed', label: 'Way out is clear'),
        ],
      );

      await tester.pumpWidget(wrap(config));
      await tester.pumpAndSettle();

      // The row's role dropdown shows the current role's display name; there
      // is exactly one HmiColorRole dropdown in the pane (the kind/label
      // dropdowns are of other types). Drive its onChanged the way the open
      // menu would, without fighting the overlay's hit geometry — this is the
      // same callback that wires an operator's pick back into config.extraBits.
      expect(find.text('Blue'), findsOneWidget);
      final roleDropdown = tester.widget<DropdownButton<HmiColorRole>>(
          find.byType(DropdownButton<HmiColorRole>));
      roleDropdown.onChanged!(HmiColorRole.green);
      await tester.pumpAndSettle();

      final bit = config.extraBits.single;
      expect(bit.onRole, HmiColorRole.green);
      // The dropdown now reflects the new role (the button renders its
      // selected label, plus an offstage copy it sizes the menu against).
      expect(find.text('Green'), findsWidgets);
      expect(bit.key, 'MVC01.PermitOutfeed');
      expect(bit.label, 'Way out is clear');
    });

    testWidgets('the remove button drops the row', (tester) async {
      final config = ThirdPartyEquipmentConfig(
        kind: ThirdPartyEquipmentKind.multivac,
        extraBits: const [
          ExtraStatusBit(key: 'MVC01.PermitOutfeed', label: 'out'),
          ExtraStatusBit(
              key: 'MVC01.PermitInfeed',
              label: 'in',
              onRole: HmiColorRole.green),
        ],
      );

      await tester.pumpWidget(wrap(config));
      await tester.pumpAndSettle();

      expect(config.extraBits, hasLength(2));

      // Remove the first row; the second must remain, with its own values.
      await tapVisible(tester, find.byTooltip('Remove').first);

      expect(config.extraBits, hasLength(1));
      final bit = config.extraBits.single;
      expect(bit.key, 'MVC01.PermitInfeed');
      expect(bit.label, 'in');
      expect(bit.onRole, HmiColorRole.green);
    });
  });
}
