/// Widget tests for FB-member affordance rendering in [BrowseNodeTile].
///
/// Phase 4 of the v1.1 UMAS Hardening milestone (UI-01, UI-02).
///
/// These tests pump a single [BrowseNodeTile] for each of the four direction
/// states ([UmasFbMemberDirection.input], `.output`, `.publicVar`, `.inOut`,
/// plus `.unknown`) and the inaccessible (`readable: false`) state.
/// Assertions are string + icon + tooltip based — no goldens.
///
/// The test fixture uses [UmasFbMember] from
/// `package:tfc_dart/core/umas_fb_browse_types.dart` (a `@phase4-stub`).
/// At merge time with Phases 2/3, only the import line + constructor call
/// here should need to change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:tfc_dart/core/umas_fb_browse_types.dart';

import 'package:tfc/widgets/browse_panel.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

BrowseNode _fbNodeFromMember(UmasFbMember m) {
  return BrowseNode(
    id: m.name,
    displayName: m.name,
    type: BrowseNodeType.variable,
    dataType: m.typeName,
    metadata: m.toBrowseNodeMetadata(),
  );
}

BrowseTreeEntry _entryFor(BrowseNode node) {
  return BrowseTreeEntry(
    node: node,
    depth: 0,
    parentId: '__root__',
  );
}

Widget _tileFor(BrowseNode node) {
  return BrowseNodeTile(
    node: _entryFor(node),
    isSelected: false,
    isExpanded: false,
    isLoading: false,
    hasChildren: false,
    onTap: () {},
    onDoubleTap: () {},
    onToggleExpand: () {},
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BrowseNodeTile FB-member affordances', () {
    testWidgets('input direction renders Icons.login + (IN) suffix',
        (tester) async {
      final member = const UmasFbMember(
        name: 'cmdSpeed',
        typeName: 'REAL',
        direction: UmasFbMemberDirection.input,
      );
      await tester.pumpWidget(_wrap(_tileFor(_fbNodeFromMember(member))));

      // BrowseNodeTile renders the displayName and the id; when id == name
      // (FB members in the test) the same text appears twice.
      expect(find.text('cmdSpeed'), findsWidgets);
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.text('(IN)'), findsOneWidget);
      // No conflicting suffixes from other directions.
      expect(find.text('(OUT)'), findsNothing);
      expect(find.text('(IN/OUT)'), findsNothing);
      expect(find.text('[not readable]'), findsNothing);
    });

    testWidgets('output direction renders Icons.logout + (OUT) suffix',
        (tester) async {
      final member = const UmasFbMember(
        name: 'actualSpeed',
        typeName: 'REAL',
        direction: UmasFbMemberDirection.output,
      );
      await tester.pumpWidget(_wrap(_tileFor(_fbNodeFromMember(member))));

      expect(find.text('actualSpeed'), findsWidgets);
      expect(find.byIcon(Icons.logout), findsOneWidget);
      expect(find.text('(OUT)'), findsOneWidget);
      expect(find.text('(IN)'), findsNothing);
      expect(find.text('(IN/OUT)'), findsNothing);
      expect(find.text('[not readable]'), findsNothing);
    });

    testWidgets(
        'publicVar direction renders the existing variable affordance — '
        'no direction suffix, no direction icon, FA tag icon retained',
        (tester) async {
      final member = const UmasFbMember(
        name: 'config',
        typeName: 'BOOL',
        direction: UmasFbMemberDirection.publicVar,
      );
      await tester.pumpWidget(_wrap(_tileFor(_fbNodeFromMember(member))));

      expect(find.text('config'), findsWidgets);
      // No direction-specific icon.
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.byIcon(Icons.block), findsNothing);
      // No direction suffix.
      expect(find.text('(IN)'), findsNothing);
      expect(find.text('(OUT)'), findsNothing);
      expect(find.text('(IN/OUT)'), findsNothing);
      // Existing variable-tag icon retained.
      expect(find.byType(FaIcon), findsWidgets);
    });

    testWidgets('inOut direction renders Icons.swap_horiz + (IN/OUT) suffix',
        (tester) async {
      final member = const UmasFbMember(
        name: 'sharedRef',
        typeName: 'INT',
        direction: UmasFbMemberDirection.inOut,
      );
      await tester.pumpWidget(_wrap(_tileFor(_fbNodeFromMember(member))));

      expect(find.text('sharedRef'), findsWidgets);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.text('(IN/OUT)'), findsOneWidget);
      expect(find.text('(IN)'), findsNothing);
      expect(find.text('(OUT)'), findsNothing);
      expect(find.text('[not readable]'), findsNothing);
    });

    testWidgets(
        'unknown direction falls back to existing variable affordance '
        '— no direction suffix, no exception text',
        (tester) async {
      final member = const UmasFbMember(
        name: 'mystery',
        typeName: 'DINT',
        direction: UmasFbMemberDirection.unknown,
      );
      await tester.pumpWidget(_wrap(_tileFor(_fbNodeFromMember(member))));

      expect(find.text('mystery'), findsWidgets);
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.byIcon(Icons.block), findsNothing);
      expect(find.text('(IN)'), findsNothing);
      expect(find.text('(OUT)'), findsNothing);
      expect(find.text('(IN/OUT)'), findsNothing);
      expect(find.text('[not readable]'), findsNothing);
      // Existing variable-tag icon retained.
      expect(find.byType(FaIcon), findsWidgets);
    });

    testWidgets(
        'inaccessible member (readable=false) renders Icons.block + '
        '[not readable] suffix + tooltip carrying the reason',
        (tester) async {
      const reason = 'VAR_IN_OUT (PLC returns 0x94)';
      final member = const UmasFbMember(
        name: 'sharedRef',
        typeName: 'INT',
        direction: UmasFbMemberDirection.inOut,
        readable: false,
        unreadableReason: reason,
      );
      await tester.pumpWidget(_wrap(_tileFor(_fbNodeFromMember(member))));

      expect(find.text('sharedRef'), findsWidgets);
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.text('[not readable]'), findsOneWidget);

      // The row is wrapped in a Tooltip carrying the unreadable reason.
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsWidgets);
      final tooltips = tester
          .widgetList<Tooltip>(tooltipFinder)
          .where((t) => t.message == reason)
          .toList();
      expect(tooltips, hasLength(1),
          reason: 'Exactly one Tooltip should carry the unreadableReason.');

      // Never shows the raw exception text.
      expect(find.textContaining('Buffer underflow'), findsNothing);
      expect(find.textContaining('read error'), findsNothing);
      expect(find.textContaining('0x94'), findsNothing,
          reason: 'PLC error code should be in tooltip only, '
              'not the visible tile.');
    });

    testWidgets(
        'non-FB variable tile (no fb metadata) renders unchanged — '
        'no direction icons, no suffix, no not-readable badge',
        (tester) async {
      final node = BrowseNode(
        id: 'App.GVL.temperature',
        displayName: 'temperature',
        type: BrowseNodeType.variable,
        dataType: 'REAL',
        metadata: const {
          'path': 'App.GVL.temperature',
          'blockNo': '1',
          'offset': '0',
        },
      );
      await tester.pumpWidget(_wrap(_tileFor(node)));

      expect(find.text('temperature'), findsOneWidget);
      // None of the FB affordances appear.
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.byIcon(Icons.block), findsNothing);
      expect(find.text('(IN)'), findsNothing);
      expect(find.text('(OUT)'), findsNothing);
      expect(find.text('(IN/OUT)'), findsNothing);
      expect(find.text('[not readable]'), findsNothing);
    });

    testWidgets('folder tile is unaffected by FB metadata helpers',
        (tester) async {
      // Sanity check: a folder node with no metadata still renders
      // its folder icon and is unaffected by the new code paths.
      final node = BrowseNode(
        id: 'App',
        displayName: 'App',
        type: BrowseNodeType.folder,
      );
      await tester.pumpWidget(_wrap(_tileFor(node)));

      expect(find.text('App'), findsWidgets);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.byIcon(Icons.block), findsNothing);
    });
  });
}
