/// Regression tests for `umas_cli read <name>` path resolution.
///
/// Bug (discovered 2026-05-20 while verifying byte-aligned named BOOLs on the
/// live M580 at 192.168.112.159): the CLI's `read` command refused to find any
/// variable addressed by a dotted path (e.g. `M_F2_RC_01.p_CMD_xManFwd`) even
/// though `browse` clearly showed those leaves and `readVariableByName`
/// happily resolved them through the symbol cache. Root cause: the CLI's
/// node-search helper compared `node.name == query`, where `name` is the
/// LEAF segment only — never the full dotted path. So any dotted query
/// failed before [UmasClient.readVariableByName] ever saw it, and the
/// operator was misled into believing the BOOLs were missing from the data
/// dictionary.
///
/// The fix accepts BOTH the leaf segment AND the full dotted path. We pin
/// the behavior here so the CLI can't regress back to leaf-only matching.
@TestOn('vm')
library;

import 'package:tfc_dart/core/umas_browse_search.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

/// Builds a tiny browse-tree fragment that mirrors the M_F2_RC_01 FB shape
/// observed on the live M580: a parent FB with byte-aligned BOOL members at
/// offsets 0x37..0x3e plus a nested `HMI` sub-FB with the `p_Stat_*` words.
List<UmasVariableTreeNode> _buildFixtureTree() {
  UmasVariableTreeNode boolLeaf(String name, String path, int off) =>
      UmasVariableTreeNode(
        name: name,
        path: path,
        variable: UmasVariable(
          name: name,
          blockNo: 0xb2,
          offset: off,
          dataTypeId: 0x0001, // BOOL
        ),
        dataType: const UmasDataTypeRef(
          id: 0x0001,
          name: 'BOOL',
          byteSize: 1,
          classIdentifier: 0,
        ),
        direction: UmasFbMemberDirection.publicVar,
      );

  UmasVariableTreeNode wordLeaf(String name, String path, int off) =>
      UmasVariableTreeNode(
        name: name,
        path: path,
        variable: UmasVariable(
          name: name,
          blockNo: 0xb2,
          offset: off,
          dataTypeId: 0x0005, // WORD
        ),
        dataType: const UmasDataTypeRef(
          id: 0x0005,
          name: 'WORD',
          byteSize: 2,
          classIdentifier: 0,
        ),
        direction: UmasFbMemberDirection.publicVar,
      );

  final hmi = UmasVariableTreeNode(
    name: 'HMI',
    path: 'M_F2_RC_01.HMI',
    children: [
      wordLeaf('Status', 'M_F2_RC_01.HMI.Status', 0x8c),
      wordLeaf('CMD', 'M_F2_RC_01.HMI.CMD', 0x8e),
    ],
    direction: UmasFbMemberDirection.publicVar,
  );

  final m = UmasVariableTreeNode(
    name: 'M_F2_RC_01',
    path: 'M_F2_RC_01',
    children: [
      boolLeaf('p_CMD_xReset', 'M_F2_RC_01.p_CMD_xReset', 0x37),
      boolLeaf('p_CMD_xManFwd', 'M_F2_RC_01.p_CMD_xManFwd', 0x38),
      boolLeaf('p_CMD_xManRev', 'M_F2_RC_01.p_CMD_xManRev', 0x39),
      boolLeaf('p_MODE_xAuto', 'M_F2_RC_01.p_MODE_xAuto', 0x3a),
      boolLeaf('p_Stat_xAuto', 'M_F2_RC_01.p_Stat_xAuto', 0x3b),
      hmi,
    ],
  );

  // Sibling root sharing a leaf segment name with M_F2_RC_01's child — this
  // catches a regression where a leaf-only matcher would return the wrong
  // node when two variables share a local name across FBs.
  final sibling = UmasVariableTreeNode(
    name: 'M_F1_SideMover_Transport',
    path: 'M_F1_SideMover_Transport',
    children: [
      boolLeaf('p_CMD_xManFwd', 'M_F1_SideMover_Transport.p_CMD_xManFwd', 0x38),
    ],
  );

  return [m, sibling];
}

void main() {
  group('findUmasNodeByPathOrName', () {
    final tree = _buildFixtureTree();

    test('resolves a leaf by its full dotted path '
        '(the regression fix for umas_cli read)', () {
      final node = findUmasNodeByPathOrName(tree, 'M_F2_RC_01.p_CMD_xManFwd');
      expect(node, isNotNull,
          reason:
              'Dotted path must resolve — the CLI used to drop these and '
              'mislead operators about missing FB BOOLs.');
      expect(node!.path, 'M_F2_RC_01.p_CMD_xManFwd');
      expect(node.variable!.offset, 0x38);
    });

    test('resolves a nested-FB member by its full dotted path', () {
      final node = findUmasNodeByPathOrName(tree, 'M_F2_RC_01.HMI.Status');
      expect(node, isNotNull);
      expect(node!.path, 'M_F2_RC_01.HMI.Status');
      expect(node.variable!.offset, 0x8c);
    });

    test('still resolves a bare leaf segment (no dots) — backwards compat', () {
      final node = findUmasNodeByPathOrName(tree, 'p_CMD_xReset');
      expect(node, isNotNull);
      expect(node!.path, 'M_F2_RC_01.p_CMD_xReset');
    });

    test('dotted query disambiguates when a leaf name is duplicated across '
        'sibling FBs', () {
      final node = findUmasNodeByPathOrName(
          tree, 'M_F1_SideMover_Transport.p_CMD_xManFwd');
      expect(node, isNotNull);
      expect(node!.path, 'M_F1_SideMover_Transport.p_CMD_xManFwd',
          reason:
              'Path-aware matcher must NOT collapse to the first M_F2_RC_01 '
              'hit when the caller passed the sibling FBs path.');
    });

    test('returns null for an unknown name', () {
      expect(findUmasNodeByPathOrName(tree, 'DoesNotExist'), isNull);
      expect(findUmasNodeByPathOrName(tree, 'M_F2_RC_01.DoesNotExist'), isNull);
    });

    test('resolves a root FB node by its own name', () {
      final node = findUmasNodeByPathOrName(tree, 'M_F2_RC_01');
      expect(node, isNotNull);
      expect(node!.path, 'M_F2_RC_01');
      expect(node.children, isNotEmpty);
    });
  });
}
